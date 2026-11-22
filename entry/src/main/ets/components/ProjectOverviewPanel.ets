import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';
import { ProjectMonogram } from './ui/ProjectMonogram';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import {
  PROJECT_TRACKED_FOLDERS_MAX,
  ProjectGroup,
  ProjectTrackedFolder,
  ScopedProject,
  groupProjectIcon,
  inferProjectTitle
} from '../protocol/Projects';
import {
  WorkspaceFolder,
  WorkspaceScannedFolder,
  appendTrackedFolders,
  folderStateLabel,
  suggestedTrackedFolders
} from '../protocol/ThreadRepositories';
import { T3Client } from '../services/T3Client';

@Component
struct ProjectRepositoriesSection {
  @Prop @Watch('reload') project: ScopedProject;
  @Prop title: string = '关联仓库';
  @Prop busy: boolean = false;
  connection: T3Client | undefined = undefined;
  onTrackFolder: (project: ScopedProject, folderPath: string, name: string) => Promise<void> = async () => {};
  onUntrackFolder: (project: ScopedProject, folderPath: string) => Promise<void> = async () => {};

  @State listedFolders: WorkspaceFolder[] | undefined = undefined;
  @State scannedFolders: WorkspaceScannedFolder[] = [];
  @State loading: boolean = false;
  @State saving: boolean = false;
  @State addingOpen: boolean = false;
  @State draftPath: string = '';
  @State draftName: string = '';
  @State error: string = '';
  private loadGeneration: number = 0;

  aboutToAppear(): void {
    void this.reload();
  }

  private canEdit(): boolean {
    const conn = this.connection;
    return !!conn && conn.ready && conn.canScope('orchestration:operate') !== false;
  }

  private canReadFiles(): boolean {
    const conn = this.connection;
    return !!conn && conn.ready && conn.canReadFiles();
  }

  private async reload(): Promise<void> {
    const gen = ++this.loadGeneration;
    const conn = this.connection;
    if (!conn || !conn.ready || !this.canReadFiles()) {
      this.listedFolders = undefined;
      this.scannedFolders = [];
      this.loading = false;
      return;
    }
    this.loading = true;
    this.error = '';
    try {
      const folders = await conn.listWorkspaceFolders(this.project.id);
      if (gen !== this.loadGeneration) return;
      this.listedFolders = folders;
    } catch (_) {
      if (gen !== this.loadGeneration) return;
      this.listedFolders = undefined;
    }
    try {
      if (this.project.workspaceRoot) {
        const scanned = await conn.scanWorkspaceFolders(this.project.workspaceRoot);
        if (gen !== this.loadGeneration) return;
        this.scannedFolders = scanned.folders;
      } else {
        this.scannedFolders = [];
      }
    } catch (_) {
      if (gen !== this.loadGeneration) return;
      this.scannedFolders = [];
    } finally {
      if (gen === this.loadGeneration) this.loading = false;
    }
  }

  private displayFolders(): WorkspaceFolder[] {
    if (this.listedFolders !== undefined) return this.listedFolders;
    const tracked = this.project.trackedFolders || [];
    return tracked.map((folder: ProjectTrackedFolder): WorkspaceFolder => ({
      name: folder.name,
      path: folder.path,
      state: '',
      discovered: folder.discovered
    }));
  }

  private suggestions(): ProjectTrackedFolder[] {
    const current: ProjectTrackedFolder[] = this.displayFolders().map((folder: WorkspaceFolder): ProjectTrackedFolder => ({
      path: folder.path,
      name: folder.name,
      discovered: folder.discovered
    }));
    return suggestedTrackedFolders(current, this.scannedFolders);
  }

  private addedFolders(): ProjectTrackedFolder[] {
    return this.displayFolders()
      .filter((folder: WorkspaceFolder) => folder.discovered !== true)
      .map((folder: WorkspaceFolder): ProjectTrackedFolder => ({ path: folder.path, name: folder.name }));
  }

