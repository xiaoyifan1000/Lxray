/*
 * SettingsPage.ets - 设置与日志页
 * 网络分组已接真实设置(SettingsStore), 改动下次 VPN 连接生效
 */
import { common } from '@kit.AbilityKit';
import { connection } from '@kit.NetworkKit';
import { AppTheme, levelColor } from '../common/Theme';
import { DebugServices, LogEntry } from '../../lib/DebugServices';
import { Subscription } from '../../lib/Subscription';
import { SubscriptionStore, SubscriptionItem } from '../../lib/SubscriptionStore';
import { RuleParser } from '../../lib/RuleParser';
import {
  SettingsStore, ROUTE_GLOBAL, ROUTE_BYPASS_MAINLAND,
  DS_ASIS, DS_IF_NON_MATCH, DS_ON_DEMAND,
  DEFAULT_DNS_CN, DEFAULT_DNS_FOREIGN
} from '../../lib/SettingsStore';

interface LogLine {
  level: number;
  time: string;
  module: string;
  message: string;
}

@Component
export struct SettingsPage {
  @State logs: LogLine[] = [];
  @State routeMode: string = ROUTE_BYPASS_MAINLAND;
  @State domainStrategy: string = DS_ASIS;
  @State sniffing: boolean = true;
  @State sniffingRouteOnly: boolean = false;
  @State localDns: boolean = true;
  @State ipv6: boolean = true;
  @State lanShare: boolean = false;
  @State autoUpdateSub: boolean = true;
  @State autoReconnect: boolean = true;
  @State subscriptions: SubscriptionItem[] = [];
  @State showSubPanel: boolean = false;
  @State subInput: string = '';
  @State subMsg: string = '';
  @State showRoutePanel: boolean = false;
  @State showRulesPanel: boolean = false;
  @State customRulesText: string = '';
  @State rulesMsg: string = '';
  @State customRuleCount: number = 0;
  @State logFilterErrorOnly: boolean = true;
  private logTimer: number = -1;
  @State showProxyPanel: boolean = false;
  @State lanIp: string = '';
  @State sysProxyText: string = '正常';
  @State sysProxyWarn: boolean = false;
  @State showDnsPanel: boolean = false;
  @State dnsCnInput: string = '';
  @State dnsForeignInput: string = '';
  @State dnsMsg: string = '';
  @State dnsCn: string = DEFAULT_DNS_CN;
  @State dnsForeign: string = DEFAULT_DNS_FOREIGN;

  aboutToAppear(): void {
    const ctx = this.uiContext();
    this.routeMode = SettingsStore.routeMode(ctx);
    this.domainStrategy = SettingsStore.domainStrategy(ctx);
    this.sniffing = SettingsStore.sniffing(ctx);
    this.sniffingRouteOnly = SettingsStore.sniffingRouteOnly(ctx);
    this.localDns = SettingsStore.localDns(ctx);
    this.ipv6 = SettingsStore.ipv6(ctx);
    this.lanShare = SettingsStore.lanShare(ctx);
    this.autoUpdateSub = SettingsStore.autoUpdateSub(ctx);
    this.autoReconnect = SettingsStore.autoReconnect(ctx);
    this.dnsCn = SettingsStore.dnsCn(ctx);
    this.dnsForeign = SettingsStore.dnsForeign(ctx);
    this.customRuleCount = SettingsStore.customRules(ctx).length;
    this.logFilterErrorOnly = SettingsStore.logErrorOnly(ctx);
    this.subscriptions = SubscriptionStore.list(ctx);
    this.refreshLogs();
    this.resolveLanIp();
    this.checkSysProxy();
    this.logTimer = setInterval(() => {
      this.refreshLogs();
    }, 5000);
    SubscriptionStore.onChanged(() => {
      this.subscriptions = SubscriptionStore.list(this.uiContext());
    });
  }

  aboutToDisappear(): void {
    if (this.logTimer >= 0) {
      clearInterval(this.logTimer);
      this.logTimer = -1;
    }
  }

  private async resolveLanIp(): Promise<void> {
    try {
      const netHandle = await connection.getDefaultNet();
      const props = await connection.getConnectionProperties(netHandle);
      for (const la of props.linkAddresses) {
        if (la.address.family === 1 && !la.address.address.startsWith('127.')) {
          this.lanIp = la.address.address;
          break;
        }
      }
    } catch {
    }
  }

