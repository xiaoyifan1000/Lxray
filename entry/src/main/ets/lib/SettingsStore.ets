/*
 * SettingsStore.ets - 应用设置持久化(preferences)
 *
 * keepAliveOnClose:  关窗保活(已下线, 保留键位)
 * routeMode:         路由模式 'global' 默认全局代理 | 'bypass_mainland' 禁用全局(国内直连分流)
 * domainStrategy:    域名策略 'AsIs'(默认) | 'IPIfNonMatch' | 'IPOnDemand'
 * sniffing:          流量探测(默认开)
 * sniffingRouteOnly: 探测域名仅用于路由(默认关)
 * localDns:          本地 DNS 拦截(53 进 xray DNS 模块, 默认开)
 * ipv6:              允许 IPv6(默认开)
 * lanShare:          局域网共享(0.0.0.0 socks/http 监听, 默认关)
 *
 * 除 keepAliveOnClose 外, 改动均在下次 VPN 连接时生效
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const PREF_NAME = 'vpn_settings';
const KEY_KEEP_ALIVE = 'keep_alive_on_close';
const KEY_ROUTE_MODE = 'route_mode';
const KEY_DOMAIN_STRATEGY = 'domain_strategy';
const KEY_SNIFFING = 'sniffing';
const KEY_SNIFFING_ROUTE_ONLY = 'sniffing_route_only';
const KEY_LOCAL_DNS = 'local_dns';
const KEY_IPV6 = 'ipv6';
const KEY_LAN_SHARE = 'lan_share';
const KEY_AUTO_UPDATE_SUB = 'auto_update_sub';
const KEY_AUTO_RECONNECT = 'auto_reconnect';
const KEY_DNS_CN = 'dns_cn';
const KEY_DNS_FOREIGN = 'dns_foreign';
const KEY_CUSTOM_RULES = 'custom_rules';
const KEY_LOG_ERROR_ONLY = 'log_error_only';

export const DEFAULT_DNS_CN = '223.5.5.5';
export const DEFAULT_DNS_FOREIGN = 'https://dns.google/dns-query';

export const ROUTE_GLOBAL = 'global';
export const ROUTE_BYPASS_MAINLAND = 'bypass_mainland';

export const DS_ASIS = 'AsIs';
export const DS_IF_NON_MATCH = 'IPIfNonMatch';
export const DS_ON_DEMAND = 'IPOnDemand';

export interface ConfigOptions {
  routeMode: string;
  domainStrategy: string;
  sniffing: boolean;
  sniffingRouteOnly: boolean;
  localDns: boolean;
  ipv6: boolean;
  lanShare: boolean;
  dnsCn: string;
  dnsForeign: string;
}

export namespace SettingsStore {

  function pref(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: PREF_NAME });
  }

  function put(key: string, value: preferences.ValueType, context: common.Context): void {
    const p = pref(context);
    p.putSync(key, value);
    p.flush();
  }

  export function keepAliveOnClose(context: common.Context): boolean {
    return pref(context).getSync(KEY_KEEP_ALIVE, false) as boolean;
  }

  export function setKeepAliveOnClose(context: common.Context, value: boolean): void {
    put(KEY_KEEP_ALIVE, value, context);
  }

  export function routeMode(context: common.Context): string {
    return pref(context).getSync(KEY_ROUTE_MODE, ROUTE_GLOBAL) as string;
  }

  export function setRouteMode(context: common.Context, value: string): void {
    put(KEY_ROUTE_MODE, value, context);
  }

  export function domainStrategy(context: common.Context): string {
    return pref(context).getSync(KEY_DOMAIN_STRATEGY, DS_ASIS) as string;
  }

  export function setDomainStrategy(context: common.Context, value: string): void {
    put(KEY_DOMAIN_STRATEGY, value, context);
  }

  export function sniffing(context: common.Context): boolean {
    return pref(context).getSync(KEY_SNIFFING, true) as boolean;
  }

  export function setSniffing(context: common.Context, value: boolean): void {
    put(KEY_SNIFFING, value, context);
  }

  export function sniffingRouteOnly(context: common.Context): boolean {
    return pref(context).getSync(KEY_SNIFFING_ROUTE_ONLY, false) as boolean;
  }

  export function setSniffingRouteOnly(context: common.Context, value: boolean): void {
    put(KEY_SNIFFING_ROUTE_ONLY, value, context);
  }

  export function localDns(context: common.Context): boolean {
    return pref(context).getSync(KEY_LOCAL_DNS, true) as boolean;
  }

  export function setLocalDns(context: common.Context, value: boolean): void {
    put(KEY_LOCAL_DNS, value, context);
  }

  export function ipv6(context: common.Context): boolean {
    return pref(context).getSync(KEY_IPV6, true) as boolean;
  }

  export function setIpv6(context: common.Context, value: boolean): void {
    put(KEY_IPV6, value, context);
  }

  export function lanShare(context: common.Context): boolean {
    return pref(context).getSync(KEY_LAN_SHARE, false) as boolean;
  }

  export function setLanShare(context: common.Context, value: boolean): void {
    put(KEY_LAN_SHARE, value, context);
  }

  export function configOptions(context: common.Context): ConfigOptions {
    return {
      routeMode: routeMode(context),
      domainStrategy: domainStrategy(context),
      sniffing: sniffing(context),
      sniffingRouteOnly: sniffingRouteOnly(context),
      localDns: localDns(context),
      ipv6: ipv6(context),
      lanShare: lanShare(context),
      dnsCn: dnsCn(context),
      dnsForeign: dnsForeign(context)
    };
  }

  export function dnsCn(context: common.Context): string {
    return pref(context).getSync(KEY_DNS_CN, DEFAULT_DNS_CN) as string;
  }

  export function setDnsCn(context: common.Context, value: string): void {
    put(KEY_DNS_CN, value, context);
  }

  export function dnsForeign(context: common.Context): string {
    return pref(context).getSync(KEY_DNS_FOREIGN, DEFAULT_DNS_FOREIGN) as string;
  }

  export function setDnsForeign(context: common.Context, value: string): void {
    put(KEY_DNS_FOREIGN, value, context);
  }

  /*
   * 自定义路由规则: 每行一条, 形如 "domain:example.com,geosite:ads -> block"
   * 由 VpnCoreConfig 在生成配置时解析为 xray 规则
   */
  export function customRules(context: common.Context): string[] {
    const raw = pref(context).getSync(KEY_CUSTOM_RULES, '[]') as string;
    try {
      return JSON.parse(raw) as string[];
    } catch {
      return [];
    }
  }

  export function setCustomRules(context: common.Context, rules: string[]): void {
    put(KEY_CUSTOM_RULES, JSON.stringify(rules), context);
  }

  export function logErrorOnly(context: common.Context): boolean {
    return pref(context).getSync(KEY_LOG_ERROR_ONLY, true) as boolean;
  }

  export function setLogErrorOnly(context: common.Context, value: boolean): void {
    put(KEY_LOG_ERROR_ONLY, value, context);
  }

  export function autoUpdateSub(context: common.Context): boolean {
    return pref(context).getSync(KEY_AUTO_UPDATE_SUB, true) as boolean;
  }

  export function setAutoUpdateSub(context: common.Context, value: boolean): void {
    put(KEY_AUTO_UPDATE_SUB, value, context);
  }

  export function autoReconnect(context: common.Context): boolean {
    return pref(context).getSync(KEY_AUTO_RECONNECT, true) as boolean;
  }

  export function setAutoReconnect(context: common.Context, value: boolean): void {
    put(KEY_AUTO_RECONNECT, value, context);
  }
}
