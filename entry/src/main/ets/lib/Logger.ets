/*
 * Logger.ets - ArkTS 层统一日志封装
 * 约定见 cpp/vpn_log.h (domain 0x3200, tag VPNAPP-ETS)
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x3200;
const TAG = 'VPNAPP-ETS';

export class Logger {
  static debug(tag: string, msg: string): void {
    hilog.debug(DOMAIN, TAG, `[${tag}] ${msg}`);
  }

  static info(tag: string, msg: string): void {
    hilog.info(DOMAIN, TAG, `[${tag}] ${msg}`);
  }

  static warn(tag: string, msg: string): void {
    hilog.warn(DOMAIN, TAG, `[${tag}] ${msg}`);
  }

  static error(tag: string, msg: string): void {
    hilog.error(DOMAIN, TAG, `[${tag}] ${msg}`);
  }
}
