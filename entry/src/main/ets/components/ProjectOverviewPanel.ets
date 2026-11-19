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
      Row({ space: 6 }) {
        Button('‹').width(44).height(44).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
          .fontSize(26).accessibilityText('返回设置').onClick(this.onBack)
        Text('项目').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('添加项目').constraintSize({ minHeight: 44 }).fontSize(14)
          .backgroundColor(Color.Transparent).fontColor($r('app.color.primary')).enabled(!this.busy)
          .onClick(this.onAddProject)
      }.width('100%').padding({ left: 8, right: 12, top: 8, bottom: 6 })
      if (this.groups.length > 1) {
        Select(this.groups.map((group: ProjectGroup) => { return { value: group.label } as SelectOption; }))
          .value(this.group()?.label || '选择项目')
          .onSelect((index: number) => this.onSelectGroup(this.groups[index]?.key || ''))
          .width('100%').height(40).font({ size: 13 }).backgroundColor($r('app.color.surface'))
          .margin({ left: 16, right: 16, bottom: 8 })
      }
      Scroll() {
        Column({ space: 16 }) {
          if (!this.group()) {
            Column({ space: 8 }) {
              Text('选择一个项目').fontSize(20).fontWeight(FontWeight.Bold)
              Text('管理名称、固定、归档和 checkout。').fontSize(13).fontColor($r('app.color.muted'))
            }.width('100%').padding(28)
          } else {
            Row({ space: 12 }) {
              Text('▱').fontSize(30).fontColor($r('app.color.muted'))
              Column({ space: 3 }) {
                Text(this.group()?.label || '').fontSize(20).fontWeight(FontWeight.Medium).maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                Text((this.group()?.projects.length || 0) + ' 个 checkout').fontSize(12)
                  .fontColor($r('app.color.muted')).width('100%')
                if (this.group()?.representative.repository) {
                  Text('仓库 · ' + (this.group()?.representative.repository?.displayName ||
                    this.group()?.representative.repository?.name ||
                    this.group()?.representative.repository?.groupingKey || ''))
                    .fontSize(11).fontColor($r('app.color.muted')).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                }
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }.width('100%')
            Column({ space: 8 }) {
              Text('名称').fontSize(12).fontColor($r('app.color.muted')).width('100%')
              Row({ space: 8 }) {
                TextInput({ text: this.draftName }).layoutWeight(1).height(44).fontSize(14)
                  .onChange((value: string) => this.draftName = value).accessibilityText('项目名称')
                if (this.canSave()) {
                  Button('保存').height(44).backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
                    .onClick(() => { const group = this.group(); if (group) this.onRename(group, this.draftName); })
                }
              }.width('100%')
            }.width('100%').padding(14).backgroundColor($r('app.color.surface')).borderRadius(14)
            if (this.canOrganize) {
              Column({ space: 10 }) {
                Text('整理').fontSize(12).fontColor($r('app.color.muted')).width('100%')
                Row() {
                  Column({ space: 3 }) {
                    Text('固定').fontSize(14).fontWeight(FontWeight.Medium).width('100%')
                    Text('固定项目会排在项目选择器前面。').fontSize(11).fontColor($r('app.color.muted')).width('100%')
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Toggle({ type: ToggleType.Switch, isOn: !!this.group()?.pinned }).enabled(!this.busy)
                    .onChange((value: boolean) => { const group = this.group(); if (group && value !== group.pinned) this.onPin(group, value); })
                }.width('100%')
                Row() {
                  Column({ space: 3 }) {
                    Text(this.group()?.archived ? '取消归档项目' : '归档项目').fontSize(14).fontWeight(FontWeight.Medium).width('100%')
                    Text('从项目选择器隐藏；会话和磁盘文件保留。').fontSize(11).fontColor($r('app.color.muted')).width('100%')
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Button(this.group()?.archived ? '取消归档' : '归档').height(36).backgroundColor(Color.Transparent)
                    .fontColor($r('app.color.primary')).enabled(!this.busy)
                    .onClick(() => { const group = this.group(); if (group) this.onArchive(group, !group.archived); })
                }.width('100%')
              }.width('100%').padding(14).backgroundColor($r('app.color.surface')).borderRadius(14)
            }
            Column({ space: 8 }) {
              Text('Checkouts').fontSize(12).fontColor($r('app.color.muted')).width('100%')
              ForEach(this.group()?.projects || [], (project: ScopedProject) => {
                Column({ space: 4 }) {
                  Row({ space: 8 }) {
                    Text(project.environmentLabel).fontSize(14).fontWeight(FontWeight.Medium).layoutWeight(1)
                    if ((this.group()?.projects.length || 0) > 1) {
                      Button('移除 checkout').height(32).fontSize(11).backgroundColor(Color.Transparent)
                        .fontColor($r('app.color.danger')).enabled(!this.busy)
                        .onClick(() => this.onRemoveCheckout(project))
                    }
                  }.width('100%')
                  Text(project.workspaceRoot).fontSize(11).fontColor($r('app.color.muted'))
                    .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                }.width('100%').padding(12).backgroundColor($r('app.color.surface')).borderRadius(10)
              }, (project: ScopedProject) => project.localId + ':' + project.id)
            }.width('100%')
            Column({ space: 6 }) {
              Text('危险操作').fontSize(12).fontColor($r('app.color.danger')).width('100%')
              Text('删除项目记录和会话，不删除磁盘文件。')
                .fontSize(11).fontColor($r('app.color.muted')).width('100%')
              Button((this.group()?.projects.length || 0) > 1 ? '在所有 checkout 删除项目' : '删除项目')
                .height(44).width('100%').backgroundColor($r('app.color.surface')).fontColor($r('app.color.danger'))
                .enabled(!this.busy).onClick(() => { const group = this.group(); if (group) this.onRemoveProject(group); })
            }.width('100%').padding(14).backgroundColor($r('app.color.surface')).borderRadius(14)
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16, bottom: 20 })
      }.width('100%').layoutWeight(1)
    }.width('100%').height('100%').foregroundColor($r('app.color.ink')).backgroundColor($r('app.color.canvas'))
  }
}
