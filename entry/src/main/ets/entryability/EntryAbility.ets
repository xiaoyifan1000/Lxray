import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { Bootstrap } from '../lib/Bootstrap';
import { VpnManager } from '../lib/VpnManager';
import { SettingsStore } from '../lib/SettingsStore';
import { SubscriptionStore } from '../lib/SubscriptionStore';
import { Subscription } from '../lib/Subscription';
import { Logger } from '../lib/Logger';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    Bootstrap.initDebugFramework(this.context, want);
    VpnManager.subscribeCoreEvents();
    VpnManager.subscribeTraffic(() => {});
    VpnManager.recover(this.context);
    this.autoRefreshSubscriptions();
  }

  /*
   * 订阅自动更新: 设置开启时, 超过 24h 未更新的订阅后台拉取一次
   */
  private async autoRefreshSubscriptions(): Promise<void> {
    if (!SettingsStore.autoUpdateSub(this.context)) {
      return;
    }
    try {
      const stale = SubscriptionStore.staleSubscriptions(this.context, 24 * 3600 * 1000);
      if (stale.length === 0) {
        return;
      }
      Logger.info('boot', `auto refresh ${stale.length} subscription(s)`);
      for (const sub of stale) {
        const added = await Subscription.fetchAndImport(this.context, sub.url);
        if (added >= 0) {
          SubscriptionStore.touch(this.context, sub.id);
          Logger.info('boot', `subscription updated: +${added} nodes`);
        }
      }
    } catch (e) {
      Logger.error('boot', `autoRefreshSubscriptions failed: ${JSON.stringify(e)}`);
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // 关窗不再停止 VPN: 保留 vpn_started 标记,
    // 下次启动时由 VpnManager.recover() 自动探测并恢复连接
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy (vpn session kept for recover)');
    Logger.info('boot', 'window closed, vpn_started flag kept for auto-recover on next launch');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}