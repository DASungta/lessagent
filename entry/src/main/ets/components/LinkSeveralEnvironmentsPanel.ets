import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { LinkAccessChoice, linkAccessChoices } from '../protocol/Core';
import { EnvironmentEntry, environmentRoutes, DirectRoute } from '../protocol/Environment';
import { linkReachableAddresses } from '../protocol/LinkTarget';
import {
  linkBatchBlockLabel,
  LinkBatchCandidate,
  linkBatchCandidates,
  linkBatchFailureLabel,
  LinkBatchMachine,
  LinkBatchOutcome,
  linkBatchSummary,
  LinkListState,
  PeerLinkCreateInput,
  runLinkBatch
} from '../protocol/LinkBatch';
import { T3Client } from '../services/T3Client';
import { AppButton } from './ui/AppButton';
import { FormRow } from './ui/FormRow';
import { GroupCard } from './ui/GroupCard';
import { StatusBadge } from './ui/StatusBadge';
import { TopBar } from './ui/TopBar';

@Component
export struct LinkSeveralEnvironmentsPanel {
  @Prop sourceLocalId: string = '';
  @Prop sourceLabel: string = '';
  @Prop entries: EnvironmentEntry[] = [];
  connectionFor: (localId: string) => T3Client | undefined = () => undefined;
  onClose: () => void = () => {};
  onLinked: () => void = () => {};

  @State private linksState: LinkListState = 'loading';
  @State private candidates: LinkBatchCandidate[] = [];
  @State private selectedIds: string[] = [];
  @State private access: string = 'approval-required';
  @State private running: boolean = false;
  @State private outcomes: Record<string, LinkBatchOutcome> = {};
  @State private summaryText: string = '';
  @State private loadError: string = '';
  private inFlight: boolean = false;
  private loadSeq: number = 0;

  aboutToAppear(): void {
    void this.loadCandidates();
  }

  aboutToDisappear(): void {
    this.loadSeq += 1;
  }

  private async loadCandidates(): Promise<void> {
    const seq = ++this.loadSeq;
    this.linksState = 'loading';
    this.loadError = '';
    const sourceClient = this.connectionFor(this.sourceLocalId);
    if (!sourceClient || !sourceClient.ready) {
      this.linksState = 'failed';
      this.loadError = '源环境未连接，无法读取已有链接';
      return;
    }
    let linkedIds: string[] = [];
    try {
      await sourceClient.refreshPeerAccess();
      const links = await sourceClient.linkedEnvironments();
      linkedIds = links.filter((l) => l.status !== 'expired' && l.expiresAt > Date.now()).map((l) => l.environmentId);
    } catch (error) {
      if (seq !== this.loadSeq) return;
      this.linksState = 'failed';
      this.loadError = (error as Error).message || '读取已有链接失败，请确认当前连接拥有管理权限';
      return;
    }
    if (seq !== this.loadSeq) return;
    const others = this.entries.filter((e: EnvironmentEntry) => !e.deleting && e.localId !== this.sourceLocalId);
    const writable = new Set<string>();
    const machines: LinkBatchMachine[] = [];
    await Promise.all(others.map(async (entry: EnvironmentEntry) => {
      const conn = this.connectionFor(entry.localId);
      const connected = !!conn && conn.ready;
      if (connected && conn) {
        try {
          await conn.refreshPeerAccess();
          if (conn.canManagePeerAccess()) writable.add(entry.environmentId);
        } catch (_) {}
      }
      const routeBases = entry.kind === 'bearer'
        ? environmentRoutes(entry).map((r: DirectRoute) => r.base)
        : [];
      const urls = linkReachableAddresses((conn?.directAddresses || []).concat(routeBases));
      machines.push({
        localId: entry.localId,
        environmentId: entry.environmentId,
        label: entry.label,
        urls,
        connected,
        linked: linkedIds.includes(entry.environmentId)
      });
    }));
    if (seq !== this.loadSeq) return;
    machines.sort((a: LinkBatchMachine, b: LinkBatchMachine) => a.label.localeCompare(b.label));
    this.linksState = 'loaded';
    this.candidates = linkBatchCandidates(machines, writable, 'loaded');
    const eligible = this.candidates
      .filter((c: LinkBatchCandidate) => c.blocked === null)
      .map((c: LinkBatchCandidate) => c.machine.environmentId);
    this.selectedIds = eligible;
  }

