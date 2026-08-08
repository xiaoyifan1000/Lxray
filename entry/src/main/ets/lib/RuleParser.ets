/*
 * RuleParser.ets - 自定义路由规则解析
 *
 * 用户格式(每行一条): "条件1,条件2 -> 出站标签"
 * 条件前缀 -> xray 字段:
 *   domain:example.com / geosite:cn / keyword:x / regexp:r -> domain
 *   ip:1.2.3.4 / geoip:cn -> ip
 *   port:80,443 -> port
 *   network:tcp / source:10.0.0.1 -> network / source
 * 出站标签: 直连 direct / 代理 proxy / 拦截 block
 * 也支持直接粘贴 xray JSON 规则对象
 */

interface RuleField {
  type: string;
  outboundTag: string;
  domain?: Object;
  ip?: Object;
  port?: string;
  network?: string;
  source?: Object;
}

export interface ParsedRule {
  ok: boolean;
  error?: string;
  rule?: Object;
}

export namespace RuleParser {

  export function parse(line: string): ParsedRule {
    const trimmed = line.trim();
    if (trimmed.length === 0) {
      return { ok: false, error: 'empty' };
    }
    if (trimmed.startsWith('{')) {
      return parseJson(trimmed);
    }
    return parseLine(trimmed);
  }

  function parseJson(text: string): ParsedRule {
    try {
      const obj = JSON.parse(text) as Record<string, Object>;
      if (obj['outboundTag'] === undefined || obj['outboundTag'] === null) {
        return { ok: false, error: '缺少 outboundTag' };
      }
      return { ok: true, rule: obj as Object };
    } catch {
      return { ok: false, error: 'JSON 解析失败' };
    }
  }

  function parseLine(line: string): ParsedRule {
    const arrow = line.indexOf('->');
    if (arrow < 0) {
      return { ok: false, error: '缺少 -> 出站标签' };
    }
    const condPart = line.substring(0, arrow).trim();
    const outboundTag = line.substring(arrow + 2).trim();
    if (condPart.length === 0 || outboundTag.length === 0) {
      return { ok: false, error: '条件或出站标签为空' };
    }
    const domains: string[] = [];
    const ips: string[] = [];
    let port = '';
    let network = '';
    let source = '';
    for (const raw of condPart.split(',')) {
      const cond = raw.trim();
      if (cond.length === 0) {
        continue;
      }
      if (cond.startsWith('domain:') || cond.startsWith('geosite:') ||
        cond.startsWith('keyword:') || cond.startsWith('regexp:')) {
        domains.push(cond);
      } else if (cond.startsWith('ip:') || cond.startsWith('geoip:')) {
        ips.push(cond);
      } else if (cond.startsWith('port:')) {
        port = cond.substring(5);
      } else if (cond.startsWith('network:')) {
        network = cond.substring(8);
      } else if (cond.startsWith('source:')) {
        source = cond.substring(7);
      } else {
        return { ok: false, error: `无法识别条件: ${cond}` };
      }
    }
    if (domains.length === 0 && ips.length === 0 && port.length === 0 &&
      network.length === 0 && source.length === 0) {
      return { ok: false, error: '没有有效条件' };
    }
    const rule: RuleField = { type: 'field', outboundTag: outboundTag };
    if (domains.length > 0) {
      rule.domain = domains as Object;
    }
    if (ips.length > 0) {
      rule.ip = ips as Object;
    }
    if (port.length > 0) {
      rule.port = port;
    }
    if (network.length > 0) {
      rule.network = network;
    }
    if (source.length > 0) {
      rule.source = [source] as Object;
    }
    return { ok: true, rule: rule as Object };
  }
}
