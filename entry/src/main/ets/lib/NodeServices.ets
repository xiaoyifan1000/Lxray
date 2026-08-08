/*
 * NodeServices.ets - 节点工具服务的 ArkTS 封装
 * Ping: TCP 握手测延迟, 返回毫秒, 失败 -1
 */
import { CoreBridge } from './CoreBridge';

export interface NodePingResult {
  latencyMs: number;
}

export interface PingParams {
  address: string;
  port: number;
  timeoutMs?: number;
}

export namespace NodeServices {

  export async function ping(address: string, port: number, timeoutMs: number = 3000): Promise<number> {
    const p: PingParams = { address: address, port: port, timeoutMs: timeoutMs };
    const resp = await CoreBridge.call<NodePingResult>('NodeService.Ping', p);
    return resp.latencyMs;
  }
}
