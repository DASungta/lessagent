import { http } from '@kit.NetworkKit';
import { record } from '../protocol/Wire';

export interface CloudHttpResult {
  status: number;
  value: Object;
}

export class CloudHttpFailure extends Error {
  status: number;
  value: Object;
  constructor(status: number, value: Object) {
    super('T3 Connect HTTP ' + status);
    this.status = status;
    this.value = value;
  }
}

function parsed(result: string | Object | ArrayBuffer | undefined): Object {
  const empty: Record<string, Object> = {};
  if (typeof result !== 'string') return empty;
  if (!result.trim()) return empty;
  try {
    return record(JSON.parse(result) as Object);
  } catch (_) {
    return empty;
  }
}

export async function cloudHttp(target: string, method: http.RequestMethod, headers: Record<string, string>,
  body: string = '', contentType: string = ''): Promise<CloudHttpResult> {
  const request = http.createHttp();
  try {
    const header: Record<string, string> = { 'Accept': 'application/json' };
    for (const key of Object.keys(headers)) header[key] = headers[key];
    if (body && contentType) header['Content-Type'] = contentType;
    const options: http.HttpRequestOptions = {
      method, header, connectTimeout: 10000, readTimeout: 15000,
      usingCache: false, maxRedirects: 0, expectDataType: http.HttpDataType.STRING
    };
    if (body) options.extraData = body;
    const response = await request.request(target, options);
    const value = parsed(response.result as string | Object | ArrayBuffer | undefined);
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new CloudHttpFailure(response.responseCode, value);
    }
    return { status: response.responseCode, value };
  } catch (error) {
    if (error instanceof CloudHttpFailure) throw error as CloudHttpFailure;
    throw new Error('T3 Connect 网络请求失败，请检查网络与中继地址');
  } finally {
    request.destroy();
  }
}
