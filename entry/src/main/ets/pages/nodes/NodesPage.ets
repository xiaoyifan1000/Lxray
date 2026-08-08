/*
 * NodesPage.ets - 节点管理页
 * 真实列表(NodeStore)/选择(连接中自动重连应用)/粘贴导入/订阅导入/滑动删除
 */
import { common } from '@kit.AbilityKit';
import { AppTheme } from '../common/Theme';
import { NodeStore } from '../../lib/NodeStore';
import { VlessNode } from '../../lib/parser/VlessParser';
import { Subscription } from '../../lib/Subscription';
import { SubscriptionStore, SubscriptionItem } from '../../lib/SubscriptionStore';
import { NodeServices } from '../../lib/NodeServices';
import { CoreServices } from '../../lib/CoreServices';
import { Assets } from '../../lib/Assets';
import { VpnCoreConfig } from '../../lib/VpnCoreConfig';
import { SettingsStore } from '../../lib/SettingsStore';
import { VpnManager, VpnStatus } from '../../lib/VpnManager';
import { Logger } from '../../lib/Logger';

@Component
export struct NodesPage {
  @State nodes: VlessNode[] = [];
  @State selectedId: string = '';
  @State showAdd: boolean = false;
  @State showSubscribe: boolean = false;
  @State linkInput: string = '';
  @State subInput: string = '';
  @State importMsg: string = '';
  @State subscriptions: SubscriptionItem[] = [];
  @State manageMode: boolean = false;
  @State pendingDelete: string[] = [];
  @State latencyMap: Map<string, number> = new Map<string, number>();

  aboutToAppear(): void {
    this.reload();
    this.reloadSubs();
    NodeStore.onChanged(() => {
      this.reload();
      this.reloadSubs();
    });
  }

  private async pingNode(item: VlessNode): Promise<void> {
    const latency = await NodeServices.ping(item.address, item.port);
    this.latencyMap.set(item.id, latency);
    this.latencyMap = new Map<string, number>(this.latencyMap);
    Logger.info('nodes', `ping ${item.name}: ${latency}ms`);
  }

  private toggleDeleteSelect(id: string): void {
    if (this.pendingDelete.includes(id)) {
      this.pendingDelete = this.pendingDelete.filter((i: string) => i !== id);
    } else {
      const next = this.pendingDelete.slice();
      next.push(id);
      this.pendingDelete = next;
    }
  }

  private startManage(): void {
    this.pendingDelete = [];
    this.manageMode = true;
  }

  private confirmDelete(): void {
    const ctx = this.uiContext();
    const selectedBefore = NodeStore.selected(ctx);
    let removedSelected = false;
    for (const id of this.pendingDelete) {
      if (selectedBefore !== null && selectedBefore.id === id) {
        removedSelected = true;
      }
      NodeStore.remove(ctx, id);
    }
    if (removedSelected && VpnManager.status === VpnStatus.Connected) {
      Logger.warn('nodes', 'deleted the connected node, stopping vpn');
      VpnManager.stop(ctx);
    }
    this.manageMode = false;
    this.pendingDelete = [];
    this.reload();
  }

  private cancelManage(): void {
    this.manageMode = false;
    this.pendingDelete = [];
  }

  /*
   * 删除重复节点: 按 地址+端口+协议 分组, 保留每组第一个(最早导入), 其余删除
   * 返回删除数量
   */
  private dedupeNodes(): number {
    const ctx = this.uiContext();
    const nodes = NodeStore.list(ctx);
    const seen = new Set<string>();
    const keep: VlessNode[] = [];
    let removed = 0;
    for (const n of nodes) {
      const key = `${n.address}:${n.port}:${n.protocol}`;
      if (seen.has(key)) {
        removed++;
        continue;
      }
      seen.add(key);
      keep.push(n);
    }
    if (removed > 0) {
      const sel = NodeStore.selected(ctx);
      NodeStore.replaceAll(ctx, keep);
      if (sel === null && VpnManager.status === VpnStatus.Connected) {
        Logger.warn('nodes', 'dedupe removed the connected node, stopping vpn');
        VpnManager.stop(ctx);
      }
      this.reload();
      Logger.info('nodes', `dedupe: removed ${removed} duplicates, kept ${keep.length}`);
    }
    return removed;
  }

