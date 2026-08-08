export interface BridgeStatus {
  loaded: boolean;
  libPath: string;
  lastError: string;
  callCount: number;
  failCount: number;
  lastService: string;
  lastDurationMs: number;
}

export const invoke: (service: string, params: string, callback?: (result: string) => void) => Promise<string> | void;
export const invokeSync: (service: string, params: string) => string;
export const getBridgeStatus: () => BridgeStatus;
export const selfTest: () => string;
