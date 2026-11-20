import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { ProjectMonogram } from './ui/ProjectMonogram';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { ProjectGroup, ScopedProject } from '../protocol/Projects';

@Component
export struct ProjectOverviewPanel {
  @Prop groups: ProjectGroup[] = [];
  @Prop @Watch('sync') groupKey: string = '';
  @Prop canOrganize: boolean = false;
  @Prop busy: boolean = false;
  @State draftName: string = '';
  onBack: () => void = () => {};
  onAddProject: () => void = () => {};
  onSelectGroup: (key: string) => void = () => {};
  onRename: (group: ProjectGroup, title: string) => void = () => {};
  onPin: (group: ProjectGroup, pinned: boolean) => void = () => {};
  onArchive: (group: ProjectGroup, archived: boolean) => void = () => {};
  onRemoveCheckout: (project: ScopedProject) => void = () => {};
  onRemoveProject: (group: ProjectGroup) => void = () => {};

  aboutToAppear(): void { this.sync(); }
  private group(): ProjectGroup | undefined {
    return this.groups.find((group: ProjectGroup) => group.key === this.groupKey);
  }
  private sync(): void { this.draftName = this.group()?.label || ''; }
  private canSave(): boolean {
    const group = this.group();
    return !!group && !this.busy && !!this.draftName.trim() && this.draftName.trim() !== group.label;
  }

  build() {
    Column({ space: 0 }) {
      TopBar({ title: '项目', showBack: true, backLabel: '返回设置', onBack: () => this.onBack() }) {
        AppButton({ label: '添加项目', kind: 'text', disabled: this.busy, onTap: () => this.onAddProject() })
      }
      if (this.groups.length > 1) {
        Column() {
          Select(this.groups.map((group: ProjectGroup) => { return { value: group.label } as SelectOption; }))
            .value(this.group()?.label || '选择项目')
            .onSelect((index: number) => this.onSelectGroup(this.groups[index]?.key || ''))
            .width('100%').height(40).font({ size: FontSize.callout }).backgroundColor($r('app.color.card'))
            .fontColor($r('app.color.ink'))
        }.width('100%').padding({ left: Space.sm, right: Space.sm, top: Space.xxs, bottom: Space.xs })
      }
      Scroll() {
        Column({ space: 0 }) {
          if (!this.group()) {
            GroupCard() {
              FormRow({
                kind: 'value', label: '选择一个项目', subtitle: '管理名称、固定、归档和 checkout。',
                value: '', valueMuted: true, chevron: false, isFirst: true
              })
            }
          } else {
            GroupCard() {
              Row({ space: Space.sm }) {
                ProjectMonogram({
                  projectId: this.group()?.representative.id || this.group()?.key || '',
                  name: this.group()?.label || '',
                  boxSize: 36
                })
                Column({ space: 2 }) {
                  Text(this.group()?.label || '')
                    .fontSize(FontSize.headline).lineHeight(LineHeight.headline).fontWeight(Weight.semibold)
                    .fontColor($r('app.color.ink')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  Text((this.group()?.projects.length || 0) + ' 个 checkout' + (this.group()?.representative.repository
                    ? (' · ' + (this.group()?.representative.repository?.displayName ||
                      this.group()?.representative.repository?.name ||
                      this.group()?.representative.repository?.groupingKey || ''))
                    : ''))
                    .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
              .constraintSize({ minHeight: Sizes.formRowMin })
            }

            GroupCard({ title: '名称' }) {
              Row({ space: Space.xs }) {
                TextInput({ text: this.draftName })
                  .layoutWeight(1).height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
                  .backgroundColor($r('app.color.group')).borderRadius(Radius.tool).padding({ left: 10, right: 10 })
                  .onChange((value: string) => this.draftName = value).accessibilityText('项目名称')
                if (this.canSave()) {
                  AppButton({
                    label: '保存', kind: 'primary', compact: true,
                    onTap: () => { const group = this.group(); if (group) this.onRename(group, this.draftName); }
                  })
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
              .constraintSize({ minHeight: Sizes.formRowMin })
            }

            if (this.canOrganize) {
              GroupCard({ title: '整理' }) {
                FormRow({
                  kind: 'switch',
                  label: '固定',
                  subtitle: '固定项目会排在项目选择器前面。',
                  checked: !!this.group()?.pinned,
                  disabled: this.busy,
                  isFirst: true,
                  onToggle: (value: boolean) => {
                    const group = this.group();
                    if (group && value !== group.pinned) this.onPin(group, value);
                  }
                })
                FormRow({
                  kind: 'value',
                  label: this.group()?.archived ? '取消归档项目' : '归档项目',
                  subtitle: '从项目选择器隐藏；会话和磁盘文件保留。',
                  value: this.group()?.archived ? '取消归档' : '归档',
                  valueMuted: false,
                  disabled: this.busy,
                  onTap: () => {
                    const group = this.group();
                    if (group) this.onArchive(group, !group.archived);
                  }
                })
              }
            }

            GroupCard({ title: 'Checkouts' }) {
              ForEach(this.group()?.projects || [], (project: ScopedProject, index: number) => {
                Column({ space: 2 }) {
                  Row({ space: Space.xs }) {
                    Text(project.environmentLabel)
                      .fontSize(FontSize.body).fontWeight(Weight.medium).fontColor($r('app.color.ink')).layoutWeight(1)
                    if ((this.group()?.projects.length || 0) > 1) {
                      AppButton({
                        label: '移除 checkout', kind: 'danger', compact: true, disabled: this.busy,
                        onTap: () => this.onRemoveCheckout(project)
                      })
                    }
                  }.width('100%').alignItems(VerticalAlign.Center)
                  Text(project.workspaceRoot)
                    .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
                    .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                .constraintSize({ minHeight: Sizes.formRowMin })
                .justifyContent(FlexAlign.Center)
                .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
              }, (project: ScopedProject) => project.localId + ':' + project.id)
            }

            GroupCard({
              title: '危险操作',
              footnote: '删除项目记录和会话，不删除磁盘文件。'
            }) {
              Column() {
                AppButton({
                  label: (this.group()?.projects.length || 0) > 1 ? '在所有 checkout 删除项目' : '删除项目',
                  kind: 'danger',
                  fill: true,
                  disabled: this.busy,
                  onTap: () => { const group = this.group(); if (group) this.onRemoveProject(group); }
                })
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
              .constraintSize({ minHeight: Sizes.formRowMin })
              .justifyContent(FlexAlign.Center)
            }
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: Space.sm, right: Space.sm, bottom: Space.lg })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').foregroundColor($r('app.color.ink')).backgroundColor($r('app.color.group'))
  }
}
