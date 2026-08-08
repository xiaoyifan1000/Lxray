/*
 * CoreServices.ets - xray 核心生命周期服务的 ArkTS 封装
 * start 的 fd 参数预留给 VPN 模式(tun fd), 本地代理模式不传
 */
import { CoreBridge } from './CoreBridge';

export interface CoreStartParams {
  fd?: number;
  assetLocation: string;
  configLocation: string;
}

export interface CoreStartResult {
  running: boolean;
  version: string;
}

export interface CoreStopResult {
  running: boolean;
  was: boolean;
}

export interface CoreState {
  running: boolean;
  version: string;
  uptimeMs?: number;
}

export interface OutboundTraffic {
  up: number;
  down: number;
}

export type CoreStats = Record<string, OutboundTraffic>;

export namespace CoreServices {

  export async function start(params: CoreStartParams): Promise<CoreStartResult> {
    return CoreBridge.call<CoreStartResult>('CoreService.Start', params);
  }

  export async function stop(): Promise<CoreStopResult> {
    return CoreBridge.call<CoreStopResult>('CoreService.Stop');
  }

  export async function state(): Promise<CoreState> {
    return CoreBridge.call<CoreState>('CoreService.State');
  }

  export async function stats(): Promise<CoreStats> {
    return CoreBridge.call<CoreStats>('CoreService.Stats');
  }
}