  private uiContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private reload(): void {
    this.nodes = NodeStore.list(this.uiContext());
    const sel = NodeStore.selected(this.uiContext());
    this.selectedId = sel?.id ?? '';
  }

  private selectNode(node: VlessNode): void {
    const ctx = this.uiContext();
    const old = NodeStore.selected(ctx);
    NodeStore.select(ctx, node.id);
    this.selectedId = node.id;
    this.pingNode(node);
    Logger.info('nodes', `switch: ${old?.name ?? '(none)'} -> ${node.name}`);
    this.restartCoreWithNewNode(ctx, node);
    if (VpnManager.status === VpnStatus.Connected) {
      Logger.info('nodes', 'node changed while connected, reconnecting');
      VpnManager.stop(ctx);
      setTimeout(() => {
        VpnManager.start(ctx);
      }, 1200);
    }
  }

  /*
   * 节点切换后重启主进程本地代理核心(其出站跟随选中节点),
   * 供出口检测/订阅代理拉取等本地代理功能使用
   */
  private async restartCoreWithNewNode(ctx: common.Context, node: VlessNode): Promise<void> {
    try {
      const localConfig = `${Assets.assetDir(ctx)}/config_local.json`;
      const opts = SettingsStore.configOptions(ctx);
      const customRules = SettingsStore.customRules(ctx);
      if (!VpnCoreConfig.buildLocalConfig(Assets.configPath(ctx), localConfig, node, opts, customRules)) {
        Logger.error('nodes', 'local config build failed');
        return;
      }
      await CoreServices.stop();
      await CoreServices.start({
        assetLocation: Assets.assetDir(ctx),
        configLocation: localConfig
      });
      Logger.info('nodes', 'main core restarted with new node');
    } catch (e) {
      Logger.error('nodes', `main core restart failed: ${JSON.stringify(e)}`);
    }
  }

  private importLink(): void {
    const ctx = this.uiContext();
    const node = NodeStore.importLink(ctx, this.linkInput);
    this.importMsg = node !== null ? `已添加: ${node.name}` : '链接解析失败';
    if (node !== null) {
      this.linkInput = '';
      this.reload();
    }
  }

  private async fetchSubscription(): Promise<void> {
    this.importMsg = '拉取中…';
    const added = await Subscription.fetchAndImport(this.uiContext(), this.subInput);
    this.importMsg = added >= 0 ? `导入 ${added} 个节点` : '订阅拉取失败';
    if (added >= 0) {
      const ctx = this.uiContext();
      if (SubscriptionStore.add(ctx, this.subInput)) {
        this.subInput = '';
        this.reloadSubs();
      }
      this.reload();
    }
  }

  private reloadSubs(): void {
    this.subscriptions = SubscriptionStore.list(this.uiContext());
  }

