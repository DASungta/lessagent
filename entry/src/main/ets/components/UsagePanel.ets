import { common } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';
import { FontSize, LineHeight, Opacity, Radius, Sizes, Space, Weight } from '../common/Theme';
import { EnvironmentEntry } from '../protocol/Environment';
import {
  accountDisplayName,
  buildUsageChartBars,
  CHATGPT_USAGE_URL,
  collectExternalUsageLinks,
  collectPooledLimitAccounts,
  collectPooledLimitGroups,
  collectPooledLimitNotices,
  consumeUsageResetCredit,
  enumerateUsageDays,
  enumerateUsageHourStarts,
  EnvironmentUsageInput,
  formatResetsIn,
  formatUsageCount,
  formatUsageDayShort,
  formatUsageHourShort,
  formatUsagePercent,
  formatUsageTokens,
  formatUsageUsd,
  LimitEnvironmentSnapshot,
  makeUsageWindow,
  maskAccountEmail,
  MergedUsageView,
  mergeUsageSummaries,
  paceRemainingPercent,
  parseUsageSummary,
  parseUsageSummaryContract,
  PooledLimitAccount,
  PooledLimitColumn,
  PooledLimitEnvironmentRef,
  PooledLimitGroup,
  PooledLimitReset,
  PooledLimitWindow,
  PooledLimitWindowEntry,
  ResetCreditChoiceView,
  resetCreditChoicesForAccount,
  toggleUsageEnvironmentSelection,
  USAGE_CONTRACT_VERSION,
  UsageChartBar,
  UsageChartSegment,
  UsageContractMismatch,
  UsageExternalLink,
  UsageModelTotals,
  UsagePeriodTotals,
  UsageProviderTotals,
  UsageSourceView,
  UsageSummaryView,
  UsageWindowSpec,
  usageProviderKind,
  usageProviderLabel,
  usageSourceMessages,
  usageWindowPayload,
} from '../protocol/Usage';
import { optionalRecord, record } from '../protocol/Wire';
import { T3Client } from '../services/T3Client';
import { AppButton } from './ui/AppButton';
import { IconButton } from './ui/IconButton';
import { ProviderLogo } from './ui/ProviderLogo';
import { TopBar } from './ui/TopBar';

interface EnvTarget {
  environmentId: string;
  localId: string;
  label: string;
  client: T3Client | undefined;
}

interface EnvUsageStatus {
  environmentId: string;
  label: string;
  isConnected: boolean;
  canReadDiagnostics: boolean;
  isPending: boolean;
  error: string;
  incompatibleDirection: '' | 'serverBehind' | 'clientBehind';
  summary: UsageSummaryView | undefined;
}

interface MixSegmentItem {
  key: string;
  label: string;
  value: number;
  color: Resource;
}

interface TotalsCellItem {
  label: string;
  value: string;
  detail: string;
}

interface SegmentOption {
  value: string;
  label: string;
}

interface ConfigStreamEntry {
  client: T3Client;
  listener: (value: Object) => void;
}

interface SummaryCompatResult {
  summary?: UsageSummaryView;
  mismatchDirection?: '' | 'serverBehind' | 'clientBehind';
}

interface AccountDetailContext {
  account?: PooledLimitAccount;
  pool?: PooledLimitWindow;
  window?: PooledLimitWindowEntry;
  restoresPercent: number;
}

interface SubscribeServerConfigPayload {
  usageLimitSources: boolean;
}

interface RefreshProvidersPayload {
  fresh: boolean;
  refreshModels: boolean;
}

const CHART_HEIGHT: number = 180;
const AUTO_LIMITS_REFRESH_MS: number = 5 * 60000;

const VIEW_OPTIONS: SegmentOption[] = [
  { value: 'cost', label: '费用' },
  { value: 'tokens', label: 'Tokens' },
  { value: 'limits', label: '限额' },
];

const WINDOW_OPTIONS: SegmentOption[] = [
  { value: '1', label: '24h' },
  { value: '7', label: '7d' },
  { value: '30', label: '30d' },
  { value: '90', label: '90d' },
];

function paceLabel(pace: string): string {
  if (pace === 'ahead') return '超出节奏';
  if (pace === 'on') return '符合节奏';
  if (pace === 'under') return '低于节奏';
  return '';
}

function cloneRecord(source: Record<string, Object>): Record<string, Object> {
  const copy: Record<string, Object> = {};
  for (const key of Object.keys(source)) {
    copy[key] = source[key];
  }
  return copy;
}

@Component
struct UsageSegmentedControl {
  @Prop options: SegmentOption[] = [];
  @Prop selected: string = '';
  @Prop compact: boolean = false;
  onSelect: (value: string) => void = () => {};

  build() {
    Row({ space: 2 }) {
      ForEach(
        this.options,
        (opt: SegmentOption) => {
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Text(opt.label)
              .fontSize(FontSize.callout)
              .lineHeight(LineHeight.callout)
              .fontWeight(this.selected === opt.value ? Weight.semibold : Weight.medium)
              .fontColor(this.selected === opt.value ? $r('app.color.ink') : $r('app.color.muted'))
              .maxLines(1)
          }
          .layoutWeight(1)
          .height(this.compact ? 28 : 34)
          .borderRadius(Radius.full)
          .backgroundColor(this.selected === opt.value ? $r('app.color.tab_bar_active') : Color.Transparent)
          .accessibilityText(opt.label + (this.selected === opt.value ? '，已选中' : ''))
          .onClick(() => this.onSelect(opt.value))
        },
        (opt: SegmentOption) => opt.value + ':' + (this.selected === opt.value ? '1' : '0'),
      )
    }
    .width('100%')
    .height(this.compact ? 34 : 40)
    .padding(3)
    .borderRadius(Radius.full)
    .backgroundColor($r('app.color.group'))
  }
}

@Component
export struct UsagePanel {
  connection: T3Client | undefined = undefined;
  @Prop environments: EnvironmentEntry[] = [];
  connectionFor: (localId: string) => T3Client | undefined = () => undefined;
  @Prop embedded: boolean = false;
  @Prop bottomInset: number = 0;
  onDetailChange: (open: boolean) => void = () => {};
  onBack: () => void = () => {};

  @State activeView: string = 'cost';
  @State windowDays: number = 30;
  @State windowSpec: UsageWindowSpec = makeUsageWindow(30, this.deviceTimeZone());
  @State selectedEnvIds: string[] | null = null;
  @State filterSheetOpen: boolean = false;

  @State envUsageStates: EnvUsageStatus[] = [];
  @State selectedEnvs: EnvUsageStatus[] = [];
  @State mergedUsage: MergedUsageView = mergeUsageSummaries([], USAGE_CONTRACT_VERSION);
  @State usagePending: boolean = true;
  @State usageDimmed: boolean = false;
  @State usageProgressLabel: string = '';
  @State usageSourceWarns: string[] = [];
  @State pullRefreshing: boolean = false;
  @State manualRefreshingUsage: boolean = false;

  @State limitSnapshots: LimitEnvironmentSnapshot[] = [];
  @State selectedSnapshots: LimitEnvironmentSnapshot[] = [];
  @State pooledGroups: PooledLimitGroup[] = [];
  @State pooledNotices: string[] = [];
  @State externalLinks: UsageExternalLink[] = [];
  @State failedLimitLabels: string[] = [];
  @State limitsNowMs: number = Date.now();
  @State @Watch('accountDetailChanged') selectedAccountKey: string = '';
  @State selectedWindowId: string = '';
  @State selectedWindowKind: string = '';
  @State emailRevealed: boolean = false;
  @State redeemBusy: boolean = false;
  @State redeemStatus: string = '';

  private alive: boolean = false;
  private pullRefreshInFlight: boolean = false;
  private usageRequestSeq: number = 0;
  private limitsRequestSeq: number = 0;
  private limitsAutoRefreshedAt: Map<string, number> = new Map<string, number>();
  private liveConfigs: Map<string, Record<string, Object>> = new Map<string, Record<string, Object>>();
  private configStreams: Map<string, ConfigStreamEntry> = new Map<string, ConfigStreamEntry>();
  private envReadySignature: string = '';
  private limitTickTimer: number = -1;
  private pollTimer: number = -1;

  private deviceTimeZone(): string {
    try {
      const id = i18n.getTimeZone().getID();
      if (id && id.trim()) return id;
    } catch (_) {}
    return 'UTC';
  }

  aboutToAppear(): void {
    this.alive = true;
    this.limitsNowMs = Date.now();
    this.windowSpec = makeUsageWindow(this.windowDays, this.deviceTimeZone());
    this.seedLiveConfigsFromClients();
    this.rebuildLimitSnapshots();
    this.syncLimitStreams();
    this.envReadySignature = this.computeEnvSignature();
    void this.loadAllUsage(false);
    void this.loadLimitConfigs();

    this.limitTickTimer = setInterval(() => {
      if (this.alive) {
        this.limitsNowMs = Date.now();
        this.recomputeLimitsView();
      }
    }, 60000) as number;

    this.pollTimer = setInterval(() => {
      if (!this.alive) return;
      this.seedLiveConfigsFromClients();
      this.syncLimitStreams();
      const nextSig = this.computeEnvSignature();
      if (nextSig !== this.envReadySignature) {
        this.envReadySignature = nextSig;
        this.rebuildLimitSnapshots();
        void this.loadAllUsage(false);
        void this.loadLimitConfigs();
      } else {
        this.rebuildLimitSnapshots();
      }
    }, 3000) as number;
  }

  aboutToDisappear(): void {
    this.alive = false;
    clearInterval(this.limitTickTimer);
    clearInterval(this.pollTimer);
    this.stopAllLimitStreams();
  }

  private accountDetailChanged(): void {
    this.onDetailChange(this.selectedAccountKey.length > 0);
  }

  private targetEnvironments(): EnvTarget[] {
    const out: EnvTarget[] = [];
    const seen = new Set<string>();
    for (const entry of this.environments) {
      if (!entry.enabled || entry.deleting || entry.pendingBase) continue;
      const envId = entry.environmentId || entry.localId;
      if (!envId || seen.has(envId)) continue;
      seen.add(envId);
      const client = this.connectionFor(entry.localId);
      out.push({
        environmentId: envId,
        localId: entry.localId,
        label: entry.label || envId,
        client,
      });
    }
    if (out.length === 0 && this.connection) {
      const emptyEnv: Record<string, Object> = {};
      const cfgEnv = optionalRecord(this.connection.config.environment) || emptyEnv;
      const envId = typeof cfgEnv.environmentId === 'string' && cfgEnv.environmentId ? cfgEnv.environmentId : 'current';
      const label = typeof cfgEnv.label === 'string' && cfgEnv.label ? cfgEnv.label : '当前环境';
      out.push({ environmentId: envId, localId: envId, label, client: this.connection });
    }
    return out;
  }

