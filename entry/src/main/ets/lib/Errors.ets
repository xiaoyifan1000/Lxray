/*
 * Errors.ets - 与 Go 侧一致的统一错误契约
 * 错误码与 golang/ipc/ipc.go 及 bridge.cpp 保持同步
 */
export const enum CoreErrorCode {
  BAD_REQUEST = 'BAD_REQUEST',
  UNKNOWN_SERVICE = 'UNKNOWN_SERVICE',
  BAD_PARAMS = 'BAD_PARAMS',
  INTERNAL = 'INTERNAL',
  PANIC = 'PANIC',
  NOT_READY = 'NOT_READY',
  LIB_NOT_LOADED = 'LIB_NOT_LOADED',
  NATIVE_NULL_RESULT = 'NATIVE_NULL_RESULT',
  BRIDGE_CALL_FAILED = 'BRIDGE_CALL_FAILED'
}

export class CoreError extends Error {
  readonly code: string;
  readonly detail?: string;

  constructor(code: string, message: string, detail?: string) {
    super(message);
    this.name = 'CoreError';
    this.code = code;
    this.detail = detail;
  }
}

export interface CoreErrorInfo {
  code: string;
  message: string;
  detail?: string;
}

export interface CoreResponse {
  success: boolean;
  data?: object;
  error?: CoreErrorInfo;
}
