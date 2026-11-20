import { i18n } from '@kit.LocalizationKit';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { T3Client } from '../services/T3Client';
import { UsageDayView, UsageAccount, UsageWindow, UsageBucketView, UsageSummaryView, usageAccounts, usageInput,
  readUsageSummary, filterUsage, usageTotal, usageDays, usageDayScale, compactUsageTokens, usagePricingLabel } from '../protocol/Usage';
import { AppButton } from './ui/AppButton';
import { TopBar } from './ui/TopBar';

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
    Column({ space: Space.sm }) {
      Row({ space: Space.sm }) {
        Text('每日趋势')
          .fontSize(FontSize.headline)
          .lineHeight(LineHeight.headline)
          .fontWeight(Weight.semibold)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
        Row({ space: 2 }) {
          Button('费用')
            .fontSize(FontSize.caption)
            .fontWeight(this.metric === 'cost' ? Weight.semibold : Weight.regular)
            .fontColor(this.metric === 'cost' ? $r('app.color.ink') : $r('app.color.muted'))
            .backgroundColor(this.metric === 'cost' ? $r('app.color.card') : Color.Transparent)
            .borderRadius(7)
            .padding({ left: Space.sm, right: Space.sm })
            .constraintSize({ minHeight: 30 })
            .onClick(() => { this.metric = 'cost'; })
          Button('Tokens')
            .fontSize(FontSize.caption)
            .fontWeight(this.metric === 'tokens' ? Weight.semibold : Weight.regular)
            .fontColor(this.metric === 'tokens' ? $r('app.color.ink') : $r('app.color.muted'))
            .backgroundColor(this.metric === 'tokens' ? $r('app.color.card') : Color.Transparent)
            .borderRadius(7)
            .padding({ left: Space.sm, right: Space.sm })
            .constraintSize({ minHeight: 30 })
            .onClick(() => { this.metric = 'tokens'; })
        }
        .padding(2)
        .backgroundColor($r('app.color.group'))
        .border({ width: Sizes.hairline, color: $r('app.color.border') })
        .borderRadius(9)
      }.width('100%').alignItems(VerticalAlign.Center)
      Text('按当前筛选汇总；只显示有返回记录的日期。条长相对本范围最大值。')
        .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
      ForEach(this.daily(), (day: UsageDayView) => {
        Column({ space: 5 }) {
          Text(day.day + ' · ' + this.dayLabel(day))
            .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.ink')).width('100%')
          Progress({ value: Math.max(0, this.dayValue(day)), total: this.trendScale(), type: ProgressType.Linear })
            .width('100%').color($r('app.color.primary')).accessibilityText(day.day + '，' + this.dayLabel(day))
        }.width('100%')
      }, (day: UsageDayView) => day.day)
    }.width('100%').alignItems(HorizontalAlign.Start).padding(Space.md).backgroundColor($r('app.color.card')).borderRadius(Radius.card)
  }
  private money(): string { return '$' + usageTotal(this.rows()).costUsd.toFixed(2); }
  private resetLabel(value: string): string {
    const date = new Date(value);
    if (!value || Number.isNaN(date.getTime())) return '未提供';
    const pad = (n: number): string => String(n).padStart(2, '0');
    return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate()) +
      ' ' + pad(date.getHours()) + ':' + pad(date.getMinutes());
  }
  @Builder
  accountCard(account: UsageAccount) {
    Column({ space: Space.xs }) {
      Text(account.label)
        .fontSize(FontSize.headline).lineHeight(LineHeight.headline).fontWeight(Weight.semibold).fontColor($r('app.color.ink')).width('100%')
      Text(account.driver + ' · 检查时间 ' + this.resetLabel(account.checkedAt))
        .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
      if (account.notice) {
        Text(account.notice).fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.ink')).width('100%')
      }
      if (!account.windows.length) {
        Text('未提供可显示的限额窗口').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
      }
      ForEach(account.windows, (window: UsageWindow) => {
        Column({ space: 4 }) {
          Text(window.label + ' · 剩余 ' + window.remaining + '%')
            .fontSize(FontSize.body).lineHeight(LineHeight.body).fontColor($r('app.color.ink')).width('100%')
          Progress({ value: window.remaining, total: 100, type: ProgressType.Linear }).width('100%')
            .color($r('app.color.primary')).accessibilityText(window.label + ' 剩余百分之' + window.remaining)
          Text('重置：' + this.resetLabel(window.resetsAt))
            .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
        }.width('100%').padding({ top: Space.xxs })
      })
    }.width('100%').alignItems(HorizontalAlign.Start).padding(Space.md).backgroundColor($r('app.color.card')).borderRadius(Radius.card)
  }
  build() {
    Column() {
      if (!this.embedded || this.selectedAccount.length > 0) {
        TopBar({
          title: this.selectedAccount ? '账号用量限额' : '用量',
          showBack: true,
          closeStyle: !this.embedded && this.selectedAccount.length === 0,
          onBack: () => { if (this.selectedAccount) this.selectedAccount = ''; else this.onBack(); }
        }) {
          AppButton({
            label: '刷新',
            kind: 'text',
            compact: true,
            disabled: this.busy || !this.connection?.ready,
            onTap: () => { void this.refresh(); }
          })
        }
      } else {
        Row({ space: Space.xs }) {
          Text('用量')
            .fontSize(FontSize.title)
            .lineHeight(LineHeight.title)
            .fontWeight(Weight.semibold)
            .fontColor($r('app.color.ink'))
            .layoutWeight(1)
          AppButton({
            label: '刷新',
            kind: 'text',
            compact: true,
            disabled: this.busy || !this.connection?.ready,
            onTap: () => { void this.refresh(); }
          })
        }
        .padding({ left: Space.page, right: Space.xs, top: Space.xxs, bottom: Space.xxs })
        .constraintSize({ minHeight: Sizes.topBar })
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      Scroll() {
        Column({ space: Space.sm }) {
          if (!this.connection?.ready) {
            Text('请先连接一个环境')
              .fontSize(FontSize.body).lineHeight(LineHeight.body).fontColor($r('app.color.muted')).width('100%')
          }
          if (this.busy) {
            Text('正在读取…').fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%')
          }
          if (this.selectedAccount) {
            ForEach(this.accounts.filter((account: UsageAccount) => account.id === this.selectedAccount), (account: UsageAccount) => {
              this.accountCard(account)
            })
            if (!this.accounts.some((account: UsageAccount) => account.id === this.selectedAccount)) {
              Text('账号已不在当前快照中，请返回并刷新')
                .fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%')
            }
          } else {
            Text('当前环境 · 历史用量')
              .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xxs }).width('100%')
            Row({ space: 2 }) {
              ForEach([1, 7, 30], (days: number) => {
                Button(days === 1 ? '今天' : days + '天')
                  .fontSize(FontSize.callout)
                  .fontWeight(this.days === days ? Weight.semibold : Weight.regular)
                  .backgroundColor(this.days === days ? $r('app.color.card') : Color.Transparent)
                  .fontColor(this.days === days ? $r('app.color.ink') : $r('app.color.muted'))
                  .borderRadius(7)
                  .layoutWeight(1)
                  .constraintSize({ minHeight: 34 })
                  .enabled(!this.busy)
                  .onClick(() => { this.days = days; void this.refresh(); })
              })
            }
            .width('100%')
            .padding(2)
            .backgroundColor($r('app.color.group'))
            .border({ width: Sizes.hairline, color: $r('app.color.border') })
            .borderRadius(9)
            if (this.error) {
              Text(this.error).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%')
            }
            if (this.summary) {
              Column({ space: Space.sm }) {
                Row({ space: Space.xs }) {
                  Select(this.providerOptions())
                    .value(this.provider || '全部提供商')
                    .onSelect((index: number) => { this.provider = index === 0 ? '' : this.providers()[index - 1]; })
                  TextInput({ text: this.model, placeholder: '筛选模型' })
                    .layoutWeight(1)
                    .height(40)
                    .fontSize(FontSize.body)
                    .fontColor($r('app.color.ink'))
                    .placeholderColor($r('app.color.placeholder'))
                    .backgroundColor($r('app.color.group'))
                    .borderRadius(Radius.button)
                    .padding({ left: Space.sm, right: Space.sm })
                    .onChange((value: string) => { this.model = value; })
                    .accessibilityText('筛选模型')
                }.width('100%').alignItems(VerticalAlign.Center)
                Text(this.money() + ' USD · ' + compactUsageTokens(usageTotal(this.rows()).tokens) + ' tokens')
                  .fontSize(FontSize.title).lineHeight(LineHeight.title).fontWeight(Weight.semibold).fontColor($r('app.color.ink')).width('100%')
                  .accessibilityText(this.money() + ' USD，' + usageTotal(this.rows()).tokens + ' tokens')
                Text('服务端报告或按模型价格估算，并非账单。推理 token 已包含在输出中。')
                  .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
                Text('读取：' + this.resetLabel(this.summary.readAt) + ' · ' + usagePricingLabel(this.summary.pricing))
                  .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
                if (usageTotal(this.rows()).unpricedRecords > 0) {
                  Text('含未定价记录，金额不完整').fontSize(FontSize.callout).fontColor($r('app.color.warning')).width('100%')
                }
                ForEach(this.summary.notices, (notice: string) => {
                  Text(notice).fontSize(FontSize.callout).fontColor($r('app.color.ink')).width('100%')
                })
                if (!this.rows().length) {
                  Text('此范围没有用量记录').fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%')
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(Space.md)
              .backgroundColor($r('app.color.card'))
              .borderRadius(Radius.card)
              if (this.rows().length > 0) { this.dailyTrend() }
              if (this.rows().length > 0) {
                Column() {
                  ForEach(this.rows(), (row: UsageBucketView, index: number) => {
                    Column({ space: 4 }) {
                      if (index > 0) {
                        Divider().color($r('app.color.separator')).strokeWidth(Sizes.hairline).margin({ bottom: Space.xs })
                      }
                      Text(row.day + ' · ' + row.provider + ' / ' + row.model)
                        .fontSize(FontSize.body).lineHeight(LineHeight.body).fontColor($r('app.color.ink')).width('100%')
                      Text('$' + row.costUsd.toFixed(2) + ' USD · ' + row.tokens + ' tokens')
                        .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.muted')).width('100%')
                    }.padding({ left: Space.md, right: Space.md, top: index === 0 ? Space.md : 0, bottom: Space.sm }).width('100%')
                  })
                }
                .width('100%')
                .backgroundColor($r('app.color.card'))
                .borderRadius(Radius.card)
                .clip(true)
              }
            }
            Text('账号限额')
              .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
            Text('分别显示各账号最近快照；跨环境池汇总尚未提供。重置时间不是执行重置操作。')
              .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
              .padding({ left: Space.xxs, right: Space.xxs }).width('100%')
            if (this.limitsError) {
              Text(this.limitsError).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%')
            }
            if (!this.accounts.length && !this.busy) {
              Column() {
                Text('当前环境未提供账号限额').fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%')
              }.width('100%').padding(Space.md).backgroundColor($r('app.color.card')).borderRadius(Radius.card)
            }
            ForEach(this.accounts, (account: UsageAccount) => {
              Button({ type: ButtonType.Normal }) { this.accountCard(account) }
                .width('100%').padding(0).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                .borderRadius(Radius.card)
                .accessibilityText(account.label + '，查看限额详情').onClick(() => { this.selectedAccount = account.id; })
            })
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: Space.page, right: Space.page, bottom: 28 + (this.embedded && !this.selectedAccount ? this.bottomInset : 0) })
      }.layoutWeight(1).width('100%').align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
