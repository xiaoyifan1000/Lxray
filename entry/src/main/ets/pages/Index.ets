/*
 * Index.ets - 应用主框架: 顶部标题 + 内容区 + 底部导航
 * 视觉稿阶段: 页面均为 mock 数据, 未接功能
 */
import { AppTheme } from './common/Theme';
import { MainPage } from './main/MainPage';
import { NodesPage } from './nodes/NodesPage';
import { SettingsPage } from './settings/SettingsPage';
import { VpnManager, VpnStatus } from '../lib/VpnManager';

@Entry
@Component
struct Index {
  @State currentTab: number = 0;
  @State vpnStatus: VpnStatus = VpnStatus.Disconnected;

  aboutToAppear(): void {
    this.vpnStatus = VpnManager.status;
    VpnManager.onChanged((s: VpnStatus) => {
      this.vpnStatus = s;
    });
  }

  private statusColor(): string {
    if (this.vpnStatus === VpnStatus.Connected) {
      return AppTheme.SUCCESS;
    }
    if (this.vpnStatus === VpnStatus.Connecting || this.vpnStatus === VpnStatus.Disconnecting) {
      return AppTheme.WARNING;
    }
    return AppTheme.TEXT_HINT;
  }

  private statusText(): string {
    if (this.vpnStatus === VpnStatus.Connected) {
      return '已连接';
    }
    if (this.vpnStatus === VpnStatus.Connecting) {
      return '连接中';
    }
    if (this.vpnStatus === VpnStatus.Disconnecting) {
      return '断开中';
    }
    return '未连接';
  }

  build() {
    Column() {
      Row() {
        Text('Lxray')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
        Blank()
        Row({ space: 6 }) {
          Circle()
            .width(8)
            .height(8)
            .fill(this.statusColor())
            .animation({ duration: 300, curve: Curve.EaseInOut })
          Text(this.statusText())
            .fontSize(12)
            .fontColor(AppTheme.TEXT_SECONDARY)
        }
      }
      .width('100%')
      .padding({ left: AppTheme.SPACE_LG, right: AppTheme.SPACE_LG, top: 14, bottom: 10 })

      Tabs({ barPosition: BarPosition.End, index: this.currentTab }) {
        TabContent() { MainPage() }
        TabContent() { NodesPage() }
        TabContent() { SettingsPage() }
      }
      .layoutWeight(1)
      .scrollable(false)
      .barHeight(0)
      .onChange((idx: number) => {
        this.currentTab = idx;
      })

      Row() {
        this.tabItem(0, '连接', $r('app.media.link_solid'))
        this.tabItemText(1, '节点', '▤')
        this.tabItem(2, '设置', $r('app.media.cogs_solid'))
      }
      .width('100%')
      .height(58)
      .backgroundColor(AppTheme.BG_CARD)
      .border({ width: { top: 1 }, color: AppTheme.DIVIDER })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG_PAGE)
  }

  @Builder
  private tabItemText(idx: number, label: string, glyph: string) {
    Column({ space: 2 }) {
      Text(glyph)
        .fontSize(18)
        .fontColor(this.currentTab === idx ? AppTheme.ACCENT : AppTheme.TEXT_HINT)
      Text(label)
        .fontSize(11)
        .fontColor(this.currentTab === idx ? AppTheme.ACCENT : AppTheme.TEXT_HINT)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.currentTab = idx;
    })
  }

  @Builder
  private tabItem(idx: number, label: string, icon: Resource) {
    Column({ space: 2 }) {
      Image(icon)
        .width(20)
        .height(20)
        .fillColor(this.currentTab === idx ? AppTheme.ACCENT : AppTheme.TEXT_HINT)
      Text(label)
        .fontSize(11)
        .fontColor(this.currentTab === idx ? AppTheme.ACCENT : AppTheme.TEXT_HINT)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.currentTab = idx;
    })
  }
}