  private toggleMachine(envId: string): void {
    if (this.running) return;
    if (this.selectedIds.includes(envId)) {
      this.selectedIds = this.selectedIds.filter((id: string) => id !== envId);
    } else {
      this.selectedIds = this.selectedIds.concat([envId]);
    }
  }

  private async runBatch(targetIds?: string[]): Promise<void> {
    if (this.inFlight || this.running) return;
    const sourceClient = this.connectionFor(this.sourceLocalId);
    if (!sourceClient || !sourceClient.ready) {
      this.loadError = '源环境连接已断开';
      return;
    }
    const chosenIds = targetIds || this.selectedIds;
    const chosenMachines = this.candidates
      .filter((c: LinkBatchCandidate) => c.blocked === null && chosenIds.includes(c.machine.environmentId))
      .map((c: LinkBatchCandidate) => c.machine);
    if (chosenMachines.length === 0) return;

    this.inFlight = true;
    this.running = true;
    this.summaryText = '';
    this.loadError = '';
    const nextOutcomes: Record<string, LinkBatchOutcome> = {};
    for (const k of Object.keys(this.outcomes)) {
      if (!chosenIds.includes(k)) nextOutcomes[k] = this.outcomes[k];
    }
    this.outcomes = nextOutcomes;

    try {
      const results = await runLinkBatch({
        machines: chosenMachines,
        access: this.access,
        mint: async (machine: LinkBatchMachine, access: string): Promise<string> => {
          const targetClient = this.connectionFor(machine.localId);
          if (!targetClient || !targetClient.ready) throw new Error('not connected');
          return await targetClient.mintPeerPairingCode(access);
        },
        link: async (payload: PeerLinkCreateInput): Promise<void> => {
          await sourceClient.linkPeerEnvironment(payload);
        },
        refreshLinks: () => { this.onLinked(); },
        onOutcome: (envId: string, outcome: LinkBatchOutcome) => {
          const updated: Record<string, LinkBatchOutcome> = {};
          for (const k of Object.keys(this.outcomes)) updated[k] = this.outcomes[k];
          updated[envId] = outcome;
          this.outcomes = updated;
        }
      });
      const summary = linkBatchSummary(results);
      if (summary.failed.length === 0) {
        this.summaryText = '已成功链接 ' + summary.linked + ' 个环境';
      } else {
        this.summaryText = '已链接 ' + summary.linked + ' 个，失败 ' + summary.failed.length + ' 个（可重试失败项）';
      }
      if (summary.linked > 0) {
        void this.loadCandidates();
      }
    } finally {
      this.inFlight = false;
      this.running = false;
    }
  }

  private failedEnvIds(): string[] {
    const failed: string[] = [];
    for (const k of Object.keys(this.outcomes)) {
      if (this.outcomes[k].kind === 'failed') failed.push(k);
    }
    return failed;
  }

