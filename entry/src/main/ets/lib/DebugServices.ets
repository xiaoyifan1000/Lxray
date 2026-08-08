/*
 * DebugServices.ets - 框架调试服务的 ArkTS 封装
 * (日志控制/运行时状态/版本/连通性与崩溃管道自检)
 */
import { CoreBridge } from './CoreBridge';

export interface LogEntry {
  time: string;
  level: number;
  module: string;
  message: string;
  fields?: object;
}

export interface CoreStatus {
  uptimeMs: number;
  goroutines: number;
  gomaxprocs: number;
  numCPU: number;
  heapAllocMB: number;
  heapSysMB: number;
  stackInUseMB: number;
  numGC: number;
  lastGCPauseMs: number;
  logLevel: number;
  logDir: string;
}

export interface CoreVersion {
  framework: string;
  go: string;
  core: string;
}

interface InitLogParams {
  dir: string;
  keepDays: number;
}

interface SetLevelParams {
  level: number;
}

interface RecentParams {
  limit: number;
}

interface WriteLogParams {
  level: number;
  module: string;
  msg: string;
}

interface OkResult {
  ok: boolean;
}

export namespace DebugServices {

  export async function initLog(filesDir: string, keepDays: number = 7): Promise<void> {
    const p: InitLogParams = { dir: `${filesDir}/logs`, keepDays: keepDays };
    await CoreBridge.call<object>('LogService.Init', p);
  }

  export async function setLogLevel(level: number): Promise<void> {
    const p: SetLevelParams = { level: level };
    await CoreBridge.call<object>('LogService.SetLevel', p);
  }

  export async function recentLogs(limit: number = 100): Promise<LogEntry[]> {
    const p: RecentParams = { limit: limit };
    return CoreBridge.call<LogEntry[]>('LogService.Recent', p);
  }

  export async function logFiles(): Promise<string[]> {
    return CoreBridge.call<string[]>('LogService.ListFiles');
  }

  export async function writeLog(level: number, module: string, msg: string): Promise<void> {
    const p: WriteLogParams = { level: level, module: module, msg: msg };
    await CoreBridge.call<object>('LogService.Write', p);
  }

  export async function status(): Promise<CoreStatus> {
    return CoreBridge.call<CoreStatus>('StatusService.Get');
  }

  export async function version(): Promise<CoreVersion> {
    return CoreBridge.call<CoreVersion>('VersionService.Get');
  }

  export async function ping(payload: object): Promise<object> {
    return CoreBridge.call<object>('PingService.Ping', payload);
  }

  export async function testCrashPipeline(): Promise<void> {
    await CoreBridge.call<object>('PingService.Panic');
  }
}
