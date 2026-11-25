import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { MentionItem } from '../protocol/Mentions';
import { BranchView } from '../protocol/R4';
import {
  TASK_FOLDER_DEFAULT_REPOSITORIES_MAX,
  WorktreeRepositoryChoice,
  resolveWorktreeRepositorySelection
} from '../protocol/ThreadRepositories';
import { AppButton } from './ui/AppButton';
import { ProviderLogo } from './ui/ProviderLogo';
import { TopBar } from './ui/TopBar';

@Component
export struct ComposerCommandPanel {
  @Prop mode: string = 'commands';
  @Prop query: string = '';
  @Prop busy: boolean = false;
  @Prop commands: string[] = [];
  @Prop skills: string[] = [];
  @Prop files: string[] = [];
  @Prop mentionThreads: MentionItem[] = [];
  @Prop mentionEnvironments: MentionItem[] = [];
  @Prop mentionModels: MentionItem[] = [];
  @Prop mentionFileItems: MentionItem[] = [];
  @Prop mentionLoading: boolean = false;
  @Prop branches: BranchView[] = [];
  @Prop environments: string[] = [];
  @Prop repoChoices: WorktreeRepositoryChoice[] = [];
  @Prop repoChoicesLoaded: boolean = true;
  @Prop selectedRepos: string[] | undefined = undefined;
  onClose: () => void = () => {};
  onQuery: (value: string) => void = () => {};
  onCommand: (value: string) => void = () => {};
  onSkill: (value: string) => void = () => {};
  onFile: (value: string) => void = () => {};
  onMentionSelect: (item: MentionItem) => void = () => {};
  onBranch: (value: BranchView) => void = () => {};
  onEnvironment: (value: string) => void = () => {};
  onWorktree: (value: boolean) => void = () => {};
  onStartFromOrigin: (value: boolean) => void = () => {};
  onSwitchCheckout: () => void = () => {};
  onRepositoriesChange: (paths: string[]) => void = () => {};
  onOpenRepositories: () => void = () => {};
  @Prop worktree: boolean = false;
  @Prop startFromOrigin: boolean = true;

  private match(value: string): boolean {
    return value.toLowerCase().includes(this.query.trim().toLowerCase());
  }

  private effectiveSelectedRepos(): string[] {
    return resolveWorktreeRepositorySelection(
      this.repoChoicesLoaded ? this.repoChoices : null,
      this.selectedRepos
    ).selected;
  }

