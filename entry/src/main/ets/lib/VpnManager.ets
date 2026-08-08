/*
 * VpnManager.ets - 主进程 VPN 状态机与启停管理
 *
 * 状态机: Disconnected -> Connecting -> Connected -> Disconnecting -> Disconnected
 * 状态来源:
 *   主动: start/stop 调用
 *   被动: 服务连接回调(onConnect/onDisconnect/onFailed, 覆盖 VPN 进程死亡)
 *   恢复: 冷启动时按 preferences 标记探测重连(不触发系统授权弹窗)
 * UI 通过 onChanged 订阅状态变化; VPN 进程内核心状态经 commonEvent 广播(见 VpnAbility)
 */
import { vpnExtension, connection } from '@kit.NetworkKit';
import { common, Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { commonEventManager } from '@kit.BasicServicesKit';
import { BackgroundKeeper } from './BackgroundKeeper';
import { SettingsStore } from './SettingsStore';
import { NodeStore } from './NodeStore';
import { Logger } from './Logger';

const TAG = 'vpnMgr';
const PREF_NAME = 'vpn_state';
const PREF_KEY_STARTED = 'vpn_started';
const EVENT_VPN_STATE = 'VPNAPP_VPN_STATE';
const EVENT_VPN_TRAFFIC = 'VPNAPP_VPN_TRAFFIC';

export enum VpnStatus {
  Disconnected = 0,
  Connecting = 1,
  Connected = 2,
  Disconnecting = 3
}

type StatusListener = (s: VpnStatus) => void;

export namespace VpnManager {

  export let status: VpnStatus = VpnStatus.Disconnected;
  let serviceId: number = 0;
  let stopping: boolean = false;
  let reconnectAttempts: number = 0;
  let reconnectTimer: number = -1;
  const listeners: StatusListener[] = [];
  const subscribers: commonEventManager.CommonEventSubscriber[] = [];
  const subscribedEvents = new Set<string>();

  export function onChanged(cb: StatusListener): void {
    listeners.push(cb);
  }

  function setStatus(s: VpnStatus): void {
    if (status === s) {
      return;
    }
    status = s;
    Logger.info(TAG, `status -> ${VpnStatus[s]}`);
    for (const cb of listeners) {
      cb(s);
    }
  }

  function pref(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: PREF_NAME });
  }

  function markStarted(context: common.Context, started: boolean): void {
    const p = pref(context);
    p.putSync(PREF_KEY_STARTED, started);
    p.flush();
  }

  export function start(context: common.UIAbilityContext): void {
    if (status !== VpnStatus.Disconnected) {
      Logger.warn(TAG, `start ignored, status=${VpnStatus[status]}`);
      return;
    }
    if (NodeStore.selected(context) === null) {
      Logger.warn(TAG, 'start ignored: no node selected');
      return;
    }
    if (reconnectTimer >= 0) {
      clearTimeout(reconnectTimer);
      reconnectTimer = -1;
    }
    reconnectAttempts = 0;
    setStatus(VpnStatus.Connecting);
    const want: Want = { bundleName: context.applicationInfo.name, abilityName: 'VpnAbility' };
    Logger.info(TAG, 'startVpnExtensionAbility...');
    vpnExtension.startVpnExtensionAbility(want).then(() => {
      connectService(context, want);
    }).catch((e: Object) => {
      Logger.error(TAG, `startVpnExtensionAbility failed: ${JSON.stringify(e)}`);
      setStatus(VpnStatus.Disconnected);
    });
  }

  export function stop(context: common.UIAbilityContext): void {
    if (status !== VpnStatus.Connected) {
      Logger.warn(TAG, `stop ignored, status=${VpnStatus[status]}`);
      return;
    }
    setStatus(VpnStatus.Disconnecting);
    stopping = true;
    BackgroundKeeper.stop(context);
    context.disconnectServiceExtensionAbility(serviceId).catch((e: Object) => {
      Logger.error(TAG, `disconnectServiceExtensionAbility failed: ${JSON.stringify(e)}`);
    }).finally(() => {
      const want: Want = { bundleName: context.applicationInfo.name, abilityName: 'VpnAbility' };
      vpnExtension.stopVpnExtensionAbility(want);
      serviceId = 0;
      markStarted(context, false);
      setStatus(VpnStatus.Disconnected);
      setTimeout(() => {
        stopping = false;
      }, 2000);
    });
  }

  /*
   * 冷启动恢复: 仅当上次是我们启动的 VPN 才探测;
   * 直接 connectService 不走 startVpnExtensionAbility, 避免重复弹授权框;
   * VpnAbility 侧 onConnect 幂等, 已运行则直接返回
   */
  export function recover(context: common.UIAbilityContext): void {
    const started = pref(context).getSync(PREF_KEY_STARTED, false) as boolean;
    if (!started) {
      Logger.info(TAG, 'recover: no active session marked');
      return;
    }
    Logger.info(TAG, 'recover: probing existing vpn session...');
    setStatus(VpnStatus.Connecting);
    const want: Want = { bundleName: context.applicationInfo.name, abilityName: 'VpnAbility' };
    connectService(context, want);
  }

  /*
   * 订阅 VPN 进程的核心状态广播, 启动时调用一次;
   * VPN 进程被杀/退出时广播 disconnected, 驱动状态机归位
   */
  export function subscribeCoreEvents(): void {
    if (subscribedEvents.has(EVENT_VPN_STATE)) {
      return;
    }
    subscribedEvents.add(EVENT_VPN_STATE);
    commonEventManager.createSubscriber({ events: [EVENT_VPN_STATE] }, (err, subscriber) => {
      if (err) {
        Logger.error(TAG, `createSubscriber failed: ${JSON.stringify(err)}`);
        return;
      }
      subscribers.push(subscriber);
      commonEventManager.subscribe(subscriber, (err, data) => {
        if (err) {
          Logger.error(TAG, `subscribe error: ${JSON.stringify(err)}`);
          return;
        }
        const state = data.parameters?.['state'] as string;
        Logger.info(TAG, `core event: ${state}`);
        if (state === 'disconnected' && status === VpnStatus.Connected && !stopping) {
          Logger.warn(TAG, 'core lost unexpectedly');
          setStatus(VpnStatus.Disconnected);
        }
      });
    });
  }

  export interface TrafficInfo {
    totalUp: number;
    totalDown: number;
    speedUp: number;
    speedDown: number;
    coreUp: number;
    coreDown: number;
  }

  /*
   * 订阅流量广播(vpn 进程每秒一发, 单位字节; coreUp/coreDown 为 xray 内核统计)
   */
  const trafficListeners: Array<(t: TrafficInfo) => void> = [];
  export let lastTraffic: TrafficInfo = { totalUp: 0, totalDown: 0, speedUp: 0, speedDown: 0, coreUp: 0, coreDown: 0 };

  export function subscribeTraffic(cb: (t: TrafficInfo) => void): void {
    trafficListeners.push(cb);
    if (subscribedEvents.has(EVENT_VPN_TRAFFIC)) {
      return;
    }
    subscribedEvents.add(EVENT_VPN_TRAFFIC);
    commonEventManager.createSubscriber({ events: [EVENT_VPN_TRAFFIC] }, (err, subscriber) => {
      if (err) {
        Logger.error(TAG, `traffic createSubscriber failed: ${JSON.stringify(err)}`);
        return;
      }
      subscribers.push(subscriber);
      commonEventManager.subscribe(subscriber, (err, data) => {
        if (err) {
          return;
        }
        const p = data.parameters;
        const info: TrafficInfo = {
          totalUp: p?.['totalUp'] as number ?? 0,
          totalDown: p?.['totalDown'] as number ?? 0,
          speedUp: p?.['speedUp'] as number ?? 0,
          speedDown: p?.['speedDown'] as number ?? 0,
          coreUp: p?.['coreUp'] as number ?? 0,
          coreDown: p?.['coreDown'] as number ?? 0
        };
        lastTraffic = info;
        for (const l of trafficListeners) {
          l(info);
        }
      });
    });
  }

  /*
   * 断线自动重连: 意外断开/连接失败时, 若设置开启且未超过重试上限, 延迟重连
   */
  function scheduleReconnect(context: common.UIAbilityContext): void {
    if (!SettingsStore.autoReconnect(context)) {
      reconnectAttempts = 0;
      return;
    }
    if (reconnectAttempts >= 3) {
      Logger.warn(TAG, 'auto reconnect: max attempts reached, giving up');
      reconnectAttempts = 0;
      return;
    }
    reconnectAttempts++;
    const delayMs = 5000 * reconnectAttempts;
    Logger.info(TAG, `auto reconnect in ${delayMs}ms (attempt ${reconnectAttempts}/3)`);
    reconnectTimer = setTimeout(() => {
      reconnectTimer = -1;
      start(context);
    }, delayMs);
  }

  function connectService(context: common.UIAbilityContext, want: Want): void {
    const linkAddr: connection.LinkAddress = {
      address: { address: '10.0.0.2', family: 1 },
      prefixLength: 24
    };
    const vpnConfig: vpnExtension.VpnConfig = {
      addresses: [linkAddr],
      mtu: 1500,
      dnsAddresses: ['223.5.5.5', '8.8.8.8'],
      blockedApplications: [context.applicationInfo.name],
      isIPv6Accepted: false
    };
    const params: Record<string, Object> = { 'VPN_CONFIG': vpnConfig };
    const connectWant: Want = {
      bundleName: want.bundleName,
      abilityName: want.abilityName,
      parameters: params
    };
    try {
      serviceId = context.connectServiceExtensionAbility(connectWant, {
        onConnect: () => {
          markStarted(context, true);
          setStatus(VpnStatus.Connected);
        },
        onDisconnect: () => {
          markStarted(context, false);
          if (!stopping && status !== VpnStatus.Disconnected) {
            Logger.warn(TAG, 'service disconnected unexpectedly (vpn process died?)');
            BackgroundKeeper.stop(context);
            scheduleReconnect(context);
          }
          setStatus(VpnStatus.Disconnected);
        },
        onFailed: (code: number) => {
          Logger.error(TAG, `service connect failed: ${code}`);
          markStarted(context, false);
          if (!stopping) {
            scheduleReconnect(context);
          }
          setStatus(VpnStatus.Disconnected);
        }
      });
    } catch (e) {
      Logger.error(TAG, `connectServiceExtensionAbility throw: ${JSON.stringify(e)}`);
      setStatus(VpnStatus.Disconnected);
    }
  }
}
