import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

export const PRIVACY_CONSENT_VERSION = 1;

export interface PrivacyConsentRecord {
  schemaVersion: number;
  acceptedVersion: number;
  acceptedAt: string;
}

export const PRIVACY_POLICY_SUMMARY: string =
  '欢迎使用 T3 Code Harmony。本应用是一款独立开发的自托管远程研发工作区客户端，仅在您主动添加连接环境或点击使用具体功能时处理必要信息。';

export const PRIVACY_POLICY_DETAIL: string =
  'T3 Code Harmony 隐私声明\n\n' +
  '1. 应用定位与数据流向\n' +
  '本应用作为远程研发工作区的移动端瘦客户端运行，不内置开发者自有业务后台，不接入任何第三方统计、推送或广告 SDK。您的项目文件、代码片段、会话内容及语音转写文本仅在您本地设备或您主动配对连接的目标服务端之间传输。\n\n' +
  '2. 权限用途与最小必要原则\n' +
  '• 网络与网络状态（INTERNET / GET_NETWORK_INFO）：用于连接您手动添加或扫码配对的目标服务端，并在网络切换时自动重连。\n' +
  '• 相机（CAMERA，按需申请）：仅在您进入「扫码配对」页面并点击允许后开启，用于识别配对二维码；不拍照、不录像、不上传图像。\n' +
  '• 麦克风（MICROPHONE，按需申请）：仅在您进入「语音输入」页面并点击开始录音后申请，通过系统端侧语音识别能力转为可编辑草稿，不会自动发送，也不向任何第三方语音云上传音频。\n' +
  '• 剪贴板：仅通过系统安全粘贴按钮（PasteButton）在您主动点击时读取剪贴板中的上下文片段，不做后台静默读取。\n\n' +
  '3. 本地存储与凭据安全\n' +
  '连接路径、草稿与偏好设置保存在应用沙箱目录；连接凭据及令牌使用系统安全资产存储（AssetStoreKit）加密保存在本机，移除环境或卸载应用时一并清理。\n\n' +
  '4. 您的选择与控制\n' +
  '您可以在应用内随时禁用或移除已连接环境、清理本地缓存，或在系统设置中撤回相机、麦克风与通知权限。如不同意本隐私声明，可点击「不同意并退出」关闭应用。';

export function privacyConsentRecord(value: Object): PrivacyConsentRecord | undefined {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const row = value as Record<string, Object>;
  if (row.schemaVersion !== 1 || typeof row.acceptedVersion !== 'number' ||
    !Number.isSafeInteger(row.acceptedVersion) || typeof row.acceptedAt !== 'string' || !row.acceptedAt) {
    return undefined;
  }
  return {
    schemaVersion: 1,
    acceptedVersion: row.acceptedVersion,
    acceptedAt: row.acceptedAt
  };
}

export class PrivacyConsentStore {
  private path: string;
  constructor(filesDir: string) { this.path = filesDir + '/privacy-consent-v1.json'; }

  load(): PrivacyConsentRecord | undefined {
    try {
      const parsed = JSON.parse(fileIo.readTextSync(this.path)) as Object;
      const record = privacyConsentRecord(parsed);
      if (!record || record.acceptedVersion < PRIVACY_CONSENT_VERSION) return undefined;
      return record;
    } catch (error) {
      if ((error as BusinessError).code === 13900002) return undefined;
      return undefined;
    }
  }

  save(record: PrivacyConsentRecord): void {
    const valid = privacyConsentRecord(record);
    if (!valid) throw new Error('隐私同意记录无效');
    const content = JSON.stringify(valid);
    const temporary = this.path + '.tmp';
    const file = fileIo.openSync(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, content);
      fileIo.fsyncSync(file.fd);
    } finally {
      fileIo.closeSync(file);
    }
    if (fileIo.readTextSync(temporary) !== content) throw new Error('隐私同意记录回读校验失败');
    fileIo.renameSync(temporary, this.path);
  }
}

let consentStore: PrivacyConsentStore | undefined = undefined;
let privacyAccepted: boolean = false;

export function preparePrivacyConsent(filesDir: string): boolean {
  consentStore = new PrivacyConsentStore(filesDir);
  privacyAccepted = consentStore.load() !== undefined;
  return privacyAccepted;
}

export function isPrivacyConsentAccepted(): boolean {
  return privacyAccepted;
}

export function acceptPrivacyConsent(): void {
  const next: PrivacyConsentRecord = {
    schemaVersion: 1,
    acceptedVersion: PRIVACY_CONSENT_VERSION,
    acceptedAt: new Date().toISOString()
  };
  if (consentStore) consentStore.save(next);
  privacyAccepted = true;
}
