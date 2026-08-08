/*
 * BackgroundKeeper.ets - 长时任务保活封装
 *
 * 作用: 关窗后防止 bundle 被系统整体回收(2in1 默认行为),
 *       申请后系统强制显示一条常驻通知, 顺带提供"VPN 运行中"可见指示
 * 用法: VPN 连接成功且 keepAliveOnClose 开启时 start, 断开时 stop
 * 权限: ohos.permission.KEEP_BACKGROUND_RUNNING (normal, 直接声明生效)
 */
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from './Logger';

const TAG = 'bgKeeper';

export namespace BackgroundKeeper {

  let running = false;

  export async function start(context: common.UIAbilityContext): Promise<boolean> {
    if (running) {
      return true;
    }
    try {
      const agent = await wantAgent.getWantAgent({
        wants: [{ bundleName: context.applicationInfo.name, abilityName: 'EntryAbility' }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0
      });
      const request = new backgroundTaskManager.ContinuousTaskRequest();
      request.backgroundTaskModes = [backgroundTaskManager.BackgroundTaskMode.MODE_SPECIAL_SCENARIO_PROCESSING];
      request.wantAgent = agent;
      if (!request.isModeSupported()) {
        Logger.error(TAG, 'special scenario mode not supported on this device');
        return false;
      }
      let auth = await request.checkSpecialScenarioAuth(context);
      Logger.info(TAG, `special scenario auth state: ${auth}`);
      if (auth === backgroundTaskManager.UserAuthResult.NOT_DETERMINED) {
        auth = await new Promise<backgroundTaskManager.UserAuthResult>((resolve) => {
          try {
            request.requestAuthFromUser(context, (result: backgroundTaskManager.UserAuthResult) => {
              resolve(result);
            });
          } catch (e) {
            Logger.error(TAG, `requestAuthFromUser throw: ${JSON.stringify(e)}`);
            resolve(backgroundTaskManager.UserAuthResult.DENIED);
          }
        });
        Logger.info(TAG, `auth after user request: ${auth}`);
      }
      if (auth !== backgroundTaskManager.UserAuthResult.GRANTED_ALWAYS &&
        auth !== backgroundTaskManager.UserAuthResult.GRANTED_ONCE) {
        Logger.error(TAG, `user auth not granted: ${auth}`);
        return false;
      }
      await backgroundTaskManager.startBackgroundRunning(context, request);
      running = true;
      Logger.info(TAG, 'continuous task started');
      return true;
    } catch (e) {
      Logger.error(TAG, `start failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  export async function stop(context: common.UIAbilityContext): Promise<void> {
    if (!running) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      Logger.info(TAG, 'continuous task stopped');
    } catch (e) {
      Logger.error(TAG, `stop failed: ${JSON.stringify(e)}`);
    } finally {
      running = false;
    }
  }

  export function isRunning(): boolean {
    return running;
  }
}
