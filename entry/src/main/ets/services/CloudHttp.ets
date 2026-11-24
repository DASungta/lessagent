import { http } from '@kit.NetworkKit';
import { record } from '../protocol/Wire';

export interface CloudHttpResult {
  status: number;
  value: Object;
  headers: Record<string, string>;
}

export class CloudHttpFailure extends Error {
  status: number;
  value: Object;
  headers: Record<string, string>;
  constructor(status: number, value: Object, headers: Record<string, string> = {}) {
    super('T3 Connect HTTP ' + status);
    this.status = status;
    this.value = value;
    this.headers = headers;
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

function normalizedHeaders(raw: Object | undefined): Record<string, string> {
  const result: Record<string, string> = {};
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return result;
  const source = raw as Record<string, Object>;
  for (const key of Object.keys(source)) {
    const value = source[key];
    const lower = key.toLowerCase();
    if (typeof value === 'string') {
      result[lower] = value;
    } else if (Array.isArray(value)) {
      const first = (value as Object[]).find((item: Object) => typeof item === 'string' && (item as string).length > 0);
      if (typeof first === 'string') result[lower] = first;
    }
  }
  return result;
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
    const responseHeaders = normalizedHeaders(response.header as Object | undefined);
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new CloudHttpFailure(response.responseCode, value, responseHeaders);
    }
    return { status: response.responseCode, value, headers: responseHeaders };
  } catch (error) {
    if (error instanceof CloudHttpFailure) throw error as CloudHttpFailure;
    throw new Error('T3 Connect 网络请求失败，请检查网络与中继地址');
  } finally {
    request.destroy();
  }
}
