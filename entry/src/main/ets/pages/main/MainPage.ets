/*
 * MainPage.ets - 主页面
 * 连接环 -> VpnManager 启停; 流量 -> commonEvent 广播;
 * 节点卡 -> NodeStore 当前选中; 在线时长本地计时
 */
import { common } from '@kit.AbilityKit';
import { AppTheme } from '../common/Theme';
import { VpnManager, VpnStatus } from '../../lib/VpnManager';
import { NodeStore } from '../../lib/NodeStore';
import { NodeServices } from '../../lib/NodeServices';
import { TestServices, IpInfo } from '../../lib/TestServices';
import { VlessNode } from '../../lib/parser/VlessParser';

@Component
export struct MainPage {
  @State upSpeedText: string = '0 B/s';
  @State downSpeedText: string = '0 B/s';
  @State upTotalText: string = '0 B';
  @State downTotalText: string = '0 B';
  @State vpnStatus: VpnStatus = VpnStatus.Disconnected;
  @State nodeName: string = '未选择节点';
  @State nodeAddr: string = '';
  @State nodeLatency: number = -2;
  @State uptime: string = '00:00:00';
  @State hintText: string = '';
  @State exitText: string = '';
  @State exitChecking: boolean = false;
  private connectedAt: number = 0;
  private uptimeTimer: number = -1;
  private trafficTimer: number = -1;

  aboutToAppear(): void {
    this.vpnStatus = VpnManager.status;
    VpnManager.onChanged((s: VpnStatus) => {
      this.vpnStatus = s;
      if (s === VpnStatus.Connected) {
        this.connectedAt = Date.now();
        this.startUptime();
      } else if (s === VpnStatus.Disconnected) {
        this.stopUptime();
        this.uptime = '00:00:00';
        this.upSpeedText = '0 B/s';
        this.downSpeedText = '0 B/s';
        this.upTotalText = '0 B';
        this.downTotalText = '0 B';
      }
    });
    NodeStore.onChanged(() => {
      this.refreshNode();
      this.exitText = '';
      setTimeout(() => {
        this.checkExit();
      }, 3500);
    });
    this.trafficTimer = setInterval(() => {
      const t = VpnManager.lastTraffic;
      this.upSpeedText = `${this.fmt(t.speedUp)}/s`;
      this.downSpeedText = `${this.fmt(t.speedDown)}/s`;
      this.upTotalText = this.fmt(t.totalUp);
      this.downTotalText = this.fmt(t.totalDown);
    }, 500);
    this.refreshNode();
  }

  private uiContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  refreshNode(): void {
    const node: VlessNode | null = NodeStore.selected(this.uiContext());
    if (node !== null) {
      this.nodeName = node.name;
      this.nodeAddr = `${node.address}:${node.port}`;
      this.nodeLatency = -2;
      NodeServices.ping(node.address, node.port).then((lat: number) => {
        this.nodeLatency = lat;
      });
    } else {
      this.nodeName = '未选择节点';
      this.nodeAddr = '';
      this.nodeLatency = -2;
    }
  }

  private startUptime(): void {
    this.stopUptime();
    this.uptimeTimer = setInterval(() => {
      const sec = Math.floor((Date.now() - this.connectedAt) / 1000);
      const h = Math.floor(sec / 3600).toString().padStart(2, '0');
      const m = Math.floor((sec % 3600) / 60).toString().padStart(2, '0');
      const s = (sec % 60).toString().padStart(2, '0');
      this.uptime = `${h}:${m}:${s}`;
    }, 1000);
  }

  private stopUptime(): void {
    if (this.uptimeTimer >= 0) {
      clearInterval(this.uptimeTimer);
      this.uptimeTimer = -1;
    }
  }

  aboutToDisappear(): void {
    this.stopUptime();
    if (this.trafficTimer >= 0) {
      clearInterval(this.trafficTimer);
      this.trafficTimer = -1;
    }
  }