  private async addFolder(folderPath: string, name: string): Promise<void> {
    if (this.saving || this.busy || !this.canEdit()) return;
    const trimmedPath = folderPath.trim();
    if (!trimmedPath) {
      this.error = '请输入仓库或目录的绝对路径';
      return;
    }
    const cleanName = (name.trim() || inferProjectTitle(trimmedPath)).slice(0, 128);
    const next = appendTrackedFolders(this.addedFolders(), [{ path: trimmedPath, name: cleanName }]);
    if (next === null) {
      this.error = '每个项目最多关联 ' + PROJECT_TRACKED_FOLDERS_MAX + ' 个目录';
      return;
    }
    this.saving = true;
    this.error = '';
    try {
      await this.onTrackFolder(this.project, trimmedPath, cleanName);
      this.draftPath = '';
      this.draftName = '';
      this.addingOpen = false;
      await this.reload();
    } catch (reason) {
      this.error = (reason as Error).message || '添加仓库失败';
    } finally {
      this.saving = false;
    }
  }

  private confirmRemove(folder: WorkspaceFolder): void {
    AlertDialog.show({
      title: '移除关联仓库？',
      message: '智能体将不再在此项目内访问「' + folder.name + '」。磁盘文件不会被删除。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '移除',
        fontColor: $r('app.color.danger'),
        action: () => { void this.removeFolder(folder.path); }
      }
    });
  }

  private async removeFolder(folderPath: string): Promise<void> {
    if (this.saving || this.busy || !this.canEdit()) return;
    this.saving = true;
    this.error = '';
    try {
      await this.onUntrackFolder(this.project, folderPath);
      await this.reload();
    } catch (reason) {
      this.error = (reason as Error).message || '移除仓库失败';
    } finally {
      this.saving = false;
    }
  }

  build() {
    GroupCard({
      title: this.title,
      footnote: this.displayFolders().length === 0 && this.suggestions().length === 0
        ? '项目根目录内的子 Git 仓库会自动纳入；也可添加项目目录外的仓库或目录。'
        : '自动发现的仓库随磁盘状态同步；手动关联的仓库可随时移除，不触碰磁盘文件。'
    }) {
      Column({ space: 0 }) {
        if (this.displayFolders().length > 0) {
          ForEach(this.displayFolders(), (folder: WorkspaceFolder, index: number) => {
            Column({ space: 3 }) {
              Row({ space: Space.xs }) {
                Text(folder.name)
                  .fontSize(FontSize.body).fontWeight(Weight.medium).fontColor($r('app.color.ink'))
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                if (folder.discovered === true) {
                  StatusBadge({ text: '自动发现', tone: 'neutral' })
                }
                if (folder.state) {
                  StatusBadge({
                    text: folderStateLabel(folder.state),
                    tone: folder.state === 'missing' ? 'warning' : folder.state === 'git' ? 'info' : 'neutral'
                  })
                }
                if (folder.discovered !== true) {
                  AppButton({
                    label: '移除',
                    kind: 'danger',
                    compact: true,
                    disabled: !this.canEdit() || this.saving || this.busy || this.loading,
                    onTap: () => this.confirmRemove(folder)
                  })
                }
              }.width('100%').alignItems(VerticalAlign.Center)
              Text(folder.path)
                .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
                .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
            .constraintSize({ minHeight: Sizes.formRowMin })
            .justifyContent(FlexAlign.Center)
            .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
          }, (folder: WorkspaceFolder) => folder.path + ':' + folder.name + ':' + folder.state + ':' + (folder.discovered ? '1' : '0'))
        }

        if (this.suggestions().length > 0) {
          ForEach(this.suggestions(), (folder: ProjectTrackedFolder, index: number) => {
            Row({ space: Space.xs }) {
              Column({ space: 2 }) {
                Text('添加 ' + folder.name)
                  .fontSize(FontSize.body).fontWeight(Weight.medium).fontColor($r('app.color.ink'))
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                Text('来自工作区文件 · ' + folder.path)
                  .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              AppButton({
                label: '添加',
                kind: 'secondary',
                compact: true,
                disabled: !this.canEdit() || this.saving || this.busy || this.loading,
                onTap: () => { void this.addFolder(folder.path, folder.name); }
              })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
            .constraintSize({ minHeight: Sizes.formRowMin })
            .border({
              width: { top: (this.displayFolders().length === 0 && index === 0) ? 0 : Sizes.hairline },
              color: { top: $r('app.color.separator') }
            })
          }, (folder: ProjectTrackedFolder) => 'suggest:' + folder.path)
        }

        if (this.canEdit()) {
          Column({ space: Space.xs }) {
            if (!this.addingOpen) {
              Row({ space: Space.xs }) {
                AppButton({
                  label: '添加关联仓库',
                  kind: 'secondary',
                  compact: true,
                  disabled: this.saving || this.busy,
                  onTap: () => { this.addingOpen = true; this.error = ''; }
                })
                if (this.loading) {
                  Text('正在检查磁盘…').fontSize(FontSize.caption).fontColor($r('app.color.muted'))
                }
              }.width('100%').alignItems(VerticalAlign.Center)
            } else {
              TextInput({ text: this.draftPath, placeholder: '仓库目录绝对路径（如 /path/to/repo）' })
                .width('100%').height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
                .placeholderColor($r('app.color.placeholder'))
                .backgroundColor($r('app.color.group')).borderRadius(Radius.tool).padding({ left: 10, right: 10 })
                .enabled(!this.saving && !this.busy)
                .accessibilityText('关联仓库路径')
                .onChange((value: string) => { this.draftPath = value; })
              TextInput({ text: this.draftName, placeholder: '显示名称（可选，默认取目录名）' })
                .width('100%').height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
                .placeholderColor($r('app.color.placeholder'))
                .backgroundColor($r('app.color.group')).borderRadius(Radius.tool).padding({ left: 10, right: 10 })
                .enabled(!this.saving && !this.busy)
                .accessibilityText('关联仓库名称')
                .onChange((value: string) => { this.draftName = value; })
              Row({ space: Space.xs }) {
                AppButton({
                  label: this.saving ? '添加中…' : '确认添加',
                  kind: 'primary',
                  compact: true,
                  disabled: this.saving || this.busy || !this.draftPath.trim(),
                  onTap: () => { void this.addFolder(this.draftPath, this.draftName); }
                })
                AppButton({
                  label: '取消',
                  kind: 'secondary',
                  compact: true,
                  disabled: this.saving || this.busy,
                  onTap: () => { this.addingOpen = false; this.draftPath = ''; this.draftName = ''; this.error = ''; }
                })
              }.width('100%')
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
          .border({
            width: { top: (this.displayFolders().length === 0 && this.suggestions().length === 0) ? 0 : Sizes.hairline },
            color: { top: $r('app.color.separator') }
          })
        }

        if (this.error) {
          Text(this.error)
            .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.danger'))
            .padding({ left: 14, right: 14, bottom: Space.xs }).width('100%')
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
  }
}

@Component
export struct ProjectOverviewPanel {
  @Prop groups: ProjectGroup[] = [];
  @Prop @Watch('sync') groupKey: string = '';
  @Prop canOrganize: boolean = false;
  @Prop busy: boolean = false;
  @State draftName: string = '';
  connectionFor: (localId: string) => T3Client | undefined = () => undefined;
  onBack: () => void = () => {};
  onAddProject: () => void = () => {};
  onSelectGroup: (key: string) => void = () => {};
  onRename: (group: ProjectGroup, title: string) => void = () => {};
  onPin: (group: ProjectGroup, pinned: boolean) => void = () => {};
  onArchive: (group: ProjectGroup, archived: boolean) => void = () => {};
  onTrackFolder: (project: ScopedProject, folderPath: string, name: string) => Promise<void> = async () => {};
  onUntrackFolder: (project: ScopedProject, folderPath: string) => Promise<void> = async () => {};
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
                  icon: groupProjectIcon(this.group()),
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

            ForEach(this.group()?.projects || [], (project: ScopedProject) => {
              ProjectRepositoriesSection({
                project,
                title: (this.group()?.projects.length || 0) > 1 ? ('关联仓库 · ' + project.environmentLabel) : '关联仓库',
                busy: this.busy,
                connection: this.connectionFor(project.localId),
                onTrackFolder: this.onTrackFolder,
                onUntrackFolder: this.onUntrackFolder
              })
            }, (project: ScopedProject) => 'repos:' + project.localId + ':' + project.id + ':' +
              (project.trackedFolders ? project.trackedFolders.map((f: ProjectTrackedFolder) => f.path).join('|') : ''))

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