  private computeEnvSignature(): string {
    return this.targetEnvironments()
      .map((env: EnvTarget) => {
        const ready = env.client?.ready ? '1' : '0';
        const gen = env.client ? String(env.client.generationValue()) : '-1';
        return env.environmentId + ':' + ready + ':' + gen;
      })
      .join('|');
  }

  private seedLiveConfigsFromClients(): void {
    for (const env of this.targetEnvironments()) {
      if (env.client?.ready && Object.keys(env.client.config).length > 0 && !this.liveConfigs.has(env.environmentId)) {
        this.liveConfigs.set(env.environmentId, env.client.config);
      } else if (!env.client?.ready) {
        this.liveConfigs.delete(env.environmentId);
      }
    }
  }

  private stopAllLimitStreams(): void {
    this.configStreams.forEach((entry: ConfigStreamEntry) => {
      try {
        entry.client.stopRpcStream(entry.listener);
      } catch (_) {}
    });
    this.configStreams.clear();
  }

  private syncLimitStreams(): void {
    const targets = this.targetEnvironments();
    const activeIds = new Set<string>(
      targets.filter((env: EnvTarget) => !!env.client?.ready).map((env: EnvTarget) => env.environmentId),
    );
    const toRemove: string[] = [];
    this.configStreams.forEach((entry: ConfigStreamEntry, envId: string) => {
      const matched = targets.find((item: EnvTarget) => item.environmentId === envId);
      if (!activeIds.has(envId) || !matched || matched.client !== entry.client) {
        try {
          entry.client.stopRpcStream(entry.listener);
        } catch (_) {}
        toRemove.push(envId);
      }
    });
    for (const id of toRemove) this.configStreams.delete(id);

    for (const env of targets) {
      if (!env.client?.ready || this.configStreams.has(env.environmentId)) continue;
      const client = env.client;
      const envId = env.environmentId;
      const gen = client.generationValue();
      try {
        const payload: SubscribeServerConfigPayload = { usageLimitSources: true };
        const listener = client.watchRpcStream('subscribeServerConfig', payload as Object, (value: Object) => {
          if (!this.alive || !client.ready || client.generationValue() !== gen) return;
          this.applyConfigStreamEvent(envId, client, value);
        });
        this.configStreams.set(envId, { client, listener });
      } catch (_) {}
    }
  }

  private applyConfigStreamEvent(envId: string, client: T3Client, value: Object): void {
    try {
      const event = record(value);
      const eventType = typeof event.type === 'string' ? event.type : '';
      const base = this.liveConfigs.get(envId) || client.config;
      if (eventType === 'snapshot' && event.config !== undefined && event.config !== null) {
        const nextCfg = cloneRecord(record(event.config));
        if (nextCfg.usageLimitSources === undefined && base.usageLimitSources !== undefined) {
          nextCfg.usageLimitSources = base.usageLimitSources;
        }
        this.liveConfigs.set(envId, nextCfg);
        this.rebuildLimitSnapshots();
      } else if (eventType === 'usageLimitSourcesUpdated' && event.payload !== undefined && event.payload !== null) {
        const payload = record(event.payload);
        const updated = cloneRecord(base);
        updated.usageLimitSources = payload.sources;
        this.liveConfigs.set(envId, updated);
        this.rebuildLimitSnapshots();
      } else if (eventType === 'providerStatuses' && event.payload !== undefined && event.payload !== null) {
        const payload = record(event.payload);
        const updated = cloneRecord(base);
        updated.providers = payload.providers;
        this.liveConfigs.set(envId, updated);
        this.rebuildLimitSnapshots();
      } else if (eventType === 'providerStatusDeltas') {
        void this.fetchOneLimitConfig(envId, client, this.limitsRequestSeq);
      }
    } catch (_) {}
  }

  private rebuildLimitSnapshots(): void {
    const snapshots: LimitEnvironmentSnapshot[] = [];
    for (const env of this.targetEnvironments()) {
      const cfg = this.liveConfigs.get(env.environmentId) || (env.client?.ready ? env.client.config : undefined);
      if (cfg && Object.keys(cfg).length > 0) {
        snapshots.push({ environmentId: env.environmentId, label: env.label, config: cfg });
      }
    }
    this.limitSnapshots = snapshots;
    this.recomputeLimitsView();
  }

  private recomputeLimitsView(): void {
    const selected = this.selectedEnvIds;
    const activeSnapshots =
      selected === null
        ? this.limitSnapshots
        : this.limitSnapshots.filter((snap: LimitEnvironmentSnapshot) => selected.includes(snap.environmentId));
    this.selectedSnapshots = activeSnapshots;
    const accounts = collectPooledLimitAccounts(activeSnapshots);
    this.pooledGroups = collectPooledLimitGroups(accounts, this.limitsNowMs);
    this.pooledNotices = collectPooledLimitNotices(activeSnapshots);
    this.externalLinks = collectExternalUsageLinks(activeSnapshots);
  }

  private recomputeUsageView(): void {
    const selected = this.selectedEnvIds;
    const active =
      selected === null
        ? this.envUsageStates
        : this.envUsageStates.filter((item: EnvUsageStatus) => selected.includes(item.environmentId));
    this.selectedEnvs = active;

    const answered = active
      .filter((item: EnvUsageStatus) => item.summary !== undefined)
      .map((item: EnvUsageStatus): EnvironmentUsageInput => ({
        environmentId: item.environmentId,
        label: item.label,
        summary: item.summary as UsageSummaryView,
      }));
    this.mergedUsage = mergeUsageSummaries(answered, USAGE_CONTRACT_VERSION);

    const answeredCount = active.filter((item: EnvUsageStatus) => item.summary !== undefined).length;
    const stillReporting = active.filter((item: EnvUsageStatus) => !item.summary && !item.error).length;
    this.usagePending = answeredCount === 0 && stillReporting > 0;
    this.usageSourceWarns = usageSourceMessages(
      active.flatMap((env: EnvUsageStatus) => env.summary?.sources || []),
    );

    const waitingLabels: string[] = [];
    const updatingProviders: string[] = [];
    let hasAnswered = false;
    let hasStale = false;

    for (const env of active) {
      if (!env.isConnected || env.error) continue;
      if (!env.summary) {
        waitingLabels.push(env.label);
        continue;
      }
      if (this.manualRefreshingUsage) {
        hasStale = true;
        waitingLabels.push(env.label);
        continue;
      }
      if (!env.isPending) {
        hasAnswered = true;
        continue;
      }
      const refreshingProviders = (env.summary.sources || [])
        .filter((s: UsageSourceView) => s.refreshing && !!s.provider)
        .map((s: UsageSourceView) => s.provider);
      if (refreshingProviders.length > 0) {
        hasAnswered = true;
        for (const p of refreshingProviders) {
          if (!updatingProviders.includes(p)) updatingProviders.push(p);
        }
      } else {
        hasStale = true;
        waitingLabels.push(env.label);
      }
    }

    let label = '';
    if (waitingLabels.length > 0) {
      if (active.length === 1) label = '正在更新…';
      else if (waitingLabels.length === 1) label = '正在更新 ' + waitingLabels[0] + '…';
      else label = '正在更新 ' + waitingLabels.length + ' 个环境…';
    } else if (updatingProviders.length === 1) {
      label = '正在更新 ' + usageProviderLabel(updatingProviders[0]) + '…';
    } else if (updatingProviders.length > 1) {
      label = '正在更新 ' + updatingProviders.length + ' 个提供商…';
    }

    this.usageDimmed = !hasAnswered && hasStale;
    this.usageProgressLabel = label;
  }

  private async fetchOneLimitConfig(envId: string, client: T3Client, seq: number): Promise<boolean> {
    if (!client.ready) return false;
    const gen = client.generationValue();
    try {
      const rawConfig = record(
        await client.rpcRequest('server.getConfig', {} as Record<string, Object>, 15000, false),
      );
      if (!this.alive || this.limitsRequestSeq !== seq || !client.ready || client.generationValue() !== gen) {
        return true;
      }
      const config = cloneRecord(rawConfig);
      const existing = this.liveConfigs.get(envId);
      if (config.usageLimitSources === undefined && existing && existing.usageLimitSources !== undefined) {
        config.usageLimitSources = existing.usageLimitSources;
      }
      this.liveConfigs.set(envId, config);
      this.rebuildLimitSnapshots();
      return true;
    } catch (_) {
      return false;
    }
  }

  private async loadLimitConfigs(): Promise<void> {
    const seq = ++this.limitsRequestSeq;
    const selected = this.selectedTargets();
    await Promise.all(
      selected.map(async (env: EnvTarget) => {
        if (!env.client?.ready) return;
        await this.fetchOneLimitConfig(env.environmentId, env.client, seq);
      }),
    );
  }

  private async refreshLimitsProviders(automatic: boolean): Promise<void> {
    const seq = ++this.limitsRequestSeq;
    const targets = this.selectedTargets().filter((env: EnvTarget) => !!env.client?.ready);
    const now = Date.now();
    const failed: string[] = [];

    await Promise.all(
      targets.map(async (env: EnvTarget) => {
        const client = env.client;
        if (!client) return;
        const last = this.limitsAutoRefreshedAt.get(env.environmentId) || 0;
        if (automatic && now < last + AUTO_LIMITS_REFRESH_MS) return;
        const gen = client.generationValue();
        try {
          const payload: RefreshProvidersPayload = { fresh: true, refreshModels: false };
          await client.rpcRequest('server.refreshProviders', payload as Object, 30000, false);
          if (!this.alive || !client.ready || client.generationValue() !== gen) return;
          this.limitsAutoRefreshedAt.set(env.environmentId, Date.now());
          const ok = await this.fetchOneLimitConfig(env.environmentId, client, seq);
          if (!ok) failed.push(env.label);
        } catch (_) {
          this.limitsAutoRefreshedAt.set(env.environmentId, Date.now());
          failed.push(env.label);
        }
      }),
    );

    if (this.alive && this.limitsRequestSeq === seq) {
      this.failedLimitLabels = failed;
    }
  }

