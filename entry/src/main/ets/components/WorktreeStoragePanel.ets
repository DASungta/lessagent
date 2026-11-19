import { T3Client } from '../services/T3Client';
import { record } from '../protocol/Wire';
import {
  WORKTREE_KEEP_VALUES, WorktreeStorage, readWorktreeStorage, worktreeStorageField, worktreeStorageNeedsConfirmation,
  worktreeStorageText, worktreeStorageValue, writeWorktreeStorage
} from '../protocol/WorktreeStorage';

const KEEP_LABELS: string[] = ['保护所有本地文件', '保护未提交改动', '只保护已追踪文件的改动'];

@Component
export struct WorktreeStoragePanel {
  connection: T3Client | undefined = undefined;
  @Prop settingsWriteAllowed: boolean | undefined = undefined;
  onBack: () => void = () => {};
  @State snapshot: WorktreeStorage | undefined = undefined;
  @State busy: boolean = false;
  @State needsRefresh: boolean = false;
  @State message: string = '';
  @State editingKey: string = '';
  @State draft: string = '';
  private epoch: number = 0;
  private alive: boolean = false;

  aboutToAppear(): void { this.alive = true; void this.refresh(); }
  aboutToDisappear(): void { this.alive = false; this.epoch++; }

  private environmentId(connection: T3Client): string {
    if (!connection.ready) return '';
    const id = record(connection.config.environment).environmentId;
    return typeof id === 'string' ? id : '';
  }
  private async refresh(): Promise<void> {
    const connection = this.connection;
    if (!this.alive || this.busy) return;
    const id = connection ? this.environmentId(connection) : '';
    if (!connection || !id) { this.message = '请先连接一个环境'; return; }
    const epoch = ++this.epoch;
    this.busy = true; this.message = ''; this.editingKey = '';
    try {
      await connection.refreshSessionAccess();
      const snapshot = await readWorktreeStorage(connection, id);
      if (epoch === this.epoch && this.connection === connection) {
        this.snapshot = snapshot; this.needsRefresh = false;
      }
    } catch (_) {
      if (epoch === this.epoch) { this.needsRefresh = true; this.message = '读取失败，请刷新核对'; }
    } finally {
      if (epoch === this.epoch) this.busy = false;
    }
  }
  private canEdit(key: string): boolean {
    const snapshot = this.snapshot;
    const connection = this.connection;
    const field = snapshot ? worktreeStorageField(snapshot, key) : undefined;
    return this.settingsWriteAllowed === true && this.alive && !this.busy && !this.needsRefresh && !!connection &&
      this.environmentId(connection) === snapshot?.environmentId && connection.canScope('settings:write') === true &&
      field?.value !== undefined && !field.locked;
  }
  private textValue(key: string): string {
    return this.snapshot ? worktreeStorageText(worktreeStorageField(this.snapshot, key)?.value) : '';
  }
  private label(key: string): string {
    const field = this.snapshot ? worktreeStorageField(this.snapshot, key) : undefined;
    if (field?.value === undefined) return '当前服务未提供';
    if (field.value === null) return '关闭';
    if (key === 'worktreesDirectory' && field.value === '') return '默认目录';
    if (key === 'worktreeKeepWhen') return KEEP_LABELS[WORKTREE_KEEP_VALUES.indexOf(this.textValue(key))];
    if (typeof field.value === 'boolean') return field.value ? '已开启' : '已关闭';
    if (typeof field.value === 'number') return String(field.value) + ' 天';
    return field.value;
  }
  private locked(key: string): boolean {
    return !!this.snapshot && worktreeStorageField(this.snapshot, key)?.locked === true;
  }
  private async save(key: string, input: string, confirmed: boolean): Promise<void> {
    const connection = this.connection;
    const id = this.snapshot?.environmentId;
    if (!connection || !id || !this.canEdit(key)) return;
    const epoch = ++this.epoch;
    this.busy = true; this.message = '';
    const stillSelected = (): boolean => this.alive && this.epoch === epoch &&
      this.connection === connection && this.environmentId(connection) === id;
    try {
      const result = await writeWorktreeStorage(connection, id, key, input, confirmed, stillSelected);
      if (stillSelected()) {
        this.snapshot = result; this.editingKey = ''; this.message = '已保存并核对';
      }
    } catch (_) {
      if (this.epoch === epoch) {
        this.needsRefresh = true; this.message = '修改未确认，请刷新核对';
      }
    } finally {
      if (this.epoch === epoch) this.busy = false;
    }
  }
  private submit(key: string, input: string): void {
    const snapshot = this.snapshot;
    if (!snapshot || !this.canEdit(key)) return;
    try {
      if (worktreeStorageValue(snapshot, key, input) === worktreeStorageField(snapshot, key)?.value) return;
    } catch (error) {
      this.message = (error as Error).message;
      return;
    }
    if (!worktreeStorageNeedsConfirmation(snapshot, key, input)) {
      void this.save(key, input, false);
      return;
    }
    AlertDialog.show({
      title: '加强自动清理规则？',
      message: '服务会在符合条件时删除工作树目录及规则未保护的本地文件，包括可能存在的 .env 文件。清理本身不会删除 Git 分支或会话历史。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '保存规则', action: () => {
        if (this.snapshot === snapshot) void this.save(key, input, true);
      } }
    });
  }
  @Builder
  caption(title: string, detail: string, key: string) {
    Text(title).fontSize(15).fontWeight(FontWeight.Medium).width('100%')
    Text(detail).fontSize(13).fontColor($r('app.color.muted')).width('100%')
    if (this.locked(key)) {
      Text(this.snapshot?.managedBy + ' 管理此设置').fontSize(13).fontColor($r('app.color.muted')).width('100%')
    }
  }
  @Builder
  editText(title: string, detail: string, key: string, placeholder: string) {
    Column({ space: 6 }) {
      this.caption(title, detail, key)
      if (this.editingKey === key) {
        TextInput({ text: this.draft, placeholder }).constraintSize({ minHeight: 44 })
          .accessibilityText(title).enabled(this.canEdit(key))
          .onChange((value: string) => { this.draft = value; })
        Row({ space: 8 }) {
          Button('取消').constraintSize({ minHeight: 44 }).enabled(!this.busy).onClick(() => { this.editingKey = ''; })
          Button('保存').constraintSize({ minHeight: 44 }).enabled(this.canEdit(key))
            .onClick(() => this.submit(key, this.draft))
        }.width('100%')
      } else {
        Text(this.label(key)).fontSize(14).width('100%').wordBreak(WordBreak.BREAK_ALL)
        Button('编辑').constraintSize({ minHeight: 44 }).enabled(this.canEdit(key))
          .accessibilityText('编辑' + title).onClick(() => { this.draft = this.textValue(key); this.editingKey = key; })
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(12).backgroundColor($r('app.color.surface')).borderRadius(12)
  }
  @Builder
  switchRule(title: string, detail: string, key: string) {
    Column({ space: 6 }) {
      this.caption(title, detail, key)
      Button(this.label(key)).constraintSize({ minHeight: 44 }).enabled(this.canEdit(key))
        .backgroundColor(this.textValue(key) === 'true' ? $r('app.color.primary') : $r('app.color.canvas'))
        .fontColor(this.textValue(key) === 'true' ? Color.White : $r('app.color.ink'))
        .accessibilityText(title + '，' + this.label(key)).onClick(() =>
          this.submit(key, this.textValue(key) === 'true' ? 'false' : 'true'))
    }.width('100%').alignItems(HorizontalAlign.Start).padding(12).backgroundColor($r('app.color.surface')).borderRadius(12)
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) { Image($r('app.media.ui_back')).width(22).height(22) }
          .width(44).height(44).backgroundColor(Color.Transparent).accessibilityText('返回设置').onClick(this.onBack)
        Text('工作树存储').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('刷新').constraintSize({ minWidth: 44, minHeight: 44 })
          .fontSize(14).backgroundColor(Color.Transparent).fontColor($r('app.color.primary'))
          .enabled(!this.busy).onClick(() => { void this.refresh(); })
      }.width('100%').padding(8)
      Scroll() {
        Column({ space: 12 }) {
          if (this.busy) { Text('正在同步…').fontSize(13).width('100%') }
          if (this.message) { Text(this.message).fontSize(14).width('100%') }
          if (this.snapshot) {
            if (this.settingsWriteAllowed !== true) {
              Text('当前连接仅可查看').fontSize(13).width('100%')
            }
            this.editText('工作树目录', '新工作树使用宿主机上的目录。既有工作树保留原位置。', 'worktreesDirectory', '留空使用默认目录')
            Text('自动清理').fontSize(16).fontWeight(FontWeight.Medium).width('100%')
            Text('保存后，服务会按这些默认规则自动清理符合条件的工作树。项目的自定义规则或关闭设置优先。')
              .fontSize(13).fontColor($r('app.color.muted')).width('100%')
            if (this.snapshot.cleanupOverride) {
              Text('当前服务的工作树清理模式覆盖这些默认规则。').fontSize(14).width('100%')
            } else {
              this.editText('闲置工作树', '会话连续闲置指定天数后，工作树可被自动清理。', 'worktreeAfterDays', '1–3650 天，留空关闭')
              this.editText('已归整工作树', '归整达到指定天数后可清理；0 天表示下次清理时检查。', 'worktreeSettledAfterDays', '0–3650 天，留空关闭')
              this.switchRule('删除会话后清理', '清理已删除会话不再使用的工作树。', 'worktreeOnDelete')
              this.switchRule('合并后清理', '清理 PR 已合并且提交已进入默认分支的工作树。', 'worktreeOnMerge')
              this.switchRule('清理未更改的工作树', '清理已归整或归档，且没有超出默认分支提交的工作树。', 'worktreeUnchanged')
              Column({ space: 6 }) {
                this.caption('本地文件保护', '保护所有本地文件时，也保护忽略文件，node_modules 目录除外。只保护已追踪改动时，未跟踪和忽略文件都可能被删除。', 'worktreeKeepWhen')
                Select(KEEP_LABELS.map((label: string): SelectOption => ({ value: label })))
                  .width('100%').constraintSize({ minHeight: 44 })
                  .value(this.label('worktreeKeepWhen')).enabled(this.canEdit('worktreeKeepWhen'))
                  .accessibilityText('本地文件保护')
                  .onSelect((index: number) => { if (WORKTREE_KEEP_VALUES[index]) this.submit('worktreeKeepWhen', WORKTREE_KEEP_VALUES[index]); })
              }.width('100%').alignItems(HorizontalAlign.Start).padding(12).backgroundColor($r('app.color.surface')).borderRadius(12)
            }
          }
        }.width('100%').padding({ left: 16, right: 16, bottom: 28 })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor($r('app.color.canvas')).foregroundColor($r('app.color.ink'))
  }
}
