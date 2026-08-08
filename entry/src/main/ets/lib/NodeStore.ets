/*
 * NodeStore.ets - 节点列表持久化(preferences)
 *
 * 存储: 'node_list' = VlessNode[] 的 JSON, 'selected_id' = 当前选中节点 id
 * 两个进程共享同一 preferences 文件; 写操作约定只在主进程发生,
 * vpn 进程只读(启动时读选中节点生成配置)
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { VlessNode, VlessParser } from './parser/VlessParser';
import { Logger } from './Logger';

const TAG = 'nodeStore';
const PREF_NAME = 'vpn_nodes';
const KEY_LIST = 'node_list';
const KEY_SELECTED = 'selected_id';

export namespace NodeStore {

  type NodeListener = () => void;
  const listeners: NodeListener[] = [];

  /*
   * 节点列表/选中变化通知(主页节点卡等依赖方订阅)
   */
  export function onChanged(cb: NodeListener): void {
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

  export function list(context: common.Context): VlessNode[] {
    const raw = pref(context).getSync(KEY_LIST, '[]') as string;
    try {
      return JSON.parse(raw) as VlessNode[];
    } catch {
      return [];
    }
  }

  export function selected(context: common.Context): VlessNode | null {
    const id = pref(context).getSync(KEY_SELECTED, '') as string;
    if (id.length === 0) {
      return null;
    }
    const nodes = list(context);
    for (const n of nodes) {
      if (n.id === id) {
        return n;
      }
    }
    return null;
  }

  export function select(context: common.Context, id: string): void {
    const p = pref(context);
    p.putSync(KEY_SELECTED, id);
    p.flush();
    notifyChanged();
  }

  /*
   * 导入 vless:// 链接, 返回节点; 重复链接(raw 相同)去重返回已有节点
   */
  export function importLink(context: common.Context, link: string): VlessNode | null {
    const node = VlessParser.parse(link);
    if (node === null) {
      Logger.warn(TAG, 'importLink: parse failed');
      return null;
    }
    const nodes = list(context);
    for (const n of nodes) {
      if (n.raw === node.raw) {
        Logger.info(TAG, `importLink: duplicate, keep existing ${n.name}`);
        return n;
      }
    }
    nodes.push(node);
    save(context, nodes);
    Logger.info(TAG, `importLink: added ${node.name} (${node.address}:${node.port})`);
    notifyChanged();
    return node;
  }

  export function remove(context: common.Context, id: string): void {
    let nodes = list(context);
    nodes = nodes.filter((n: VlessNode) => n.id !== id);
    save(context, nodes);
    if (pref(context).getSync(KEY_SELECTED, '') === id) {
      select(context, '');
    }
    notifyChanged();
  }

  /*
   * 整表替换(用于去重等批量操作), 若当前选中节点被移除则清空选中
   */
  export function replaceAll(context: common.Context, nodes: VlessNode[]): void {
    save(context, nodes);
    const sel = pref(context).getSync(KEY_SELECTED, '') as string;
    if (sel.length > 0 && !nodes.some((n: VlessNode) => n.id === sel)) {
      pref(context).putSync(KEY_SELECTED, '');
    }
    pref(context).flush();
    notifyChanged();
  }

  export function count(context: common.Context): number {
    return list(context).length;
  }

  function save(context: common.Context, nodes: VlessNode[]): void {
    const p = pref(context);
    p.putSync(KEY_LIST, JSON.stringify(nodes));
    p.flush();
  }
}