  private selectedTargets(): EnvTarget[] {
    const all = this.targetEnvironments();
    const selected = this.selectedEnvIds;
    if (selected === null) return all;
    return all.filter((env: EnvTarget) => selected.includes(env.environmentId));
  }

  private selectView(nextView: string): void {
    if (this.activeView === nextView) return;
    this.activeView = nextView;
    if (nextView === 'limits') {
      this.syncLimitStreams();
      void this.refreshLimitsProviders(true);
    }
  }

  private selectWindow(days: number): void {
    if (this.windowDays === days) return;
    this.windowDays = days;
    this.windowSpec = makeUsageWindow(days, this.deviceTimeZone());
    void this.loadAllUsage(false);
  }

  private async handlePullRefresh(): Promise<void> {
    if (this.pullRefreshInFlight) return;
    this.pullRefreshInFlight = true;
    this.pullRefreshing = true;
    try {
      if (this.activeView === 'limits') {
        await this.refreshLimitsProviders(false);
      } else {
        this.windowSpec = makeUsageWindow(this.windowDays, this.deviceTimeZone());
        await this.loadAllUsage(true);
      }
    } finally {
      this.pullRefreshInFlight = false;
      if (this.alive) this.pullRefreshing = false;
    }
  }

  private replaceEnvState(
    envId: string,
    isPending: boolean,
    summary: UsageSummaryView | undefined,
    error: string,
    mismatch: '' | 'serverBehind' | 'clientBehind',
  ): void {
    this.envUsageStates = this.envUsageStates.map((item: EnvUsageStatus): EnvUsageStatus => {
      if (item.environmentId !== envId) return item;
      return {
        environmentId: item.environmentId,
        label: item.label,
        isConnected: item.isConnected,
        canReadDiagnostics: item.canReadDiagnostics,
        isPending,
        error,
        incompatibleDirection: mismatch,
        summary,
      };
    });
    this.recomputeUsageView();
  }

  private async loadAllUsage(forceRefresh: boolean): Promise<void> {
    const seq = ++this.usageRequestSeq;
    const targets = this.targetEnvironments();
    const spec = this.windowSpec;
    if (forceRefresh) this.manualRefreshingUsage = true;

    const initial: EnvUsageStatus[] = targets.map((env: EnvTarget): EnvUsageStatus => {
      const prev = this.envUsageStates.find((s: EnvUsageStatus) => s.environmentId === env.environmentId);
      const isConnected = !!env.client?.ready;
      const canRead = isConnected && env.client !== undefined && env.client.canScope('diagnostics:read') !== false;
      return {
        environmentId: env.environmentId,
        label: env.label,
        isConnected,
        canReadDiagnostics: canRead,
        isPending: canRead,
        error: isConnected && !canRead ? '当前连接缺少诊断读取权限。' : '',
        incompatibleDirection: '',
        summary: isConnected ? prev?.summary : undefined,
      };
    });
    this.envUsageStates = initial;
    this.recomputeUsageView();

    try {
      await Promise.all(
        targets.map(async (env: EnvTarget) => {
          const client = env.client;
          if (!client || !client.ready || client.canScope('diagnostics:read') === false) return;
          const gen = client.generationValue();
          const stillValid = (): boolean =>
            this.alive && this.usageRequestSeq === seq && client.ready && client.generationValue() === gen;

          if (forceRefresh) {
            try {
              await client.rpcRequest('server.refreshUsageRates', {} as Record<string, Object>, 15000, false);
            } catch (_) {}
            if (!stillValid()) return;
          }

          try {
            const firstPayload = forceRefresh
              ? usageWindowPayload(spec, { awaitRefresh: true })
              : usageWindowPayload(spec, { provisional: true });
            const firstResult = await this.fetchSummaryWithCompatibilityCheck(client, firstPayload);
            if (!stillValid()) return;
            if (firstResult.mismatchDirection) {
              this.replaceEnvState(
                env.environmentId,
                false,
                firstResult.summary,
                '',
                firstResult.mismatchDirection,
              );
              return;
            }
            const needsRefresh =
              !forceRefresh &&
              (firstResult.summary?.sources || []).some((src: UsageSourceView) => src.refreshing);
            this.replaceEnvState(env.environmentId, needsRefresh, firstResult.summary, '', '');

            if (needsRefresh) {
              const settled = await this.fetchSummaryWithCompatibilityCheck(
                client,
                usageWindowPayload(spec, { awaitRefresh: true }),
              );
              if (!stillValid()) return;
              this.replaceEnvState(
                env.environmentId,
                false,
                settled.summary || firstResult.summary,
                '',
                settled.mismatchDirection || '',
              );
            }
          } catch (_) {
            if (this.alive && this.usageRequestSeq === seq && client.generationValue() === gen) {
              const prev = this.envUsageStates.find((s: EnvUsageStatus) => s.environmentId === env.environmentId);
              this.replaceEnvState(env.environmentId, false, prev?.summary, '此环境未能上报用量。', '');
            }
          }
        }),
      );
    } finally {
      if (this.alive && this.usageRequestSeq === seq) {
        this.manualRefreshingUsage = false;
        this.recomputeUsageView();
      }
    }
  }

  private async fetchSummaryWithCompatibilityCheck(
    client: T3Client,
    payload: Record<string, Object>,
  ): Promise<SummaryCompatResult> {
    const gen = client.generationValue();
    const emptySettings: Record<string, Object> = {};
    const settings =
      client.config.settings !== undefined && client.config.settings !== null
        ? record(client.config.settings)
        : emptySettings;
    const request = cloneRecord(payload);
    if (settings.usageModelFilter !== undefined && settings.usageModelFilter !== null) {
      request.modelFilter = settings.usageModelFilter;
    }
    const raw = await client.rpcRequest('server.getUsageSummary', request, 60000, false);
    if (!client.ready || gen !== client.generationValue()) throw new Error('连接已变更');
    const version = parseUsageSummaryContract(raw);
    if (version < 4) return { mismatchDirection: 'serverBehind' };
    if (version > USAGE_CONTRACT_VERSION) return { mismatchDirection: 'clientBehind' };
    const summary = parseUsageSummary(raw);
    if (request.modelFilter !== undefined && record(raw).modelFilter === undefined) {
      summary.notices.push('服务端未确认模型排除规则，当前返回可能包含被排除模型');
    }
    return { summary };
  }

  private envStatusFor(env: EnvTarget): EnvUsageStatus {
    const found = this.envUsageStates.find((s: EnvUsageStatus) => s.environmentId === env.environmentId);
    if (found) return found;
    return {
      environmentId: env.environmentId,
      label: env.label,
      isConnected: !!env.client?.ready,
      canReadDiagnostics: true,
      isPending: false,
      error: '',
      incompatibleDirection: '',
      summary: undefined,
    };
  }

  private envStatusLabel(env: EnvUsageStatus): string {
    if (env.incompatibleDirection === 'serverBehind') return '服务端版本较旧，已排除在总计外';
    if (env.incompatibleDirection === 'clientBehind') return '客户端版本较旧，无法解析此环境用量';
    if (env.error) return env.summary ? env.error + ' 当前显示已保存总计。' : env.error;
    if (!env.isConnected) return env.summary ? '已断开 · 显示已保存用量' : '等待连接…';
    if (!env.summary) return '正在读取用量…';
    if (this.manualRefreshingUsage) return '正在更新用量…';
    if (env.isPending) {
      const refreshing = (env.summary.sources || []).filter((s: UsageSourceView) => s.refreshing);
      if (refreshing.length === 1 && refreshing[0].provider) {
        return '正在更新 ' + usageProviderLabel(refreshing[0].provider) + '…';
      }
      if (refreshing.length > 1) return '正在更新 ' + refreshing.length + ' 个提供商…';
      return '正在更新用量…';
    }
    return '用量已是最新';
  }

  private providerColor(provider: string): Resource {
    const kind = usageProviderKind(provider);
    if (kind === 'claude') return $r('app.color.usage_claude');
    if (kind === 'grok') return $r('app.color.usage_grok');
    if (kind === 'cursor') return $r('app.color.usage_cursor');
    if (kind === 'opencode') return $r('app.color.usage_opencode');
    if (kind === 'antigravity') return $r('app.color.usage_antigravity');
    if (kind === 'pi') return $r('app.color.usage_pi');
    if (kind === 'muse') return $r('app.color.usage_muse');
    return $r('app.color.usage_codex');
  }

  private limitBarColor(driver: string, accentColor: string): ResourceColor {
    if (accentColor) return accentColor;
    const kind = usageProviderKind(driver);
    if (kind) return this.providerColor(kind);
    return $r('app.color.ink');
  }

  private async openExternalUrl(url: string): Promise<void> {
    if (!/^https?:\/\//i.test(url)) return;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await context.openLink(url);
    } catch (_) {}
  }

  private toggleEnvironment(envId: string): void {
    const ids = this.targetEnvironments().map((item: EnvTarget) => item.environmentId);
    if (envId === 'all') {
      this.selectedEnvIds = null;
    } else {
      this.selectedEnvIds = toggleUsageEnvironmentSelection(this.selectedEnvIds, ids, envId);
    }
    this.recomputeUsageView();
    this.recomputeLimitsView();
  }

  private openAccountDetail(accountKey: string, windowId: string, windowKind: string): void {
    this.selectedAccountKey = accountKey;
    this.selectedWindowId = windowId;
    this.selectedWindowKind = windowKind;
    this.emailRevealed = false;
    this.redeemBusy = false;
    this.redeemStatus = '';
  }

  private closeAccountDetail(): void {
    this.selectedAccountKey = '';
    this.selectedWindowId = '';
    this.selectedWindowKind = '';
    this.emailRevealed = false;
    this.redeemStatus = '';
  }

