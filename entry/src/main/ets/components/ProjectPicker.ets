import { TopBar } from './ui/TopBar';
import { IconButton } from './ui/IconButton';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';
import { ProjectMonogram } from './ui/ProjectMonogram';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { AddProjectEnvironment } from '../services/Workspace';
import { ProjectGroup, ScopedProject, projectMatchesQuery } from '../protocol/Projects';
import { ComposerDraft, composerDraftLabel } from '../protocol/R4';

@Component
export struct ProjectPicker {
  @Prop groups: ProjectGroup[] = [];
  @Prop environments: AddProjectEnvironment[] = [];
  @Prop environmentId: string = '';
  @Prop query: string = '';
  @Prop scratchAvailable: boolean = false;
  @Prop busy: boolean = false;
  @Prop shareTarget: boolean = false;
  @Prop drafts: ComposerDraft[] = [];
  onBack: () => void = () => {};
  onAddProject: () => void = () => {};
  onSelect: (project: ScopedProject) => void = () => {};
  onScratch: (environmentId: string) => void = () => {};
  onQuery: (value: string) => void = () => {};
  onEnvironment: (environmentId: string) => void = () => {};
  onResumeDraft: (draft: ComposerDraft) => void = () => {};
  onDeleteDraft: (draft: ComposerDraft) => void = () => {};

  private visible(): ProjectGroup[] {
    const matches = this.groups.filter((group: ProjectGroup) =>
      (!this.environmentId || group.projects.some((project: ScopedProject) => project.environmentId === this.environmentId)) &&
      (projectMatchesQuery(group.representative, this.query) ||
        group.projects.some((project: ScopedProject) => projectMatchesQuery(project, this.query))));
    return matches.filter((group: ProjectGroup) => group.pinned).concat(matches.filter((group: ProjectGroup) => !group.pinned));
  }
  private target(group: ProjectGroup): ScopedProject {
    return group.projects.find((project: ScopedProject) => project.environmentId === this.environmentId) ||
      group.representative;
  }
  private scratchEnvironment(): AddProjectEnvironment | undefined {
    return this.environments.find((environment: AddProjectEnvironment) =>
      environment.environmentId === this.environmentId && environment.scratchWorkspaceRoot && environment.ready) ||
      this.environments.find((environment: AddProjectEnvironment) => environment.scratchWorkspaceRoot && environment.ready);
  }

