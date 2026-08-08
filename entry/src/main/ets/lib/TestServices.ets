/*
 * TestServices.ets - 出口检测服务封装
 * CheckIp: 经本地代理(主进程 xray, 走选中节点)获取真实出口 IP 与地区
 */
import { CoreBridge } from './CoreBridge';

export interface IpInfo {
  ip: string;
  location: string;
}

export namespace TestServices {

  export async function checkIp(): Promise<IpInfo | null> {
    try {
      const resp = await CoreBridge.call<IpInfo>('TestService.CheckIp');
      return resp;
    } catch {
      return null;
    }
  }
}
