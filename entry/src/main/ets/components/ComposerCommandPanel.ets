import { BranchView } from '../protocol/R4';

@Component
export struct ComposerCommandPanel {
  @Prop mode: string = 'commands';
  @Prop query: string = '';
  @Prop busy: boolean = false;
  @Prop commands: string[] = [];
  @Prop skills: string[] = [];
  @Prop files: string[] = [];
  @Prop branches: BranchView[] = [];
  @Prop environments: string[] = [];
  onClose: () => void = () => {};
  onQuery: (value: string) => void = () => {};
  onCommand: (value: string) => void = () => {};
  onSkill: (value: string) => void = () => {};
  onFile: (value: string) => void = () => {};
  onBranch: (value: BranchView) => void = () => {};
  onEnvironment: (value: string) => void = () => {};
  onWorktree: (value: boolean) => void = () => {};
  onStartFromOrigin: (value: boolean) => void = () => {};
  onSwitchCheckout: () => void = () => {};
  @Prop worktree: boolean = false;
  @Prop startFromOrigin: boolean = true;

  private match(value: string): boolean {
    return value.toLowerCase().includes(this.query.trim().toLowerCase());
  }

  @Builder row(label: string, detail: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text(label).fontSize(15).fontWeight(FontWeight.Medium).width('100%').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (detail) { Text(detail).fontSize(11).fontColor($r('app.color.muted')).width('100%').maxLines(1) }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text('›').fontSize(18).fontColor($r('app.color.muted'))
      }.width('100%').padding(13)
    }.width('100%').backgroundColor($r('app.color.surface')).borderRadius(12)
      .enabled(!this.busy).onClick(action)
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Text(this.mode === 'branch' ? '分支与工作区' : this.mode === 'environment' ? '环境' :
          this.mode === 'mention' ? '文件与提及' : this.mode === 'skill' ? 'Skills' : '命令')
          .fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('×').width(40).height(40).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
          .accessibilityText('关闭').onClick(this.onClose)
      }.width('100%')
      TextInput({ placeholder: this.mode === 'mention' ? '搜索工作区文件' : this.mode === 'branch' ? '搜索分支' : '输入以筛选',
        text: this.query }).height(42).fontSize(14).backgroundColor($r('app.color.surface')).borderRadius(20)
        .enabled(!this.busy).onChange((value: string) => this.onQuery(value))
      if (this.mode === 'commands') {
        this.row('/model', '切换模型与选项', () => this.onCommand('model'))
        ForEach(this.commands.filter((name: string) => this.match(name)), (name: string) =>
          this.row('/' + name, 'Provider 命令（仅在消息开头生效）', () => this.onCommand(name)))
        this.row('/skill', '插入 Skill', () => this.onCommand('skill'))
      } else if (this.mode === 'skill') {
        if (this.skills.filter((name: string) => this.match(name)).length === 0) {
          Text('没有匹配的 Skill').fontSize(13).fontColor($r('app.color.muted'))
        }
        ForEach(this.skills.filter((name: string) => this.match(name)), (name: string) =>
          this.row('skill:' + name, '作为结构化上下文附加', () => this.onSkill(name)))
      } else if (this.mode === 'mention') {
        if (!this.query.trim()) Text('输入文件名或路径开始搜索').fontSize(13).fontColor($r('app.color.muted'))
        ForEach(this.files.filter((path: string) => this.match(path)), (path: string) =>
          this.row(path, '附加文件引用', () => this.onFile(path)))
      } else if (this.mode === 'environment') {
        ForEach(this.environments, (label: string) => this.row(label, '切换到该环境', () => this.onEnvironment(label)))
      } else {
        if (this.worktree) {
          this.row('工作区：新工作树', '切换到当前 checkout', () => this.onWorktree(false))
        } else {
          this.row('工作区：当前 checkout', '切换到新工作树', () => this.onWorktree(true))
        }
        if (this.worktree) {
          Row() {
            Column({ space: 3 }) {
              Text('从远端更新起点').fontSize(14).width('100%')
              Text('关闭时从本地分支创建').fontSize(11).fontColor($r('app.color.muted')).width('100%')
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.startFromOrigin }).enabled(!this.busy)
              .onChange((value: boolean) => this.onStartFromOrigin(value))
          }.width('100%').padding(12).backgroundColor($r('app.color.surface')).borderRadius(12)
        }
        ForEach(this.branches.filter((ref: BranchView) => this.match(ref.name)), (ref: BranchView) =>
          this.row(ref.name, (ref.current ? '当前 · ' : '') + (ref.isRemote ? '远端 · ' : '') +
            (ref.worktreePath ? '已有工作树' : ref.isDefault ? '默认分支' : '本地分支'), () => this.onBranch(ref)))
        if (!this.worktree && this.query.trim()) {
          Button('将当前 checkout 切换到 “' + this.query.trim() + '”').width('100%').height(42)
            .backgroundColor($r('app.color.canvas')).fontColor($r('app.color.ink')).enabled(!this.busy)
            .onClick(this.onSwitchCheckout)
        }
      }
    }.padding(20).width('100%').height('100%').alignItems(HorizontalAlign.Start)
      .foregroundColor($r('app.color.ink')).backgroundColor($r('app.color.canvas'))
  }
}