  build() {
    Column({ space: 0 }) {
      TopBar({ title: '选择项目', showBack: true, backLabel: '返回', onBack: () => this.onBack() }) {
        if (!this.shareTarget) {
          IconButton({
            icon: $r('app.media.ui_plus'),
            label: '添加项目',
            disabled: this.busy,
            onTap: () => this.onAddProject()
          })
        }
      }

      Column({ space: Space.xs }) {
        Row({ space: Space.xs }) {
          Image($r('app.media.ui_search')).width(16).height(16).opacity(0.6).accessibilityLevel('no')
          TextInput({ placeholder: '搜索项目', text: this.query })
            .layoutWeight(1).height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
            .placeholderColor($r('app.color.placeholder')).backgroundColor(Color.Transparent).padding(0)
            .onChange((value: string) => this.onQuery(value)).accessibilityText('搜索项目')
          if (this.environments.length > 0) {
            Select(this.environments.map((environment: AddProjectEnvironment) => {
              return { value: environment.label } as SelectOption;
            }))
              .value(this.environments.find((environment: AddProjectEnvironment) => environment.environmentId === this.environmentId)?.label || '所有环境')
              .constraintSize({ minHeight: 34, maxWidth: 140 }).font({ size: FontSize.caption })
              .backgroundColor($r('app.color.group')).fontColor($r('app.color.ink'))
              .onSelect((index: number) => this.onEnvironment(this.environments[index]?.environmentId || ''))
          }
        }
        .width('100%').padding({ left: Space.sm, right: Space.xs }).backgroundColor($r('app.color.card'))
        .borderRadius(Radius.button).alignItems(VerticalAlign.Center)
      }.width('100%').padding({ left: Space.sm, right: Space.sm, top: Space.xxs, bottom: Space.xs })

      Scroll() {
        Column({ space: 0 }) {
          if (this.scratchAvailable && this.scratchEnvironment()) {
            GroupCard() {
              FormRow({
                kind: 'value',
                label: '临时任务',
                subtitle: '不选择项目，直接开始任务',
                value: '',
                disabled: this.busy,
                isFirst: true,
                onTap: () => this.onScratch(this.scratchEnvironment()?.environmentId || '')
              })
            }
          }
          if (this.drafts.length && !this.query.trim() && !this.environmentId) {
            GroupCard({ title: '草稿' }) {
              ForEach(this.drafts.slice(0, 8), (draft: ComposerDraft, index: number) => {
                Row({ space: Space.xs }) {
                  Button({ type: ButtonType.Normal }) {
                    Row({ space: Space.sm }) {
                      Image($r('app.media.ui_compose')).width(18).height(18).opacity(0.75).accessibilityLevel('no')
                      Column({ space: 2 }) {
                        Text(composerDraftLabel(draft)).fontSize(FontSize.body).lineHeight(LineHeight.body)
                          .fontColor($r('app.color.ink')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                        Text(new Date(draft.updatedAt).toLocaleString() + ' · ' + (draft.attachments.length ? draft.attachments.length + ' 个附件' : '未发送'))
                          .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).maxLines(1).width('100%')
                      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                      Image($r('app.media.ui_chevron_right')).width(Sizes.chevron).height(Sizes.chevron).opacity(0.6).accessibilityLevel('no')
                    }.width('100%').alignItems(VerticalAlign.Center)
                  }.layoutWeight(1).backgroundColor(Color.Transparent).padding(0)
                    .enabled(!this.busy).onClick(() => this.onResumeDraft(draft))
                  AppButton({
                    label: '删除', kind: 'danger', compact: true, disabled: this.busy,
                    a11yLabel: '删除草稿：' + composerDraftLabel(draft),
                    onTap: () => this.onDeleteDraft(draft)
                  })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                .constraintSize({ minHeight: Sizes.formRowMin })
                .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
              }, (draft: ComposerDraft) => draft.draftId)
            }
          }

          if (this.groups.length === 0) {
            GroupCard() {
              Column({ space: Space.xs }) {
                Text(this.shareTarget ? '暂无可选项目' : '没有可用的项目')
                  .fontSize(FontSize.headline).fontWeight(Weight.semibold).fontColor($r('app.color.ink'))
                Text(this.shareTarget ? '环境连接后会显示可用项目。' : this.environments.length ? '连接环境后添加项目。' : '先添加一个工作环境。')
                  .fontSize(FontSize.callout).fontColor($r('app.color.muted')).textAlign(TextAlign.Center)
                Column() {
                  AppButton({
                    label: this.shareTarget ? '管理连接' : '添加项目',
                    kind: 'primary',
                    onTap: () => this.onAddProject()
                  })
                }.padding({ top: Space.xs })
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: Space.lg, bottom: Space.lg })
              .alignItems(HorizontalAlign.Center)
            }
          } else if (this.visible().length === 0) {
            GroupCard() {
              FormRow({
                kind: 'value', label: '没有匹配的项目', subtitle: '换一个项目名或工作区路径。',
                value: '', valueMuted: true, chevron: false, isFirst: true
              })
            }
          } else {
            GroupCard({ title: '全部项目' }) {
              ForEach(this.visible(), (group: ProjectGroup, index: number) => {
                Button({ type: ButtonType.Normal }) {
                  Row({ space: Space.sm }) {
                    ProjectMonogram({ projectId: group.representative.id || group.key, name: group.label })
                    Column({ space: 2 }) {
                      Text(group.label).fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.medium)
                        .fontColor($r('app.color.ink')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                      Text(group.projects.length > 1 ? group.projects.length + ' 个工作区' : this.target(group).workspaceRoot)
                        .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    if (group.pinned) {
                      StatusBadge({ text: '固定', tone: 'info' })
                    }
                    Image($r('app.media.ui_chevron_right')).width(Sizes.chevron).height(Sizes.chevron).opacity(0.6).accessibilityLevel('no')
                  }.width('100%').alignItems(VerticalAlign.Center)
                }
                .width('100%')
                .backgroundColor(Color.Transparent)
                .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                .constraintSize({ minHeight: Sizes.formRowMin })
                .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
                .enabled(!this.busy)
                .onClick(() => this.onSelect(this.target(group)))
              }, (group: ProjectGroup) => group.key)
            }
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: Space.sm, right: Space.sm, bottom: Space.lg })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').foregroundColor($r('app.color.ink')).backgroundColor($r('app.color.group'))
  }
}
