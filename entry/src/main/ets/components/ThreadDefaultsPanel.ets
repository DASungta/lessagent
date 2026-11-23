import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { FontSize, LineHeight, Space } from '../common/Theme';
import { T3Client } from '../services/T3Client';
import { configEnvironmentId } from '../protocol/Wire';
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
    this.environmentId = this.connection ? configEnvironmentId(this.connection.config) : '';
    void this.refresh();
  }
  aboutToDisappear(): void { this.alive = false; this.epoch++; }
  private current(connection: T3Client, epoch: number): boolean {
    return this.alive && this.epoch === epoch && this.connection === connection && connection.ready && !!this.environmentId &&
      configEnvironmentId(connection.config) === this.environmentId;
  }
  private async refresh(): Promise<void> {
    const connection = this.connection;
    if (!connection || this.busy) return;
    const id = this.environmentId || configEnvironmentId(connection.config);
    if (!connection.ready || !id) { this.message = '请先连接一个环境'; return; }
    this.environmentId = id;
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
  sectionHeader(title: string, key: string) {
    Text(title)
      .fontSize(FontSize.caption)
      .lineHeight(LineHeight.caption)
      .fontColor($r('app.color.muted'))
      .padding({ left: Space.xxs, right: Space.xxs, top: Space.sm, bottom: 5 })
      .width('100%')
    if (this.snapshot && !threadDefaultField(this.snapshot, key).supported) {
      Text('当前服务未提供受支持的设置值')
        .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
        .padding({ left: Space.xxs, right: Space.xxs, bottom: 4 }).width('100%')
    } else if (this.snapshot && threadDefaultField(this.snapshot, key).locked) {
      Text(this.snapshot.managedBy + ' 管理此设置')
        .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
        .padding({ left: Space.xxs, right: Space.xxs, bottom: 4 }).width('100%')
    }
  }

  @Builder
  choice(key: string, value: string, title: string, detail: string, isFirst: boolean = false) {
    FormRow({
      kind: 'choice',
      label: title,
      subtitle: detail,
      checked: this.selected(key, value),
      disabled: !this.canChoose(key, value),
      isFirst,
      onTap: () => { void this.save(key, value); }
    })
  }

  build() {
    Column({ space: 0 }) {
      TopBar({
        title: '会话默认设置',
        showBack: true,
        backLabel: '返回设置',
        onBack: () => this.onBack()
      }) {
        AppButton({
          label: '刷新',
          kind: 'text',
          disabled: this.busy,
          onTap: () => { void this.refresh(); }
        })
      }
      Scroll() {
        Column({ space: 0 }) {
          Text('修改当前环境的设置。新草稿优先使用项目单独设置；已有草稿保留原权限和工作区。')
            .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.muted'))
            .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs, bottom: Space.xxs }).width('100%')
          if (!this.connection) {
            GroupCard() {
              FormRow({
                kind: 'value', label: '请先连接一个环境', value: '', valueMuted: true, chevron: false, isFirst: true
              })
            }
          }
          if (this.busy) {
            Text('正在同步…').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }
          if (this.message) {
            Text(this.message).fontSize(FontSize.callout).fontColor($r('app.color.primary_text'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }
          if (this.snapshot) {
            if (this.connection?.canScope('settings:write') === false) {
              Text('当前连接仅可查看，无法修改设置')
                .fontSize(FontSize.callout).fontColor($r('app.color.muted'))
                .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
            }
            this.sectionHeader('默认权限', 'defaultRuntimeMode')
            if (this.snapshot.maxRuntimeMode !== 'full-access') {
              Text('部分权限受组织上限限制')
                .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
                .padding({ left: Space.xxs, right: Space.xxs, bottom: 4 }).width('100%')
            }
            Column() {
              this.choice('defaultRuntimeMode', 'approval-required', '操作前审批', '需要批准后执行受限操作。', true)
              this.choice('defaultRuntimeMode', 'auto-accept-edits', '自动接受编辑', '自动应用文件编辑，其他操作仍按策略审批。')
              this.choice('defaultRuntimeMode', 'auto', '自动模式', '由运行时按策略处理操作权限。')
              this.choice('defaultRuntimeMode', 'full-access', '完全访问', '允许更广泛的工具与文件操作，请仅用于可信任务。')
            }.width('100%').backgroundColor($r('app.color.card')).borderRadius(14).clip(true)

            this.sectionHeader('默认工作区', 'defaultThreadEnvMode')
            Column() {
              this.choice('defaultThreadEnvMode', 'inherit', '遵循仓库设置', '使用 t3.json；未配置时使用当前检出。', true)
              this.choice('defaultThreadEnvMode', 'local', '当前检出', '在现有工作区中新建会话。')
              this.choice('defaultThreadEnvMode', 'worktree', '新工作树', '为新会话建立独立检出。')
            }.width('100%').backgroundColor($r('app.color.card')).borderRadius(14).clip(true)

            this.sectionHeader('响应展示', 'responseStreamingMode')
            Column() {
              this.choice('responseStreamingMode', 'paragraph', '逐段显示', '段落或代码块完成后显示。', true)
              this.choice('responseStreamingMode', 'turn', '完成后显示', '等待整轮回复完成后显示。')
            }.width('100%').backgroundColor($r('app.color.card')).borderRadius(14).clip(true)

            this.sectionHeader('Agent 浏览器访问', 'enableAgentBrowserAccess')
            Column() {
              this.choice('enableAgentBrowserAccess', 'true', '允许使用预览浏览器', 'Agent 可以调用环境中的预览浏览器工具。', true)
              this.choice('enableAgentBrowserAccess', 'false', '关闭 Agent 浏览器访问', '禁止 Agent 使用预览浏览器工具。')
            }.width('100%').backgroundColor($r('app.color.card')).borderRadius(14).clip(true)
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: Space.sm, right: Space.sm, bottom: Space.lg })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
