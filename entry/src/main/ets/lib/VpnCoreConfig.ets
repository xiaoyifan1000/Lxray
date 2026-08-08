/*
 * VpnCoreConfig.ets - VPN 模式 xray 配置生成器(设置驱动)
 *
 * 以基础配置(rawfile config.json)为底, 按 ConfigOptions 生成:
 *   inbounds:  tun(必带) + 局域网共享 socks/http(可选)
 *   sniffing:  tun inbound 的探测开关/routeOnly
 *   routing:   模式(global 全局/bypass_mainland 绕过大陆/direct 全局直连)
 *              + domainStrategy + 本地 DNS 拦截规则(可关)
 *   dns:       IPv6 关闭时 queryStrategy=UseIPv4
 *   outbound:  选中节点替换 tag=proxy 出站
 * tun fd 不写进配置, 由 CoreService.Start 经 xray.tun.fd 环境变量注入
 */
import { fileIo } from '@kit.CoreFileKit';
import { Logger } from './Logger';
import { VlessNode } from './parser/VlessParser';
import { OutboundGenerator } from './OutboundGenerator';
import { ConfigOptions, ROUTE_BYPASS_MAINLAND, ROUTE_GLOBAL } from './SettingsStore';
import { RuleParser } from './RuleParser';

const TAG = 'vpnConfig';

interface SniffingSettings {
  enabled: boolean;
  destOverride: string[];
  routeOnly: boolean;
}

interface TunSettings {
  name: string;
  MTU: number;
}

interface Inbound {
  tag: string;
  protocol: string;
  listen?: string;
  port?: number;
  settings: Object;
  sniffing?: SniffingSettings;
}

interface SocksSettings {
  auth: string;
  udp: boolean;
}

interface HttpSettings {
  auth: string;
}

interface DnsOutbound {
  tag: string;
  protocol: string;
}

interface FieldRule {
  type: string;
  outboundTag: string;
  port?: string;
  network?: string;
  domain?: string[];
  ip?: string[];
}

interface RoutingSection {
  domainStrategy?: string;
  rules: Object[];
}

export namespace VpnCoreConfig {

