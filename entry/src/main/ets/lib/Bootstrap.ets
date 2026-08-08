/*
 * Bootstrap.ets - 应用启动引导(调试框架阶段)
 *
 * 流程: 桥自检 -> 初始化 Go 侧日志 -> 输出版本/状态 -> 部署 xray 资源 -> 启动 xray 核心
 * 注意: 当前为调试阶段, xray 随 app 启动自动运行(本地 socks/http 代理模式),
 *       接入 UI 后应改为用户手动触发, 并移除本文件中的 startCoreForTest
 */
import { common, Want } from '@kit.AbilityKit';
import { hiAppEvent } from '@kit.PerformanceAnalysisKit';
import { Logger } from './Logger';
import { CoreBridge } from './CoreBridge';
import { DebugServices } from './DebugServices';
import { CoreServices } from './CoreServices';
import { Assets } from './Assets';
import { NodeStore } from './NodeStore';
import { VpnCoreConfig } from './VpnCoreConfig';
import { SettingsStore } from './SettingsStore';

export namespace Bootstrap {

  export async function initDebugFramework(context: common.UIAbilityContext,
    launchWant?: Want): Promise<void> {
    Logger.info('boot', 'debug framework bootstrap start');
    try {
      const bridgeStatus = CoreBridge.status();
      Logger.info('boot', `bridge: loaded=${bridgeStatus.loaded} err=${bridgeStatus.lastError}`);

      if (!CoreBridge.selfTest()) {
        Logger.error('boot', 'bridge selfTest failed, core library unavailable');
        return;
      }

      await DebugServices.initLog(context.filesDir, 7);
      const version = await DebugServices.version();
      Logger.info('boot', `core version: framework=${version.framework} go=${version.go} core=${version.core}`);
      Logger.info('boot', `settings: route=${SettingsStore.routeMode(context)} ds=${SettingsStore.domainStrategy(context)} ` +
        `sniff=${SettingsStore.sniffing(context)} routeOnly=${SettingsStore.sniffingRouteOnly(context)} ` +
        `dns=${SettingsStore.localDns(context)} v6=${SettingsStore.ipv6(context)} ` +
        `lan=${SettingsStore.lanShare(context)} reconnect=${SettingsStore.autoReconnect(context)} ` +
        `subUpdate=${SettingsStore.autoUpdateSub(context)} dnsCn=${SettingsStore.dnsCn(context)} ` +
        `rules=${SettingsStore.customRules(context).length}`);
      const status = await DebugServices.status();
      Logger.info('boot', `core status: goroutines=${status.goroutines} heap=${status.heapAllocMB.toFixed(1)}MB cpus=${status.numCPU}`);
      Logger.info('boot', 'debug framework bootstrap ok');
      setupCrashWatcher();

      await startCoreForTest(context);
    } catch (e) {
      Logger.error('boot', `bootstrap failed: ${JSON.stringify(e)}`);
    }
  }

  /*
   * 崩溃监听: 订阅系统 APP_CRASH 事件, 将崩溃信息写入统一日志
   * (crash 发生后进程可能即将退出, 日志落盘由 xlog 文件写入保证)
   */
  function setupCrashWatcher(): void {
    try {
      hiAppEvent.addWatcher({
        name: 'vpnapp_crash_watcher',
        appEventFilters: [{ domain: 'os', eventTypes: [hiAppEvent.EventType.FAULT] }],
        onReceive: (domain: string, groups: Array<hiAppEvent.AppEventGroup>) => {
          for (const group of groups) {
            for (const info of group.appEventInfos) {
              const params = info.params;
              let reason = '';
              try {
                reason = JSON.stringify(params);
              } catch {
              }
              Logger.error('crash', `${info.name}: ${reason}`);
              DebugServices.writeLog(6, 'crash', `${info.name}: ${reason}`);
            }
          }
        }
      });
      Logger.info('boot', 'crash watcher registered');
    } catch (e) {
      Logger.error('boot', `crash watcher failed: ${JSON.stringify(e)}`);
    }
  }

  async function startCoreForTest(context: common.Context): Promise<void> {
    if (!Assets.ensureDeployed(context)) {
      Logger.error('boot', 'asset deploy failed, skip core start');
      return;
    }
    try {
      const node = NodeStore.selected(context);
      let configPath = Assets.configPath(context);
      if (node !== null) {
        const localConfig = `${Assets.assetDir(context)}/config_local.json`;
        const opts = SettingsStore.configOptions(context);
        const customRules = SettingsStore.customRules(context);
        if (VpnCoreConfig.buildLocalConfig(configPath, localConfig, node, opts, customRules)) {
          configPath = localConfig;
        }
      }
      const result = await CoreServices.start({
        assetLocation: Assets.assetDir(context),
        configLocation: configPath
      });
      Logger.info('boot', `xray started: version=${result.version} running=${result.running}`);
      const state = await CoreServices.state();
      Logger.info('boot', `xray state: running=${state.running} uptime=${state.uptimeMs}ms`);
    } catch (e) {
      Logger.error('boot', `xray start failed: ${JSON.stringify(e)}`);
    }
  }
}
