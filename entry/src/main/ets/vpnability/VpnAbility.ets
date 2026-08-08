/*
 * VpnAbility.ets - VPN 扩展能力(独立进程 :vpn)
 *
 * 生命周期:
 *   onConnect    幂等: 核心已运行则直接返回(供主进程冷启动重连探测);
 *                否则 获取 tun fd -> protectProcessNet -> 初始化桥/日志 -> 启动 xray
 *   onDisconnect 停止 xray -> 销毁 tun
 *   onDestroy    进程退出(Go runtime 不可卸载, 整进程退出最干净)
 *
 * 跨进程状态: 核心启停经 commonEvent 'VPNAPP_VPN_STATE' 广播给主进程/UI
 */
import { vpnExtension, VpnExtensionAbility, statistics } from '@kit.NetworkKit';
import { rpc } from '@kit.IPCKit';
import { process } from '@kit.ArkTS';
import { commonEventManager } from '@kit.BasicServicesKit';
import { Want } from '@kit.AbilityKit';
import { Logger } from '../lib/Logger';
import { DebugServices } from '../lib/DebugServices';
import { CoreServices } from '../lib/CoreServices';
import { Assets } from '../lib/Assets';
import { VpnCoreConfig } from '../lib/VpnCoreConfig';
import { NodeStore } from '../lib/NodeStore';
import { SettingsStore } from '../lib/SettingsStore';

const TAG = 'vpn';
const TUN_CONFIG_NAME = 'config_tun.json';
const EVENT_VPN_STATE = 'VPNAPP_VPN_STATE';
const EVENT_VPN_TRAFFIC = 'VPNAPP_VPN_TRAFFIC';
const TUN_IFACE = 'vpn-tun';
const STAT_INTERVAL_MS = 1000;

export default class VpnAbility extends VpnExtensionAbility {
  private connection = new Object() as vpnExtension.VpnConnection;
  private coreRunning = false;
  private statTimer: number = -1;
  private lastTx: number = 0;
  private lastRx: number = 0;

  onCreate(): void {
    Logger.info(TAG, 'VpnAbility.onCreate');
    this.connection = vpnExtension.createVpnConnection(this.context);
  }

  async onConnect(want: Want): Promise<rpc.RemoteObject> {
    Logger.info(TAG, 'VpnAbility.onConnect');
    if (this.coreRunning) {
      Logger.info(TAG, 'core already running, return existing session');
      return new rpc.RemoteObject('VPNAPP_VPN_ABILITY');
    }
    let fd = -1;
    try {
      const config = want.parameters!['VPN_CONFIG'] as vpnExtension.VpnConfig;
      fd = await this.connection.create(config);
      Logger.info(TAG, `tun fd acquired: ${fd}`);
      await this.connection.protectProcessNet();
      Logger.info(TAG, 'protectProcessNet done');

      await DebugServices.initLog(this.context.filesDir, 7);
      if (!Assets.ensureDeployed(this.context)) {
        throw new Error('asset deploy failed');
      }
      const tunConfig = `${Assets.assetDir(this.context)}/${TUN_CONFIG_NAME}`;
      const node = NodeStore.selected(this.context);
      const opts = SettingsStore.configOptions(this.context);
      if (node === null) {
        Logger.error(TAG, 'no node selected, refusing to start vpn');
        throw new Error('未选择节点，请先在节点页添加并选择节点');
      }
      Logger.info(TAG, `selected node: ${node.name}`);
      const customRules = SettingsStore.customRules(this.context);
      if (!VpnCoreConfig.buildTunConfig(Assets.configPath(this.context), tunConfig, config.mtu ?? 1500,
        node, opts, customRules)) {
        throw new Error('tun config build failed');
      }
      const result = await CoreServices.start({
        fd: fd,
        assetLocation: Assets.assetDir(this.context),
        configLocation: tunConfig
      });
      this.coreRunning = true;
      this.publishState('connected');
      this.startStatLoop();
      Logger.info(TAG, `xray started in vpn process: ${result.version}`);
      return new rpc.RemoteObject('VPNAPP_VPN_ABILITY');
    } catch (e) {
      Logger.error(TAG, `onConnect failed: ${JSON.stringify(e)}`);
      if (fd > 0) {
        try {
          await this.connection.destroy();
          Logger.info(TAG, 'tun connection cleaned up after failure');
        } catch (e2) {
          Logger.error(TAG, `cleanup destroy failed: ${JSON.stringify(e2)}`);
        }
      }
      throw e as Error;
    }
  }

  async onDisconnect(): Promise<void> {
    Logger.info(TAG, 'VpnAbility.onDisconnect');
    this.coreRunning = false;
    this.stopStatLoop();
    try {
      await CoreServices.stop();
    } catch (e) {
      Logger.error(TAG, `core stop failed: ${JSON.stringify(e)}`);
    }
    try {
      await this.connection.destroy();
    } catch (e) {
      Logger.error(TAG, `destroy failed: ${JSON.stringify(e)}`);
    }
    this.publishState('disconnected');
  }

  onDestroy(): void {
    Logger.info(TAG, 'VpnAbility.onDestroy');
    this.publishState('disconnected');
    const pm = new process.ProcessManager();
    pm.exit(0);
  }

  private publishState(state: string): void {
    try {
      commonEventManager.publish(EVENT_VPN_STATE, {
        bundleName: this.context.applicationInfo.name,
        parameters: { 'state': state }
      }, () => {});
    } catch (e) {
      Logger.error(TAG, `publishState failed: ${JSON.stringify(e)}`);
    }
  }

  /*
   * 流量统计: 每秒读 vpn-tun 接口累计收发字节, 差值即速率,
   * 经 commonEvent 'VPNAPP_VPN_TRAFFIC' 广播(totalUp/totalDown/speedUp/speedDown, 字节)
   */
  private startStatLoop(): void {
    this.stopStatLoop();
    this.lastTx = 0;
    this.lastRx = 0;
    this.statTimer = setInterval(async () => {
      try {
        const tx = await statistics.getIfaceTxBytes(TUN_IFACE);
        const rx = await statistics.getIfaceRxBytes(TUN_IFACE);
        let coreUp = 0;
        let coreDown = 0;
        try {
          const st = await CoreServices.stats();
          for (const tag of Object.keys(st)) {
            coreUp += st[tag].up ?? 0;
            coreDown += st[tag].down ?? 0;
          }
        } catch {
        }
        const totalUp = coreUp > 0 ? coreUp : tx;
        const totalDown = coreDown > 0 ? coreDown : rx;
        const speedUp = this.lastTx === 0 ? 0 : totalUp - this.lastTx;
        const speedDown = this.lastRx === 0 ? 0 : totalDown - this.lastRx;
        commonEventManager.publish(EVENT_VPN_TRAFFIC, {
          bundleName: this.context.applicationInfo.name,
          parameters: {
            'totalUp': totalUp,
            'totalDown': totalDown,
            'speedUp': speedUp,
            'speedDown': speedDown,
            'coreUp': coreUp,
            'coreDown': coreDown
          }
        }, () => {});
        this.lastTx = totalUp;
        this.lastRx = totalDown;
      } catch (e) {
        Logger.error(TAG, `stat loop error: ${JSON.stringify(e)}`);
        this.stopStatLoop();
      }
    }, STAT_INTERVAL_MS);
  }

  private stopStatLoop(): void {
    if (this.statTimer >= 0) {
      clearInterval(this.statTimer);
      this.statTimer = -1;
    }
  }
}