  private confirmRedeemCredit(account: PooledLimitAccount, choice: ResetCreditChoiceView): void {
    const client = this.findClientForEnvironment(account.redeemEnvironmentId);
    if (!client || !client.ready || client.canScope('providers:manage') === false || this.redeemBusy) return;
    AlertDialog.show({
      title: '使用重置额度？',
      message: choice.confirmDescription,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '确认使用',
        action: () => {
          void this.executeRedeemCredit(client, choice.payload);
        },
      },
    });
  }

  private async executeRedeemCredit(client: T3Client, payload: Record<string, Object>): Promise<void> {
    if (this.redeemBusy) return;
    this.redeemBusy = true;
    this.redeemStatus = '';
    try {
      const result = await consumeUsageResetCredit(client, payload);
      if (!this.alive) return;
      if (result.warning) {
        this.redeemStatus = result.warning;
      } else if (result.outcome === 'reset') {
        this.redeemStatus = '已应用重置，当前限额窗口已清空。';
      } else if (result.outcome === 'nothingToReset') {
        this.redeemStatus = '当前无需重置。';
      } else if (result.outcome === 'noCredit') {
        this.redeemStatus = '没有可用的重置额度。';
      } else if (result.outcome === 'alreadyRedeemed') {
        this.redeemStatus = '该重置额度已被使用。';
      } else {
        this.redeemStatus = '操作已提交，请刷新查看最新额度。';
      }
      void this.refreshLimitsProviders(false);
    } catch (error) {
      if (this.alive) this.redeemStatus = (error as Error).message || '无法使用重置额度。';
    } finally {
      if (this.alive) this.redeemBusy = false;
    }
  }

  private findClientForEnvironment(envId: string): T3Client | undefined {
    const hit = this.targetEnvironments().find((item: EnvTarget) => item.environmentId === envId);
    return hit?.client || this.connection;
  }

  private canManageAccount(account: PooledLimitAccount): boolean {
    const client = this.findClientForEnvironment(account.redeemEnvironmentId);
    return !!client && client.ready && client.canScope('providers:manage') !== false;
  }

  private formatExactDateTime(iso: string): string {
    const date = new Date(iso);
    if (!iso || Number.isNaN(date.getTime())) return '未提供';
    const pad = (n: number): string => String(n).padStart(2, '0');
    return (
      date.getFullYear() +
      '-' +
      pad(date.getMonth() + 1) +
      '-' +
      pad(date.getDate()) +
      ' ' +
      pad(date.getHours()) +
      ':' +
      pad(date.getMinutes())
    );
  }

  private activeMetric(): 'cost' | 'tokens' {
    return this.activeView === 'tokens' ? 'tokens' : 'cost';
  }

  private chartPeriods(): string[] {
    if (this.windowDays === 1 && this.windowSpec.sinceTime && this.windowSpec.untilTime) {
      return enumerateUsageHourStarts(this.windowSpec.sinceTime, this.windowSpec.untilTime);
    }
    return enumerateUsageDays(this.windowSpec.sinceDay, this.windowSpec.untilDay);
  }

  private chartData(): UsagePeriodTotals[] {
    return this.windowDays === 1 ? this.mergedUsage.hourly : this.mergedUsage.daily;
  }

  private chartBars(): UsageChartBar[] {
    return buildUsageChartBars(this.chartPeriods(), this.chartData(), this.activeMetric());
  }

  private chartMaxTotal(): number {
    let peak = 0;
    for (const bar of this.chartBars()) {
      if (bar.total > peak) peak = bar.total;
    }
    return peak;
  }

  private sortedProviders(): UsageProviderTotals[] {
    const metric = this.activeMetric();
    return this.mergedUsage.providers.slice().sort((a: UsageProviderTotals, b: UsageProviderTotals) =>
      metric === 'cost' ? b.costUsd - a.costUsd : b.totalTokens - a.totalTokens,
    );
  }

  private sortedModels(): UsageModelTotals[] {
    const metric = this.activeMetric();
    return this.mergedUsage.models.slice().sort((a: UsageModelTotals, b: UsageModelTotals) =>
      metric === 'cost'
        ? b.costUsd - a.costUsd || b.totalTokens - a.totalTokens
        : b.totalTokens - a.totalTokens || b.costUsd - a.costUsd,
    );
  }

  private firstRestoringResetLabel(pool: PooledLimitWindow): string {
    const reset = pool.resets.find((r: PooledLimitReset) => r.restoresPercent > 0);
    if (!reset) return '';
    const when = formatResetsIn(reset.resetsAt, this.limitsNowMs, true) || '即将';
    return '↻ +' + reset.restoresPercent + '% · ' + when + '后恢复';
  }

  private paceTickXPercent(win: PooledLimitWindowEntry): string {
    const pct = paceRemainingPercent(win, this.limitsNowMs);
    if (pct === null) return '';
    return Math.max(4, Math.min(96, pct)) + '%';
  }

  private resolveDetailContext(): AccountDetailContext {
    const accounts = collectPooledLimitAccounts(this.selectedSnapshots);
    const account = accounts.find((item: PooledLimitAccount) => item.key === this.selectedAccountKey);
    if (!account) return { restoresPercent: 0 };
    const pool = this.pooledGroups
      .find((g: PooledLimitGroup) => g.driver === account.driver)
      ?.windows.find((w: PooledLimitWindow) => w.id === this.selectedWindowId && w.kind === this.selectedWindowKind);
    const col = pool?.columns.find((c: PooledLimitColumn) => c.account.key === account.key);
    const reset = pool?.resets.find((r: PooledLimitReset) => r.accountKey === account.key);
    return {
      account,
      pool,
      window: col?.window,
      restoresPercent: reset ? reset.restoresPercent : 0,
    };
  }

  private totalsRows(): TotalsCellItem[][] {
    const merged = this.mergedUsage;
    const isHourly = this.windowDays === 1;
    const activePeriods = (isHourly ? merged.hourly : merged.daily).filter(
      (period: UsagePeriodTotals) => period.totalTokens > 0,
    ).length;
    const periodAverage = activePeriods === 0 ? 0 : merged.totalTokens / activePeriods;
    const observedInput = merged.uncachedInputTokens + merged.cachedInputTokens;
    const cachedShare = observedInput === 0 ? 0 : merged.cachedInputTokens / observedInput;
    const savingsDetail =
      merged.costUsd > 0
        ? '原始费用的 ' + (merged.cacheSavingsUsd / merged.costUsd).toFixed(1) + 'x'
        : '对比全价输入';

    return [
      [
        {
          label: '已处理 Tokens',
          value: formatUsageTokens(merged.totalTokens),
          detail: formatUsageTokens(periodAverage) + ' / ' + (isHourly ? '活跃小时' : '活跃日'),
        },
        {
          label: '缓存节省',
          value: formatUsageUsd(merged.cacheSavingsUsd),
          detail: savingsDetail,
        },
      ],
      [
        {
          label: '缓存输入',
          value: formatUsageTokens(merged.cachedInputTokens),
          detail: formatUsagePercent(cachedShare) + ' 已观测输入',
        },
        {
          label: '未缓存输入',
          value: formatUsageTokens(merged.uncachedInputTokens),
          detail: formatUsageTokens(merged.cacheCreationTokens) + ' 缓存写入',
        },
      ],
      [
        {
          label: '输出',
          value: formatUsageTokens(merged.outputTokens),
          detail: '含 ' + formatUsageTokens(merged.reasoningTokens) + ' 推理',
        },
        {
          label: '未定价',
          value: formatUsagePercent(merged.unpricedShare),
          detail: '的记录，未计入费用',
        },
      ],
    ];
  }

  private typeMixSegments(): MixSegmentItem[] {
    const merged = this.mergedUsage;
    const items: MixSegmentItem[] = [
      { key: 'input', label: '输入', value: merged.categoryCost.input, color: $r('app.color.usage_mix_input') },
      {
        key: 'cacheRead',
        label: '缓存读取',
        value: merged.categoryCost.cacheRead,
        color: $r('app.color.usage_mix_cache_read'),
      },
      {
        key: 'cacheWrite',
        label: '缓存写入',
        value: merged.categoryCost.cacheWrite,
        color: $r('app.color.usage_mix_cache_write'),
      },
      { key: 'output', label: '输出', value: merged.categoryCost.output, color: $r('app.color.usage_mix_output') },
      {
        key: 'other',
        label: '其他',
        value: merged.categoryCost.unsplit >= 0.005 ? merged.categoryCost.unsplit : 0,
        color: $r('app.color.usage_mix_other'),
      },
    ];
    return items.filter((item: MixSegmentItem) => item.value > 0);
  }

  private speedMixSegments(): MixSegmentItem[] {
    const merged = this.mergedUsage;
    const items: MixSegmentItem[] = [
      { key: 'standard', label: '标准', value: merged.speedCost.standard, color: $r('app.color.usage_mix_standard') },
      { key: 'fast', label: '快速', value: merged.speedCost.fast, color: $r('app.color.usage_mix_fast') },
      { key: 'ultrafast', label: '极速', value: merged.speedCost.ultrafast, color: $r('app.color.usage_mix_ultrafast') },
    ];
    return items.filter((item: MixSegmentItem) => item.value > 0);
  }

  private sumMixSegments(items: MixSegmentItem[]): number {
    let total = 0;
    for (const item of items) total += item.value;
    return total > 0 ? total : 0.0001;
  }

  @Builder
  filterActionButton() {
    if (this.targetEnvironments().length > 0 || this.selectedEnvIds !== null) {
      Stack({ alignContent: Alignment.TopEnd }) {
        IconButton({
          icon: $r('app.media.ui_filter'),
          label: this.selectedEnvIds === null ? '筛选用量环境' : '筛选用量环境（已启用）',
          onTap: () => {
            this.filterSheetOpen = true;
          },
        })
        if (this.selectedEnvIds !== null) {
          Circle()
            .width(6)
            .height(6)
            .fill($r('app.color.primary'))
            .margin({ top: 7, right: 7 })
            .hitTestBehavior(HitTestMode.None)
        }
      }
    }
  }

  @Builder
  sectionLabel(title: string) {
    Text(title)
      .fontSize(FontSize.callout)
      .lineHeight(LineHeight.callout)
      .fontWeight(Weight.medium)
      .fontColor($r('app.color.muted'))
      .padding({ left: Space.md, right: Space.md, bottom: Space.xs })
      .width('100%')
  }

  @Builder
  heroChartCard() {
    Column({ space: Space.md }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column({ space: 2 }) {
          Text(this.activeView === 'tokens' ? '已处理 Tokens' : '原始 Token 费用')
            .fontSize(FontSize.callout)
            .lineHeight(LineHeight.callout)
            .fontColor($r('app.color.muted'))
            .width('100%')
          Text(
            this.activeView === 'tokens'
              ? formatUsageTokens(this.mergedUsage.totalTokens)
              : formatUsageUsd(this.mergedUsage.costUsd) + '*',
          )
            .fontSize(32)
            .lineHeight('38fp')
            .fontWeight(Weight.bold)
            .fontColor($r('app.color.ink'))
            .width('100%')
          Text(
            this.activeView === 'tokens'
              ? '共 ' + formatUsageCount(this.mergedUsage.sessions) + ' 个会话'
              : '* 按完整 API 费率估算',
          )
            .fontSize(FontSize.callout)
            .lineHeight(LineHeight.callout)
            .fontColor($r('app.color.muted'))
            .width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)

        if (this.usageProgressLabel) {
          Row({ space: 6 }) {
            LoadingProgress().width(14).height(14).color($r('app.color.primary_text'))
            Text(this.usageProgressLabel)
              .fontSize(FontSize.caption)
              .fontColor($r('app.color.primary_text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor($r('app.color.info_bg'))
          .borderRadius(Radius.full)
          .constraintSize({ maxWidth: '55%' })
        }
      }.width('100%')

      if (!this.chartData().some((period: UsagePeriodTotals) => period.totalTokens > 0)) {
        Column() {
          Text('此时间段无活动记录')
            .fontSize(FontSize.body)
            .lineHeight(LineHeight.body)
            .fontColor($r('app.color.muted'))
        }
        .width('100%')
        .height(CHART_HEIGHT)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Row({ space: this.windowDays >= 90 ? 1 : 2 }) {
          ForEach(
            this.chartBars(),
            (bar: UsageChartBar) => {
              Column() {
                if (bar.total > 0 && this.chartMaxTotal() > 0) {
                  Column() {
                    ForEach(
                      bar.values.slice().reverse(),
                      (seg: UsageChartSegment) => {
                        if (seg.value > 0) {
                          Row()
                            .width('100%')
                            .layoutWeight(Math.max(1, Math.round((seg.value / bar.total) * 1000)))
                            .backgroundColor(this.providerColor(seg.provider))
                        }
                      },
                      (seg: UsageChartSegment) => seg.provider + ':' + seg.value,
                    )
                  }
                  .width('100%')
                  .height(Math.max(2, Math.round((bar.total / this.chartMaxTotal()) * CHART_HEIGHT)))
                  .borderRadius({ topLeft: 3, topRight: 3 })
                  .clip(true)
                }
              }
              .layoutWeight(1)
              .height(CHART_HEIGHT)
              .justifyContent(FlexAlign.End)
            },
            (bar: UsageChartBar) =>
              bar.period + ':' + bar.total + ':' + this.chartMaxTotal() + ':' + this.activeView + ':' + this.windowDays,
          )
        }
        .width('100%')
        .height(CHART_HEIGHT)
        .alignItems(VerticalAlign.Bottom)
      }

      Column({ space: Space.xs }) {
        Row() {
          Text(
            this.windowDays === 1
              ? formatUsageHourShort(this.chartPeriods()[0] || '', this.windowSpec.timeZone)
              : formatUsageDayShort(this.windowSpec.sinceDay),
          )
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.muted_tertiary'))
          Blank()
          Text(
            this.windowDays === 1
              ? formatUsageHourShort(
                  this.chartPeriods()[this.chartPeriods().length - 1] || '',
                  this.windowSpec.timeZone,
                )
              : formatUsageDayShort(this.windowSpec.untilDay),
          )
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.muted_tertiary'))
        }.width('100%').alignItems(VerticalAlign.Center)

        if (this.mergedUsage.providers.length > 0) {
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            ForEach(
              this.mergedUsage.providers,
              (prov: UsageProviderTotals) => {
                Row({ space: 6 }) {
                  Circle().width(8).height(8).fill(this.providerColor(prov.provider))
                  Text(usageProviderLabel(prov.provider))
                    .fontSize(FontSize.caption)
                    .lineHeight(LineHeight.caption)
                    .fontColor($r('app.color.muted'))
                }.margin({ right: Space.md, bottom: 4 }).alignItems(VerticalAlign.Center)
              },
              (prov: UsageProviderTotals) => prov.provider,
            )
          }.width('100%')
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(Space.md)
    .backgroundColor($r('app.color.group'))
    .borderRadius(24)
    .clip(true)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  providersCard() {
    Column() {
      this.sectionLabel('提供商')
      Column() {
        ForEach(
          this.sortedProviders(),
          (prov: UsageProviderTotals, index: number) => {
            Column({ space: Space.xs }) {
              Row({ space: Space.sm }) {
                Row({ space: Space.xs }) {
                  Circle().width(10).height(10).fill(this.providerColor(prov.provider))
                  Text(usageProviderLabel(prov.provider))
                    .fontSize(FontSize.headline)
                    .lineHeight(LineHeight.headline)
                    .fontColor($r('app.color.ink'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(VerticalAlign.Center)

                Text(
                  this.activeView === 'tokens'
                    ? formatUsageTokens(prov.totalTokens)
                    : formatUsageUsd(prov.costUsd),
                )
                  .fontSize(FontSize.headline)
                  .lineHeight(LineHeight.headline)
                  .fontColor($r('app.color.ink'))
              }.width('100%').alignItems(VerticalAlign.Center)

              Row() {
                if ((this.activeView === 'tokens' ? prov.tokenShare : prov.costShare) > 0) {
                  Row()
                    .height('100%')
                    .width(
                      Math.max(
                        2,
                        Math.min(
                          100,
                          Math.round((this.activeView === 'tokens' ? prov.tokenShare : prov.costShare) * 1000) / 10,
                        ),
                      ) + '%',
                    )
                    .borderRadius(Radius.full)
                    .backgroundColor(this.providerColor(prov.provider))
                }
              }
              .width('100%')
              .height(4)
              .borderRadius(Radius.full)
              .backgroundColor($r('app.color.usage_track'))
              .clip(true)

              Text(
                this.activeView === 'tokens'
                  ? formatUsagePercent(prov.tokenShare) + ' tokens · ' + formatUsageUsd(prov.costUsd)
                  : formatUsagePercent(prov.costShare) + ' 费用 · ' + formatUsageTokens(prov.totalTokens) + ' tokens',
              )
                .fontSize(FontSize.callout)
                .lineHeight(LineHeight.callout)
                .fontColor($r('app.color.muted'))
                .width('100%')
            }
            .width('100%')
            .padding(Space.md)
            .alignItems(HorizontalAlign.Start)
            .border({
              width: { top: index > 0 ? Sizes.hairline : 0 },
              color: { top: $r('app.color.separator') },
            })
          },
          (prov: UsageProviderTotals, index: number) =>
            prov.provider + ':' + index + ':' + prov.costUsd + ':' + prov.totalTokens + ':' + this.activeView,
        )
      }
      .width('100%')
      .backgroundColor($r('app.color.group'))
      .borderRadius(24)
      .clip(true)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  totalsCard() {
    Column() {
      this.sectionLabel('总计')
      Column({ space: Space.lg }) {
        ForEach(
          this.totalsRows(),
          (pair: TotalsCellItem[]) => {
            Row({ space: Space.md }) {
              ForEach(
                pair,
                (cell: TotalsCellItem) => {
                  Column({ space: 2 }) {
                    Text(cell.label)
                      .fontSize(FontSize.callout)
                      .lineHeight(LineHeight.callout)
                      .fontColor($r('app.color.muted'))
                    Text(cell.value)
                      .fontSize(FontSize.title)
                      .lineHeight(LineHeight.title)
                      .fontWeight(Weight.medium)
                      .fontColor($r('app.color.ink'))
                    Text(cell.detail)
                      .fontSize(FontSize.caption)
                      .lineHeight(LineHeight.caption)
                      .fontColor($r('app.color.muted_tertiary'))
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                },
                (cell: TotalsCellItem) => cell.label + ':' + cell.value + ':' + cell.detail,
              )
            }.width('100%').alignItems(VerticalAlign.Top)
          },
          (pair: TotalsCellItem[], idx: number) =>
            String(idx) + ':' + pair[0].value + ':' + pair[1].value + ':' + pair[0].detail,
        )
      }
      .width('100%')
      .padding(Space.md)
      .backgroundColor($r('app.color.group'))
      .borderRadius(24)
      .clip(true)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  costBreakdownCard() {
    if (
      this.mergedUsage.costUsd > 0 &&
      (this.typeMixSegments().length > 0 ||
        (this.mergedUsage.speedCost.fast + this.mergedUsage.speedCost.ultrafast > 0 &&
          this.speedMixSegments().length > 0))
    ) {
      Column() {
        this.sectionLabel('费用构成')
        Column() {
          if (this.typeMixSegments().length > 0) {
            Column({ space: Space.sm }) {
              Text('按类型')
                .fontSize(FontSize.callout)
                .lineHeight(LineHeight.callout)
                .fontColor($r('app.color.muted'))
                .width('100%')

              Row({ space: 2 }) {
                ForEach(
                  this.typeMixSegments(),
                  (seg: MixSegmentItem) => {
                    Row()
                      .height('100%')
                      .layoutWeight(
                        Math.max(
                          1,
                          Math.round((seg.value / this.sumMixSegments(this.typeMixSegments())) * 1000),
                        ),
                      )
                      .borderRadius(3)
                      .backgroundColor(seg.color)
                  },
                  (seg: MixSegmentItem) => seg.key + ':' + seg.value,
                )
              }.width('100%').height(8)

              Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
                ForEach(
                  this.typeMixSegments(),
                  (seg: MixSegmentItem) => {
                    Row({ space: 6 }) {
                      Row().width(8).height(8).borderRadius(2).backgroundColor(seg.color)
                      Text(seg.label)
                        .fontSize(FontSize.callout)
                        .lineHeight(LineHeight.callout)
                        .fontColor($r('app.color.muted'))
                      Text(formatUsageUsd(seg.value))
                        .fontSize(FontSize.callout)
                        .lineHeight(LineHeight.callout)
                        .fontColor($r('app.color.ink'))
                    }.margin({ right: Space.md, bottom: 6 }).alignItems(VerticalAlign.Center)
                  },
                  (seg: MixSegmentItem) => seg.key + ':' + seg.value,
                )
              }.width('100%')
            }.width('100%').padding(Space.md).alignItems(HorizontalAlign.Start)
          }

          if (
            this.mergedUsage.speedCost.fast + this.mergedUsage.speedCost.ultrafast > 0 &&
            this.speedMixSegments().length > 0
          ) {
            Column() {
              if (this.typeMixSegments().length > 0) {
                Divider().color($r('app.color.separator')).strokeWidth(Sizes.hairline)
              }
              Column({ space: Space.sm }) {
                Row({ space: Space.sm }) {
                  Text('按速度')
                    .fontSize(FontSize.callout)
                    .lineHeight(LineHeight.callout)
                    .fontColor($r('app.color.muted'))
                    .layoutWeight(1)
                  Text(formatUsageUsd(this.mergedUsage.speedCost.premium) + ' 溢价')
                    .fontSize(FontSize.callout)
                    .lineHeight(LineHeight.callout)
                    .fontColor($r('app.color.muted'))
                }.width('100%').alignItems(VerticalAlign.Center)

                Row({ space: 2 }) {
                  ForEach(
                    this.speedMixSegments(),
                    (seg: MixSegmentItem) => {
                      Row()
                        .height('100%')
                        .layoutWeight(
                          Math.max(
                            1,
                            Math.round((seg.value / this.sumMixSegments(this.speedMixSegments())) * 1000),
                          ),
                        )
                        .borderRadius(3)
                        .backgroundColor(seg.color)
                    },
                    (seg: MixSegmentItem) => seg.key + ':' + seg.value,
                  )
                }.width('100%').height(8)

                Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
                  ForEach(
                    this.speedMixSegments(),
                    (seg: MixSegmentItem) => {
                      Row({ space: 6 }) {
                        Row().width(8).height(8).borderRadius(2).backgroundColor(seg.color)
                        Text(seg.label)
                          .fontSize(FontSize.callout)
                          .lineHeight(LineHeight.callout)
                          .fontColor($r('app.color.muted'))
                        Text(formatUsageUsd(seg.value))
                          .fontSize(FontSize.callout)
                          .lineHeight(LineHeight.callout)
                          .fontColor($r('app.color.ink'))
                      }.margin({ right: Space.md, bottom: 6 }).alignItems(VerticalAlign.Center)
                    },
                    (seg: MixSegmentItem) => seg.key + ':' + seg.value,
                  )
                }.width('100%')
              }.width('100%').padding(Space.md).alignItems(HorizontalAlign.Start)
            }.width('100%')
          }
        }
        .width('100%')
        .backgroundColor($r('app.color.group'))
        .borderRadius(24)
        .clip(true)
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  modelsCard() {
    if (this.mergedUsage.models.length > 0) {
      Column() {
        this.sectionLabel('按模型')
        Column() {
          ForEach(
            this.sortedModels(),
            (item: UsageModelTotals, index: number) => {
              Row({ space: Space.sm }) {
                Circle().width(10).height(10).fill(this.providerColor(item.provider))
                Column({ space: 2 }) {
                  Text(item.model)
                    .fontSize(FontSize.body)
                    .lineHeight(LineHeight.body)
                    .fontColor($r('app.color.ink'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(
                    this.activeView === 'tokens'
                      ? formatUsagePercent(item.tokenShare) +
                          ' tokens · ' +
                          (item.costUnknown ? '暂无费率' : formatUsageUsd(item.costUsd))
                      : item.costUnknown
                        ? '暂无费率 · ' + formatUsageTokens(item.totalTokens) + ' tokens'
                        : formatUsagePercent(item.costShare) +
                            ' 费用 · ' +
                            formatUsageTokens(item.totalTokens) +
                            ' tokens',
                  )
                    .fontSize(FontSize.callout)
                    .lineHeight(LineHeight.callout)
                    .fontColor($r('app.color.muted'))
                    .width('100%')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)

                Text(
                  this.activeView === 'tokens'
                    ? formatUsageTokens(item.totalTokens)
                    : item.costUnknown
                      ? '未定价'
                      : formatUsageUsd(item.costUsd),
                )
                  .fontSize(FontSize.body)
                  .lineHeight(LineHeight.body)
                  .fontColor($r('app.color.ink'))
                  .flexShrink(0)
              }
              .width('100%')
              .padding(Space.md)
              .alignItems(VerticalAlign.Center)
              .border({
                width: { top: index > 0 ? Sizes.hairline : 0 },
                color: { top: $r('app.color.separator') },
              })
            },
            (item: UsageModelTotals, index: number) =>
              item.provider + ':' + item.model + ':' + index + ':' + item.costUsd + ':' + item.totalTokens + ':' + this.activeView,
          )
        }
        .width('100%')
        .backgroundColor($r('app.color.group'))
        .borderRadius(24)
        .clip(true)
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  chatGptSharedRow() {
    ForEach(
      this.externalLinks.filter((item: UsageExternalLink) => item.url === CHATGPT_USAGE_URL),
      (link: UsageExternalLink) => {
        Column({ space: 4 }) {
          Row({ space: Space.sm }) {
            Row({ space: Space.xs }) {
              ProviderLogo({ driver: 'codex', logoSize: 16 })
              Text('ChatGPT 共享用量')
                .fontSize(FontSize.callout)
                .lineHeight(LineHeight.callout)
                .fontColor($r('app.color.ink'))
            }.layoutWeight(1).alignItems(VerticalAlign.Center)

            Button({ type: ButtonType.Normal }) {
              Text('管理用量')
                .fontSize(FontSize.callout)
                .fontWeight(Weight.medium)
                .fontColor($r('app.color.primary_text'))
            }
            .backgroundColor(Color.Transparent)
            .constraintSize({ minHeight: 36 })
            .onClick(() => {
              void this.openExternalUrl(link.url);
            })
          }.width('100%').alignItems(VerticalAlign.Center)

          Text(link.accounts.join('、') + '。请使用关联的账号打开 ChatGPT 查看。')
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.muted'))
            .width('100%')
        }
        .width('100%')
        .padding({ left: Space.xxs, right: Space.xxs })
        .alignItems(HorizontalAlign.Start)
      },
      (link: UsageExternalLink) => link.url + ':' + link.accounts.join(','),
    )
  }

  @Builder
  usageTabContent() {
    Column({ space: Space.lg }) {
      UsageSegmentedControl({
        options: WINDOW_OPTIONS,
        selected: String(this.windowDays),
        compact: true,
        onSelect: (value: string) => this.selectWindow(Number(value)),
      })

      this.chatGptSharedRow()

      if (this.mergedUsage.duplicateSources.length > 0) {
        Text('跨环境共享同一记录目录的来源仅计入一次：' + this.mergedUsage.duplicateSources.join('、'))
          .fontSize(FontSize.callout)
          .lineHeight(LineHeight.callout)
          .fontColor($r('app.color.muted'))
          .width('100%')
      }

      if (this.usagePending) {
        Column() {
          Text('正在扫描提供商用量记录…')
            .fontSize(FontSize.body)
            .lineHeight(LineHeight.body)
            .fontColor($r('app.color.muted'))
        }.width('100%').padding({ top: 56, bottom: 56 }).alignItems(HorizontalAlign.Center)
      } else if (this.selectedEnvs.length === 0) {
        Column() {
          Text(this.targetEnvironments().length === 0 ? '请先连接一个环境以查看用量。' : '请选择至少一个环境以查看用量。')
            .fontSize(FontSize.body)
            .lineHeight(LineHeight.body)
            .fontColor($r('app.color.muted'))
        }.width('100%').padding({ top: 56, bottom: 56 }).alignItems(HorizontalAlign.Center)
      } else if (!this.selectedEnvs.some((env: EnvUsageStatus) => env.canReadDiagnostics)) {
        Column({ space: Space.xs }) {
          ForEach(
            this.selectedEnvs,
            (env: EnvUsageStatus) => {
              Text((this.selectedEnvs.length > 1 ? env.label + ': ' : '') + (env.error || this.envStatusLabel(env)))
                .fontSize(FontSize.body)
                .lineHeight(LineHeight.body)
                .fontColor($r('app.color.muted'))
                .textAlign(TextAlign.Center)
                .width('100%')
            },
            (env: EnvUsageStatus) => env.environmentId + ':' + env.error,
          )
        }.width('100%').padding({ top: 56, bottom: 56 }).alignItems(HorizontalAlign.Center)
      } else {
        ForEach(
          this.usageSourceWarns,
          (msg: string) => {
            Text(msg)
              .fontSize(FontSize.callout)
              .lineHeight(LineHeight.callout)
              .fontColor($r('app.color.muted'))
              .width('100%')
          },
          (msg: string) => msg,
        )

        ForEach(
          this.mergedUsage.contractMismatches,
          (mismatch: UsageContractMismatch) => {
            Text(
              mismatch.direction === 'serverBehind'
                ? mismatch.label + ' 运行的桌面服务端版本较旧，已排除在总计外。'
                : '当前客户端版本低于 ' + mismatch.label + ' 服务端，其用量已排除在总计外。',
            )
              .fontSize(FontSize.callout)
              .lineHeight(LineHeight.callout)
              .fontColor($r('app.color.warning'))
              .width('100%')
          },
          (mismatch: UsageContractMismatch) => mismatch.environmentId + ':' + mismatch.contractVersion,
        )

        Column({ space: Space.lg }) {
          this.heroChartCard()
          if (this.mergedUsage.providers.length > 0) {
            this.providersCard()
          }
          this.totalsCard()
          this.costBreakdownCard()
          this.modelsCard()
        }
        .width('100%')
        .opacity(this.usageDimmed ? 0.5 : 1)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  poolWindowCard(group: PooledLimitGroup, pool: PooledLimitWindow) {
    Column({ space: Space.sm }) {
      Row({ space: Space.sm }) {
        Column({ space: 2 }) {
          if (!pool.hideLabel && pool.label) {
            Text(pool.label)
              .fontSize(FontSize.callout)
              .lineHeight(LineHeight.callout)
              .fontWeight(Weight.medium)
              .fontColor($r('app.color.ink'))
          }
          Row({ space: 6 }) {
            Text(pool.remainingPercent + '%')
              .fontSize(28)
              .lineHeight('34fp')
              .fontWeight(Weight.bold)
              .fontColor($r('app.color.ink'))
            Text('剩余')
              .fontSize(FontSize.callout)
              .lineHeight(LineHeight.callout)
              .fontColor($r('app.color.muted'))
          }.alignItems(VerticalAlign.Bottom)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)

        if (pool.pace) {
          Text(paceLabel(pool.pace))
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.muted_tertiary'))
        }
      }.width('100%').alignItems(VerticalAlign.Top)

      if (pool.description) {
        Text(pool.description)
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.muted'))
          .width('100%')
      }

      if (this.firstRestoringResetLabel(pool)) {
        Text(this.firstRestoringResetLabel(pool))
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.muted'))
          .width('100%')
      }

      Row({ space: 4 }) {
        ForEach(
          pool.columns,
          (col: PooledLimitColumn, index: number) => {
            if (!col.window) {
              Column().layoutWeight(1).height(28)
            } else {
              Stack({ alignContent: Alignment.Center }) {
                Row().width('100%').height('100%').backgroundColor($r('app.color.usage_track'))

                if (col.window.resetsAt && col.refillPercent > 0) {
                  Row() {
                    Row()
                      .width(Math.min(100 - col.window.remaining, col.refillPercent) + '%')
                      .height('100%')
                      .backgroundColor(this.limitBarColor(group.driver, col.account.accentColor))
                      .opacity(0.16)
                  }.width('100%').height('100%').justifyContent(FlexAlign.End)
                }

                Row() {
                  Row()
                    .width(col.window.remaining + '%')
                    .height('100%')
                    .backgroundColor(this.limitBarColor(group.driver, col.account.accentColor))
                    .opacity(0.38)
                }.width('100%').height('100%').justifyContent(FlexAlign.Start)

                if (this.paceTickXPercent(col.window)) {
                  Row()
                    .width(2)
                    .height(22)
                    .borderRadius(1)
                    .backgroundColor($r('app.color.ink'))
                    .markAnchor({ x: 1, y: 0 })
                    .position({ x: this.paceTickXPercent(col.window), y: 3 })
                }

                Text(String(index + 1))
                  .fontSize(FontSize.caption)
                  .fontWeight(Weight.medium)
                  .fontColor($r('app.color.ink'))
              }
              .layoutWeight(1)
              .height(28)
              .borderRadius(6)
              .clip(true)
              .accessibilityGroup(true)
              .accessibilityText(
                '分段 ' + (index + 1) + '，' + accountDisplayName(col.account) + '，剩余 ' + col.window.remaining + '%',
              )
              .onClick(() => this.openAccountDetail(col.account.key, pool.id, pool.kind))
            }
          },
          (col: PooledLimitColumn) =>
            col.account.key + ':' + (col.window ? col.window.remaining + ':' + col.refillPercent : 'empty') + ':' + this.limitsNowMs,
        )
      }.width('100%')

      Column() {
        ForEach(
          pool.columns,
          (col: PooledLimitColumn, index: number) => {
            if (col.window) {
              Row({ space: Space.xs }) {
                Stack({ alignContent: Alignment.Center }) {
                  Row().width('100%').height('100%').backgroundColor($r('app.color.tab_bar_active'))
                  Row()
                    .width('100%')
                    .height('100%')
                    .backgroundColor(this.limitBarColor(group.driver, col.account.accentColor))
                    .opacity(0.38)
                  Text(String(index + 1))
                    .fontSize(FontSize.caption)
                    .fontWeight(Weight.medium)
                    .fontColor($r('app.color.ink'))
                }.width(20).height(20).borderRadius(6).clip(true)

                Text(accountDisplayName(col.account))
                  .fontSize(FontSize.callout)
                  .fontWeight(Weight.medium)
                  .fontColor($r('app.color.ink'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)

                Text(col.window.remaining + '%')
                  .fontSize(FontSize.callout)
                  .fontWeight(Weight.medium)
                  .fontColor($r('app.color.ink'))

                if (formatResetsIn(col.window.resetsAt, this.limitsNowMs, true)) {
                  Text('↻ ' + formatResetsIn(col.window.resetsAt, this.limitsNowMs, true))
                    .fontSize(FontSize.caption)
                    .fontColor($r('app.color.muted'))
                }

                if ((col.account.resetCredits?.availableCount || 0) > 0) {
                  Text('· ' + (col.account.resetCredits?.availableCount || 0) + ' 次重置')
                    .fontSize(FontSize.caption)
                    .fontWeight(Weight.medium)
                    .fontColor($r('app.color.ink'))
                }
              }
              .width('100%')
              .constraintSize({ minHeight: 44 })
              .alignItems(VerticalAlign.Center)
              .accessibilityGroup(true)
              .accessibilityText(
                accountDisplayName(col.account) + '，剩余 ' + col.window.remaining + '%，点击查看账号详情',
              )
              .onClick(() => this.openAccountDetail(col.account.key, pool.id, pool.kind))
            }
          },
          (col: PooledLimitColumn) =>
            col.account.key + ':' + (col.window ? col.window.remaining : -1) + ':' + this.limitsNowMs,
        )
      }.width('100%')
    }
    .width('100%')
    .padding(Space.md)
    .backgroundColor($r('app.color.group'))
    .borderRadius(24)
    .clip(true)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  limitsTabContent() {
    Column({ space: Space.lg }) {
      if (
        this.pooledGroups.length === 0 &&
        this.pooledNotices.length === 0 &&
        this.failedLimitLabels.length === 0 &&
        this.externalLinks.length === 0
      ) {
        Column() {
          Text(
            this.selectedSnapshots.length === 0
              ? '请选择已连接环境以查看订阅限额。'
              : '当前所选环境暂无提供商上报订阅限额。',
          )
            .fontSize(FontSize.body)
            .lineHeight(LineHeight.body)
            .fontColor($r('app.color.muted'))
            .textAlign(TextAlign.Center)
        }.width('100%').padding({ top: 48, bottom: 48 }).alignItems(HorizontalAlign.Center)
      }

      ForEach(
        this.pooledGroups,
        (group: PooledLimitGroup) => {
          Column({ space: Space.sm }) {
            Row({ space: Space.xs }) {
              ProviderLogo({ driver: group.driver, logoSize: 18 })
              Text(usageProviderLabel(group.driver))
                .fontSize(FontSize.body)
                .lineHeight(LineHeight.body)
                .fontWeight(Weight.medium)
                .fontColor($r('app.color.ink'))
            }.padding({ left: Space.xxs, right: Space.xxs }).alignItems(VerticalAlign.Center)

            ForEach(
              group.windows,
              (pool: PooledLimitWindow) => {
                this.poolWindowCard(group, pool)
              },
              (pool: PooledLimitWindow) =>
                pool.kind + ':' + pool.id + ':' + pool.remainingPercent + ':' + pool.pace + ':' + this.limitsNowMs,
            )
          }.width('100%').alignItems(HorizontalAlign.Start)
        },
        (group: PooledLimitGroup) => group.driver + ':' + group.windows.length + ':' + this.limitsNowMs,
      )

      ForEach(
        this.externalLinks,
        (link: UsageExternalLink) => {
          Column({ space: Space.xs }) {
            Text(link.label)
              .fontSize(FontSize.body)
              .fontWeight(Weight.medium)
              .fontColor($r('app.color.ink'))
            Text(link.accounts.join('、'))
              .fontSize(FontSize.caption)
              .fontColor($r('app.color.muted'))
            if (link.message) {
              Text(link.message)
                .fontSize(FontSize.callout)
                .fontColor($r('app.color.muted'))
            }
            Button({ type: ButtonType.Normal }) {
              Text('管理用量')
                .fontSize(FontSize.callout)
                .fontWeight(Weight.medium)
                .fontColor($r('app.color.primary_text'))
            }
            .backgroundColor(Color.Transparent)
            .constraintSize({ minHeight: 40 })
            .onClick(() => {
              void this.openExternalUrl(link.url);
            })
          }
          .width('100%')
          .padding(Space.md)
          .alignItems(HorizontalAlign.Start)
          .border({ width: Sizes.hairline, color: $r('app.color.separator') })
          .borderRadius(Radius.card)
        },
        (link: UsageExternalLink) => link.url + ':' + link.accounts.join(','),
      )

      if (this.pooledNotices.length > 0 || this.failedLimitLabels.length > 0) {
        Column({ space: 4 }) {
          ForEach(
            this.pooledNotices,
            (notice: string) => {
              Text(notice)
                .fontSize(FontSize.callout)
                .lineHeight(LineHeight.callout)
                .fontWeight(Weight.medium)
                .fontColor($r('app.color.warning'))
                .width('100%')
            },
            (notice: string) => notice,
          )
          if (this.failedLimitLabels.length > 0) {
            Text(this.failedLimitLabels.join('、') + ' 刷新限额失败，当前显示上次已知数据。')
              .fontSize(FontSize.callout)
              .lineHeight(LineHeight.callout)
              .fontWeight(Weight.medium)
              .fontColor($r('app.color.warning'))
              .width('100%')
          }
        }
        .width('100%')
        .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
        .backgroundColor($r('app.color.warning_bg'))
        .border({ width: Sizes.hairline, color: $r('app.color.warning_border') })
        .borderRadius(Radius.card)
        .alignItems(HorizontalAlign.Start)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  accountDetailView() {
    Scroll() {
      Column({ space: Space.lg }) {
        if (!this.resolveDetailContext().account || !this.resolveDetailContext().window) {
          Text('此账号已不再在所选环境中上报限额。')
            .fontSize(FontSize.body)
            .lineHeight(LineHeight.body)
            .fontColor($r('app.color.muted'))
            .width('100%')
        } else {
          Column({ space: Space.xs }) {
            Row({ space: Space.xs }) {
              ProviderLogo({ driver: this.resolveDetailContext().account!.driver, logoSize: 24 })
              Text(
                this.resolveDetailContext().account!.displayName ||
                  usageProviderLabel(this.resolveDetailContext().account!.driver),
              )
                .fontSize(FontSize.title)
                .lineHeight(LineHeight.title)
                .fontWeight(Weight.bold)
                .fontColor($r('app.color.ink'))
                .layoutWeight(1)
            }.width('100%').alignItems(VerticalAlign.Center)

            if (this.resolveDetailContext().account!.email) {
              Button({ type: ButtonType.Normal }) {
                Text(
                  this.emailRevealed
                    ? this.resolveDetailContext().account!.email
                    : maskAccountEmail(this.resolveDetailContext().account!.email),
                )
                  .fontSize(FontSize.callout)
                  .lineHeight(LineHeight.callout)
                  .fontColor($r('app.color.muted'))
                  .width('100%')
                  .textAlign(TextAlign.Start)
              }
              .width('100%')
              .constraintSize({ minHeight: 40 })
              .backgroundColor(Color.Transparent)
              .accessibilityText(this.emailRevealed ? '隐藏账号邮箱' : '显示账号邮箱')
              .onClick(() => {
                this.emailRevealed = !this.emailRevealed;
              })
            }

            if (this.resolveDetailContext().account!.plan) {
              Text(this.resolveDetailContext().account!.plan)
                .fontSize(FontSize.callout)
                .lineHeight(LineHeight.callout)
                .fontColor($r('app.color.muted'))
                .width('100%')
                .copyOption(CopyOptions.LocalDevice)
            }
          }.width('100%').alignItems(HorizontalAlign.Start)

          Column({ space: Space.xs }) {
            Text(this.resolveDetailContext().window!.label)
              .fontSize(FontSize.callout)
              .fontWeight(Weight.medium)
              .fontColor($r('app.color.ink'))
            Text(this.resolveDetailContext().window!.remaining + '% 剩余')
              .fontSize(28)
              .lineHeight('34fp')
              .fontWeight(Weight.bold)
              .fontColor($r('app.color.ink'))
            if (this.resolveDetailContext().window!.resetsAt) {
              Text('重置时间：' + this.formatExactDateTime(this.resolveDetailContext().window!.resetsAt))
                .fontSize(FontSize.callout)
                .fontColor($r('app.color.muted'))
                .copyOption(CopyOptions.LocalDevice)
            }
            if (paceRemainingPercent(this.resolveDetailContext().window!, this.limitsNowMs) !== null) {
              Text('均衡节奏参考：此时应剩 ' + paceRemainingPercent(this.resolveDetailContext().window!, this.limitsNowMs) + '%')
                .fontSize(FontSize.callout)
                .fontColor($r('app.color.muted'))
            }
            if (this.resolveDetailContext().restoresPercent > 0) {
              Text('重置后将恢复池中 ' + this.resolveDetailContext().restoresPercent + '% 额度')
                .fontSize(FontSize.callout)
                .fontColor($r('app.color.muted'))
            }
            if (this.resolveDetailContext().account!.checkedAt) {
              Text('检查时间：' + this.formatExactDateTime(this.resolveDetailContext().account!.checkedAt))
                .fontSize(FontSize.caption)
                .fontColor($r('app.color.muted_tertiary'))
            }
            if (this.resolveDetailContext().window!.outOfRange) {
              Text('服务端比例超出契约范围，已按边界显示')
                .fontSize(FontSize.caption)
                .fontColor($r('app.color.warning'))
            }
          }
          .width('100%')
          .padding(Space.md)
          .backgroundColor($r('app.color.group'))
          .borderRadius(24)
          .alignItems(HorizontalAlign.Start)

          Column({ space: Space.xs }) {
            Text(this.resolveDetailContext().account!.environments.length > 0 ? '已登录环境' : '限额来源')
              .fontSize(FontSize.callout)
              .fontWeight(Weight.medium)
              .fontColor($r('app.color.ink'))
            if (this.resolveDetailContext().account!.environments.length > 0) {
              ForEach(
                this.resolveDetailContext().account!.environments,
                (envRef: PooledLimitEnvironmentRef) => {
                  Text(envRef.label)
                    .fontSize(FontSize.callout)
                    .fontColor($r('app.color.muted'))
                },
                (envRef: PooledLimitEnvironmentRef) => envRef.environmentId,
              )
            } else {
              Text(this.resolveDetailContext().account!.sourceLabel || 'CLI Proxy')
                .fontSize(FontSize.callout)
                .fontColor($r('app.color.muted'))
            }
          }
          .width('100%')
          .padding(Space.md)
          .backgroundColor($r('app.color.group'))
          .borderRadius(24)
          .alignItems(HorizontalAlign.Start)

          if (this.resolveDetailContext().account!.resetCredits && this.resolveDetailContext().account!.redeemPayload) {
            Column({ space: Space.sm }) {
              Text('重置额度')
                .fontSize(FontSize.callout)
                .fontWeight(Weight.medium)
                .fontColor($r('app.color.ink'))
              ForEach(
                resetCreditChoicesForAccount(
                  this.resolveDetailContext().account!.resetCredits!,
                  this.resolveDetailContext().account!.redeemPayload!,
                  this.limitsNowMs,
                ),
                (choice: ResetCreditChoiceView) => {
                  Row({ space: Space.sm }) {
                    Text(choice.summary)
                      .fontSize(FontSize.caption)
                      .fontColor($r('app.color.muted'))
                      .layoutWeight(1)
                    if (choice.availableCount > 0) {
                      Button({ type: ButtonType.Normal }) {
                        Text(this.redeemBusy ? '使用中…' : choice.actionLabel)
                          .fontSize(FontSize.callout)
                          .fontWeight(Weight.medium)
                          .fontColor($r('app.color.ink'))
                      }
                      .padding({ left: Space.sm, right: Space.sm })
                      .constraintSize({ minHeight: 40 })
                      .borderRadius(Radius.full)
                      .backgroundColor($r('app.color.tab_bar_active'))
                      .enabled(!this.redeemBusy && this.canManageAccount(this.resolveDetailContext().account!))
                      .opacity(
                        this.redeemBusy || !this.canManageAccount(this.resolveDetailContext().account!)
                          ? Opacity.disabled
                          : 1,
                      )
                      .onClick(() => this.confirmRedeemCredit(this.resolveDetailContext().account!, choice))
                    }
                  }.width('100%').alignItems(VerticalAlign.Center)
                },
                (choice: ResetCreditChoiceView) => choice.key + ':' + choice.availableCount,
              )
              if (!this.canManageAccount(this.resolveDetailContext().account!)) {
                Text('当前连接无权管理 Provider 账号。')
                  .fontSize(FontSize.caption)
                  .fontColor($r('app.color.muted'))
              }
              if (this.redeemStatus) {
                Text(this.redeemStatus)
                  .fontSize(FontSize.callout)
                  .fontColor($r('app.color.ink'))
              }
            }
            .width('100%')
            .padding(Space.md)
            .backgroundColor($r('app.color.group'))
            .borderRadius(24)
            .alignItems(HorizontalAlign.Start)
          }
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: Space.page, right: Space.page, top: Space.md, bottom: 28 })
    }.width('100%').height('100%').align(Alignment.TopStart)
  }

  @Builder
  environmentFilterSheet() {
    Column({ space: 0 }) {
      TopBar({
        title: '筛选用量环境',
        showBack: true,
        closeStyle: true,
        backLabel: '关闭筛选',
        onBack: () => {
          this.filterSheetOpen = false;
        },
      })
      Scroll() {
        Column({ space: Space.md }) {
          Column() {
            Row({ space: Space.sm }) {
              Text('全部环境')
                .fontSize(FontSize.body)
                .fontColor($r('app.color.ink'))
                .layoutWeight(1)
              if (this.selectedEnvIds === null) {
                Text('✓')
                  .fontSize(FontSize.headline)
                  .fontWeight(Weight.semibold)
                  .fontColor($r('app.color.primary_text'))
              }
            }
            .width('100%')
            .constraintSize({ minHeight: Sizes.formRowMin })
            .padding({ left: Space.md, right: Space.md, top: Space.xs, bottom: Space.xs })
            .alignItems(VerticalAlign.Center)
            .onClick(() => this.toggleEnvironment('all'))

            ForEach(
              this.targetEnvironments(),
              (env: EnvTarget) => {
                Row({ space: Space.sm }) {
                  Column({ space: 2 }) {
                    Text(env.label)
                      .fontSize(FontSize.body)
                      .fontColor($r('app.color.ink'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                    Text(this.envStatusLabel(this.envStatusFor(env)))
                      .fontSize(FontSize.caption)
                      .fontColor($r('app.color.muted'))
                      .width('100%')
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)

                  if (this.selectedEnvIds === null || this.selectedEnvIds.includes(env.environmentId)) {
                    Text('✓')
                      .fontSize(FontSize.headline)
                      .fontWeight(Weight.semibold)
                      .fontColor($r('app.color.primary_text'))
                  }
                }
                .width('100%')
                .constraintSize({ minHeight: Sizes.formRowMin })
                .padding({ left: Space.md, right: Space.md, top: Space.xs, bottom: Space.xs })
                .alignItems(VerticalAlign.Center)
                .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
                .onClick(() => this.toggleEnvironment(env.environmentId))
              },
              (env: EnvTarget) =>
                env.environmentId +
                ':' +
                this.envStatusLabel(this.envStatusFor(env)) +
                ':' +
                (this.selectedEnvIds === null ? 'all' : this.selectedEnvIds.join(',')),
            )
          }
          .width('100%')
          .backgroundColor($r('app.color.card'))
          .borderRadius(Radius.card)
          .clip(true)

          AppButton({
            label: '立即刷新',
            kind: 'secondary',
            fill: true,
            onTap: () => {
              this.filterSheetOpen = false;
              void this.handlePullRefresh();
            },
          })
        }
        .width('100%')
        .padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.lg })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.group'))
    .foregroundColor($r('app.color.ink'))
  }

  build() {
    Column({ space: 0 }) {
      if (this.selectedAccountKey.length > 0) {
        TopBar({
          title: '账号详情',
          showBack: true,
          backLabel: '返回限额',
          onBack: () => this.closeAccountDetail(),
        })
      } else if (!this.embedded) {
        TopBar({
          title: '用量',
          showBack: true,
          closeStyle: true,
          backLabel: '返回',
          onBack: () => this.onBack(),
        }) {
          this.filterActionButton()
        }
      } else {
        Row() {
          Text('用量')
            .fontSize(FontSize.title)
            .lineHeight(LineHeight.title)
            .fontWeight(Weight.semibold)
            .fontColor($r('app.color.ink'))
            .layoutWeight(1)
          this.filterActionButton()
        }
        .width('100%')
        .constraintSize({ minHeight: Sizes.topBar })
        .padding({ left: Space.page, right: Space.xs, top: Space.xxs, bottom: Space.xxs })
        .alignItems(VerticalAlign.Center)
      }

      Column() {
        if (this.selectedAccountKey.length > 0) {
          this.accountDetailView()
        } else {
          Refresh({ refreshing: $$this.pullRefreshing }) {
            Scroll() {
              Column({ space: Space.lg }) {
                UsageSegmentedControl({
                  options: VIEW_OPTIONS,
                  selected: this.activeView,
                  compact: false,
                  onSelect: (value: string) => this.selectView(value),
                })

                if (this.activeView === 'limits') {
                  this.limitsTabContent()
                } else {
                  this.usageTabContent()
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({
                left: Space.page,
                right: Space.page,
                top: Space.md,
                bottom: 24 + (this.embedded ? this.bottomInset : 0),
              })
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Off)
            .align(Alignment.TopStart)
          }
          .width('100%')
          .height('100%')
          .onRefreshing(() => {
            void this.handlePullRefresh();
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('app.color.screen'))
      .borderRadius({ topLeft: 26, topRight: 26 })
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.group'))
    .foregroundColor($r('app.color.ink'))
    .bindSheet($$this.filterSheetOpen, this.environmentFilterSheet(), {
      height: '58%',
      showClose: false,
      backgroundColor: $r('app.color.group'),
    })
  }
}
