/*
 * Subscription.ets - 订阅链接拉取与解析
 *
 * 拉取订阅 URL(明文或 base64), 按行解析 vless:// 链接并入库;
 * 返回新增节点数; 拉取走直连(订阅时代理可能未就绪)
 */
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { NodeStore } from './NodeStore';
import { CoreBridge } from './CoreBridge';
import { Logger } from './Logger';

const TAG = 'subscription';

interface FetchResponse {
  body: string;
}

interface FetchParams {
  url: string;
}

export namespace Subscription {

  export async function fetchAndImport(context: common.Context, url: string): Promise<number> {
    const body = await fetchDirect(url);
    if (body !== null) {
      return importLines(context, body);
    }
    Logger.info(TAG, 'direct fetch failed, trying via local proxy');
    try {
      const params: FetchParams = { url: url };
      const resp = await CoreBridge.call<FetchResponse>('SubscriptionService.Fetch', params);
      return importLines(context, resp.body);
    } catch (e) {
      Logger.error(TAG, `proxy fetch error: ${JSON.stringify(e)}`);
      return -1;
    }
  }

  async function fetchDirect(url: string): Promise<string | null> {
    const req = http.createHttp();
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 8000,
        readTimeout: 8000
      });
      if (resp.responseCode !== 200) {
        return null;
      }
      return resp.result as string;
    } catch {
      return null;
    } finally {
      req.destroy();
    }
  }

  function decodeMaybeBase64(body: string): string {
    const trimmed = body.trim();
    if (trimmed.includes('://')) {
      return trimmed;
    }
    try {
      const decoder = util.TextDecoder.create('utf-8');
      const bytes = new util.Base64Helper().decodeSync(trimmed);
      return decoder.decodeToString(bytes);
    } catch {
      return trimmed;
    }
  }

  export function importLines(context: common.Context, text: string): number {
    const decoded = decodeMaybeBase64(text);
    let added = 0;
    for (const line of decoded.split('\n')) {
      const trimmed = line.trim();
      if (!trimmed.startsWith('vless://') && !trimmed.startsWith('vmess://')) {
        continue;
      }
      const node = NodeStore.importLink(context, trimmed);
      if (node !== null) {
        added++;
      }
    }
    Logger.info(TAG, `import done: ${added} nodes`);
    return added;
  }
}
