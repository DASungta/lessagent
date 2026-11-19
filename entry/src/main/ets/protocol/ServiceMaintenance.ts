import { record, sequence } from './Wire';
import { ScheduleConnection } from './ScheduledTasks';

export interface ServiceMaintenance {
  environmentId: string;
  version: string;
  installation: string;
  updateMethod: string;
  desktopCanUpdate: boolean;
  registrySpec: string;
  databaseSupported: boolean;
  restartContinuation: boolean | undefined;
  updatesManagedBy: string;
}

export interface DatabaseStorageView {
  databaseBytes: number;
  reclaimableBytes: number;
  incrementalVacuumEnabled: boolean;
  canReclaim: boolean;
  reclaimFailed: boolean;
}

export interface ReclaimConnection extends ScheduleConnection {
  generationValue(): number;
}

export interface ReleaseCheck {
  installedVersion: string;
  registryVersion: string | null;
  updateAvailable: boolean;
}

function optionalRecord(value: Object | undefined): Record<string, Object> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? record(value) : {} as Record<string, Object>;
}

function numericVersion(version: string): number[] | undefined {
  const match = /^v?(\d{1,9})\.(\d{1,9})\.(\d{1,9})(?:-nightly\.(\d{8})\.(\d{1,12}))?(?:\+[0-9A-Za-z.-]{1,64})?$/.exec(version);
  if (!match) return undefined;
  return [Number(match[1]), Number(match[2]), Number(match[3]), Number(match[4] || 0), Number(match[5] || 0)];
}

export function maintenanceInfo(config: Object, expectedEnvironment: string): ServiceMaintenance {
  const root = record(config);
  const environment = record(root.environment);
  if (!expectedEnvironment || environment.environmentId !== expectedEnvironment) throw new Error('环境身份变化');
  const capabilities = optionalRecord(environment.capabilities);
  const installation = optionalRecord(capabilities.serverInstallation);
  const policy = optionalRecord(root.managedPolicy);
  const updates = optionalRecord(optionalRecord(policy.limits).updates);
  const settings = optionalRecord(root.settings);
  const version = typeof environment.serverVersion === 'string' && /^[0-9A-Za-z.+_-]{1,128}$/.test(environment.serverVersion)
    ? environment.serverVersion : '';
  const parsedVersion = numericVersion(version);
  const installKind = installation.kind;
  const method = capabilities.serverSelfUpdate;
  return {
    environmentId: expectedEnvironment,
    version,
    installation: typeof installKind === 'string' && ['npx', 'pnpm-dlx', 'bunx', 'npm-global', 't3-launcher'].includes(installKind) ? installKind : '',
    updateMethod: typeof method === 'string' && ['boot-service', 'respawn', 'desktop-managed'].includes(method) ? method : '',
    desktopCanUpdate: capabilities.desktopAppUpdate === true,
    registrySpec: capabilities.npmReleaseLookup === true && parsedVersion ? (parsedVersion[3] > 0 ? 'nightly' : 'latest') : '',
    databaseSupported: capabilities.databaseStorage === true,
    restartContinuation: capabilities.threadRestartContinuation === true && typeof settings.continueThreadsAfterServerUpdate === 'boolean'
      ? settings.continueThreadsAfterServerUpdate : undefined,
    updatesManagedBy: updates.mode === 'off' ? (typeof policy.organization === 'string' ? policy.organization : '组织') : ''
  };
}

function assertRead(connection: ScheduleConnection, environmentId: string): void {
  if (!connection.ready || !environmentId || record(record(connection.config).environment).environmentId !== environmentId) {
    throw new Error('环境未连接或身份变化');
  }
  if (connection.canScope('orchestration:read') === false) throw new Error('没有环境读取权限');
}

export async function readMaintenance(connection: ScheduleConnection, environmentId: string): Promise<ServiceMaintenance> {
  assertRead(connection, environmentId);
  const config = await connection.rpcRequest('server.getConfig', {}, 15000, false);
  assertRead(connection, environmentId);
  return maintenanceInfo(config, environmentId);
}

export function databaseStorageView(value: Object): DatabaseStorageView | null {
  if (value === null) return null;
  const row = record(value);
  if (typeof row.incrementalVacuumEnabled !== 'boolean') throw new Error('数据库存储响应无效');
  const databaseBytes = sequence(row.databaseBytes);
  const reclaimableBytes = sequence(row.reclaimableBytes);
  if (reclaimableBytes > databaseBytes) throw new Error('数据库存储响应无效');
  return {
    databaseBytes, reclaimableBytes, incrementalVacuumEnabled: row.incrementalVacuumEnabled,
    canReclaim: row.canReclaim === true,
    reclaimFailed: typeof row.reclaimFailure === 'string'
  };
}

