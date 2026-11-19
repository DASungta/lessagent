import { i18n } from '@kit.LocalizationKit';
import { T3Client } from '../services/T3Client';
import { UsageDayView, UsageAccount, UsageWindow, UsageBucketView, UsageSummaryView, usageAccounts, usageInput,
  readUsageSummary, filterUsage, usageTotal, usageDays, usageDayScale, compactUsageTokens, usagePricingLabel } from '../protocol/Usage';

@Component
export struct UsagePanel {
  connection: T3Client | undefined = undefined;
  @Prop embedded: boolean = false;
  @Prop bottomInset: number = 0;
  onDetailChange: (open: boolean) => void = () => {};
  onBack: () => void = () => {};
  @State summary: UsageSummaryView | undefined = undefined;
  @State accounts: UsageAccount[] = [];
  @State @Watch('selectedAccountChanged') selectedAccount: string = '';
  @State days: number = 7;
  @State provider: string = '';
  @State model: string = '';
  @State metric: string = 'cost';
  @State busy: boolean = false;
  @State error: string = '';
  @State limitsError: string = '';
  private alive: boolean = false;
  private timer: number = -1;
  private generation: number = -1;
  private liveAccounts: string = '';

  aboutToAppear(): void {
    this.alive = true;
    void this.refresh();
    this.timer = setInterval(() => {
      if (!this.connection?.ready || this.generation !== this.connection.generationValue()) {
        this.summary = undefined; this.accounts = []; this.error = '连接已变化，请刷新';
      }
      else {
        try {
          const latest = usageAccounts(this.connection.config);
          const key = JSON.stringify(latest);
          if (key !== this.liveAccounts) { this.accounts = latest; this.liveAccounts = key; }
        } catch (_) {}
      }
    }, 3000);
  }
  aboutToDisappear(): void { this.alive = false; clearInterval(this.timer); }
  private selectedAccountChanged(): void { this.onDetailChange(this.selectedAccount.length > 0); }
  private async refresh(): Promise<void> {
    const connection = this.connection;
    if (!connection || this.busy) return;
    this.busy = true; this.error = ''; this.limitsError = ''; this.summary = undefined;
    const generation = connection.generationValue();
    this.generation = generation;
    try { this.liveAccounts = JSON.stringify(usageAccounts(connection.config)); } catch (_) { this.liveAccounts = ''; }
    try {
      const config = await connection.rpcRequest('server.getConfig', {} as Record<string, Object>, 15000, false);
      if (this.alive && generation === connection.generationValue()) this.accounts = usageAccounts(config);
    } catch (_) { if (this.alive) { this.accounts = []; this.limitsError = '无法读取账号限额，请检查连接与权限'; } }
    try {
      const result = await readUsageSummary(connection, usageInput(this.days, i18n.getTimeZone().getID()));
      if (this.alive && generation === connection.generationValue()) this.summary = result;
    } catch (_) { if (this.alive) this.error = '无法读取用量：请检查连接、诊断读取权限和服务端协议版本'; }
    finally { if (this.alive) this.busy = false; }
  }
  private rows(): UsageBucketView[] { return filterUsage(this.summary?.buckets || [], this.provider, this.model); }
  private providers(): string[] {
    const result: string[] = [];
    this.summary?.buckets.forEach((row: UsageBucketView) => { if (!result.includes(row.provider)) result.push(row.provider); });
    return result;
  }
  private providerOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '全部提供商' }];
    this.providers().forEach((value: string) => { options.push({ value: value }); });
    return options;
  }
  private daily(): UsageDayView[] { return usageDays(this.rows()); }
  private trendScale(): number {
    const peak = usageDayScale(this.daily(), this.metric);
    return peak > 0 ? peak : 1;
  }
  private dayValue(day: UsageDayView): number { return this.metric === 'tokens' ? day.tokens : day.costUsd; }
  private dayLabel(day: UsageDayView): string {
    if (this.metric === 'tokens') return day.tokens + ' tokens';
    return '$' + day.costUsd.toFixed(2) + ' USD' + (day.unpricedRecords > 0 ? ' · 金额不完整（含未定价记录）' : '');
  }
  @Builder
  dailyTrend() {
    Column({ space: 10 }) {
      Text('每日趋势').fontSize(16).fontWeight(FontWeight.Medium).width('100%')
      Row({ space: 8 }) {
        Button('费用').fontSize(14).backgroundColor(this.metric === 'cost' ? $r('app.color.primary') : $r('app.color.surface'))
          .fontColor(this.metric === 'cost' ? Color.White : $r('app.color.ink')).onClick(() => { this.metric = 'cost'; })
        Button('Tokens').fontSize(14).backgroundColor(this.metric === 'tokens' ? $r('app.color.primary') : $r('app.color.surface'))
          .fontColor(this.metric === 'tokens' ? Color.White : $r('app.color.ink')).onClick(() => { this.metric = 'tokens'; })
      }
      Text('按当前筛选汇总；只显示有返回记录的日期。条长相对本范围最大值。')
        .fontSize(12).fontColor($r('app.color.muted')).width('100%')
      ForEach(this.daily(), (day: UsageDayView) => {
        Column({ space: 5 }) {
          Text(day.day + ' · ' + this.dayLabel(day)).fontSize(13).width('100%')
          Progress({ value: Math.max(0, this.dayValue(day)), total: this.trendScale(), type: ProgressType.Linear })
            .width('100%').color($r('app.color.primary')).accessibilityText(day.day + '，' + this.dayLabel(day))
        }.width('100%')
      }, (day: UsageDayView) => day.day)
    }.width('100%').alignItems(HorizontalAlign.Start).padding(12).backgroundColor($r('app.color.surface')).borderRadius(12)
  }
  private money(): string { return '$' + usageTotal(this.rows()).costUsd.toFixed(2); }
  private resetLabel(value: string): string {
    const date = new Date(value);
    return value && !Number.isNaN(date.getTime()) ? date.toLocaleString() : '未提供';
  }
  @Builder
  accountCard(account: UsageAccount) {
    Column({ space: 8 }) {
      Text(account.label).fontSize(16).fontWeight(FontWeight.Medium).width('100%')
      Text(account.driver + ' · 检查时间 ' + this.resetLabel(account.checkedAt))
        .fontSize(12).fontColor($r('app.color.muted')).width('100%')
      if (account.notice) { Text(account.notice).fontSize(13).width('100%') }
      if (!account.windows.length) { Text('未提供可显示的限额窗口').fontSize(13) }
      ForEach(account.windows, (window: UsageWindow) => {
        Column({ space: 4 }) {
          Text(window.label + ' · 剩余 ' + window.remaining + '%').fontSize(14).width('100%')
          Progress({ value: window.remaining, total: 100, type: ProgressType.Linear }).width('100%')
            .color($r('app.color.primary')).accessibilityText(window.label + ' 剩余百分之' + window.remaining)
          Text('重置：' + this.resetLabel(window.resetsAt)).fontSize(12).fontColor($r('app.color.muted')).width('100%')
        }.width('100%')
      })
    }.width('100%').alignItems(HorizontalAlign.Start).padding(14).backgroundColor($r('app.color.surface')).borderRadius(12)
  }
  build() {
    Column() {
      Row({ space: 8 }) {
        if (!this.embedded || this.selectedAccount.length > 0) {
          Button({ type: ButtonType.Normal }) { Image($r('app.media.ui_back')).width(22).height(22) }
            .width(44).height(44).backgroundColor(Color.Transparent).accessibilityText('返回')
            .onClick(() => { if (this.selectedAccount) this.selectedAccount = ''; else this.onBack(); })
        }
        Text(this.selectedAccount ? '账号用量限额' : '用量').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('刷新').fontSize(14).backgroundColor(Color.Transparent).fontColor($r('app.color.primary'))
          .enabled(!this.busy && !!this.connection?.ready).onClick(() => { void this.refresh(); })
      }.padding({ left: !this.embedded || this.selectedAccount.length > 0 ? 8 : 16, right: 8, top: 4, bottom: 4 })
        .constraintSize({ minHeight: 52 }).width('100%')
      Scroll() {
        Column({ space: 12 }) {
          if (!this.connection?.ready) { Text('请先连接一个环境').fontSize(15) }
          if (this.busy) { Text('正在读取…').fontSize(14) }
          if (this.selectedAccount) {
            ForEach(this.accounts.filter((account: UsageAccount) => account.id === this.selectedAccount), (account: UsageAccount) => {
              this.accountCard(account)
            })
            if (!this.accounts.some((account: UsageAccount) => account.id === this.selectedAccount)) {
              Text('账号已不在当前快照中，请返回并刷新').fontSize(14)
            }
          } else {
            Text('当前环境 · 历史用量').fontSize(16).fontWeight(FontWeight.Medium).width('100%')
            Row({ space: 8 }) {
              ForEach([1, 7, 30], (days: number) => {
                Button(days === 1 ? '今天' : days + '天').fontSize(14)
                  .backgroundColor(this.days === days ? $r('app.color.primary') : $r('app.color.surface'))
                  .fontColor(this.days === days ? Color.White : $r('app.color.ink')).enabled(!this.busy)
                  .onClick(() => { this.days = days; void this.refresh(); })
              })
            }
            if (this.error) { Text(this.error).fontSize(14).width('100%') }
            if (this.summary) {
              Select(this.providerOptions())
                .value(this.provider || '全部提供商').onSelect((index: number) => { this.provider = index === 0 ? '' : this.providers()[index - 1]; })
              TextInput({ text: this.model, placeholder: '筛选模型' }).onChange((value: string) => { this.model = value; })
                .accessibilityText('筛选模型')
              Text(this.money() + ' USD · ' + compactUsageTokens(usageTotal(this.rows()).tokens) + ' tokens').fontSize(21).fontWeight(FontWeight.Medium).width('100%')
                .accessibilityText(this.money() + ' USD，' + usageTotal(this.rows()).tokens + ' tokens')
              Text('服务端报告或按模型价格估算，并非账单。推理 token 已包含在输出中。').fontSize(12).fontColor($r('app.color.muted')).width('100%')
              Text('读取：' + this.resetLabel(this.summary.readAt) + ' · ' + usagePricingLabel(this.summary.pricing)).fontSize(12).width('100%')
              if (usageTotal(this.rows()).unpricedRecords > 0) { Text('含未定价记录，金额不完整').fontSize(14) }
              ForEach(this.summary.notices, (notice: string) => { Text(notice).fontSize(13).width('100%') })
              if (!this.rows().length) { Text('此范围没有用量记录').fontSize(14) }
              if (this.rows().length > 0) { this.dailyTrend() }
              ForEach(this.rows(), (row: UsageBucketView) => {
                Column({ space: 4 }) {
                  Text(row.day + ' · ' + row.provider + ' / ' + row.model).fontSize(14).width('100%')
                  Text('$' + row.costUsd.toFixed(2) + ' USD · ' + row.tokens + ' tokens').fontSize(13).width('100%')
                }.padding(12).width('100%').backgroundColor($r('app.color.surface')).borderRadius(10)
              })
            }
            Text('账号限额').fontSize(16).fontWeight(FontWeight.Medium).width('100%')
            Text('分别显示各账号最近快照；跨环境池汇总尚未提供。重置时间不是执行重置操作。')
              .fontSize(12).fontColor($r('app.color.muted')).width('100%')
            if (this.limitsError) { Text(this.limitsError).fontSize(14) }
            if (!this.accounts.length && !this.busy) { Text('当前环境未提供账号限额').fontSize(14) }
            ForEach(this.accounts, (account: UsageAccount) => {
              Button({ type: ButtonType.Normal }) { this.accountCard(account) }
                .width('100%').backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                .accessibilityText(account.label + '，查看限额详情').onClick(() => { this.selectedAccount = account.id; })
            })
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16, bottom: 28 + (this.embedded && !this.selectedAccount ? this.bottomInset : 0) })
      }.layoutWeight(1).width('100%').align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor($r('app.color.canvas')).foregroundColor($r('app.color.ink'))
  }
}