  build() {
    Column({ space: 0 }) {
      TopBar({
        title: '批量链接环境',
        subtitle: '链接到 ' + (this.sourceLabel || '当前环境'),
        showBack: true,
        closeStyle: true,
        backLabel: '关闭批量链接',
        onBack: () => { if (!this.running) this.onClose(); }
      })
      Scroll() {
        Column({ space: Space.sm }) {
          if (this.linksState === 'loading') {
            Column({ space: Space.xs }) {
              LoadingProgress().width(28).height(28).color($r('app.color.primary'))
              Text('正在检查可链接的环境与权限…')
                .fontSize(FontSize.callout).fontColor($r('app.color.muted'))
            }.width('100%').padding(Space.xl).alignItems(HorizontalAlign.Center)
          } else if (this.linksState === 'failed') {
            GroupCard() {
              Column({ space: Space.xs }) {
                Text(this.loadError || '无法加载环境链接列表')
                  .fontSize(FontSize.body).fontColor($r('app.color.danger')).width('100%')
                AppButton({
                  label: '重试', kind: 'secondary', compact: true,
                  onTap: () => { void this.loadCandidates(); }
                })
              }.padding(Space.md).width('100%').alignItems(HorizontalAlign.Start)
            }
          } else {
            GroupCard({
              title: '选择要链接到「' + this.sourceLabel + '」的环境',
              footnote: '一次性配对码将在各目标环境现场生成并直接发送，不会在本地保存或显示。'
            }) {
              ForEach(this.candidates, (item: LinkBatchCandidate, index: number) => {
                Column({ space: 2 }) {
                  Row({ space: Space.xs }) {
                    Column({ space: 2 }) {
                      Text(item.machine.label)
                        .fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.medium)
                        .fontColor(item.blocked === null ? $r('app.color.ink') : $r('app.color.muted'))
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                      if (item.blocked !== null) {
                        Text(linkBatchBlockLabel(item.blocked))
                          .fontSize(FontSize.caption).lineHeight(LineHeight.caption)
                          .fontColor($r('app.color.muted')).width('100%')
                      } else if (this.outcomes[item.machine.environmentId]) {
                        Text(this.outcomes[item.machine.environmentId].kind === 'linked'
                          ? '已链接成功'
                          : (linkBatchFailureLabel(this.outcomes[item.machine.environmentId].failure || 'other') +
                            (this.outcomes[item.machine.environmentId].detail ? '：' + this.outcomes[item.machine.environmentId].detail : '')))
                          .fontSize(FontSize.caption).lineHeight(LineHeight.caption)
                          .fontColor(this.outcomes[item.machine.environmentId].kind === 'linked'
                            ? $r('app.color.success') : $r('app.color.danger'))
                          .width('100%')
                      } else {
                        Text(item.machine.urls[0] || '')
                          .fontSize(FontSize.caption).lineHeight(LineHeight.caption)
                          .fontColor($r('app.color.muted')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                      }
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    if (item.blocked !== null) {
                      StatusBadge({
                        text: item.blocked === 'linked' ? '已链接' : '不可选',
                        tone: item.blocked === 'linked' ? 'success' : 'neutral'
                      })
                    } else if (this.outcomes[item.machine.environmentId]) {
                      StatusBadge({
                        text: this.outcomes[item.machine.environmentId].kind === 'linked' ? '已链接' : '失败',
                        tone: this.outcomes[item.machine.environmentId].kind === 'linked' ? 'success' : 'danger'
                      })
                    } else {
                      Text(this.selectedIds.includes(item.machine.environmentId) ? '✓' : '○')
                        .fontSize(FontSize.headline).fontWeight(Weight.semibold)
                        .fontColor(this.selectedIds.includes(item.machine.environmentId)
                          ? $r('app.color.primary_text') : $r('app.color.muted'))
                    }
                  }.width('100%').alignItems(VerticalAlign.Center)
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                .constraintSize({ minHeight: Sizes.formRowMin })
                .justifyContent(FlexAlign.Center)
                .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
                .onClick(() => { if (item.blocked === null) this.toggleMachine(item.machine.environmentId); })
              }, (item: LinkBatchCandidate) => item.machine.environmentId + ':' + (item.blocked || 'ok') + ':' +
                String(this.selectedIds.includes(item.machine.environmentId)) + ':' +
                (this.outcomes[item.machine.environmentId]?.kind || ''))
            }

            GroupCard({ title: '访问权限' }) {
              ForEach(linkAccessChoices, (choice: LinkAccessChoice, idx: number) => {
                FormRow({
                  kind: 'choice',
                  label: choice.label,
                  subtitle: choice.description,
                  checked: this.access === choice.value,
                  disabled: this.running,
                  isFirst: idx === 0,
                  onTap: () => { this.access = choice.value; }
                })
              }, (choice: LinkAccessChoice) => choice.value + ':' + String(this.access === choice.value))
            }

            if (this.summaryText) {
              Text(this.summaryText)
                .fontSize(FontSize.callout).lineHeight(LineHeight.callout)
                .fontColor(this.failedEnvIds().length > 0 ? $r('app.color.danger') : $r('app.color.primary_text'))
                .padding({ left: Space.xxs, right: Space.xxs }).width('100%')
            }

            Row({ space: Space.xs }) {
              Row() {
                AppButton({
                  label: this.running ? '正在批量链接…' : ('批量链接 (' + this.selectedIds.length + ')'),
                  kind: 'primary',
                  fill: true,
                  disabled: this.running || this.selectedIds.length === 0,
                  onTap: () => { void this.runBatch(); }
                })
              }.layoutWeight(1)
              if (this.failedEnvIds().length > 0 && !this.running) {
                AppButton({
                  label: '重试失败项',
                  kind: 'secondary',
                  onTap: () => { void this.runBatch(this.failedEnvIds()); }
                })
              }
            }.width('100%').padding({ top: Space.xs })
          }
        }.width('100%').padding({ left: Space.sm, right: Space.sm, top: Space.xs, bottom: Space.lg }).alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