export async function readDatabaseStorage(connection: ScheduleConnection, info: ServiceMaintenance): Promise<DatabaseStorageView | null> {
  assertRead(connection, info.environmentId);
  if (!info.databaseSupported) throw new Error('当前服务未提供数据库存储状态');
  return new Promise<DatabaseStorageView | null>((resolve, reject) => {
    let handle: ((value: Object) => void) | undefined = undefined;
    let done = false;
    const timer = setTimeout(() => {
      done = true;
      if (handle) connection.stopRpcStream(handle);
      reject(new Error('数据库存储读取超时'));
    }, 10000);
    try {
      handle = connection.watchRpcStream('server.getDatabaseStorage', {}, (value: Object): void => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        if (handle) connection.stopRpcStream(handle);
        try { assertRead(connection, info.environmentId); resolve(databaseStorageView(value)); }
        catch (error) { reject(error); }
      });
      if (done) connection.stopRpcStream(handle);
    } catch (error) {
      clearTimeout(timer);
      reject(error);
    }
  });
}

export function canRequestDatabaseReclaim(database: DatabaseStorageView | null | undefined): boolean {
  return !!database && database.canReclaim && !database.incrementalVacuumEnabled && database.reclaimableBytes > 0;
}

export async function requestDatabaseReclaim(connection: ReclaimConnection, environmentId: string,
  stillSelected: () => boolean): Promise<number> {
  const generation = connection.generationValue();
  if (connection.canScope('environment:maintain') !== true) throw new Error('没有环境维护权限');
  const info = await readMaintenance(connection, environmentId);
  const database = await readDatabaseStorage(connection, info);
  assertRead(connection, environmentId);
  if (connection.canScope('environment:maintain') !== true || connection.generationValue() !== generation || !stillSelected()) {
    throw new Error('环境或维护权限已变化');
  }
  if (!canRequestDatabaseReclaim(database)) throw new Error('数据库当前不可手动回收');
  await connection.rpcRequest('server.reclaimDatabaseSpace', {}, 15000, false);
  return generation;
}

export async function verifyDatabaseReclaim(connection: ReclaimConnection, environmentId: string, generation: number,
  stillSelected: () => boolean): Promise<DatabaseStorageView | null> {
  const deadline = Date.now() + 60000;
  // The Void acknowledgement arrives before the server restarts. Wait for a new transport.
  while (stillSelected() && Date.now() < deadline) {
    if (connection.ready && connection.generationValue() !== generation) {
      const info = await readMaintenance(connection, environmentId);
      if (!stillSelected()) throw new Error('环境已变化');
      return readDatabaseStorage(connection, info);
    }
    await new Promise<void>(resolve => { setTimeout(resolve, 1000); });
  }
  throw new Error('请在重连后刷新核对');
}

export async function checkServiceRelease(connection: ScheduleConnection, environmentId: string): Promise<ReleaseCheck> {
  if (connection.canScope('environment:maintain') !== true) throw new Error('没有环境维护权限');
  const info = await readMaintenance(connection, environmentId);
  if (connection.canScope('environment:maintain') !== true) throw new Error('环境维护权限已变化');
  if (info.updatesManagedBy || !info.registrySpec) throw new Error('当前环境无法检查更新');
  const reply = await connection.rpcRequest('server.getNpmRelease', { spec: info.registrySpec }, 20000, false);
  assertRead(connection, environmentId);
  if (connection.canScope('environment:maintain') !== true) throw new Error('环境维护权限已变化');
  if (reply === null) return { installedVersion: info.version, registryVersion: null, updateAvailable: false };
  const registryVersion = record(reply).version;
  const installed = numericVersion(info.version);
  const candidate = typeof registryVersion === 'string' ? numericVersion(registryVersion) : undefined;
  if (!installed || !candidate || (info.registrySpec === 'nightly') !== (candidate[3] > 0)) throw new Error('发布版本响应无效');
  const difference = candidate.findIndex((part: number, index: number) => part !== installed[index]);
  return {
    installedVersion: info.version, registryVersion: registryVersion as string,
    updateAvailable: difference >= 0 && candidate[difference] > installed[difference]
  };
}