  private async updateSub(sub: SubscriptionItem): Promise<void> {
    this.importMsg = `更新 ${sub.url} …`;
    const added = await Subscription.fetchAndImport(this.uiContext(), sub.url);
    this.importMsg = added >= 0 ? `更新完成: ${added} 个节点` : '订阅拉取失败';
    if (added >= 0) {
      SubscriptionStore.touch(this.uiContext(), sub.id);
      this.reloadSubs();
      this.reload();
    }
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text('节点')
            .fontSize(26)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_PRIMARY)
            .layoutWeight(1)
          if (this.manageMode) {
            Text(`删除重复`)
              .fontSize(15)
              .fontColor(AppTheme.WARNING)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor(AppTheme.BG_CARD)
              .borderRadius(AppTheme.RADIUS_SM)
              .onClick(() => {
                const removed = this.dedupeNodes();
                this.manageMode = false;
                this.pendingDelete = [];
                if (removed > 0) {
                  this.importMsg = `已删除 ${removed} 个重复节点`;
                } else {
                  this.importMsg = '没有重复节点';
                }
              })
            Text(`删除 (${this.pendingDelete.length})`)
              .fontSize(15)
              .fontColor(AppTheme.DANGER)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor(AppTheme.BG_CARD)
              .borderRadius(AppTheme.RADIUS_SM)
              .onClick(() => {
                this.confirmDelete();
              })
            Text('确定')
              .fontSize(15)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor(AppTheme.BG_CARD)
              .borderRadius(AppTheme.RADIUS_SM)
              .margin({ left: 10 })
              .onClick(() => {
                this.cancelManage();
              })
          } else {
            Text('管理')
              .fontSize(15)
              .fontColor(AppTheme.WARNING)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor(AppTheme.BG_CARD)
              .borderRadius(AppTheme.RADIUS_SM)
              .onClick(() => {
                this.startManage();
              })
            Text('订阅')
              .fontSize(15)
              .fontColor(AppTheme.ACCENT)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor(AppTheme.BG_CARD)
              .borderRadius(AppTheme.RADIUS_SM)
              .margin({ left: 10 })
              .onClick(() => {
                this.showSubscribe = true;
              })
            Text('+ 添加')
              .fontSize(15)
              .fontColor(AppTheme.ACCENT)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor(AppTheme.BG_CARD)
              .borderRadius(AppTheme.RADIUS_SM)
              .margin({ left: 10 })
              .onClick(() => {
                this.showAdd = true;
              })
          }
        }
        .width('100%')
        .margin({ bottom: AppTheme.SPACE_MD })

        if (this.importMsg.length > 0) {
          Text(this.importMsg)
            .fontSize(12)
            .fontColor(AppTheme.TEXT_SECONDARY)
            .width('100%')
            .margin({ bottom: 8 })
        }

        if (this.nodes.length === 0) {
          Column({ space: 8 }) {
            Text('暂无节点')
              .fontSize(15)
              .fontColor(AppTheme.TEXT_SECONDARY)
            Text('粘贴 vless:// 链接或导入订阅')
              .fontSize(12)
              .fontColor(AppTheme.TEXT_HINT)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: AppTheme.SPACE_MD }) {
            ForEach(this.nodes, (item: VlessNode) => {
              ListItem() {
                this.nodeCard(item)
              }
              .swipeAction({
                end: {
                  builder: () => {
                    this.deleteButton(item);
                  }
                }
              })
            }, (item: VlessNode) => item.id)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: AppTheme.SPACE_LG, right: AppTheme.SPACE_LG, top: AppTheme.SPACE_LG })

      if (this.showAdd) {
        this.overlayMask()
        this.addPanel()
      }
      if (this.showSubscribe) {
        this.overlayMask()
        this.subscribePanel()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG_PAGE)
  }

  @Builder
  private overlayMask() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('#80000000')
      .onClick(() => {
        this.showAdd = false;
        this.showSubscribe = false;
      })
  }

  @Builder
  private nodeCard(item: VlessNode) {
    Row({ space: AppTheme.SPACE_MD }) {
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(item.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_PRIMARY)
          Text(item.protocol === 'vmess' ? 'VMESS' : 'VLESS')
            .fontSize(10)
            .fontColor(item.protocol === 'vmess' ? AppTheme.SUCCESS : AppTheme.ACCENT)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor(item.protocol === 'vmess' ? '#222BD98F' : '#224F7CFF')
            .borderRadius(4)
        }
        Text(`${item.address}:${item.port}`)
          .fontSize(12)
          .fontColor(AppTheme.TEXT_SECONDARY)
        if (this.latencyMap.has(item.id)) {
          Text(this.latencyMap.get(item.id)! >= 0 ? `延迟 ${this.latencyMap.get(item.id)!}ms` : '连接超时')
            .fontSize(11)
            .fontColor(this.latencyMap.get(item.id)! >= 0 && this.latencyMap.get(item.id)! < 200 ?
              AppTheme.SUCCESS : (this.latencyMap.get(item.id)! >= 0 ? AppTheme.WARNING : AppTheme.DANGER))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.manageMode) {
        Text(this.pendingDelete.includes(item.id) ? '✓' : '')
          .fontSize(14)
          .fontColor(AppTheme.DANGER)
          .width(26)
          .height(26)
          .textAlign(TextAlign.Center)
          .borderRadius(13)
          .border({
            width: 2,
            color: this.pendingDelete.includes(item.id) ? AppTheme.DANGER : AppTheme.DIVIDER
          })
      } else if (item.id === this.selectedId) {
        Text('✓')
          .fontSize(18)
          .fontColor(AppTheme.ACCENT)
          .fontWeight(FontWeight.Bold)
      }
    }
    .width('100%')
    .padding(AppTheme.SPACE_MD)
    .backgroundColor(
      this.pendingDelete.includes(item.id) ? '#3326263A' :
        (item.id === this.selectedId ? AppTheme.BG_CARD_HOVER : AppTheme.BG_CARD))
    .borderRadius(AppTheme.RADIUS_MD)
    .border({
      width: 1,
      color: this.pendingDelete.includes(item.id) ? AppTheme.DANGER :
        (item.id === this.selectedId ? AppTheme.ACCENT : AppTheme.DIVIDER)
    })
    .onClick(() => {
      if (this.manageMode) {
        this.toggleDeleteSelect(item.id);
      } else {
        this.selectNode(item);
      }
    })
  }

  @Builder
  private deleteButton(item: VlessNode) {
    Button('删除')
      .type(ButtonType.Normal)
      .backgroundColor(AppTheme.DANGER)
      .fontColor(AppTheme.TEXT_PRIMARY)
      .onClick(() => {
        NodeStore.remove(this.uiContext(), item.id);
        this.reload();
      })
  }

  @Builder
  private addPanel() {
    Column({ space: AppTheme.SPACE_MD }) {
      Row() {
        Text('添加节点')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .layoutWeight(1)
        Text('×')
          .fontSize(20)
          .fontColor(AppTheme.TEXT_HINT)
          .onClick(() => {
            this.showAdd = false;
          })
      }
      .width('100%')
      Text('粘贴 vless:// 分享链接')
        .fontSize(13)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .width('100%')
      TextArea({ placeholder: 'vless://uuid@host:port?...', text: this.linkInput })
        .height(100)
        .fontSize(13)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .backgroundColor(AppTheme.BG_INPUT)
        .borderRadius(AppTheme.RADIUS_SM)
        .onChange((v: string) => {
          this.linkInput = v;
        })
      Button('导入')
        .width('100%')
        .backgroundColor(AppTheme.ACCENT)
        .onClick(() => {
          this.importLink();
        })
    }
    .padding(AppTheme.SPACE_LG)
    .width('86%')
    .backgroundColor(AppTheme.BG_CARD)
    .borderRadius(AppTheme.RADIUS_LG)
  }

  @Builder
  private subscribePanel() {
    Column({ space: AppTheme.SPACE_MD }) {
      Row() {
        Text('订阅管理')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .layoutWeight(1)
        Text('×')
          .fontSize(20)
          .fontColor(AppTheme.TEXT_HINT)
          .onClick(() => {
            this.showSubscribe = false;
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        TextInput({ placeholder: 'https://example.com/sub', text: this.subInput })
          .height(40)
          .fontSize(13)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .backgroundColor(AppTheme.BG_INPUT)
          .borderRadius(AppTheme.RADIUS_SM)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.subInput = v;
          })
        Button('添加')
          .height(40)
          .backgroundColor(AppTheme.ACCENT)
          .onClick(() => {
            this.fetchSubscription();
          })
      }
      .width('100%')

      if (this.subscriptions.length === 0) {
        Text('暂无已保存的订阅')
          .fontSize(12)
          .fontColor(AppTheme.TEXT_HINT)
      } else {
        Column({ space: 6 }) {
          ForEach(this.subscriptions, (sub: SubscriptionItem) => {
            Row() {
              Text(sub.url)
                .fontSize(12)
                .fontColor(AppTheme.TEXT_PRIMARY)
                .layoutWeight(1)
              Text('更新')
                .fontSize(13)
                .fontColor(AppTheme.ACCENT)
                .onClick(() => {
                  this.updateSub(sub);
                })
              Text('×')
                .fontSize(16)
                .fontColor(AppTheme.DANGER)
                .margin({ left: 12 })
                .onClick(() => {
                  SubscriptionStore.remove(this.uiContext(), sub.id);
                  this.reloadSubs();
                })
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor(AppTheme.BG_INPUT)
            .borderRadius(AppTheme.RADIUS_SM)
          }, (sub: SubscriptionItem) => sub.id)
        }
        .width('100%')
      }
    }
    .padding(AppTheme.SPACE_LG)
    .width('86%')
    .backgroundColor(AppTheme.BG_CARD)
    .borderRadius(AppTheme.RADIUS_LG)
  }
}
