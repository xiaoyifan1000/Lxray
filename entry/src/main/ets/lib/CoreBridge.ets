/*
 * CoreBridge.ets - ArkTS 到 Go 核心的类型化桥接
 *
 * call/callSync 负责 JSON 编解码与统一错误契约解包,
 * 核心侧 error 会转换为 CoreError 异常抛出;
 * status/selfTest 用于桥健康检查
 */
import libentry from 'libentry.so';
import { CoreError, CoreResponse, CoreErrorCode } from './Errors';
import { Logger } from './Logger';

export interface BridgeStatus {
  loaded: boolean;
  libPath: string;
  lastError: string;
  callCount: number;
  failCount: number;
  lastService: string;
  lastDurationMs: number;
}

function parse(raw: string): CoreResponse {
  try {
    return JSON.parse(raw) as CoreResponse;
  } catch (e) {
    throw new CoreError(CoreErrorCode.INTERNAL, `unparseable core response: ${raw.substring(0, 200)}`);
  }
}

function unwrap<T>(raw: string): T {
  const resp = parse(raw);
  if (!resp.success) {
    const err = resp.error;
    throw new CoreError(err?.code ?? CoreErrorCode.INTERNAL, err?.message ?? 'unknown core error', err?.detail);
  }
  return resp.data as T;
}

export namespace CoreBridge {

  export async function call<T>(service: string, params?: object): Promise<T> {
    Logger.debug('bridge', `call ${service}`);
    const raw = await libentry.invoke(service, JSON.stringify(params ?? null)) as string;
    return unwrap<T>(raw);
  }

  export function callSync<T>(service: string, params?: object): T {
    Logger.debug('bridge', `callSync ${service}`);
    const raw = libentry.invokeSync(service, JSON.stringify(params ?? null));
    return unwrap<T>(raw);
  }

  export function status(): BridgeStatus {
    return libentry.getBridgeStatus();
  }

  export function selfTest(): boolean {
    const raw = libentry.selfTest();
    const resp = parse(raw);
    if (!resp.success) {
      Logger.error('bridge', `selfTest failed: ${resp.error?.code} ${resp.error?.message}`);
      return false;
    }
    Logger.info('bridge', 'selfTest passed');
    return true;
  }
}
