import { T3Client } from '../services/T3Client';
import { record } from '../protocol/Wire';
import { ThreadDefaults, threadDefaultField, threadDefaultAllowed, readThreadDefaults, writeThreadDefault } from '../protocol/ThreadDefaults';

@Component
export struct ThreadDefaultsPanel {
  connection: T3Client | undefined = undefined;
  onBack: () => void = () => {};
  @State snapshot: ThreadDefaults | undefined = undefined;
  @State busy: boolean = false;
  @State message: string = '';
  @State needsRefresh: boolean = false;
  private environmentId: string = '';
  private alive: boolean = false;
  private epoch: number = 0;

  aboutToAppear(): void {
    this.alive = true;
    if (this.connection) {
      const id = record(this.connection.config.environment).environmentId;
      this.environmentId = typeof id === 'string' ? id : '';
    }
    void this.refresh();
  }
  aboutToDisappear(): void { this.alive = false; this.epoch++; }
  private current(connection: T3Client, epoch: number): boolean {
    return this.alive && this.epoch === epoch && this.connection === connection && connection.ready &&
      record(connection.config.environment).environmentId === this.environmentId;
  }
  private async refresh(): Promise<void> {
    const connection = this.connection;
    if (!connection || this.busy) return;
    const epoch = ++this.epoch;
    this.busy = true;
    try {
      const result = await readThreadDefaults(connection, this.environmentId);
      if (this.current(connection, epoch)) { this.snapshot = result; this.message = ''; this.needsRefresh = false; }
    } catch (_) {
      if (this.alive && this.epoch === epoch) { this.message = '读取失败，请检查连接后刷新'; this.needsRefresh = true; }
    } finally { if (this.alive && this.epoch === epoch) this.busy = false; }
  }
  private canChoose(key: string, value: string): boolean {
    return !!this.snapshot && !!this.connection && this.current(this.connection, this.epoch) &&
      !this.busy && !this.needsRefresh && this.connection.canScope('settings:write') !== false &&
      threadDefaultAllowed(this.snapshot, key, value);
  }
  private selected(key: string, value: string): boolean {
    return !!this.snapshot && threadDefaultField(this.snapshot, key).value === value;
  }
  private async save(key: string, value: string): Promise<void> {
    const connection = this.connection;
    if (!connection || !this.canChoose(key, value) || this.selected(key, value)) return;
    const epoch = ++this.epoch;
    this.busy = true; this.message = '';
    try {
      const result = await writeThreadDefault(connection, this.environmentId, key, value);
      if (this.current(connection, epoch)) { this.snapshot = result; this.message = '已保存并核对服务端结果'; }
    } catch (_) {
      if (this.alive && this.epoch === epoch) {
        this.needsRefresh = true; this.message = '修改未确认，请刷新核对。不会自动重试。';
      }
    } finally { if (this.alive && this.epoch === epoch) this.busy = false; }
  }
  @Builder
  section(title: string, key: string) {
    Text(title).fontSize(14).fontWeight(FontWeight.Medium).width('100%').margin({ top: 10 })
    if (this.snapshot && !threadDefaultField(this.snapshot, key).supported) {
      Text('当前服务未提供受支持的设置值').fontSize(13).fontColor($r('app.color.muted')).width('100%')
    } else if (this.snapshot && threadDefaultField(this.snapshot, key).locked) {
      Text(this.snapshot.managedBy + ' 管理此设置').fontSize(13).fontColor($r('app.color.muted')).width('100%')
    }
  }
  @Builder
  choice(key: string, value: string, title: string, detail: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Radio({ value, group: key }).checked(this.selected(key, value)).width(20).height(20)
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
        Column({ space: 4 }) {
          Text(title).fontSize(15).width('100%')
          Text(detail).fontSize(13).fontColor($r('app.color.muted')).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding(14)
    }.width('100%').backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(12)
      .enabled(this.canChoose(key, value)).accessibilityText(title + (this.selected(key, value) ? '，已选择' : ''))
      .onClick(() => { void this.save(key, value); })
  }
  build() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) { Image($r('app.media.ui_back')).width(22).height(22) }
          .width(44).height(44).backgroundColor(Color.Transparent).accessibilityText('返回设置').onClick(this.onBack)
        Text('会话默认设置').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('刷新').fontSize(14).backgroundColor(Color.Transparent).fontColor($r('app.color.primary'))
          .enabled(!this.busy).onClick(() => { void this.refresh(); })
      }.width('100%').padding(8)
      Scroll() {
        Column({ space: 10 }) {
          Text('修改当前环境的设置。新草稿优先使用项目单独设置；已有草稿保留原权限和工作区。')
            .fontSize(13).fontColor($r('app.color.muted')).width('100%')
          if (!this.connection) { Text('请先连接一个环境').fontSize(15) }
          if (this.busy) { Text('正在同步…').fontSize(13).fontColor($r('app.color.muted')) }
          if (this.message) { Text(this.message).fontSize(14).width('100%') }
          if (this.snapshot) {
            if (this.connection?.canScope('settings:write') === false) {
              Text('当前连接仅可查看，无法修改设置').fontSize(13).fontColor($r('app.color.muted'))
            }
            this.section('默认权限', 'defaultRuntimeMode')
            if (this.snapshot.maxRuntimeMode !== 'full-access') {
              Text('部分权限受组织上限限制').fontSize(13).fontColor($r('app.color.muted')).width('100%')
            }
            this.choice('defaultRuntimeMode', 'approval-required', '操作前审批', '需要批准后执行受限操作。')
            this.choice('defaultRuntimeMode', 'auto-accept-edits', '自动接受编辑', '自动应用文件编辑，其他操作仍按策略审批。')
            this.choice('defaultRuntimeMode', 'auto', '自动模式', '由运行时按策略处理操作权限。')
            this.choice('defaultRuntimeMode', 'full-access', '完全访问', '允许更广泛的工具与文件操作，请仅用于可信任务。')
            this.section('默认工作区', 'defaultThreadEnvMode')
            this.choice('defaultThreadEnvMode', 'inherit', '遵循仓库设置', '使用 t3.json；未配置时使用当前检出。')
            this.choice('defaultThreadEnvMode', 'local', '当前检出', '在现有工作区中新建会话。')
            this.choice('defaultThreadEnvMode', 'worktree', '新工作树', '为新会话建立独立检出。')
            this.section('响应展示', 'responseStreamingMode')
            this.choice('responseStreamingMode', 'paragraph', '逐段显示', '段落或代码块完成后显示。')
            this.choice('responseStreamingMode', 'turn', '完成后显示', '等待整轮回复完成后显示。')
            this.section('Agent 浏览器访问', 'enableAgentBrowserAccess')
            this.choice('enableAgentBrowserAccess', 'true', '允许使用预览浏览器', 'Agent 可以调用环境中的预览浏览器工具。')
            this.choice('enableAgentBrowserAccess', 'false', '关闭 Agent 浏览器访问', '禁止 Agent 使用预览浏览器工具。')
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16, bottom: 28 })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor($r('app.color.canvas')).foregroundColor($r('app.color.ink'))
  }
}