  private fmt(bytes: number): string {
    if (bytes >= 1048576) {
      return `${(bytes / 1048576).toFixed(1)} MB`;
    }
    if (bytes >= 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`;
    }
    return `${bytes} B`;
  }

  private stateColor(): string {
    if (this.vpnStatus === VpnStatus.Connected) {
      return AppTheme.SUCCESS;
    }
    if (this.vpnStatus === VpnStatus.Connecting || this.vpnStatus === VpnStatus.Disconnecting) {
      return AppTheme.WARNING;
    }
    return AppTheme.TEXT_HINT;
  }

  private stateText(): string {
    if (this.vpnStatus === VpnStatus.Connected) {
      return '已连接';
    }
    if (this.vpnStatus === VpnStatus.Connecting) {
      return '连接中…';
    }
    if (this.vpnStatus === VpnStatus.Disconnecting) {
      return '断开中…';
    }
    return '未连接';
  }

  private async checkExit(): Promise<void> {
    if (this.exitChecking) {
      return;
    }
    this.exitChecking = true;
    this.exitText = '检测中…';
    const info: IpInfo | null = await TestServices.checkIp();
    if (info !== null) {
      this.exitText = `出口 ${info.ip} · ${info.location}`;
    } else {
      this.exitText = '出口检测失败（本地代理未就绪？）';
    }
    this.exitChecking = false;
  }

  build() {
    Column({ space: 34 }) {
      Blank()
      this.connectRing()
      if (this.hintText.length > 0) {
        Text(this.hintText)
          .fontSize(13)
          .fontColor(AppTheme.WARNING)
      }
      Row({ space: AppTheme.SPACE_MD }) {
        Column({ space: 4 }) {
          Row({ space: 6 }) {
            Circle().width(8).height(8).fill('#4F7CFF')
            Text('上行').fontSize(13).fontColor(AppTheme.TEXT_SECONDARY)
          }
          Text(this.upSpeedText)
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_PRIMARY)
          Text(`累计 ${this.upTotalText}`)
            .fontSize(12)
            .fontColor(AppTheme.TEXT_HINT)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(AppTheme.SPACE_MD)
        .backgroundColor(AppTheme.BG_CARD)
        .borderRadius(AppTheme.RADIUS_MD)
        .layoutWeight(1)

        Column({ space: 4 }) {
          Row({ space: 6 }) {
            Circle().width(8).height(8).fill('#2BD98F')
            Text('下行').fontSize(13).fontColor(AppTheme.TEXT_SECONDARY)
          }
          Text(this.downSpeedText)
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_PRIMARY)
          Text(`累计 ${this.downTotalText}`)
            .fontSize(12)
            .fontColor(AppTheme.TEXT_HINT)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(AppTheme.SPACE_MD)
        .backgroundColor(AppTheme.BG_CARD)
        .borderRadius(AppTheme.RADIUS_MD)
        .layoutWeight(1)
      }
      .width('100%')
      this.nodeCard()
      this.exitRow()
      Blank().layoutWeight(0.6)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG_PAGE)
    .padding({ left: AppTheme.SPACE_LG, right: AppTheme.SPACE_LG })
  }

  @Builder
  private exitRow() {
    Row() {
      Text(this.exitText.length > 0 ? this.exitText : '出口检测')
        .fontSize(13)
        .fontColor(this.exitText.length > 0 ? AppTheme.TEXT_PRIMARY : AppTheme.ACCENT)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text('检测 ›')
        .fontSize(13)
        .fontColor(AppTheme.ACCENT)
    }
    .width('100%')
    .padding(AppTheme.SPACE_MD)
    .backgroundColor(AppTheme.BG_CARD)
    .borderRadius(AppTheme.RADIUS_MD)
    .onClick(() => {
      this.checkExit();
    })
  }

  @Builder
  private connectRing() {
    Column() {
      Stack() {
        Circle()
          .width(196)
          .height(196)
          .fillOpacity(0)
          .stroke(this.stateColor())
          .strokeWidth(3)
          .opacity(this.vpnStatus === VpnStatus.Disconnected ? 0.35 : 1)
          .animation({ duration: 400, curve: Curve.EaseInOut })
        Column({ space: 6 }) {
          Text(this.stateText())
            .fontSize(24)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_PRIMARY)
          if (this.vpnStatus === VpnStatus.Connected) {
            Text(this.uptime)
              .fontSize(13)
              .fontColor(AppTheme.TEXT_SECONDARY)
          } else {
            Text('轻点连接')
              .fontSize(13)
              .fontColor(AppTheme.TEXT_HINT)
          }
        }
      }
    }
    .width(220)
    .height(220)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      const ctx = this.uiContext();
      if (this.vpnStatus === VpnStatus.Connected) {
        VpnManager.stop(ctx);
      } else if (this.vpnStatus === VpnStatus.Disconnected) {
        if (NodeStore.selected(ctx) === null) {
          this.hintText = '请先到"节点"页添加并选择节点';
          setTimeout(() => {
            this.hintText = '';
          }, 2500);
          return;
        }
        VpnManager.start(ctx);
      }
    })
  }

  @Builder
  private nodeCard() {
    Row() {
      Column({ space: 4 }) {
        Text('当前节点')
          .fontSize(12)
          .fontColor(AppTheme.TEXT_HINT)
        Text(this.nodeName)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
        if (this.nodeAddr.length > 0) {
          Text(this.nodeAddr)
            .fontSize(12)
            .fontColor(AppTheme.TEXT_SECONDARY)
        }
        if (this.nodeLatency === -2) {
          Text('延迟测试中…')
            .fontSize(11)
            .fontColor(AppTheme.TEXT_HINT)
        } else if (this.nodeLatency >= 0) {
          Text(`延迟 ${this.nodeLatency}ms`)
            .fontSize(11)
            .fontColor(this.nodeLatency < 200 ? AppTheme.SUCCESS : AppTheme.WARNING)
        } else {
          Text('连接超时')
            .fontSize(11)
            .fontColor(AppTheme.DANGER)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(AppTheme.SPACE_MD)
    .backgroundColor(AppTheme.BG_CARD)
    .borderRadius(AppTheme.RADIUS_MD)
    .onClick(() => {
      this.refreshNode();
    })
  }
}