  private async checkSysProxy(): Promise<void> {
    try {
      const proxy = await connection.getDefaultHttpProxy();
      if (proxy === null || proxy === undefined || proxy.host === undefined || proxy.host.length === 0) {
        this.sysProxyText = '正常';
        this.sysProxyWarn = false;
        return;
      }
      const addr = `${proxy.host}:${proxy.port}`;
      if (proxy.host === '127.0.0.1' && (proxy.port === 10808 || proxy.port === 10809)) {
        this.sysProxyText = `已指向本代理 ${addr}，其他应用也会走`;
        this.sysProxyWarn = true;
      } else {
        this.sysProxyText = `已设置 ${addr}`;
        this.sysProxyWarn = false;
      }
    } catch {
      this.sysProxyText = '读取失败';
      this.sysProxyWarn = false;
    }
  }

  private async refreshLogs(): Promise<void> {
    try {
      const entries = await DebugServices.recentLogs(100);
      this.logs = entries.filter((e: LogEntry) => {
        if (this.logFilterErrorOnly && e.level < 5) {
          return false;
        }
        return true;
      }).map((e: LogEntry): LogLine => {
        return {
          level: e.level,
          time: e.time.length >= 19 ? e.time.substring(11, 19) : e.time,
          module: e.module,
          message: e.message
        };
      });
    } catch (e) {
    }
  }

  private uiContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private levelName(level: number): string {
    const names: string[] = ['?', '?', '?', 'D', 'I', 'W', 'E', 'F'];
    return names[level] ?? '?';
  }

  private routeModeText(): string {
    if (this.routeMode === ROUTE_GLOBAL) {
      return '默认全局';
    }
    return '默认禁用全局';
  }

  private cycleRouteMode(): void {
    const ctx = this.uiContext();
    if (this.routeMode === ROUTE_GLOBAL) {
      this.routeMode = ROUTE_BYPASS_MAINLAND;
    } else {
      this.routeMode = ROUTE_GLOBAL;
    }
    SettingsStore.setRouteMode(ctx, this.routeMode);
  }

  private pickRouteMode(mode: string): void {
    this.routeMode = mode;
    SettingsStore.setRouteMode(this.uiContext(), mode);
    this.showRoutePanel = false;
  }

  private cycleDomainStrategy(): void {
    const ctx = this.uiContext();
    if (this.domainStrategy === DS_ASIS) {
      this.domainStrategy = DS_IF_NON_MATCH;
    } else if (this.domainStrategy === DS_IF_NON_MATCH) {
      this.domainStrategy = DS_ON_DEMAND;
    } else {
      this.domainStrategy = DS_ASIS;
    }
    SettingsStore.setDomainStrategy(ctx, this.domainStrategy);
  }