  private toggleRepo(path: string): void {
    const current = this.effectiveSelectedRepos();
    const exists = current.includes(path);
    const next = exists
      ? current.filter((item: string) => item !== path)
      : this.repoChoices
          .map((choice: WorktreeRepositoryChoice) => choice.repositoryPath)
          .filter((candidate: string) => candidate === path || current.includes(candidate));
    this.onRepositoriesChange(next);
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

  @Builder checkRow(label: string, detail: string, checked: boolean, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: Space.sm }) {
        Column({ space: 2 }) {
          Text(label).fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.medium)
            .fontColor($r('app.color.ink')).width('100%').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (detail) {
            Text(detail).fontSize(FontSize.caption).lineHeight(LineHeight.caption)
              .fontColor($r('app.color.muted')).width('100%').maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(checked ? '✓' : '')
          .fontSize(FontSize.headline).fontWeight(Weight.semibold).fontColor($r('app.color.primary_text'))
          .width(22).textAlign(TextAlign.End)
      }.width('100%').padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
    }.width('100%').padding(0).backgroundColor($r('app.color.card')).borderRadius(Radius.card)
      .enabled(!this.busy)
      .accessibilityText(label + (checked ? '，已选中' : '，未选中'))
      .onClick(action)
  }

  @Builder mentionSectionHeader(title: string) {
    Text(title)
      .fontSize(FontSize.caption)
      .lineHeight(LineHeight.caption)
      .fontWeight(Weight.semibold)
      .fontColor($r('app.color.muted'))
      .width('100%')
      .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs, bottom: 2 })
  }

  @Builder mentionRow(item: MentionItem) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: Space.sm }) {
        if (item.kind === 'model') {
          Row() {
            ProviderLogo({ driver: item.providerDriver, model: item.model, logoSize: 18 })
          }.width(20).height(20).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center).flexShrink(0)
        } else {
          Image(
            item.kind === 'thread' ? $r('app.media.ui_tab_chats') :
            item.kind === 'environment' ? $r('app.media.ui_env_desktop') :
            item.fileKind === 'directory' ? $r('app.media.ui_folder') :
            $r('app.media.ui_tool_file')
          )
            .width(17)
            .height(17)
            .opacity(0.75)
            .flexShrink(0)
            .accessibilityLevel('no')
        }
        Column({ space: 2 }) {
          Text(item.label)
            .fontSize(FontSize.body)
            .lineHeight(LineHeight.body)
            .fontWeight(Weight.medium)
            .fontColor($r('app.color.ink'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (item.description) {
            Text(item.description)
              .fontSize(FontSize.caption)
              .lineHeight(LineHeight.caption)
              .fontColor($r('app.color.muted'))
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Image($r('app.media.ui_chevron_right')).width(Sizes.chevron).height(Sizes.chevron).opacity(0.45).accessibilityLevel('no')
      }.width('100%').padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
    }.width('100%').padding(0).backgroundColor($r('app.color.card')).borderRadius(Radius.card)
      .enabled(!this.busy).onClick(() => this.onMentionSelect(item))
  }

  private hasMentionItems(): boolean {
    return this.mentionThreads.length > 0 ||
      this.mentionEnvironments.length > 0 ||
      this.mentionModels.length > 0 ||
      this.mentionFileItems.length > 0 ||
      this.files.length > 0;
  }

  build() {
    Column() {
      TopBar({
        title: this.mode === 'branch' ? '分支与工作区' : this.mode === 'repositories' ? '选择关联仓库' :
          this.mode === 'environment' ? '环境' : this.mode === 'mention' ? '文件与提及' :
          this.mode === 'skill' ? 'Skills' : '命令',
        showBack: true,
        closeStyle: true,
        onBack: this.onClose
      })
      Column({ space: Space.sm }) {
        Row({ space: Space.xs }) {
          Image($r('app.media.ui_search')).width(16).height(16).opacity(0.6).accessibilityLevel('no')
          TextInput({
            placeholder: this.mode === 'mention' ? '搜索会话、环境、模型或文件' : this.mode === 'branch' ? '搜索分支' :
              this.mode === 'repositories' ? '筛选仓库' : '输入以筛选',
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
              if (this.mentionThreads.length > 0) {
                if (this.query.trim()) {
                  this.mentionSectionHeader('会话')
                } else {
                  this.mentionSectionHeader('最近会话')
                }
                ForEach(this.mentionThreads, (item: MentionItem) => {
                  this.mentionRow(item)
                }, (item: MentionItem) => item.id + '|' + item.label + '|' + item.description)
              }
              if (this.mentionEnvironments.length > 0) {
                this.mentionSectionHeader('环境')
                ForEach(this.mentionEnvironments, (item: MentionItem) => {
                  this.mentionRow(item)
                }, (item: MentionItem) => item.id + '|' + item.label)
              }
              if (this.mentionModels.length > 0) {
                this.mentionSectionHeader('模型')
                ForEach(this.mentionModels, (item: MentionItem) => {
                  this.mentionRow(item)
                }, (item: MentionItem) => item.id + '|' + item.label)
              }
              if (this.mentionFileItems.length > 0) {
                this.mentionSectionHeader('工作区文件')
                ForEach(this.mentionFileItems, (item: MentionItem) => {
                  this.mentionRow(item)
                }, (item: MentionItem) => item.id + '|' + item.fileKind)
              } else if (this.files.length > 0) {
                this.mentionSectionHeader('工作区文件')
                ForEach(this.files.filter((path: string) => this.match(path)), (path: string) =>
                  this.row(path, '附加文件引用', () => this.onFile(path)))
              }
              if (this.mentionLoading) {
                Row({ space: Space.xs }) {
                  LoadingProgress().width(14).height(14).color($r('app.color.muted')).accessibilityLevel('no')
                  Text(this.hasMentionItems() ? '正在搜索更多会话与文件…' : '正在搜索…')
                    .fontSize(FontSize.caption)
                    .fontColor($r('app.color.muted'))
                }.width('100%').padding({ left: Space.xxs, top: Space.xs, bottom: Space.xs }).alignItems(VerticalAlign.Center)
              } else if (!this.hasMentionItems()) {
                Text(this.query.trim()
                  ? '没有匹配的会话、环境、模型或文件'
                  : '输入关键词搜索会话、环境、模型或工作区文件')
                  .fontSize(FontSize.callout)
                  .fontColor($r('app.color.muted'))
                  .width('100%')
                  .padding({ left: Space.xxs, top: Space.xs })
              }
            } else if (this.mode === 'environment') {
              ForEach(this.environments, (label: string) =>
                this.row(label, '切换到该环境', () => this.onEnvironment(label)))
            } else if (this.mode === 'repositories') {
              if (!this.repoChoicesLoaded) {
                Text('正在加载项目关联仓库…').fontSize(FontSize.callout).fontColor($r('app.color.muted')).padding(Space.sm)
              } else if (this.repoChoices.length === 0) {
                Text('此项目未关联其他 Git 仓库').fontSize(FontSize.callout).fontColor($r('app.color.muted')).padding(Space.sm)
              } else {
                Text(this.repoChoices.length > TASK_FOLDER_DEFAULT_REPOSITORIES_MAX
                  ? '此项目关联仓库较多（>' + TASK_FOLDER_DEFAULT_REPOSITORIES_MAX + ' 个），请手动勾选需要创建独立工作树的仓库。'
                  : '选择新建工作树任务时一并隔离的关联仓库。')
                  .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
                  .width('100%').padding({ left: Space.xxs, right: Space.xxs })
                Row({ space: Space.xs }) {
                  AppButton({
                    label: '全选',
                    kind: 'secondary',
                    compact: true,
                    disabled: this.busy || this.effectiveSelectedRepos().length === this.repoChoices.length,
                    onTap: () => this.onRepositoriesChange(
                      this.repoChoices.map((choice: WorktreeRepositoryChoice) => choice.repositoryPath)
                    )
                  })
                  AppButton({
                    label: '全不选',
                    kind: 'secondary',
                    compact: true,
                    disabled: this.busy || (this.selectedRepos !== undefined && this.effectiveSelectedRepos().length === 0),
                    onTap: () => this.onRepositoriesChange([])
                  })
                }.width('100%').padding({ bottom: Space.xxs })
                ForEach(
                  this.repoChoices.filter((choice: WorktreeRepositoryChoice) =>
                    this.match(choice.name) || this.match(choice.relativePath || choice.repositoryPath)),
                  (choice: WorktreeRepositoryChoice) => {
                    this.checkRow(
                      choice.name,
                      choice.relativePath && choice.relativePath !== choice.name ? choice.relativePath : choice.repositoryPath,
                      this.effectiveSelectedRepos().includes(choice.repositoryPath),
                      () => this.toggleRepo(choice.repositoryPath)
                    )
                  },
                  (choice: WorktreeRepositoryChoice) => choice.repositoryPath + ':' +
                    (this.effectiveSelectedRepos().includes(choice.repositoryPath) ? '1' : '0')
                )
              }
            } else {
              if (this.worktree) {
                this.row('工作区：新工作树', '切换到当前 checkout', () => this.onWorktree(false))
              } else {
                this.row('工作区：当前 checkout', '切换到新工作树', () => this.onWorktree(true))
              }
              if (this.worktree && this.repoChoices.length > 0) {
                this.row(
                  '关联仓库：' + resolveWorktreeRepositorySelection(
                    this.repoChoicesLoaded ? this.repoChoices : null,
                    this.selectedRepos
                  ).label,
                  '选择新工作树包含的仓库',
                  () => this.onOpenRepositories()
                )
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
