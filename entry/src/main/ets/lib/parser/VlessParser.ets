/*
 * VlessParser.ets - 分享链接解析(统一节点模型)
 *
 * 支持: vless://uuid@host:port?k=v#remark
 *       vmess://base64(JSON) (见 VmessParser)
 * 统一输出 VlessNode(名称沿用), protocol 区分 'vless'/'vmess'
 * 解析失败返回 null(由调用方记日志), 不做异常抛出
 */
import { util } from '@kit.ArkTS';
import { parseVmess } from './VmessParser';

export interface VlessNode {
  id: string;
  name: string;
  address: string;
  port: number;
  uuid: string;
  flow: string;
  security: string;
  sni: string;
  fingerprint: string;
  publicKey: string;
  shortId: string;
  network: string;
  path: string;
  host: string;
  headerType: string;
  encryption: string;
  protocol: string;
  raw: string;
}

export namespace VlessParser {

  export function parse(link: string): VlessNode | null {
    const trimmed = link.trim();
    if (trimmed.startsWith('vmess://')) {
      return parseVmess(trimmed);
    }
    if (!trimmed.startsWith('vless://')) {
      return null;
    }
    const body = trimmed.substring('vless://'.length);

    let name = '';
    const hashIdx = body.indexOf('#');
    let main = body;
    if (hashIdx >= 0) {
      name = decodeURIComponent(body.substring(hashIdx + 1));
      main = body.substring(0, hashIdx);
    }

    let query = '';
    const qIdx = main.indexOf('?');
    let addrPart = main;
    if (qIdx >= 0) {
      query = main.substring(qIdx + 1);
      addrPart = main.substring(0, qIdx);
    }

    const atIdx = addrPart.lastIndexOf('@');
    if (atIdx < 0) {
      return null;
    }
    const uuid = addrPart.substring(0, atIdx);
    const hostPort = addrPart.substring(atIdx + 1);
    const colonIdx = hostPort.lastIndexOf(':');
    if (colonIdx < 0) {
      return null;
    }
    const address = hostPort.substring(0, colonIdx);
    const port = parseInt(hostPort.substring(colonIdx + 1), 10);
    if (uuid.length === 0 || address.length === 0 || isNaN(port)) {
      return null;
    }

    const params = parseQuery(query);
    const node: VlessNode = {
      id: util.generateRandomUUID(false),
      name: name.length > 0 ? name : `${address}:${port}`,
      address: address,
      port: port,
      uuid: uuid,
      flow: params.get('flow') ?? '',
      security: params.get('security') ?? 'none',
      sni: params.get('sni') ?? '',
      fingerprint: params.get('fp') ?? '',
      publicKey: params.get('pbk') ?? '',
      shortId: params.get('sid') ?? '',
      network: params.get('type') ?? 'tcp',
      path: params.get('path') ?? '',
      host: params.get('host') ?? '',
      headerType: params.get('headerType') ?? '',
      encryption: params.get('encryption') ?? 'none',
      protocol: 'vless',
      raw: trimmed
    };
    return node;
  }

  function parseQuery(query: string): Map<string, string> {
    const out = new Map<string, string>();
    if (query.length === 0) {
      return out;
    }
    for (const pair of query.split('&')) {
      const eq = pair.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const k = pair.substring(0, eq);
      const v = decodeURIComponent(pair.substring(eq + 1));
      out.set(k, v);
    }
    return out;
  }
}
