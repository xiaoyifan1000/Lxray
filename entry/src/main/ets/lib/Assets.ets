/*
 * Assets.ets - xray 运行资源部署
 * 将 rawfile 中的 geoip.dat/geosite.dat/config.json 拷贝到 filesDir/xray,
 * 已存在则跳过; assetDir 同时作为 xray 的 xray.asset.location
 */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from './Logger';

const TAG = 'assets';
const ASSET_FILES: string[] = ['geoip.dat', 'geosite.dat', 'config.json'];

export namespace Assets {

  export function assetDir(context: common.Context): string {
    return `${context.filesDir}/xray`;
  }

  export function configPath(context: common.Context): string {
    return `${assetDir(context)}/config.json`;
  }

  export function ensureDeployed(context: common.Context): boolean {
    const dir = assetDir(context);
    try {
      fileIo.mkdir(dir, true);
      const resMgr = context.resourceManager;
      for (const name of ASSET_FILES) {
        const target = `${dir}/${name}`;
        const content = resMgr.getRawFileContentSync(name);
        if (fileIo.accessSync(target)) {
          const existing = fileIo.statSync(target);
          if (existing.size === content.length) {
            continue;
          }
          Logger.info(TAG, `${name} changed (${existing.size} -> ${content.length}), redeploy`);
        }
        const fd = fileIo.openSync(target, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        fileIo.writeSync(fd.fd, content.buffer);
        fileIo.closeSync(fd);
        Logger.info(TAG, `deployed ${name} (${content.length} bytes)`);
      }
      return true;
    } catch (e) {
      const err = e as BusinessError;
      Logger.error(TAG, `deploy failed: code=${err.code} msg=${err.message}`);
      return false;
    }
  }
}