  /*
   * 主进程本地代理配置: 保留 base 配置的 socks/http 监听与路由,
   * 仅将 tag=proxy 出站替换为选中节点, 并按设置应用 DNS
   */
  export function buildLocalConfig(baseConfigPath: string, outPath: string, node: VlessNode,
    opts: ConfigOptions, customRules: string[]): boolean {
    try {
      const text = readText(baseConfigPath);
      const config = JSON.parse(text) as Record<string, Object>;
      replaceProxyOutbound(config, node);
      applyRouting(config, opts, customRules);
      applyDns(config, opts);
      writeText(outPath, JSON.stringify(config));
      Logger.info(TAG, `local proxy config written: ${outPath} (node=${node.name})`);
      return true;
    } catch (e) {
      Logger.error(TAG, `buildLocalConfig failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  export function buildTunConfig(baseConfigPath: string, outPath: string, mtu: number,
    node: VlessNode | null, opts: ConfigOptions, customRules: string[]): boolean {
    try {
      const text = readText(baseConfigPath);
      const config = JSON.parse(text) as Record<string, Object>;

      config['inbounds'] = buildInbounds(mtu, opts) as Object;
      applyRouting(config, opts, customRules);
      applyDns(config, opts);
      if (node !== null) {
        replaceProxyOutbound(config, node);
      }

      writeText(outPath, JSON.stringify(config));
      Logger.info(TAG, `tun config written: ${outPath} (mtu=${mtu}, node=${node?.name ?? 'base'}, ` +
        `mode=${opts.routeMode}, ds=${opts.domainStrategy}, dns=${opts.localDns}, v6=${opts.ipv6}, lan=${opts.lanShare})`);
      return true;
    } catch (e) {
      Logger.error(TAG, `buildTunConfig failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  function buildInbounds(mtu: number, opts: ConfigOptions): Inbound[] {
    const inbounds: Inbound[] = [];
    const tunSettings: TunSettings = { name: 'vpn-tun', MTU: mtu };
    const tun: Inbound = {
      tag: 'tun',
      protocol: 'tun',
      settings: tunSettings as Object
    };
    if (opts.sniffing) {
      const sn: SniffingSettings = {
        enabled: true,
        destOverride: ['http', 'tls', 'quic'],
        routeOnly: opts.sniffingRouteOnly
      };
      tun.sniffing = sn;
    }
    inbounds.push(tun);

    if (opts.lanShare) {
      const socksSettings: SocksSettings = { auth: 'noauth', udp: true };
      const httpSettings: HttpSettings = { auth: 'noauth' };
      const lanSocks: Inbound = {
        tag: 'lan-socks',
        protocol: 'socks',
        listen: '0.0.0.0',
        port: 10810,
        settings: socksSettings as Object
      };
      const lanHttp: Inbound = {
        tag: 'lan-http',
        protocol: 'http',
        listen: '0.0.0.0',
        port: 10811,
        settings: httpSettings as Object
      };
      inbounds.push(lanSocks);
      inbounds.push(lanHttp);
    }
    return inbounds;
  }

  function applyRouting(config: Record<string, Object>, opts: ConfigOptions, customRules: string[]): void {
    const routing = config['routing'] as RoutingSection;
    routing.domainStrategy = opts.domainStrategy;

    const rules: Object[] = [];
    if (opts.localDns) {
      injectDnsOutbound(config);
      const dnsRule: FieldRule = { type: 'field', outboundTag: 'dns-out', port: '53', network: 'tcp,udp' };
      rules.push(dnsRule as Object);
    }
    for (const line of customRules) {
      const parsed = RuleParser.parse(line);
      if (parsed.ok && parsed.rule !== undefined) {
        rules.push(parsed.rule as Object);
        Logger.info(TAG, `custom rule added: ${line}`);
      } else {
        Logger.warn(TAG, `custom rule invalid: ${line} (${parsed.error ?? '?'})`);
      }
    }
    Logger.info(TAG, `routing rules total: ${rules.length} (custom=${customRules.length})`);

    if (opts.routeMode === ROUTE_GLOBAL) {
      routing.rules = rules;
      return;
    }

    const blockAds: FieldRule = { type: 'field', outboundTag: 'block', domain: ['geosite:category-ads-all'] };
    const directCnDomain: FieldRule = { type: 'field', outboundTag: 'direct', domain: ['geosite:cn'] };
    const directCnIp: FieldRule = { type: 'field', outboundTag: 'direct', ip: ['geoip:private', 'geoip:cn'] };
    rules.push(blockAds as Object);
    rules.push(directCnDomain as Object);
    rules.push(directCnIp as Object);
    routing.rules = rules;
  }

  function applyDns(config: Record<string, Object>, opts: ConfigOptions): void {
    const dns = config['dns'] as Record<string, Object>;
    if (dns === undefined || dns === null) {
      return;
    }
    if (opts.dnsCn.length > 0 || opts.dnsForeign.length > 0) {
      const servers: Object[] = [];
      if (opts.dnsCn.length > 0) {
        const cnEntry: DnsServerEntry = {
          address: opts.dnsCn,
          domains: ['geosite:cn'],
          expectIPs: ['geoip:cn']
        };
        servers.push(cnEntry as Object);
      }
      if (opts.dnsForeign.length > 0) {
        servers.push(opts.dnsForeign as Object);
        servers.push('https://1.1.1.1/dns-query' as Object);
      }
      dns['servers'] = servers;
    }
    if (!opts.ipv6) {
      dns['queryStrategy'] = 'UseIPv4';
    }
  }

  interface DnsServerEntry {
    address: string;
    domains: string[];
    expectIPs: string[];
  }

  function replaceProxyOutbound(config: Record<string, Object>, node: VlessNode): void {
    const generated = OutboundGenerator.buildProxy(node);
    const outbounds = config['outbounds'] as Object[];
    for (let i = 0; i < outbounds.length; i++) {
      const ob = outbounds[i] as Record<string, Object>;
      if (ob['tag'] === 'proxy') {
        outbounds[i] = generated as Object;
        Logger.info(TAG, `proxy outbound replaced by node: ${node.name}`);
        return;
      }
    }
    outbounds.unshift(generated as Object);
    Logger.info(TAG, `proxy outbound inserted: ${node.name}`);
  }

  function injectDnsOutbound(config: Record<string, Object>): void {
    const outbounds = config['outbounds'] as Object[];
    for (const item of outbounds) {
      const ob = item as Record<string, Object>;
      if (ob['tag'] === 'dns-out') {
        return;
      }
    }
    const dnsOut: DnsOutbound = { tag: 'dns-out', protocol: 'dns' };
    outbounds.push(dnsOut as Object);
  }

  function readText(path: string): string {
    const stat = fileIo.statSync(path);
    const buf = new ArrayBuffer(stat.size);
    const fd = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    fileIo.readSync(fd.fd, buf);
    fileIo.closeSync(fd);
    return String.fromCharCode(...new Uint8Array(buf));
  }

  function writeText(path: string, text: string): void {
    if (fileIo.accessSync(path)) {
      fileIo.unlinkSync(path);
    }
    const fd = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    fileIo.writeSync(fd.fd, text);
    fileIo.closeSync(fd);
  }
}
