/*
 * SubscriptionStore.ets - 订阅链接管理(持久化)
 *
 * 保存多条订阅 URL, 记录最后更新时间用于自动刷新策略
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const PREF_NAME = 'vpn_subscriptions';
const KEY_SUBS = 'sub_list';

export interface SubscriptionItem {
  id: string;
  url: string;
  updatedAt: number;
}

export namespace SubscriptionStore {

  type SubListener = () => void;
  const listeners: SubListener[] = [];

  export function onChanged(cb: SubListener): void {
    listeners.push(cb);
  }

  function notifyChanged(): void {
    for (const cb of listeners) {
      cb();
    }
  }

  function pref(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: PREF_NAME });
  }

  export function list(context: common.Context): SubscriptionItem[] {
    const raw = pref(context).getSync(KEY_SUBS, '[]') as string;
    try {
      return JSON.parse(raw) as SubscriptionItem[];
    } catch {
      return [];
    }
  }

  export function add(context: common.Context, url: string): boolean {
    const subs = list(context);
    for (const s of subs) {
      if (s.url === url) {
        return false;
      }
    }
    subs.push({ id: `${Date.now()}`, url: url, updatedAt: 0 });
    save(context, subs);
    notifyChanged();
    return true;
  }

  export function remove(context: common.Context, id: string): void {
    save(context, list(context).filter((s: SubscriptionItem) => s.id !== id));
    notifyChanged();
  }

  export function touch(context: common.Context, id: string): void {
    const subs = list(context).map((s: SubscriptionItem): SubscriptionItem => {
      if (s.id === id) {
        return { id: s.id, url: s.url, updatedAt: Date.now() };
      }
      return s;
    });
    save(context, subs);
    notifyChanged();
  }

  export function staleSubscriptions(context: common.Context, maxAgeMs: number): SubscriptionItem[] {
    const now = Date.now();
    return list(context).filter((s: SubscriptionItem) => now - s.updatedAt > maxAgeMs);
  }

  function save(context: common.Context, subs: SubscriptionItem[]): void {
    const p = pref(context);
    p.putSync(KEY_SUBS, JSON.stringify(subs));
    p.flush();
  }
}
