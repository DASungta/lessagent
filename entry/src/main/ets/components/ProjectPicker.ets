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
      Row({ space: 6 }) {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ui_back')).width(22).height(22)
        }.width(44).height(44).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
          .fontSize(26).accessibilityText('返回').onClick(this.onBack)
        Text('选择项目').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        if (!this.shareTarget) {
          Button({ type: ButtonType.Circle }) {
            Image($r('app.media.ui_plus')).width(22).height(22)
          }.width(44).height(44).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
            .fontSize(24).accessibilityText('添加项目').enabled(!this.busy).onClick(this.onAddProject)
        }
      }.width('100%').padding({ top: 8, bottom: 12 })
      Column({ space: 10 }) {
        Select(this.environments.map((environment: AddProjectEnvironment) => {
          return { value: environment.label } as SelectOption;
        }))
          .value(this.environments.find((environment: AddProjectEnvironment) => environment.environmentId === this.environmentId)?.label || '所有环境')
          .constraintSize({ minHeight: 44 }).font({ size: 13 }).backgroundColor($r('app.color.surface'))
          .onSelect((index: number) => this.onEnvironment(this.environments[index]?.environmentId || ''))
        TextInput({ placeholder: '搜索项目', text: this.query }).height(44).width('100%')
          .fontSize(14).backgroundColor($r('app.color.surface')).borderRadius(12).fontColor($r('app.color.ink'))
          .onChange((value: string) => this.onQuery(value)).accessibilityText('搜索项目')
      }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: 16 })
      Scroll() {
        Column({ space: 8 }) {
          if (this.scratchAvailable && this.scratchEnvironment()) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 12 }) {
                Text('◌').fontSize(22).fontColor($r('app.color.muted'))
                Column({ space: 3 }) {
                  Text('临时任务').fontSize(15).fontWeight(FontWeight.Medium).width('100%')
                  Text('不选择项目，直接开始任务').fontSize(12).fontColor($r('app.color.muted')).width('100%')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text('›').fontSize(18).fontColor($r('app.color.muted'))
              }.width('100%').padding(14)
            }.width('100%').backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(12)
              .enabled(!this.busy).onClick(() => this.onScratch(this.scratchEnvironment()?.environmentId || ''))
          }
          if (this.drafts.length && !this.query.trim() && !this.environmentId) {
            Text('草稿').fontSize(12).fontColor($r('app.color.muted')).width('100%').padding({ left: 4, top: 6 })
            ForEach(this.drafts.slice(0, 8), (draft: ComposerDraft) => {
              Row({ space: 4 }) {
                Button({ type: ButtonType.Normal }) {
                  Row({ space: 10 }) {
                    Image($r('app.media.ui_compose')).width(20).height(20)
                    Column({ space: 3 }) {
                      Text(composerDraftLabel(draft)).fontSize(14).maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                      Text(new Date(draft.updatedAt).toLocaleString() + ' · ' + (draft.attachments.length ? draft.attachments.length + ' 个附件' : '未发送'))
                        .fontSize(11).fontColor($r('app.color.muted')).maxLines(1).width('100%')
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    Text('›').fontSize(18).fontColor($r('app.color.muted'))
                  }.width('100%').padding(12)
                }.layoutWeight(1).backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(12)
                  .enabled(!this.busy).onClick(() => this.onResumeDraft(draft))
                Button('删除').constraintSize({ minWidth: 48, minHeight: 48 }).fontSize(12).backgroundColor($r('app.color.surface'))
                  .fontColor($r('app.color.muted')).enabled(!this.busy)
                  .accessibilityText('删除草稿：' + (composerDraftLabel(draft)))
                  .onClick(() => this.onDeleteDraft(draft))
              }.width('100%')
            }, (draft: ComposerDraft) => draft.draftId)
          }
          if (this.groups.length === 0) {
            Column({ space: 12 }) {
              Text(this.shareTarget ? '暂无可选项目' : '没有可用的项目').fontSize(20).fontWeight(FontWeight.Bold)
              Text(this.shareTarget ? '环境连接后会显示可用项目。' : this.environments.length ? '连接环境后添加项目。' : '先添加一个工作环境。')
                .fontSize(13).fontColor($r('app.color.muted')).textAlign(TextAlign.Center)
              Button(this.shareTarget ? '管理连接' : '添加项目').backgroundColor($r('app.color.primary')).fontColor($r('app.color.on_primary'))
                .constraintSize({ minHeight: 44 }).onClick(this.onAddProject)
            }.width('100%').padding(32)
          } else if (this.visible().length === 0) {
            Column({ space: 8 }) {
              Text('没有匹配的项目').fontSize(18).fontWeight(FontWeight.Medium)
              Text('换一个项目名或工作区路径。').fontSize(13).fontColor($r('app.color.muted'))
            }.width('100%').padding(28)
          } else {
            ForEach(this.visible(), (group: ProjectGroup) => {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 12 }) {
                  Image($r('app.media.ui_folder')).width(22).height(22)
                  Column({ space: 3 }) {
                    Text(group.label).fontSize(15).fontWeight(FontWeight.Medium).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                    Text(group.projects.length > 1 ? group.projects.length + ' 个工作区' : this.target(group).workspaceRoot)
                      .fontSize(12).fontColor($r('app.color.muted')).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  if (group.pinned) { Text('固定').fontSize(10).fontColor($r('app.color.primary')) }
                  Text('›').fontSize(18).fontColor($r('app.color.muted'))
                }.width('100%').padding(14)
              }.width('100%').backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(12)
                .enabled(!this.busy).onClick(() => this.onSelect(this.target(group)))
            }, (group: ProjectGroup) => group.key)
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').padding({ left: 16, right: 16, bottom: 12 })
      .foregroundColor($r('app.color.ink')).backgroundColor($r('app.color.canvas'))
  }
}
