/*
 * VmessParser.ets - vmess:// 链接解析
 *
 * 格式: vmess://base64(JSON), JSON 字段:
 *   v=2, ps=备注, add=地址, port, id=uuid, aid=alterId, net=network(tcp/ws/grpc),
 *   type=headerType(none/http), host, path, tls=security(tls/none), sni, fp=fingerprint
 * 输出统一 VlessNode(protocol='vmess')
 */
import { util } from '@kit.ArkTS';
import { VlessNode } from './VlessParser';

export function parseVmess(link: string): VlessNode | null {
  const body = link.substring('vmess://'.length);
  const json = decodeBase64(body);
  if (json === null) {
    return null;
  }
  let obj: Record<string, Object>;
  try {
    obj = JSON.parse(json) as Record<string, Object>;
  } catch {
    return null;
  }
  const address = str(obj, 'add');
  const port = parseInt(str(obj, 'port'), 10);
  const uuid = str(obj, 'id');
  if (address.length === 0 || uuid.length === 0 || isNaN(port)) {
    return null;
  }
  const network = str(obj, 'net');
  const security = str(obj, 'tls') === 'tls' ? 'tls' : 'none';
  const name = str(obj, 'ps');
  return {
    id: util.generateRandomUUID(false),
    name: name.length > 0 ? name : `${address}:${port}`,
    address: address,
    port: port,
    uuid: uuid,
    flow: '',
    security: security,
    sni: str(obj, 'sni'),
    fingerprint: str(obj, 'fp'),
    publicKey: '',
    shortId: '',
    network: network.length > 0 ? network : 'tcp',
    path: str(obj, 'path'),
    host: str(obj, 'host'),
    headerType: str(obj, 'type') === 'http' ? 'http' : '',
    encryption: 'auto',
    protocol: 'vmess',
    raw: link
  };
}

function str(obj: Record<string, Object>, key: string): string {
  const v = obj[key];
  if (v === undefined || v === null) {
    return '';
  }
  return `${v}`;
}

function decodeBase64(s: string): string | null {
  let padded = s;
  const rem = s.length % 4;
  if (rem !== 0) {
    padded = s + '='.repeat(4 - rem);
  }
  try {
    const decoder = util.TextDecoder.create('utf-8');
    const bytes = new util.Base64Helper().decodeSync(padded);
    return decoder.decodeToString(bytes);
  } catch {
    return null;
  }
}