  build() {
    Stack() {
      Column() {
        Text('设置')
          .fontSize(26)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .width('100%')
          .margin({ bottom: AppTheme.SPACE_MD })

        List({ space: 26 }) {
        ListItemGroup({ header: this.groupHeader('连接') }) {
          ListItem() {
            this.settingToggle('断线自动重连', this.autoReconnect, (v: boolean) => {
              this.autoReconnect = v;
              SettingsStore.setAutoReconnect(this.uiContext(), v);
            })
          }
        }

        ListItemGroup({ header: this.groupHeader('网络 · 重连后生效') }) {
          ListItem() {
            this.settingRowAction('路由设置', this.routeModeText(), () => {
              this.showRoutePanel = true;
            })
          }
          ListItem() {
            this.settingRowAction('域名策略', this.domainStrategy, () => {
              this.cycleDomainStrategy();
            })
          }
          ListItem() {
            this.settingToggle('流量探测', this.sniffing, (v: boolean) => {
              this.sniffing = v;
              SettingsStore.setSniffing(this.uiContext(), v);
            })
          }
          ListItem() {
            this.settingToggle('探测域名仅用于路由 (routeOnly)', this.sniffingRouteOnly, (v: boolean) => {
              this.sniffingRouteOnly = v;
              SettingsStore.setSniffingRouteOnly(this.uiContext(), v);
            })
          }
          ListItem() {
            this.settingToggle('本地 DNS (53 拦截进内核)', this.localDns, (v: boolean) => {
              this.localDns = v;
              SettingsStore.setLocalDns(this.uiContext(), v);
            })
          }
          ListItem() {
            this.settingRowAction('DNS 服务器', `${this.dnsCn} · ${this.dnsForeign}`, () => {
              this.dnsCnInput = this.dnsCn;
              this.dnsForeignInput = this.dnsForeign;
              this.dnsMsg = '';
              this.showDnsPanel = true;
            })
          }
          ListItem() {
            this.settingToggle('允许 IPv6', this.ipv6, (v: boolean) => {
              this.ipv6 = v;
              SettingsStore.setIpv6(this.uiContext(), v);
            })
          }
        }

        ListItemGroup({ header: this.groupHeader('本地代理服务') }) {
          ListItem() {
            this.settingRowAction('代理地址', '查看', () => {
              this.showProxyPanel = true;
              this.checkSysProxy();
            })
          }
          ListItem() {
            Row() {
              Text('系统代理状态')
                .fontSize(15)
                .fontColor(AppTheme.TEXT_PRIMARY)
                .layoutWeight(1)
              Text(this.sysProxyText)
                .fontSize(13)
                .fontColor(this.sysProxyWarn ? AppTheme.WARNING : AppTheme.TEXT_SECONDARY)
            }
            .width('100%')
            .padding(AppTheme.SPACE_MD)
            .backgroundColor(this.sysProxyWarn ? '#22F5B94F' : AppTheme.BG_CARD)
            .borderRadius(AppTheme.RADIUS_MD)
            .onClick(() => {
              this.checkSysProxy();
            })
          }
          ListItem() {
            this.settingToggle('局域网共享 (0.0.0.0:10810/10811)', this.lanShare, (v: boolean) => {
              this.lanShare = v;
              SettingsStore.setLanShare(this.uiContext(), v);
            })
          }
        }

        ListItemGroup({ header: this.groupHeader('订阅') }) {
          ListItem() {
            Row() {
              Text('订阅设置')
                .fontSize(15)
                .fontColor(AppTheme.TEXT_PRIMARY)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${this.subscriptions.length} 个订阅`)
                .fontSize(13)
                .fontColor(AppTheme.ACCENT)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ left: 12 })
                .layoutWeight(1)
                .textAlign(TextAlign.End)
            }
            .width('100%')
            .padding(AppTheme.SPACE_MD)
            .backgroundColor(AppTheme.BG_CARD)
            .borderRadius(AppTheme.RADIUS_MD)
            .onClick(() => {
              this.showSubPanel = true;
            })
          }
          ListItem() {
            this.settingToggle('自动更新 (每 24 小时)', this.autoUpdateSub, (v: boolean) => {
              this.autoUpdateSub = v;
              SettingsStore.setAutoUpdateSub(this.uiContext(), v);
            })
          }
        }

        ListItemGroup({ header: this.groupHeader('运行日志 · 主进程') }) {
          ListItem() {
            Row() {
              Text('仅显示错误/警告')
                .fontSize(14)
                .fontColor(AppTheme.TEXT_PRIMARY)
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.logFilterErrorOnly })
                .selectedColor(AppTheme.ACCENT)
                .onChange((v: boolean) => {
                  this.logFilterErrorOnly = v;
                  SettingsStore.setLogErrorOnly(this.uiContext(), v);
                  this.refreshLogs();
                })
            }
            .width('100%')
            .padding(AppTheme.SPACE_MD)
            .backgroundColor(AppTheme.BG_CARD)
            .borderRadius(AppTheme.RADIUS_MD)
          }
          ListItem() {
            Column() {
              if (this.logs.length === 0) {
                Text('暂无日志')
                  .fontSize(12)
                  .fontColor(AppTheme.TEXT_HINT)
              }
              Scroll() {
                Column({ space: 2 }) {
                  ForEach(this.logs, (line: LogLine) => {
                    Row({ space: 6 }) {
                      Text(this.levelName(line.level))
                        .fontSize(11)
                        .fontFamily('monospace')
                        .fontColor(levelColor(line.level))
                      Text(line.time)
                        .fontSize(11)
                        .fontFamily('monospace')
                        .fontColor(AppTheme.TEXT_HINT)
                      Text(`[${line.module}]`)
                        .fontSize(11)
                        .fontFamily('monospace')
                        .fontColor(AppTheme.ACCENT)
                      Text(line.message)
                        .fontSize(11)
                        .fontFamily('monospace')
                        .fontColor(AppTheme.TEXT_SECONDARY)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                    }
                    .width('100%')
                  }, (line: LogLine) => line.time + line.module + line.message)
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .height(180)
              .scrollBar(BarState.Auto)
              .scrollable(ScrollDirection.Vertical)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .justifyContent(FlexAlign.Start)
            .padding(AppTheme.SPACE_MD)
            .backgroundColor(AppTheme.BG_INPUT)
            .borderRadius(AppTheme.RADIUS_MD)
          }
          ListItem() {
            this.settingRowAction('刷新日志', `${this.logs.length} 条`, () => {
              this.refreshLogs();
            })
          }
        }

        ListItemGroup({ header: this.groupHeader('关于') }) {
          ListItem() {
            this.settingRow('核心版本', 'Xray 26.3.27')
          }
          ListItem() {
            this.settingRow('框架版本', '1.0.0')
          }
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .padding({ left: AppTheme.SPACE_LG, right: AppTheme.SPACE_LG, top: AppTheme.SPACE_LG })

      if (this.showSubPanel) {
        this.overlayMask()
        this.subPanel()
      }
      if (this.showRoutePanel) {
        this.overlayMask()
        this.routePanel()
      }
      if (this.showProxyPanel) {
        this.overlayMask()
        this.proxyPanel()
      }
      if (this.showDnsPanel) {
        this.overlayMask()
        this.dnsPanel()
      }
      if (this.showRulesPanel) {
        this.overlayMask()
        this.rulesPanel()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG_PAGE)
  }

  private saveDns(): void {
    const ctx = this.uiContext();
    this.dnsCn = this.dnsCnInput.trim().length > 0 ? this.dnsCnInput.trim() : DEFAULT_DNS_CN;
    this.dnsForeign = this.dnsForeignInput.trim().length > 0 ? this.dnsForeignInput.trim() : DEFAULT_DNS_FOREIGN;
    SettingsStore.setDnsCn(ctx, this.dnsCn);
    SettingsStore.setDnsForeign(ctx, this.dnsForeign);
    this.dnsMsg = '已保存，重连 VPN 后生效';
  }

  private resetDns(): void {
    this.dnsCnInput = DEFAULT_DNS_CN;
    this.dnsForeignInput = DEFAULT_DNS_FOREIGN;
    this.dnsMsg = '';
  }

  @Builder
  private dnsPanel() {
    Column({ space: AppTheme.SPACE_MD }) {
      Row() {
        Text('DNS 服务器')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .layoutWeight(1)
        Text('×')
          .fontSize(20)
          .fontColor(AppTheme.TEXT_HINT)
          .onClick(() => {
            this.showDnsPanel = false;
          })
      }
      .width('100%')

      Text('国内 DNS (geosite:cn 域名)')
        .fontSize(12)
        .fontColor(AppTheme.TEXT_HINT)
        .width('100%')
      TextInput({ placeholder: DEFAULT_DNS_CN, text: this.dnsCnInput })
        .height(40)
        .fontSize(13)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .backgroundColor(AppTheme.BG_INPUT)
        .borderRadius(AppTheme.RADIUS_SM)
        .onChange((v: string) => {
          this.dnsCnInput = v;
        })

      Text('国外 DNS (DoH, 经代理)')
        .fontSize(12)
        .fontColor(AppTheme.TEXT_HINT)
        .width('100%')
      TextInput({ placeholder: DEFAULT_DNS_FOREIGN, text: this.dnsForeignInput })
        .height(40)
        .fontSize(13)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .backgroundColor(AppTheme.BG_INPUT)
        .borderRadius(AppTheme.RADIUS_SM)
        .onChange((v: string) => {
          this.dnsForeignInput = v;
        })

      if (this.dnsMsg.length > 0) {
        Text(this.dnsMsg)
          .fontSize(12)
          .fontColor(AppTheme.SUCCESS)
          .width('100%')
      }

      Row({ space: AppTheme.SPACE_MD }) {
        Button('还原默认')
          .layoutWeight(1)
          .backgroundColor(AppTheme.BG_INPUT)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .onClick(() => {
            this.resetDns();
          })
        Button('保存')
          .layoutWeight(1)
          .backgroundColor(AppTheme.ACCENT)
          .onClick(() => {
            this.saveDns();
          })
      }
      .width('100%')

      Text('修改后重连 VPN 生效')
        .fontSize(11)
        .fontColor(AppTheme.TEXT_HINT)
        .width('100%')
    }
    .padding(AppTheme.SPACE_LG)
    .width('86%')
    .backgroundColor(AppTheme.BG_CARD)
    .borderRadius(AppTheme.RADIUS_LG)
  }

  @Builder
  private proxyPanel() {
    Column({ space: AppTheme.SPACE_MD }) {
      Row() {
        Text('本地代理地址')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .layoutWeight(1)
        Text('×')
          .fontSize(20)
          .fontColor(AppTheme.TEXT_HINT)
          .onClick(() => {
            this.showProxyPanel = false;
          })
      }
      .width('100%')

      this.proxyAddr('本机 SOCKS', '127.0.0.1:10808')
      this.proxyAddr('本机 HTTP', '127.0.0.1:10809')
      if (this.lanIp.length > 0) {
        this.proxyAddr('局域网 SOCKS (需开启共享)', `${this.lanIp}:10810`)
        this.proxyAddr('局域网 HTTP (需开启共享)', `${this.lanIp}:10811`)
      } else {
        this.proxyAddr('局域网 (需开启共享)', '未获取到局域网 IP')
      }

      Row() {
        Text('系统代理')
          .fontSize(13)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .layoutWeight(1)
        Text(this.sysProxyText)
          .fontSize(13)
          .fontColor(this.sysProxyText.includes('⚠️') ? AppTheme.WARNING : AppTheme.TEXT_PRIMARY)
      }
      .width('100%')
      .padding(AppTheme.SPACE_MD)
      .backgroundColor(AppTheme.BG_INPUT)
      .borderRadius(AppTheme.RADIUS_SM)

      Text('其他应用在系统代理设置中手动填入以上地址即可使用本代理，'
        .concat('未配置的应用不受影响；不要与本应用的 VPN 同时使用'))
        .fontSize(11)
        .fontColor(AppTheme.TEXT_HINT)
        .width('100%')
    }
    .padding(AppTheme.SPACE_LG)
    .width('86%')
    .backgroundColor(AppTheme.BG_CARD)
    .borderRadius(AppTheme.RADIUS_LG)
  }

  @Builder
  private proxyAddr(title: string, addr: string) {
    Row() {
      Text(title)
        .fontSize(13)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .layoutWeight(1)
      Text(addr)
        .fontSize(13)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .fontFamily('monospace')
    }
    .width('100%')
    .padding(AppTheme.SPACE_MD)
    .backgroundColor(AppTheme.BG_INPUT)
    .borderRadius(AppTheme.RADIUS_SM)
  }

  @Builder
  private routePanel() {
    Column({ space: AppTheme.SPACE_MD }) {
      Row() {
        Text('路由设置')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .layoutWeight(1)
        Text('×')
          .fontSize(20)
          .fontColor(AppTheme.TEXT_HINT)
          .onClick(() => {
            this.showRoutePanel = false;
          })
      }
      .width('100%')

      this.routeOption(ROUTE_GLOBAL, '默认全局', '所有流量走代理节点')
      this.routeOption(ROUTE_BYPASS_MAINLAND, '默认禁用全局', '国内直连，国外走代理（智能分流）')

      Row() {
        Text('自定义规则')
          .fontSize(15)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .layoutWeight(1)
        Text(this.customRuleCount > 0 ? `${this.customRuleCount} 条 ›` : '添加 ›')
          .fontSize(13)
          .fontColor(AppTheme.ACCENT)
      }
      .width('100%')
      .padding(AppTheme.SPACE_MD)
      .backgroundColor(AppTheme.BG_INPUT)
      .borderRadius(AppTheme.RADIUS_MD)
      .onClick(() => {
        this.customRulesText = SettingsStore.customRules(this.uiContext()).join('\n');
        this.rulesMsg = '';
        this.showRoutePanel = false;
        this.showRulesPanel = true;
      })

      Text('自定义规则优先于内置规则，修改后需重连 VPN 生效')
        .fontSize(11)
        .fontColor(AppTheme.TEXT_HINT)
        .width('100%')
    }
    .padding(AppTheme.SPACE_LG)
    .width('86%')
    .backgroundColor(AppTheme.BG_CARD)
    .borderRadius(AppTheme.RADIUS_LG)
  }

  private saveCustomRules(): void {
    const ctx = this.uiContext();
    const lines: string[] = [];
    let invalid = 0;
    for (const raw of this.customRulesText.split('\n')) {
      const line = raw.trim();
      if (line.length === 0) {
        continue;
      }
      const parsed = RuleParser.parse(line);
      if (parsed.ok) {
        lines.push(line);
      } else {
        invalid++;
      }
    }
    SettingsStore.setCustomRules(ctx, lines);
    this.customRuleCount = lines.length;
    this.rulesMsg = invalid > 0 ? `已保存 ${lines.length} 条，忽略 ${invalid} 条无效` : `已保存 ${lines.length} 条`;
  }

  @Builder
  private rulesPanel() {
    Column({ space: AppTheme.SPACE_MD }) {
      Row() {
        Text('自定义规则')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .layoutWeight(1)
        Text('×')
          .fontSize(20)
          .fontColor(AppTheme.TEXT_HINT)
          .onClick(() => {
            this.showRulesPanel = false;
          })
      }
      .width('100%')

      Text('格式：条件1,条件2 -> 出站标签（direct/proxy/block）\n'
        .concat('支持 domain: geosite: ip: geoip: port: network: source: 前缀；或直接粘贴 xray JSON 规则'))
        .fontSize(11)
        .fontColor(AppTheme.TEXT_HINT)
        .width('100%')

      TextArea({ placeholder: 'geosite:category-ads-all -> block\ndomain:example.com -> direct', text: this.customRulesText })
        .height(180)
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor(AppTheme.TEXT_PRIMARY)
        .backgroundColor(AppTheme.BG_INPUT)
        .borderRadius(AppTheme.RADIUS_SM)
        .onChange((v: string) => {
          this.customRulesText = v;
        })

      if (this.rulesMsg.length > 0) {
        Text(this.rulesMsg)
          .fontSize(12)
          .fontColor(AppTheme.SUCCESS)
          .width('100%')
      }

      Row({ space: AppTheme.SPACE_MD }) {
        Button('清空')
          .layoutWeight(1)
          .backgroundColor(AppTheme.BG_INPUT)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .onClick(() => {
            this.customRulesText = '';
            SettingsStore.setCustomRules(this.uiContext(), []);
            this.customRuleCount = 0;
            this.rulesMsg = '已清空';
          })
        Button('保存')
          .layoutWeight(1)
          .backgroundColor(AppTheme.ACCENT)
          .onClick(() => {
            this.saveCustomRules();
          })
      }
      .width('100%')

      Text('保存后重连 VPN 生效')
        .fontSize(11)
        .fontColor(AppTheme.TEXT_HINT)
        .width('100%')
    }
    .padding(AppTheme.SPACE_LG)
    .width('86%')
    .backgroundColor(AppTheme.BG_CARD)
    .borderRadius(AppTheme.RADIUS_LG)
  }

  @Builder
  private routeOption(mode: string, title: string, desc: string) {
    Row() {
      Column({ space: 3 }) {
        Text(title)
          .fontSize(15)
          .fontColor(AppTheme.TEXT_PRIMARY)
        Text(desc)
          .fontSize(11)
          .fontColor(AppTheme.TEXT_HINT)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Radio({ value: '', group: 'routeSelect' })
        .checked(this.routeMode === mode)
        .radioStyle({ checkedBackgroundColor: AppTheme.ACCENT })
    }
    .width('100%')
    .padding(AppTheme.SPACE_MD)
    .backgroundColor(this.routeMode === mode ? AppTheme.BG_CARD_HOVER : AppTheme.BG_INPUT)
    .borderRadius(AppTheme.RADIUS_MD)
    .border({
      width: 1,
      color: this.routeMode === mode ? AppTheme.ACCENT : AppTheme.DIVIDER
    })
    .onClick(() => {
      this.pickRouteMode(mode);
    })
  }

  @Builder
  private subPanel() {
    Column({ space: AppTheme.SPACE_MD }) {
      Row() {
        Text('订阅设置')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .layoutWeight(1)
        Text('×')
          .fontSize(20)
          .fontColor(AppTheme.TEXT_HINT)
          .onClick(() => {
            this.showSubPanel = false;
          })
      }
      .width('100%')

      if (this.subMsg.length > 0) {
        Text(this.subMsg)
          .fontSize(12)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .width('100%')
      }

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
            this.addSubscription();
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
                  this.updateSubscription(sub);
                })
              Text('×')
                .fontSize(16)
                .fontColor(AppTheme.DANGER)
                .margin({ left: 12 })
                .onClick(() => {
                  SubscriptionStore.remove(this.uiContext(), sub.id);
                  this.subscriptions = SubscriptionStore.list(this.uiContext());
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

  private async addSubscription(): Promise<void> {
    const ctx = this.uiContext();
    const url = this.subInput.trim();
    if (url.length === 0) {
      return;
    }
    this.subMsg = '拉取中…';
    const added = await Subscription.fetchAndImport(ctx, url);
    if (added < 0) {
      this.subMsg = '订阅拉取失败';
      return;
    }
    if (!SubscriptionStore.add(ctx, url)) {
      this.subMsg = '订阅已存在';
    } else {
      this.subMsg = `导入 ${added} 个节点`;
    }
    this.subInput = '';
    this.subscriptions = SubscriptionStore.list(ctx);
  }

  private async updateSubscription(sub: SubscriptionItem): Promise<void> {
    this.subMsg = '更新中…';
    const added = await Subscription.fetchAndImport(this.uiContext(), sub.url);
    this.subMsg = added >= 0 ? `更新完成: ${added} 个节点` : '订阅拉取失败';
    if (added >= 0) {
      SubscriptionStore.touch(this.uiContext(), sub.id);
      this.subscriptions = SubscriptionStore.list(this.uiContext());
    }
  }

  @Builder
  private overlayMask() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('#80000000')
      .onClick(() => {
        this.showSubPanel = false;
        this.showRoutePanel = false;
        this.showProxyPanel = false;
        this.showDnsPanel = false;
        this.showRulesPanel = false;
      })
  }

  @Builder
  private groupHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(AppTheme.TEXT_HINT)
      .margin({ bottom: 6 })
  }

  @Builder
  private groupFooter(text: string) {
    Text(text)
      .fontSize(11)
      .fontColor(AppTheme.TEXT_HINT)
      .margin({ top: 6 })
  }

  @Builder
  private settingRow(title: string, value: string) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(value)
        .fontSize(13)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .wordBreak(WordBreak.BREAK_ALL)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .margin({ left: 12 })
        .layoutWeight(1)
    }
    .width('100%')
    .padding(AppTheme.SPACE_MD)
    .backgroundColor(AppTheme.BG_CARD)
    .borderRadius(AppTheme.RADIUS_MD)
  }

  @Builder
  private settingRowAction(title: string, value: string, action: () => void) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(value)
        .fontSize(13)
        .fontColor(AppTheme.ACCENT)
        .wordBreak(WordBreak.BREAK_ALL)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .margin({ left: 12 })
        .layoutWeight(1)
    }
    .width('100%')
    .padding(AppTheme.SPACE_MD)
    .backgroundColor(AppTheme.BG_CARD)
    .borderRadius(AppTheme.RADIUS_MD)
    .onClick(action)
  }

  @Builder
  private settingToggle(title: string, value: boolean, onChange: (v: boolean) => void) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(AppTheme.ACCENT)
        .onChange(onChange)
    }
    .width('100%')
    .padding(AppTheme.SPACE_MD)
    .backgroundColor(AppTheme.BG_CARD)
    .borderRadius(AppTheme.RADIUS_MD)
  }
}
