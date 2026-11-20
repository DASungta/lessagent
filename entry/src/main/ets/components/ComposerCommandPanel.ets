import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { BranchView } from '../protocol/R4';
import { AppButton } from './ui/AppButton';
import { TopBar } from './ui/TopBar';

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
      Row({ space: Space.sm }) {
        Column({ space: 2 }) {
          Text(label).fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.medium)
            .fontColor($r('app.color.ink')).width('100%').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (detail) {
            Text(detail).fontSize(FontSize.caption).lineHeight(LineHeight.caption)
              .fontColor($r('app.color.muted')).width('100%').maxLines(1)
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Image($r('app.media.ui_chevron_right')).width(Sizes.chevron).height(Sizes.chevron).opacity(0.45).accessibilityLevel('no')
      }.width('100%').padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
    }.width('100%').padding(0).backgroundColor($r('app.color.card')).borderRadius(Radius.card)
      .enabled(!this.busy).onClick(action)
  }

  build() {
    Column() {
      TopBar({
        title: this.mode === 'branch' ? '分支与工作区' : this.mode === 'environment' ? '环境' :
          this.mode === 'mention' ? '文件与提及' : this.mode === 'skill' ? 'Skills' : '命令',
        showBack: true,
        closeStyle: true,
        onBack: this.onClose
      })
      Column({ space: Space.sm }) {
        Row({ space: Space.xs }) {
          Image($r('app.media.ui_search')).width(16).height(16).opacity(0.6).accessibilityLevel('no')
          TextInput({
            placeholder: this.mode === 'mention' ? '搜索工作区文件' : this.mode === 'branch' ? '搜索分支' : '输入以筛选',
            text: this.query
          })
            .layoutWeight(1).height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
            .placeholderColor($r('app.color.placeholder')).backgroundColor(Color.Transparent).padding(0)
            .enabled(!this.busy).onChange((value: string) => this.onQuery(value))
        }
        .width('100%')
        .padding({ left: Space.sm, right: Space.sm })
        .backgroundColor($r('app.color.card'))
        .borderRadius(Radius.button)
        .alignItems(VerticalAlign.Center)

        Scroll() {
          Column({ space: Space.xs }) {
            if (this.mode === 'commands') {
              this.row('/model', '切换模型与选项', () => this.onCommand('model'))
              ForEach(this.commands.filter((name: string) => this.match(name)), (name: string) =>
                this.row('/' + name, 'Provider 命令（仅在消息开头生效）', () => this.onCommand(name)))
              this.row('/skill', '插入 Skill', () => this.onCommand('skill'))
            } else if (this.mode === 'skill') {
              if (this.skills.filter((name: string) => this.match(name)).length === 0) {
                Text('没有匹配的 Skill').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
              }
              ForEach(this.skills.filter((name: string) => this.match(name)), (name: string) =>
                this.row('skill:' + name, '作为结构化上下文附加', () => this.onSkill(name)))
            } else if (this.mode === 'mention') {
              if (!this.query.trim()) {
                Text('输入文件名或路径开始搜索').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
              }
              ForEach(this.files.filter((path: string) => this.match(path)), (path: string) =>
                this.row(path, '附加文件引用', () => this.onFile(path)))
            } else if (this.mode === 'environment') {
              ForEach(this.environments, (label: string) =>
                this.row(label, '切换到该环境', () => this.onEnvironment(label)))
            } else {
              if (this.worktree) {
                this.row('工作区：新工作树', '切换到当前 checkout', () => this.onWorktree(false))
              } else {
                this.row('工作区：当前 checkout', '切换到新工作树', () => this.onWorktree(true))
              }
              if (this.worktree) {
                Row() {
                  Column({ space: 2 }) {
                    Text('从远端更新起点').fontSize(FontSize.body).fontColor($r('app.color.ink')).width('100%')
                    Text('关闭时从本地分支创建').fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Toggle({ type: ToggleType.Switch, isOn: this.startFromOrigin }).enabled(!this.busy)
                    .onChange((value: boolean) => this.onStartFromOrigin(value))
                }.width('100%').padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
                  .backgroundColor($r('app.color.card')).borderRadius(Radius.card)
              }
              ForEach(this.branches.filter((ref: BranchView) => this.match(ref.name)), (ref: BranchView) =>
                this.row(ref.name, (ref.current ? '当前 · ' : '') + (ref.isRemote ? '远端 · ' : '') +
                  (ref.worktreePath ? '已有工作树' : ref.isDefault ? '默认分支' : '本地分支'), () => this.onBranch(ref)))
              if (!this.worktree && this.query.trim()) {
                AppButton({
                  label: '将当前 checkout 切换到 “' + this.query.trim() + '”',
                  kind: 'secondary',
                  fill: true,
                  disabled: this.busy,
                  onTap: this.onSwitchCheckout
                })
              }
            }
          }.width('100%').alignItems(HorizontalAlign.Start)
        }.layoutWeight(1).width('100%').align(Alignment.TopStart)
      }.layoutWeight(1).width('100%').padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.md })
    }.width('100%').height('100%').foregroundColor($r('app.color.ink')).backgroundColor($r('app.color.group'))
  }
}

