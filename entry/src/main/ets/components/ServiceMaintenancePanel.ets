import { T3Client } from '../services/T3Client';
import { record } from '../protocol/Wire';
import {
  DatabaseStorageView, ReleaseCheck, ServiceMaintenance, canRequestDatabaseReclaim, checkServiceRelease,
  readDatabaseStorage, readMaintenance, requestDatabaseReclaim, verifyDatabaseReclaim
} from '../protocol/ServiceMaintenance';

@Component
export struct ServiceMaintenancePanel {
  connection: T3Client | undefined = undefined;
  onBack: () => void = () => {};
  @State info: ServiceMaintenance | undefined = undefined;
  @State database: DatabaseStorageView | undefined = undefined;
  @State databaseStatus: string = '';
  @State message: string = '';
  @State release: ReleaseCheck | undefined = undefined;
  @State reclaimNeedsRefresh: boolean = false;
  @State busy: boolean = false;
  private epoch: number = 0;

  aboutToAppear(): void {
    this.busy = false;
    void this.refresh();
  }
  aboutToDisappear(): void { this.epoch++; }

  private environmentId(connection: T3Client): string {
    if (!connection.ready) return '';
    const id = record(connection.config.environment).environmentId;
    return typeof id === 'string' ? id : '';
  }
  private current(connection: T3Client, environmentId: string, epoch: number): boolean {
    return this.epoch === epoch && this.connection === connection && this.environmentId(connection) === environmentId;
  }
  private async refresh(): Promise<void> {
    if (this.busy) return;
    this.info = undefined;
    this.database = undefined;
    this.release = undefined;
    this.databaseStatus = '';
    this.message = '';
    const connection = this.connection;
    const environmentId = connection ? this.environmentId(connection) : '';
    if (!connection || !environmentId) { this.message = '请先连接一个环境'; return; }
    const epoch = ++this.epoch;
    this.busy = true;
    try {
      const info = await readMaintenance(connection, environmentId);
      if (!this.current(connection, environmentId, epoch)) return;
      this.info = info;
      if (!info.databaseSupported) {
        this.databaseStatus = '当前服务未提供数据库存储状态';
      } else {
        this.databaseStatus = '正在读取数据库存储…';
        try {
          const database = await readDatabaseStorage(connection, info);
          if (!this.current(connection, environmentId, epoch)) return;
          if (database === null) this.databaseStatus = '服务端暂无数据库存储状态';
          else { this.database = database; this.databaseStatus = ''; this.reclaimNeedsRefresh = false; }
        } catch (_) {
          if (this.epoch === epoch) this.databaseStatus = '数据库存储读取失败，请刷新重试';
        }
      }
    } catch (_) {
      if (this.epoch === epoch) this.message = '维护信息读取失败，请检查连接与权限后刷新';
    } finally {
      if (this.epoch === epoch) this.busy = false;
    }
  }
  private canReclaim(): boolean {
    const connection = this.connection;
    return !this.busy && !this.reclaimNeedsRefresh && !!connection &&
      this.environmentId(connection) === this.info?.environmentId &&
      connection.canScope('environment:maintain') === true && canRequestDatabaseReclaim(this.database);
  }
  private confirmReclaim(): void {
    const connection = this.connection;
    const info = this.info;
    if (!connection || !info || !this.canReclaim()) return;
    const generation = connection.generationValue();
    AlertDialog.show({
      title: '回收数据库空间？',
      message: '服务会整理数据库以回收空闲空间，不会删除会话。此操作会重启服务，并中断正在运行的任务。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '回收并重启',
        action: () => {
          if (this.connection === connection && this.info === info && connection.generationValue() === generation) {
            void this.reclaim(connection, info.environmentId);
          }
        }
      }
    });
  }
  private async reclaim(connection: T3Client, environmentId: string): Promise<void> {
    if (!this.canReclaim()) return;
    const epoch = ++this.epoch;
    this.busy = true;
    this.message = '正在重新核对数据库存储…';
    const stillSelected = (): boolean => this.epoch === epoch && this.connection === connection;
    try {
      const generation = await requestDatabaseReclaim(connection, environmentId, stillSelected);
      if (!stillSelected()) return;
      this.reclaimNeedsRefresh = true;
      this.message = '服务已受理，等待重连后核对数据库存储…';
      const database = await verifyDatabaseReclaim(connection, environmentId, generation, stillSelected);
      if (!this.current(connection, environmentId, epoch)) return;
      this.database = database === null ? undefined : database;
      this.databaseStatus = database === null ? '服务端暂无数据库存储状态' : '';
      this.reclaimNeedsRefresh = !database || !database.incrementalVacuumEnabled;
      this.message = database?.reclaimFailed ? '服务报告数据库整理失败，请刷新核对' :
        database?.incrementalVacuumEnabled ? '已重新读取数据库存储，增量回收已开启' :
          '未能确认整理结果，请刷新核对';
    } catch (_) {
      if (stillSelected()) {
        this.reclaimNeedsRefresh = true;
        this.message = '回收未确认，请在服务可用后刷新核对';
      }
    } finally {
      if (stillSelected()) this.busy = false;
    }
  }

  private canCheck(): boolean {
    return !this.busy && !!this.info?.registrySpec && !this.info.updatesManagedBy &&
      !!this.connection && this.environmentId(this.connection) === this.info.environmentId &&
      this.connection.canScope('orchestration:read') !== false && this.connection.canScope('environment:maintain') === true;
  }
  private async check(): Promise<void> {
    const connection = this.connection;
    const info = this.info;
    if (!connection || !info || !this.canCheck()) return;
    const epoch = ++this.epoch;
    this.busy = true;
    this.release = undefined;
    this.message = '正在查询发布版本…';
    try {
      const result = await checkServiceRelease(connection, info.environmentId);
      if (this.current(connection, info.environmentId, epoch)) {
        this.release = result;
        this.message = '';
      }
    } catch (_) {
      if (this.epoch === epoch) this.message = '检查更新失败，请核对环境的连接、权限和发布源';
    } finally {
      if (this.epoch === epoch) this.busy = false;
    }
  }
  private updateMethod(): string {
    if (this.info?.updateMethod === 'boot-service') return '后台服务';
    if (this.info?.updateMethod === 'respawn') return '服务进程重启';
    if (this.info?.updateMethod === 'desktop-managed') return this.info.desktopCanUpdate ? '桌面应用管理' : '由桌面端处理';
    return '服务未提供';
  }
  private releaseSummary(): string {
    if (!this.release) return '';
    const release = this.release;
    if (release.registryVersion === null) return '环境发布源暂无此发布轨道';
    if (release.updateAvailable) return '可用版本 ' + release.registryVersion + '（检查时服务版本 ' + release.installedVersion + '）';
    return '发布源暂无较新版本（检查时服务版本 ' + release.installedVersion + '）';
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) { Image($r('app.media.ui_back')).width(22).height(22) }
          .width(44).height(44).backgroundColor(Color.Transparent).accessibilityText('返回设置').onClick(this.onBack)
        Text('服务维护').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('刷新').fontSize(14).backgroundColor(Color.Transparent).fontColor($r('app.color.primary'))
          .enabled(!this.busy).onClick(() => { void this.refresh(); })
      }.width('100%').padding(8)
      Scroll() {
        Column({ space: 12 }) {
          if (this.busy && !this.info && !this.message) { Text('正在读取维护信息…').fontSize(14).width('100%') }
          if (this.message) { Text(this.message).fontSize(14).width('100%') }
          if (this.info) {
            Column({ space: 6 }) {
              Text('服务版本：' + (this.info.version || '服务未提供')).fontSize(15).width('100%')
              Text('安装方式：' + (this.info.installation || '服务未提供')).fontSize(14).width('100%')
              Text('更新方式：' + this.updateMethod()).fontSize(14).width('100%')
              Text('重启后继续会话：' + (this.info.restartContinuation === undefined ? '服务未提供' :
                this.info.restartContinuation ? '已开启' : '已关闭')).fontSize(14).width('100%')
            }.width('100%').padding(12).backgroundColor($r('app.color.surface')).borderRadius(12)
            Column({ space: 6 }) {
              Text('数据库存储').fontSize(15).fontWeight(FontWeight.Medium).width('100%')
              if (this.database) {
                Text('数据库大小：' + String(this.database.databaseBytes) + ' 字节').fontSize(14).width('100%')
                Text('可回收：' + String(this.database.reclaimableBytes) + ' 字节').fontSize(14).width('100%')
                Text('增量回收：' + (this.database.incrementalVacuumEnabled ? '已开启' : '已关闭')).fontSize(14).width('100%')
                if (this.database.incrementalVacuumEnabled) {
                  Text('已启用自动回收，无需手动整理').fontSize(13).width('100%')
                } else if (canRequestDatabaseReclaim(this.database)) {
                  if (this.connection?.canScope('environment:maintain') === true) {
                    Button('回收数据库空间').constraintSize({ minHeight: 44 }).enabled(this.canReclaim())
                      .onClick(() => this.confirmReclaim())
                  } else {
                    Text('当前连接没有维护权限').fontSize(13).width('100%')
                  }
                } else {
                  Text(this.database.reclaimableBytes > 0 ? '当前服务不支持手动整理' : '当前没有可回收空间')
                    .fontSize(13).width('100%')
                }
              } else if (this.databaseStatus) {
                Text(this.databaseStatus).fontSize(14).width('100%')
              }
            }.width('100%').padding(12).backgroundColor($r('app.color.surface')).borderRadius(12)
            if (this.info.updatesManagedBy) {
              Text(this.info.updatesManagedBy + ' 管理服务更新').fontSize(14).width('100%')
            } else if (!this.info.registrySpec) {
              Text('此服务或发布轨道不支持检查更新').fontSize(14).width('100%')
            } else if (this.connection?.canScope('environment:maintain') !== true) {
              Text('当前连接没有维护权限').fontSize(14).width('100%')
            } else {
              Button('检查更新').constraintSize({ minHeight: 44 }).enabled(this.canCheck())
                .onClick(() => { void this.check(); })
            }
            if (this.release) { Text(this.releaseSummary()).fontSize(14).width('100%') }
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16, bottom: 28 })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor($r('app.color.canvas')).foregroundColor($r('app.color.ink'))
  }
}
