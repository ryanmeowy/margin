# 01 · 原型规格审计（CoRouter 菜单栏用量 App）

## 0. 审计基线

| 项 | 值 |
|---|---|
| 原型路径 | /Users/ryan/Downloads/index.html |
| 只读副本 | opendesign-usage/fixtures/prototype.html |
| 两份文件一致性 | sha256 相同：037fbb2b4752b684a820ff1b647beb45aa61b85eb0c52f5ced05fa9f7aa7ada6 |
| 总行数 | 2859（style 7–1445，body 1447–2022，script 2024–2857） |
| 语言/主题 | html[lang=zh-CN][data-theme=light]（JS 启动后按系统/偏好覆写） |
| 文档性质 | 描述「原型已实现的行为」，不是「应该实现的行为」；需要改造的部分集中在 §7 / §8 |
| 行号引用 | 正文中的 L#### 均指副本行号 |

原型是一个 1:1 的 macOS 桌面模拟页（壁纸 + 假菜单栏 + 假窗口层），App 本体只占三块：状态项、弹出面板、设置窗口。§7 把这些模拟层逐项拆掉。

---

## 1. 界面清单与层级

### 1.1 顶层结构树

~~~
body
└─ div.stage                                   position:fixed; inset:0; overflow:hidden
   ├─ div.wallpaper[aria-hidden]               L184  壁纸（三层渐变 + 噪点，纯装饰）
   ├─ header.menubar                            L213  z-index 55，高 30px（假系统菜单栏）
   │  ├─ div.menubar-left
   │  │  ├─ span.apple                          苹果图标（26×22，内联 SVG）
   │  │  ├─ button#appMenuButton.mb-app         "CoRouter"，aria-haspopup=menu / aria-expanded
   │  │  └─ span.mb-item × 5                    文件 / 编辑 / 显示 / 窗口 / 帮助（纯文本，不可点）
   │  └─ div.menubar-right
   │     ├─ button#statusItem.status-item       ★ 状态项，aria-haspopup=dialog / aria-expanded=true
   │     │  ├─ svg.status-ring                  viewBox 0 0 18 18
   │     │  │  ├─ circle.ring-track  r=6.3 sw=2.1
   │     │  │  ├─ circle.ring-arc    r=6.3 sw=2.1 dasharray 39.58 dashoffset 1.58
   │     │  │  └─ circle.ring-dot    r=1.25
   │     │  └─ span#statusPct.status-pct        "96%"
   │     ├─ span.mb-glyph.control               控制中心图标
   │     ├─ span.mb-glyph.wifi                  Wi-Fi 图标
   │     ├─ span.mb-glyph                       电池图标
   │     └─ span#menuClock.mb-clock             "11月6日 周五 21:42"（每 30s 刷新）
   ├─ div#appMenu.app-menu[hidden]               L1495  z-index 60  应用下拉菜单
   ├─ aside#popover.popover                      L1504  z-index 50  ★ 主面板，初始可见
   ├─ div#settingsLayer.window-layer[hidden]     L1728  z-index 30  ★ 设置窗口层
   ├─ div#toast.toast[hidden]                    L2003  z-index 70
   └─ div#quitLayer.quit-layer[hidden]           L2008  z-index 80  退出层
~~~

### 1.2 初始可见性矩阵

| 节点 | 初始 hidden | 初始 class / aria | 说明 |
|---|---|---|---|
| #popover | 否（无 hidden 属性） | aria-expanded=true，tabindex=-1 | 原型为看图默认展开；真实 App 必须默认收起 |
| #appMenu | 是 | aria-expanded=false | |
| #settingsLayer | 是 | 无 is-open | |
| #toast | 是 | role=status aria-live=polite | |
| #quitLayer | 是 | role=alertdialog aria-modal=true | |
| #viewOverview | 否 | — | 概览页 |
| #viewDetail | 是 | — | 明细页 |
| #pane-account | 否 | nav-item.is-active + aria-current=page | |
| #pane-general / #pane-notifications / #pane-about | 是 | — | |

### 1.3 状态项（菜单栏）

| 属性 | 值 |
|---|---|
| 容器 | button#statusItem.status-item，display inline-flex，gap 5px |
| 尺寸 | 高 23px，padding 0 7px，margin-right 2px，border-radius 6px |
| 背景 | 常态 rgba(255,255,255,0.10)；hover 0.18；aria-expanded=true 0.20；:active transform scale(0.97) |
| 图标 | svg.status-ring 17×17，viewBox 0 0 18 18，r 6.3，stroke-width 2.1，track 白 26%，arc #9AE6CB，dot r 1.25 白 90% |
| 文本 | span.status-pct，font-num，11.5px / 600，色 #F4FBF8 |
| 精简模式 | .hide-pct → gap 0 且 .status-pct display none（环保留） |
| aria-label（百分比模式） | CoRouter，5 小时额度剩余 96%，点击查看套餐与用量 |
| aria-label（仅图标） | CoRouter，点击查看套餐与用量 |

### 1.4 弹出面板

~~~
aside#popover.popover[role=dialog][aria-modal=false][aria-label="CoRouter 套餐与用量"][tabindex=-1]
├─ ::before                                  caret 三角（14×14，rotate 45°，top -7px，left calc(var(--caret-x) - 7px)）
├─ div.pop-head
│  ├─ div.brand
│  │  ├─ span.brand-mark                    30×30，radius 9.5，渐变 #10503F→#0A2F26（内嵌 30×30 SVG 环）
│  │  └─ span.brand-text
│  │     ├─ span.brand-name                 "CoRouter" 14px/600
│  │     └─ span.brand-badge[aria-hidden]   "Go" 9px/700，高 16，accent-soft 底
│  └─ div.pop-head-actions
│     └─ button#openSettingsBtn.icon-btn    ▲ 齿轮，aria-label="打开设置"，title="设置"
├─ div#popBody.pop-body.od-scroll
│  ├─ div#viewOverview.pop-view
│  │  ├─ section.plan-card[aria-label="当前订阅"]
│  │  │  ├─ div.plan-info
│  │  │  │  ├─ span.plan-eyebrow            "当前订阅"
│  │  │  │  ├─ div.plan-name-row
│  │  │  │  │  ├─ h2.plan-name              "Go"
│  │  │  │  │  └─ span.plan-status          "生效中"（::before 4.5px 圆点）
│  │  │  │  ├─ div.plan-price
│  │  │  │  │  ├─ span.price-num.num        "$7"
│  │  │  │  │  └─ span.price-unit           "/ 月"
│  │  │  │  └─ span.plan-meta               日历图标 + "年付 $84 · 11月20日到期"
│  │  │  └─ div.usage-ring                  104×104
│  │  │     ├─ svg.ring-svg[viewBox 0 0 104 104][role=img][aria-label="5 小时额度剩余 96%"]
│  │  │     │  ├─ circle.ring-track  r=42 sw=7
│  │  │     │  └─ circle.ring-value  r=42 sw=7 dasharray 263.89 dashoffset 10.56
│  │  │     └─ div.ring-center
│  │  │        ├─ span.ring-number-line > span#ringNum.ring-num "96" + span.ring-pct "%"
│  │  │        └─ span.ring-cap             "5 hour"
│  │  ├─ div.section-head
│  │  │  ├─ h3                              "Design Plan 额度"
│  │  │  └─ button#popDetailBtn.text-btn    "用量明细" + chevron-right
│  │  ├─ div.quota-card.quota-split
│  │  │  ├─ div.quota-col                   5 小时：q-label(q-dot.a) + q-big "96%" + div.bar > span(96%) + q-meta
│  │  │  ├─ div.quota-col                   7 天： q-label(q-dot.b) + q-big "89%" + div.bar.bar-b > span(89%) + q-meta
│  │  │  └─ div.quota-foot                  q-label(q-dot.c) "按量额度" + strong "$1.00" + span.muted "可用"
│  │  ├─ div.section-head（仅 h3 "近 7 天用量"）
│  │  └─ div.chart-card
│  │     ├─ div.chart-head
│  │     │  ├─ div > h3 "Token 消耗" + p.chart-sub "总计 522.32M · 日均 74.62M"
│  │     │  └─ span.chip "Token"
│  │     └─ svg.chart-svg[viewBox 0 0 340 120][role=img]
│  │        ├─ line.chart-grid × 2（y=40 / y=68，x 14→326）
│  │        ├─ rect.chart-bar × 7（rx 7，width 24，--i:0..6，最后一根 .is-today）
│  │        └─ text.chart-label × 7（"六 日 一 二 三 四 今"，最后一枚 .is-today）
│  └─ div#viewDetail.pop-view[hidden]
│     ├─ div.detail-head
│     │  ├─ button#backOverviewBtn.icon-btn       chevron-left，aria-label="返回概览"
│     │  ├─ div.detail-title > h2 "用量明细" + p "近 7 天 · 10月31日 – 11月6日"
│     │  └─ span.chip "7 天"
│     ├─ div.detail-card
│     │  ├─ div.detail-total-row
│     │  │  ├─ div > span.detail-label "总 Token" + div.detail-big.num "522.32M"
│     │  │  └─ span.pct-pill "Design Plan"
│     │  └─ p.detail-meta "全部请求由 Design Plan 额度抵扣"
│     ├─ div.section-head > h3 "Token 明细"
│     ├─ div.res-grid（4 × div.res-tile：q-label(q-dot) + div.res-value.num）
│     │     输入 517.91M / 输出 4.4M / 缓存读取 509.8M / 缓存写入 30.72K
│     ├─ div.section-head > h3 "最近请求"
│     ├─ div.activity-card > ul.activity > li × 3
│     │     span.act-badge.a "DS" + span.act-text(act-name + act-meta)
│     │     + span.act-cost(span.act-points + span.act-tag "Design Plan")
│     └─ button#exportBtn.btn-wide             "导出近 7 天用量 CSV"
└─ div.pop-foot
   ├─ span#syncText.sync[role=status][aria-live=polite]   "2 分钟前同步"
   └─ div.foot-actions
      ├─ button#footRefresh.btn-compact       "刷新"（图标 13px）
      └─ button#footSettings.btn-compact.primary  "设置"（图标 13px）
~~~

### 1.5 应用菜单（CoRouter 下拉）

~~~
div#appMenu.app-menu[role=menu][aria-label="CoRouter 菜单"]
├─ button.menu-item[role=menuitem][data-action=about]      "关于 CoRouter"
├─ div.menu-sep[role=separator]
├─ button.menu-item[data-action=settings]                  "设置…" + span.shortcut "⌘,"
├─ button.menu-item[data-action=refresh]                   "刷新用量" + span.shortcut "⌘R"
├─ div.menu-sep
└─ button.menu-item[data-action=quit]                      "退出 CoRouter" + span.shortcut "⌘Q"
~~~

### 1.6 设置窗口（792×632，四页）

~~~
div#settingsLayer.window-layer[hidden]           ← 全屏遮罩，只做居中，pointer-events none
└─ div#settingsWindow.app-window[role=dialog][aria-modal=false][aria-labelledby=settingsTitle]
   ├─ div.window-bar                             高 46，grid 1fr auto 1fr
   │  ├─ div.traffic > button.tl.tl-red#closeSettings + span.tl.tl-yellow + span.tl.tl-green
   │  ├─ h1#settingsTitle.window-title           "设置"
   │  └─ div.window-bar-end（空占位）
   └─ div.window-body                            grid 196px / minmax(0,1fr)
      ├─ nav.settings-nav[aria-label="设置分类"]
      │  ├─ button.nav-item.is-active[data-pane=account][aria-current=page]   账户
      │  ├─ button.nav-item[data-pane=general]                                通用
      │  ├─ button.nav-item[data-pane=notifications]                          通知
      │  ├─ button.nav-item[data-pane=about]                                  关于
      │  └─ div.nav-foot > span.mini-avatar "RY" + span.nav-foot-text
      │        (span.nav-foot-name "Ryan Y" + span.nav-foot-plan "Go · 正常")
      └─ div#settingsContent.settings-content.od-scroll
         ├─ section#pane-account.pane
         │  ├─ header.pane-head > p.eyebrow "连接" + h2 "账户与登录" + p.pane-sub
         │  ├─ div.status-card
         │  │  ├─ span.status-orb（对勾，32×32）
         │  │  ├─ span.status-text > span.status-title "工作区已连接" + span#connectionMeta.status-meta
         │  │  └─ span.status-pill "正常"
         │  └─ form#accountForm.account-form[novalidate]
         │     ├─ div.field[data-field=workspace]
         │     │  ├─ label[for=workspaceUrl] "服务地址"
         │     │  ├─ input#workspaceUrl.input[type=url][aria-describedby=errWorkspace]
         │     │  ├─ p.help "用于连接 CoRouter 并拉取套餐额度与用量。"
         │     │  └─ p#errWorkspace.field-error[hidden]
         │     ├─ div.field[data-field=email]     同上：input#accountEmail[type=email]，p#errEmail
         │     ├─ div.field[data-field=token]
         │     │  ├─ label "访问令牌"
         │     │  ├─ div.input-wrap > input#accessToken.input[type=password] + button#toggleToken.reveal
         │     │  │     （内含 svg.eye-open 与 svg.eye-off[hidden]）
         │     │  ├─ p.help "仅用于验证工作区访问权限。"
         │     │  └─ p#errToken.field-error[hidden]
         │     ├─ div.form-actions > p#formNote.form-note + button#saveAccount.btn-primary
         │     │     （内含 span#saveSpinner.spinner[hidden] + span#saveLabel）
         │     └─ div#accountSuccess.success-strip[role=status][hidden] "连接成功，用量已同步。"
         ├─ section#pane-general.pane[hidden]
         │  ├─ header.pane-head（eyebrow "运行" / h2 "通用" / pane-sub）
         │  ├─ div.group > p.group-title "外观" + div.group-card
         │  │  ├─ div.setting-row.has-segmented  主题：segmented[role=group][aria-label=主题] × 3
         │  │  │     button[data-theme-choice=system|light|dark][aria-pressed]
         │  │  └─ div.setting-row.has-segmented  菜单栏显示：segmented[aria-label=菜单栏显示] × 2
         │  │        button[data-display=percent|icon][aria-pressed]
         │  └─ div.group > p.group-title "启动与同步" + div.group-card
         │     ├─ div.setting-row 登录时自动启动 → button#switchLaunch.switch[role=switch][aria-checked=true]
         │     └─ div.setting-row 自动刷新用量 → select#intervalSelect.select + button#switchAutoRefresh.switch
         ├─ section#pane-notifications.pane[hidden]
         │  ├─ header.pane-head（eyebrow "提醒" / h2 "通知"）
         │  └─ div.group > p.group-title "系统通知" + div.group-card
         │     ├─ div.setting-row 额度不足提醒 → button#switchUsageAlert.switch
         │     ├─ div.slider-row#thresholdRow
         │     │  ├─ div.slider-label > span "提醒阈值（剩余额度）" + output#thresholdOut[for=threshold]
         │     │  ├─ input#threshold.range[type=range][min=50][max=100][step=5][value=80]
         │     │  └─ div.range-scale > span "50%" + span "100%"
         │     ├─ div.setting-row 本期结束前提醒 → button#switchRenewal.switch
         │     └─ div.setting-row 每周用量摘要 → button#switchWeekly.switch[aria-checked=false]
         └─ section#pane-about.pane[hidden]
            └─ div.about
               ├─ span.about-mark（72×72，渐变底 + 30×30 SVG 环）
               ├─ h2 "CoRouter"
               ├─ p.about-sub "菜单栏套餐与用量"
               ├─ span.version-pill "版本 2.4.1 (2400)"
               ├─ div.update-row > button#checkUpdate.btn-compact + span#updateStatus.update-status
               │     （按钮内 span#updateSpinner.spinner[hidden] + span#updateLabel）
               ├─ dl.about-facts > div.about-fact × 3（dt/dd：运行方式 / 同步间隔 / 凭证存储）
               └─ p.copyright "© 2026 CoRouter"
~~~

### 1.7 退出层与 toast

~~~
div#toast.toast[role=status][aria-live=polite][hidden]
├─ svg.od-icon.i-14（对勾）
└─ span#toastText

div#quitLayer.quit-layer[hidden]
└─ div.quit-card[role=alertdialog][aria-modal=true][aria-labelledby=quitTitle]
   ├─ span.quit-mark（54×54，渐变底 + 30×30 SVG 环）
   ├─ h2#quitTitle "CoRouter 已退出"
   ├─ p
   └─ button#restartApp.btn-primary "重新启动"
~~~

---

## 2. 设计变量表

### 2.1 明色 :root（L54–L99，42 个变量 + color-scheme）

| 变量 | 原值 | 主要消费点 |
|---|---|---|
| --font-ui | -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Hiragino Sans GB", "Helvetica Neue", Arial, sans-serif | body、.chart-label |
| --font-num | ui-rounded, "SF Pro Rounded", "Hiragino Maru Gothic ProN", -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif | .num、.status-pct |
| --surface | #F6F8F6 | .app-window、.quit-card、.settings-content |
| --surface-2 | #FFFFFF | 卡片底：.quota-card / .chart-card / .detail-card / .group-card / .res-tile、.segmented 选中、.status-pill |
| --surface-3 | #EDF1EE | hover 底、.bar 轨道、.chip、.segmented 轨道、.version-pill、.nav-item:hover |
| --surface-inset | #F1F4F1 | 未被任何规则引用（死变量） |
| --sidebar | #EFF3F0 | .settings-nav 背景 |
| --text | #14201C | 正文、.menu-item、按钮文字 |
| --text-2 | #4E5C56 | 次级文字、.nav-item、.pane-sub、.window-title |
| --text-3 | #5F6C66 | 说明与元信息（全站 29 处） |
| --line | rgba(18, 44, 35, 0.09) | 卡片描边、分隔线 |
| --line-strong | rgba(18, 44, 35, 0.15) | 窗口描边、input 描边、按钮描边、滚动条 thumb |
| --accent | #0E7C63 | 进度条、焦点框、开关打开、range accent、q-dot.a |
| --accent-strong | #0A5A47 | .text-btn、.nav-item.is-active、.pct-pill、.act-badge.a、滑块数值、图表今日标签 |
| --accent-soft | #E2F2EC | .brand-badge、.text-btn:hover、.pct-pill、.act-badge.a、.mini-avatar、.status-orb |
| --accent-tint | rgba(14, 124, 99, 0.10) | 仅 1 处：input:focus 的 3px 外发光 |
| --pine | #0B3A30 | 未被引用（死变量） |
| --mint | #9AE6CB | 未被引用（死变量；同色值在 SVG 内硬编码） |
| --blue | #3F6E9E | q-dot.b、.bar-b、.act-badge.b |
| --amber | #A5641C | q-dot.c、.bar-c、.act-badge.c |
| --danger | #B3261E | .field-error 文字、.is-invalid 描边 |
| --ok | #167A5C | .sync::before、.status-pill::before |
| --ok-surface | #EDF7F2 | .status-card、.success-strip、.act-tag |
| --ok-line | rgba(14, 124, 99, 0.16) | 上述三者描边、.status-pill 描边 |
| --ok-text | #0A5A47 | 上述三者文字、.status-orb |
| --nav-active | #E1F1EA | .nav-item.is-active 背景 |
| --input-bg | #FFFFFF | .input / .select |
| --btn-primary-bg | #0B3A30 | .btn-primary、.btn-compact.primary |
| --btn-primary-text | #F7FCF9 | 同上文字 |
| --panel | rgba(249, 251, 249, 0.95) | .popover 底色 + caret 底色 |
| --panel-border | rgba(255, 255, 255, 0.65) | .popover 描边、caret 描边、.app-menu 描边、.quit-card 描边 |
| --menu-bg | rgba(250, 252, 250, 0.90) | .app-menu 底 |
| --menu-hover-bg | #0E7C63 | .menu-item:hover 底 |
| --menu-hover-text | #FFFFFF | 同上文字 |
| --shadow-pop | 0 28px 70px -18px rgba(3,16,12,0.55), 0 8px 22px -10px rgba(3,16,12,0.28), 0 0 0 0.5px rgba(4,24,18,0.18) | .popover |
| --shadow-window | 0 50px 120px -32px rgba(2,12,9,0.70), 0 18px 44px -20px rgba(2,12,9,0.45), 0 0 0 0.5px rgba(255,255,255,0.16) | .app-window、.quit-card |
| --chart-bar | rgba(14, 124, 99, 0.20) | .chart-bar（非今日） |
| --chart-bar-hi | #0E7C63 | .chart-bar.is-today |
| --chart-grid | rgba(18, 44, 35, 0.08) | 网格虚线（3 5） |
| --switch-off | #C9D2CD | .switch 关态底 |
| --switch-knob | #FFFFFF | .switch::after 圆点（暗色不覆写） |
| --focus | #0E7C63 | :focus-visible 2px 描边 |
| color-scheme | light | — |

### 2.2 暗色 [data-theme="dark"]（L101–L141，覆盖 38 个）

| 变量 | 暗色原值 |
|---|---|
| --surface | #161B19 |
| --surface-2 | #1D2320 |
| --surface-3 | #252C29 |
| --surface-inset | #121715（仍未被引用） |
| --sidebar | #1A201D |
| --text | #EEF4F0 |
| --text-2 | #B2BDB7 |
| --text-3 | #98A49E |
| --line | rgba(255, 255, 255, 0.08) |
| --line-strong | rgba(255, 255, 255, 0.15) |
| --accent | #5FCBA9 |
| --accent-strong | #8FE6C9 |
| --accent-soft | rgba(95, 203, 169, 0.13) |
| --accent-tint | rgba(95, 203, 169, 0.10) |
| --mint | #9AE6CB（与明色相同） |
| --danger | #FF8A80 |
| --blue | #8CB9E2 |
| --amber | #E0A35C |
| --ok | #6FD8B7 |
| --ok-surface | rgba(95, 203, 169, 0.10) |
| --ok-line | rgba(95, 203, 169, 0.20) |
| --ok-text | #8FE6C9 |
| --nav-active | rgba(95, 203, 169, 0.14) |
| --input-bg | #121715 |
| --btn-primary-bg | #79D9BB |
| --btn-primary-text | #06251C |
| --panel | rgba(24, 30, 27, 0.95) |
| --panel-border | rgba(255, 255, 255, 0.08) |
| --menu-bg | rgba(28, 34, 31, 0.92) |
| --menu-hover-bg | #5FCBA9 |
| --menu-hover-text | #06251C |
| --shadow-pop | 0 28px 80px -18px rgba(0,0,0,0.80), 0 8px 22px -10px rgba(0,0,0,0.50), 0 0 0 0.5px rgba(255,255,255,0.12) |
| --shadow-window | 0 50px 130px -32px rgba(0,0,0,0.85), 0 18px 44px -20px rgba(0,0,0,0.60), 0 0 0 0.5px rgba(255,255,255,0.12) |
| --chart-bar | rgba(95, 203, 169, 0.18) |
| --chart-bar-hi | #6FD8B7 |
| --chart-grid | rgba(255, 255, 255, 0.07) |
| --switch-off | #3B4540 |
| --focus | #6FD8B7 |
| color-scheme | dark |

暗色不覆写的 4 个：--font-ui、--font-num、--pine、--switch-knob。另有 3 组硬编码暗色补丁不在变量体系内：

| 位置 | 规则 |
|---|---|
| L812–L813 | [data-theme=dark] .act-badge.b color #9CC6EE；.act-badge.c color #E0A35C |
| L1234–L1236 | [data-theme=dark] .select 换 stroke 为 #98A49E 的下拉箭头 |
| L1350–L1352 | [data-theme=dark] .plan-card 渐变改为 radial rgba(120,222,190,0.16) + linear #12463A→#0A3028 |

### 2.3 两套主题之外的硬编码颜色

| 值 | 使用处 |
|---|---|
| #08110F | body 背景 |
| rgba(9,17,14,0.44) / rgba(255,255,255,0.07) | .menubar 底色 / 下边框 |
| #F4FBF8 | .status-item 文字 |
| rgba(255,255,255,0.10 / 0.18 / 0.20) | .status-item 常态 / hover / 展开 |
| rgba(255,255,255,0.26) / #9AE6CB / rgba(255,255,255,0.9) | 状态项环形 track / arc / dot |
| #F3FAF6、#F7FCF9、rgba(224,244,236,0.72/0.78/0.70)、rgba(154,230,203,0.15/0.20)、#B7F2DD | .plan-card 内整套文字与状态胶囊 |
| #0E4337→#082E26、rgba(255,255,255,0.09)、rgba(255,255,255,0.12)、rgba(3,22,16,0.55) | .plan-card 渐变 / 描边 / 内高光 / 投影 |
| #10503F→#0A2F26 | .brand-mark、.about-mark、.quit-mark 渐变 |
| rgba(3,20,15,0.28/0.5)、rgba(3,20,14,0.12)、rgba(9,25,19,0.28) | 内阴影 / 分段滑块投影 / 开关圆点投影 |
| rgba(63,110,158,0.12)、rgba(165,100,28,0.12) | .act-badge.b / .act-badge.c 底色 |
| rgba(179,38,30,0.12) | .field.is-invalid .input:focus 外发光 |
| rgba(17,28,24,0.94)、rgba(255,255,255,0.12)、rgba(0,0,0,0.5)、#F1F8F4 | .toast 底 / 边 / 影 / 字 |
| rgba(4,12,9,0.52) | .quit-layer 遮罩 |
| #FF5F57 / #FEBC2E / #28C840 | 红绿灯 |
| rgba(14,124,99,0.24) | ::selection |

---
## 3. 尺寸规约（硬编码数值全表）

### 3.1 菜单栏与状态项

| 对象 | 数值 |
|---|---|
| .menubar | height 30px；padding 0 12px 0 10px；gap 12px；font-size 13px；blur(30px) saturate(1.5) |
| .menubar-left gap / .menubar-right gap | 1px / 3px |
| .apple | 26×22，opacity 0.92 |
| .mb-app / .mb-item / .mb-glyph | height 22px；border-radius 5px |
| .mb-app | padding 0 9px；margin-right 2px；font 13px/600；letter-spacing -0.01em |
| .mb-item | padding 0 9px；color rgba(255,255,255,0.88) |
| .mb-glyph | width 24px |
| .mb-clock | height 22px；padding 0 8px；radius 5px；font 12.5px |
| .status-item | height 23px；padding 0 7px；gap 5px；radius 6px；margin-right 2px |
| .status-ring | 17×17（viewBox 18×18，r 6.3，stroke 2.1，dasharray 39.58，dashoffset 1.58） |
| .status-pct | 11.5px / 600 |

### 3.2 弹出面板框架

| 对象 | 数值 |
|---|---|
| .popover 宽 | 392px（CSS 声明；运行时被 JS 覆写，见 3.3） |
| .popover 圆角 | 26px |
| .popover 描边 | 1px var(--panel-border) |
| .popover 阴影 | --shadow-pop（三段） |
| .popover 初始定位 | top 38px；left 54px |
| .popover max-height | calc(100vh - 54px)（CSS）/ JS 覆写为 max(240, H - top - 16) |
| backdrop-filter | blur(36px) saturate(1.55) |
| transform-origin | var(--caret-x, 300px) 0 |
| caret | 14×14；top -7px；left calc(var(--caret-x) - 7px)；radius 3px 0 0 0；rotate 45°；上/左各 1px 描边；.is-compact 时 display none |
| .pop-head | padding 14px 16px 12px；gap 12px |
| .pop-body | padding 0 16px 16px |
| .pop-foot | padding 12px 16px 14px；gap 10px；border-top 1px |
| .brand gap / .brand-text gap | 9px / 6px |
| .brand-mark | 30×30；radius 9.5px |
| .brand-badge | height 16px；padding 0 5px；radius 5px；font 9px/700；letter-spacing 0.02em |
| .pop-head-actions gap | 2px |
| .icon-btn | 30×30；radius 8px |
| .sync | font 11px；gap 6px；圆点 5.5×5.5 |
| .foot-actions gap | 7px |
| .btn-compact | height 32px；padding 0 11px；radius 9px；gap 5px；font 12px/500 |

### 3.3 caret 定位算法（positionPopover，L2244–L2265）

输入：状态项 rect（left / width / bottom）、视口宽 W、高 H。

| 步骤 | 规则 |
|---|---|
| 1 | compact = W < 520 |
| 2 | 面板宽 width = min(392, W - 24) |
| 3 | compact 时：left = 12；caretX = width / 2；加 .is-compact（隐藏 caret） |
| 4 | 非 compact：desiredLeft = rect.left + rect.width/2 - width + 68；left = clamp(desiredLeft, 12, W - width - 12) |
| 5 | 非 compact：caretX = clamp(rect.left + rect.width/2 - left, 26, width - 26) |
| 6 | top = max(38, rect.bottom + 10) |
| 7 | left / top / caretX 各自四舍五入到整数像素 |
| 8 | 写入 CSS 变量 --caret-x = round(caretX) px |
| 9 | maxHeight = max(240, H - top - 16) |

注：常数 68 无文档来源，属硬编码经验值；caret 的 26px 边距保证三角不压住圆角。

### 3.4 面板内卡片

| 对象 | padding | radius | 其他 |
|---|---|---|---|
| .plan-card | 17px 18px | 21px | gap 14；描边 1px rgba(255,255,255,0.09)；渐变 155deg #0E4337→#082E26 + radial 130% 150% at 102% -8% |
| .plan-eyebrow | — | — | font 11px；margin-bottom 5px；color rgba(224,244,236,0.72) |
| .plan-name | — | — | 20px/600；letter-spacing -0.025em；line-height 1.2 |
| .plan-status | 0 7px | 999px | height 18px；font 10.5px/600；::before 4.5px 圆点；gap 4 |
| .plan-price | — | — | margin-top 7px；gap 3 |
| .price-num | — | — | 24px/600；letter-spacing -0.03em；line-height 1.1 |
| .price-unit | — | — | 11px |
| .plan-meta | — | — | margin-top 5px；gap 4；font 11px |
| .usage-ring | — | — | 104×104 |
| .ring-track | — | — | stroke rgba(255,255,255,0.15)；stroke-width 7 |
| .ring-value | — | — | stroke #9AE6CB；width 7；linecap round；dasharray 263.89；dashoffset 10.56 |
| .ring-num | — | — | 27px/600；letter-spacing -0.035em；line-height 1 |
| .ring-pct | — | — | 11.5px/500 |
| .ring-cap | — | — | 10.5px；margin-top 4px；letter-spacing 0.02em |
| .section-head | — | — | margin 16px 2px 9px；gap 12 |
| .section-head h3 | — | — | 12.5px/600；letter-spacing -0.005em |
| .text-btn | 3px 5px（margin -3 -5） | 6px | font 11.5px/500；gap 2 |
| .quota-card | 14px 15px | 18px | gap 13；.quota-split 为 1fr 1fr / gap 11px 16px |
| .quota-col + .quota-col | padding-left 16px | — | border-left 1px |
| .q-label | — | — | font 12px；gap 6 |
| .q-dot | — | 999px | 6×6 |
| .q-big | — | — | margin-top 4px；22px/600；letter-spacing -0.02em；line-height 1.1 |
| .bar | — | 999px | height 6px；margin-top 7px（明细页 8px / margin-top 12px） |
| .q-meta | — | — | margin 6px 0 0；font 11px；line-height 1.4 |
| .quota-foot | padding-top 11px | — | border-top 1px；gap 6；strong 13.5px/600；.muted 11px |
| .chart-card | 14px 14px 7px | 18px | — |
| .chart-head | — | — | gap 10 |
| .chart-sub | — | — | margin 3px 0 0；font 11px |
| .chip | 0 7px | 6px | height 20px；font 10.5px |
| .chart-svg | — | — | margin-top 5px；overflow visible |
| .detail-head | 2px 0 12px | — | gap 9 |
| .detail-title h2 | — | — | 16px/600；letter-spacing -0.02em |
| .detail-title p | — | — | margin-top 1px；font 11px |
| .detail-card | 16px | 18px | — |
| .detail-big | — | — | 23px/600；letter-spacing -0.03em；line-height 1.1；内 span 11.5px/500 |
| .pct-pill | 0 8px | 7px | height 22px；font 11px/600 |
| .detail-meta | — | — | margin 9px 0 0；font 11px |
| .res-grid | — | — | 1fr 1fr；gap 10px |
| .res-tile | 12px 13px | 14px | 内 q-label 11px；res-value 17px/600，margin-top 5px |
| .activity-card | 3px 14px | 18px | — |
| .activity li | 10px 0 | — | gap 10；相邻项 border-top 1px |
| .act-badge | — | 9px | 30×30；font 11px/600 |
| .act-name | — | — | 12px/500 |
| .act-meta | — | — | margin-top 1px；font 10.5px |
| .act-cost | — | — | gap 3px |
| .act-points | — | — | 11.5px |
| .act-tag | 1px 5px | 5px | font 10px/600；line-height 1.4 |
| .btn-wide | — | 10px | width 100%；height 34px；margin-top 12px；gap 6；font 12px/500 |

### 3.5 环形图几何

| 项 | 值 |
|---|---|
| 盒子 | 104×104 |
| viewBox | 0 0 104 104 |
| 圆心 / 半径 | cx=cy=52；r=42 |
| 描边宽 | 7 |
| 周长（dasharray） | 263.89（= 2π×42 = 263.894） |
| 当前 dashoffset | 10.56（= 263.89 × 4%），对应剩余 96% |
| 旋转 | rotate(-90deg)，transform-origin 52px 52px |
| 动画 | ringFill 1100ms，delay 160ms，cubic-bezier(0.22, 1, 0.36, 1)，from dashoffset 263.89 |
| 中心数字 | 27px / 600 / -0.035em；% 11.5px；cap 10.5px，间隔 4px |
| 状态项小环 | 17×17 盒 / viewBox 18×18 / r 6.3 / sw 2.1 / 周长 39.58 / offset 1.58 / dot 1.25 |
| 数字滚动 | 0→96，900ms，延迟 200ms，缓动 1-(1-p)³ |

### 3.6 柱状图几何

| 项 | 值 |
|---|---|
| viewBox | 0 0 340 120 |
| 网格线 | y=40 与 y=68，x 从 14 到 326，stroke-width 1，dasharray 3 5 |
| 柱宽 / 圆角 | 24 / rx 7 |
| 基线 | y = 94；height = round(tokens_M × 64 / 97.8) |
| 横向步进 | 48px；x = 16 + 48i |
| 标签 | y=112，text-anchor middle，font 10.5px；x = 28 + 48i |

逐柱坐标：

| i | 日期 | 值 | x | y | height | 标签 x | 标签 |
|---|---|---|---|---|---|---|---|
| 0 | 10-31 | 48.2M | 16 | 62 | 32 | 28 | 六 |
| 1 | 11-01 | 62.4M | 64 | 53 | 41 | 76 | 日 |
| 2 | 11-02 | 71.6M | 112 | 47 | 47 | 124 | 一 |
| 3 | 11-03 | 88.1M | 160 | 36 | 58 | 172 | 二 |
| 4 | 11-04 | 76.5M | 208 | 44 | 50 | 220 | 三 |
| 5 | 11-05 | 97.8M | 256 | 30 | 64 | 268 | 四 |
| 6 | 今天 | 77.72M | 304 | 43 | 51 | 316 | 今（.is-today） |

比例常数：64px 对应 97.8M，即 0.65440 px/百万；7 根柱的 y + height 恒为 94。

### 3.7 设置窗口

| 对象 | 数值 |
|---|---|
| .window-layer | inset 30px 0 0 0（顶部让出菜单栏）；padding 20px；opacity 0↔1 180ms；pointer-events none（子元素 auto） |
| .app-window | width min(792px, 100vw - 48px)；height min(632px, 100vh - 84px)；radius 20px；border 1px；阴影 --shadow-window |
| .app-window 过渡 | opacity 200ms；transform 260ms cubic-bezier(0.2, 0.9, 0.3, 1)；初始 translateY(12px) scale(0.985) |
| .window-bar | height 46px；grid 1fr auto 1fr；border-bottom 1px |
| .traffic | gap 8px；padding-left 16px |
| .tl | 12×12；border 0.5px rgba(0,0,0,0.14)；内高光 inset 0 0.5px 0 rgba(255,255,255,0.28) |
| .window-title | 13px/600；color var(--text-2) |
| .window-body | grid 196px minmax(0, 1fr) |
| .settings-nav | padding 10px；gap 2px；border-right 1px；背景 --sidebar |
| .nav-item | height 36px；padding 0 10px；gap 9px；radius 9px；font 13px/500 |
| .nav-foot | padding 12px 8px 4px；gap 9px；margin-top auto；border-top 1px |
| .mini-avatar | 28×28；radius 8px；font 11px/700 |
| .nav-foot-name / -plan | 12px/600；10.5px，margin-top 1px |
| .settings-content | padding 26px 30px 30px |
| .pane | max-width 560px |
| .pane-head | margin-bottom 20px |
| .eyebrow | font 11px/600；letter-spacing 0.07em；margin 0 0 5px |
| .pane-head h2 | 22px/600；letter-spacing -0.025em；line-height 1.25 |
| .pane-sub | margin 6px 0 0；12.5px；line-height 1.55；max-width 46ch |
| .status-card | padding 13px 14px；radius 14px；margin-bottom 18px；gap 11px |
| .status-orb | 32×32；radius 999 |
| .status-title / .status-meta | 12.5px/600；11px，margin-top 1px |
| .status-pill | height 20px；padding 0 8px；radius 999；font 10.5px/600；::before 4.5px |
| .field + .field | margin-top 15px |
| .field label | margin-bottom 6px；12px/600 |
| .input / .select | width 100%；height 40px；padding 0 12px；radius 10px；font 13px |
| .input:focus | border var(--accent) + box-shadow 0 0 0 3px var(--accent-tint) |
| .help | margin 6px 0 0；11px；line-height 1.5 |
| .field-error | margin 6px 0 0；11px；line-height 1.45；gap 4px |
| .input-wrap .input | padding-right 42px |
| .reveal | 28×28；top 6px；right 6px；radius 7px |
| .form-actions | margin-top 22px；gap 10px；flex-wrap wrap |
| .btn-primary | height 38px；padding 0 18px；radius 10px；gap 7px；font 13px/600 |
| .spinner | 14×14；border 2px；700ms linear infinite |
| .success-strip | margin-top 14px；padding 10px 12px；radius 10px；font 11.5px/500；stripIn 220ms |
| .group | margin-top 18px |
| .group-title | margin 0 0 8px 4px；11px/600；letter-spacing 0.06em |
| .group-card | radius 16px；border 1px；overflow hidden |
| .setting-row | padding 13px 15px；min-height 58px；gap 18px |
| .setting-label / .setting-help | 12.5px/500；11px，margin-top 2px，line-height 1.45，max-width 34ch |
| .setting-control | gap 8px |
| .segmented | padding 3px；gap 2px；radius 9px |
| .segmented button | height 27px；padding 0 9px；radius 7px；font 11.5px/500 |
| .segmented [aria-pressed=true] | 底 --surface-2 + box-shadow 0 1px 2px rgba(3,20,14,0.12) |
| .switch | 38×22；radius 999；::after 18×18，top/left 2px，translateX(16px) |
| .select（行内） | width auto；height 32px；min-width 104px；padding 0 30px 0 10px；radius 8px；font 11.5px |
| .slider-row | padding 2px 15px 15px；.is-disabled opacity 0.5 |
| .slider-label | 11.5px；output 12px/600 |
| .range | width 100%；margin 8px 0 0 |
| .range-scale | margin-top 2px；10.5px |
| .about-mark | 72×72；radius 22px；margin 0 auto 14px |
| .about h2 | 21px/600；-0.025em |
| .about-sub | margin 4px 0 0；11.5px |
| .version-pill | height 22px；margin-top 9px；padding 0 9px；radius 999；10.5px |
| .update-row | margin-top 18px；gap 10px |
| .update-status | 11px |
| .about-facts | max-width 430px；margin 24px auto 0；border-top 1px |
| .about-fact | padding 9px 2px；gap 16px；border-bottom 1px；dt 11px / dd 11.5px/500 |
| .copyright | margin 22px 0 0；10.5px |

### 3.8 退出层与 toast

| 对象 | 数值 |
|---|---|
| .toast | 水平居中；bottom 28px；padding 10px 15px；radius 999；max-width calc(100vw - 32px)；font 12px；gap 7px；底 rgba(17,28,24,0.94)；边 1px rgba(255,255,255,0.12)；影 0 14px 34px -12px rgba(0,0,0,0.5) |
| .quit-layer | inset 0；padding 24px；背景 rgba(4,12,9,0.52)；blur(14px) saturate(1.2) |
| .quit-card | width min(372px, 100vw - 40px)；padding 28px；radius 22px；popIn 240ms |
| .quit-mark | 54×54；radius 16px；margin 0 auto 14px |
| .quit h2 | 19px/600；-0.02em |
| .quit p | margin 8px 0 20px；12px；line-height 1.6 |
| .quit .btn-primary | width 100% |

### 3.9 层级 z-index

| 层 | z-index |
|---|---|
| .window-layer | 30 |
| .popover | 50 |
| .menubar | 55 |
| .app-menu | 60 |
| .toast | 70 |
| .quit-layer | 80 |

### 3.10 响应式断点（原型专用，见 §7）

| 断点 | 规则 |
|---|---|
| max-width 860 | .app-window width calc(100vw - 40px) |
| max-width 720 | 隐藏 .mb-item；pop-head 13/14/11；pop-body 0 14 14；pop-foot 11/14/13；settings-content 22px；window-body 单列（grid-template-rows auto minmax(0,1fr)）；settings-nav 横排（border-bottom、overflow-x auto、padding 8px、nav-item 34px）；隐藏 .nav-foot；pane-head h2 20px |
| max-width 600 | 隐藏 .mb-glyph.wifi / .mb-glyph.control；mb-clock padding 0 4px、12px；menubar padding 0 8px |
| max-width 520 | app-window calc(100vw - 20px) × calc(100vh - 66px)、radius 18；window-layer padding 10；window-bar 44；traffic padding-left 13；popover max-height calc(100vh - 48px)；plan-card 15/16、gap 10；usage-ring 92；ring-num 24；ring-cap 10；detail-big 21；隐藏 .status-pill；settings-content 18px；pane-sub 12px；setting-row 换行（row-gap 9）；segmented 拉满；setting-help 24ch |
| max-width 380 | pop-head 12/12/10；pop-body 0 12 12；pop-foot 10/12/12；plan-card 14；usage-ring 84；ring-num 22；plan-name 18；price-num 22；chart-label 12；btn-compact padding 0 9；segmented button padding 0 7；form-actions 竖排、按钮 100%；res-grid 单列 |
| max-width 340 | quota-split 单列；quota-col 竖排（padding-top 12、border-top）；chart-label 13.5px |
| 视口 < 520（JS） | 面板加 .is-compact（无 caret） |
| prefers-reduced-motion | 所有动画 0.01ms / delay 0 / iteration 1；过渡 0.01ms；scroll-behavior auto |

### 3.11 字号 / 字重 / 行高

| 字号 | 使用处 |
|---|---|
| 9px | .brand-badge |
| 10px | .act-tag |
| 10.5px | .plan-status、.ring-cap、.chip、.act-meta、.nav-foot-plan、.status-pill、.range-scale、.version-pill、.copyright、.chart-label、.q-value |
| 11px | .plan-eyebrow、.price-unit、.plan-meta、.q-meta、.q-pct、.chart-sub、.sync、.update-status、.help、.field-error、.form-note、.group-title、.setting-help、.eyebrow、.status-meta、.detail-label、.detail-meta、.about-fact dt |
| 11.5px | .status-pct、.ring-pct、.text-btn、.segmented button、.select、.slider-label、.act-points、.success-strip、.about-sub、.detail-big span、.res-value span、.about-fact dd |
| 12px | .q-label、.shortcut、.act-name、.btn-compact、.btn-wide、.quit p |
| 12.5px | .section-head h3、.chart-head h3、.q-value strong、.status-title、.setting-label、.pane-sub、.mb-clock |
| 13px | .menu-item、.mb-app、.mb-item、.input、.select（表单态）、.nav-item、.window-title、.btn-primary |
| 13.5px | body、.quota-foot strong |
| 14px | .brand-name |
| 16px | .detail-title h2 |
| 17px | .res-value |
| 19px | .quit-card h2 |
| 20px | .plan-name |
| 21px | .about h2 |
| 22px | .q-big、.pane-head h2 |
| 23px | .detail-big |
| 24px | .price-num |
| 27px | .ring-num |

行高：body 1.5；plan-name 1.2；price-num / q-big / detail-big 1.1；ring-num 1；q-meta 1.4；help 1.5；field-error 1.45；setting-help 1.45；pane-sub 1.55；quit p 1.6；act-tag 1.4。
字重：400 / 500 / 600 / 700（700 仅 .brand-badge、.mini-avatar）。
字距：-0.035em（ring-num）、-0.03em（price-num、detail-big）、-0.025em（plan-name、pane-head h2、about h2）、-0.02em（q-big、detail-title h2、quit h2）、-0.015em（brand-name）、-0.01em（.num、mb-app）、-0.005em（section-head h3、window-title）、+0.02em（brand-badge、ring-cap）、+0.04em（plan-eyebrow）、+0.06em（group-title）、+0.07em（eyebrow）。

---
## 4. 交互状态机

约定：关闭 = hidden 置真；打开 = hidden 置假；焦点恢复统一用 focus({preventScroll:true})。

### 4.1 状态项点击（L2598）

| 阶段 | DOM / 属性变化 |
|---|---|
| 打开 | #popover hidden=false；移除 .is-closing；#statusItem aria-expanded=true；positionPopover()；popover.focus() |
| 关闭 | 加 .is-closing（popOut 140ms）；aria-expanded=false；145ms 后 hidden=true 并移除 .is-closing；焦点回 #statusItem |

### 4.2 外部点击（pointerdown 捕获，L2788）

| 落点 | 行为 |
|---|---|
| 不在 #appMenu 且不在 #appMenuButton 内 | closeAppMenu()（不还焦点） |
| 不在 #popover / #statusItem / #appMenu 内 | closePopover()（无焦点恢复） |
| 面板内部 | popover 的 click stopPropagation + 包含判断，不关闭 |
| 设置窗口内部 | 无「点外部关闭」逻辑，只认红灯与 ESC |

补充：L2824 另有一个 document click 监听重复关闭 appMenu（冗余，不改变行为）。

### 4.3 ESC（L2798）

| 优先序 | 条件 | 行为 |
|---|---|---|
| 0 | #quitLayer 可见 | 直接 return，ESC 无效 |
| 1 | #appMenu 可见 | 关闭并还焦点给 #appMenuButton |
| 2 | #popover 可见 | 关闭并还焦点给 #statusItem |
| 3 | #settingsLayer 可见 | closeSettings()（170ms 后 hidden） |

### 4.4 快捷键

| 键 | 处理 | 备注 |
|---|---|---|
| ⌘R / Ctrl+R | preventDefault + refreshUsage() | 与面板开合无关 |
| ⌘, / Ctrl+, | preventDefault + openSettings(currentPane, statusItem) | |
| ⌘Q | 无处理（仅菜单项文字标注） | 原型缺口，原生必须映射 NSApp.terminate |
| 方向键 / Home / End（菜单内） | 上下循环、跳首尾 | 仅 appMenu 生效 |
| Tab（菜单内） | 关闭菜单并还焦点 | 设置窗口无 Tab 陷阱 |

### 4.5 概览 ↔ 明细（showDetail，L2309）

| 触发 | 变化 |
|---|---|
| #popDetailBtn | #viewOverview hidden=true；#viewDetail hidden=false；#popBody scrollTop=0；焦点 → #backOverviewBtn |
| #backOverviewBtn | 反向；焦点 → #popDetailBtn |
| 布局 | 面板高度随内容自适应（flex），无过渡；两视图各自重播 viewIn 240ms |

### 4.6 设置窗口开合

| 动作 | 变化 |
|---|---|
| 打开（齿轮 / 页脚设置 / 菜单设置… / ⌘, / 菜单关于） | 记录 settingsTrigger=当前焦点；清定时器；移除 .is-closing；closePopover()；closeAppMenu()；hidden=false → rAF 加 .is-open；showPane(pane)；150ms（reduced 20ms）后焦点到对应 nav-item |
| 关闭（红灯 / ESC） | 移除 .is-open、加 .is-closing；170ms（reduced 0ms）后 hidden=true 并移除 .is-closing；焦点回 settingsTrigger，不可见则回 #statusItem |
| 关于入口 | openSettings('about', statusItem)，触发者记为状态项 |

### 4.7 设置页切换（showPane，L2344）

| 变化 | 细节 |
|---|---|
| nav | 命中项加 .is-active + aria-current=page；其余移除两者 |
| pane | hidden = (id 不等于 pane-名)；每次切换 #settingsContent scrollTop=0 |
| 焦点 | 仅显式传 focus 时移动；点击导航不移动 |

### 4.8 控件状态

| 控件 | 触发 | 状态变化 |
|---|---|---|
| 主题分段 × 3 | click | prefs.theme 赋值；html[data-theme] 立即改；三按钮 aria-pressed 互斥；写 localStorage；无过渡 |
| 菜单栏显示分段 × 2 | click | prefs.display；#statusItem 切 .hide-pct；aria-label 在两套文案间切换；面板若开着则重新定位；写盘 |
| 开关 × 5 | click | aria-checked 取反；写盘。联动：switchAutoRefresh → #intervalSelect.disabled = !on；switchUsageAlert → #threshold.disabled = !on 且 #thresholdRow 切 .is-disabled（opacity 0.5） |
| 下拉 #intervalSelect | change | prefs.interval；#aboutInterval 文本 = 值 + " 分钟"；写盘；禁用态 .select:disabled opacity 0.45 |
| 滑块 #threshold | input | prefs.threshold（50–100，step 5）；#thresholdOut = 值 + "%"；写盘 |
| 密码显隐 #toggleToken | click | input type 在 password / text 间切换；aria-pressed；aria-label 在「显示访问令牌 / 隐藏访问令牌」间切换；.eye-open 与 .eye-off 的 hidden 互换 |

### 4.9 表单校验（三条规则）

| 字段 | 规则 | 失败文案（原文） | 失败态 |
|---|---|---|---|
| workspace | trim 后可被 URL 解析，且 protocol 为 https:，且 hostname 非空 | 请输入以 https:// 开头的有效地址。 | .field 加 .is-invalid + input[aria-invalid=true] + #errWorkspace 显示 |
| email | 正则 ^[^\s@]+@[^\s@]+\.[^\s@]{2,}$ | 请输入有效的邮箱地址。 | 同上，#errEmail |
| token | trim 后长度 ≥ 12 | 访问令牌至少需要 12 个字符。 | 同上，#errToken |

触发时机：blur 校验本字段；input 时先隐藏成功条，仅当该字段当前 aria-invalid=true 时才重校验（即出错后才实时纠错）；提交时三字段全量校验，焦点跳第一个非法字段并 return。

### 4.10 保存并验证（900ms）

| 阶段 | DOM 变化 |
|---|---|
| 提交合法 | #saveAccount disabled=true + aria-busy=true；#saveSpinner hidden=false；#saveLabel = 正在验证…；成功条先置 hidden |
| 900ms 后 | disabled=false；移除 aria-busy；spinner 隐藏；label 回 保存并验证；#accountSuccess hidden=false（stripIn）；#connectionMeta = 刚刚同步 · 示例工作区；#formNote = 刚刚验证；若不在刷新中则 #syncText = 刚刚同步；toast 连接成功，用量已同步 |

### 4.11 刷新（720ms）

| 阶段 | DOM 变化 |
|---|---|
| 点击 / ⌘R | 守卫 refreshBusy（重入直接 return）；#footRefresh aria-disabled=true + 加 .is-spinning（图标 700ms 线性无限旋转）；#popover aria-busy=true；#syncText 加 .is-syncing（圆点 syncPulse 900ms 无限）并置 正在同步… |
| 720ms 后 | 全部还原；#syncText = 刚刚同步；#connectionMeta = 刚刚同步 · 工作区名；toast 用量已更新 |

### 4.12 检查更新（1000ms）

| 阶段 | DOM 变化 |
|---|---|
| 点击 | updateBusy 守卫；#checkUpdate disabled=true + aria-busy=true；#updateSpinner 显示；#updateLabel = 检查中… |
| 1000ms 后 | 还原；#updateLabel = 检查更新；#updateStatus = 已是最新版本 · 2.4.1；toast 已是最新版本 |

### 4.13 导出 CSV

| 项 | 规格 |
|---|---|
| 触发 | #exportBtn 点击，立即执行，无 loading 态 |
| 生成 | BOM 前缀 + 行内逗号 join 后按换行 join；Blob 类型 text/csv;charset=utf-8; |
| 文件名 | corouter-usage-2026-11.csv（月份硬编码） |
| 成功 | toast 已导出近 7 天用量 CSV；1200ms 后 revokeObjectURL |
| 失败 | toast 当前环境无法下载文件 |

### 4.14 退出与重启

| 动作 | 变化顺序 |
|---|---|
| 菜单退出 CoRouter | closeAppMenu → closePopover(immediate) → cancelPendingWork（清 3 个定时器、复位刷新/保存/更新按钮与文案、#syncText 回 2 分钟前同步）→ 设置层若开着直接 hidden 并清定时器（无动画）→ toast 隐藏并清定时器 → #statusItem hidden=true → #quitLayer hidden=false → 焦点 #restartApp |
| 退出层键盘 | Tab 被拦截并强制回 #restartApp（全页唯一 Tab 陷阱） |
| 重新启动 | #quitLayer hidden=true → #statusItem hidden=false → positionPopover() → openPopover({focus:true}) |
| 原型缺口 | 退出是假退出，不做真实进程退出；原生应 NSApp.terminate 并删除整个 quit 层 |

### 4.15 环境与启动态

| 事件 | 行为 |
|---|---|
| 系统主题变化 | 仅当 prefs.theme = system 时重算 html[data-theme] |
| 窗口 resize | 面板开着则 positionPopover；菜单开着则 positionAppMenu |
| 时钟 | 每 30s 重算：M月D日 + 周X + HH:MM |
| 启动序列 | applyTheme → applyDisplay → syncControls → showPane('account') → updateClock → animateRingNumber → setInterval(30s) → positionPopover → rAF 再定位 → load 再定位 → 120ms 再定位（共 4 次，防字体加载抖动） |
| 偏好持久化 | localStorage 键 corouter.prefs.v1，9 个键；读入时做白名单与类型矫正（theme ∈ system/light/dark、display ∈ percent/icon、interval ∈ 5/15/30/60、threshold ∈ 50–100） |

---
## 5. 动画与时长

| 名称 | 时长 | 延迟 | 缓动 | 属性 / 关键帧 | 触发点 |
|---|---|---|---|---|---|
| popIn | 300ms | 0 | cubic-bezier(0.2, 0.9, 0.3, 1) | opacity 0 + translateY(-9px) scale(0.965) → none | 面板取消 hidden（每次打开） |
| popOut | 140ms | 0 | ease-in | none → opacity 0 + translateY(-6px) scale(0.98) | .is-closing（JS 145ms 后落 hidden） |
| menuIn | 150ms | 0 | cubic-bezier(0.2, 0.9, 0.3, 1) | opacity 0 + translateY(-4px) scale(0.97) → none；transform-origin top left | 应用菜单打开 |
| viewIn | 240ms | 0 | cubic-bezier(0.2, 0.9, 0.3, 1) | opacity 0 + translateY(4px) → none | .pop-view 每次显示（概览 ↔ 明细） |
| ringFill | 1100ms | 160ms | cubic-bezier(0.22, 1, 0.36, 1) | stroke-dashoffset 263.89 → 10.56 | 环首次绘制 |
| 环数字滚动 | 900ms | 200ms | 1-(1-p)³（JS rAF） | 0 → 96 整数 | 启动 |
| barIn | 850ms | 220ms | cubic-bezier(0.22, 1, 0.36, 1) | scaleX(0.02) → 1（origin left center） | 进度条（概览与明细各播一次） |
| barGrow | 620ms | 180ms + i×45ms（i=0..6 → 180 / 225 / 270 / 315 / 360 / 405 / 450） | cubic-bezier(0.22, 1, 0.36, 1) | scaleY(0.04) + opacity 0.4 → 1；transform-box fill-box；origin center bottom | 柱状图 |
| spin（一次性） | 650ms | 0 | linear | rotate 0→360；.icon-btn.is-spinning | 已定义，JS 未使用 |
| spin（加载） | 700ms | 0 | linear infinite | 同上；.btn-compact.is-spinning .od-icon 与 .spinner | 刷新 / 保存 / 检查更新 |
| syncPulse | 900ms | 0 | ease-in-out infinite | 50%：opacity 0.35 + scale(0.72) | .sync.is-syncing |
| toastIn | 220ms | 0 | cubic-bezier(0.2, 0.9, 0.3, 1) | translate(-50%, 8px) → (-50%, 0)，opacity 0→1 | 每次 toast |
| stripIn | 220ms | 0 | ease-out | opacity 0 + translateY(-3px) → none | 保存成功条 |
| 窗口层透明度 | 180ms | 0 | ease | opacity 0↔1（.window-layer / .is-open） | 设置窗口开合 |
| 窗口 transform | 260ms | 0 | cubic-bezier(0.2, 0.9, 0.3, 1) | translateY(12px) scale(0.985) → none | 同上 |
| 窗口 opacity | 200ms | 0 | ease | 0 → 1 | 同上 |
| 设置关闭延时 | 170ms | — | — | JS 定时器，与 180ms 过渡对齐 | closeSettings |
| 设置聚焦延时 | 150ms（reduced 20ms） | — | — | JS 定时器 | openSettings |
| toast 存活 | 2400ms | — | — | JS 定时器，重复触发会重置 | showToast |
| 关闭面板延时 | 145ms | — | — | JS 定时器（比 popOut 多 5ms 余量） | closePopover |

兜底：@media (prefers-reduced-motion: reduce) 下 animation-duration 0.01ms、animation-delay 0ms、iteration-count 1、transition-duration 0.01ms；JS 同步降级（关面板立即落 hidden、设置关闭 0ms、聚焦 20ms、环数字直出 96）。

---

## 6. 数据字段映射（接真实 API 的契约）

字段名是本规格定义的契约名；左列是原型里的呈现位置与原文。

### 6.1 状态项

| 位置 | 原型值 | 字段 | 格式化 |
|---|---|---|---|
| #statusPct | 96% | quota.fiveHour.remainingPct | 四舍五入整数 + "%" |
| 小环 arc offset | 1.58 | 同上派生 | 39.58 × (1 - pct/100)，保留两位 |
| aria-label | CoRouter，5 小时额度剩余 96%，点击查看套餐与用量 | 同上 + app.name | 模板：CoRouter，5 小时额度剩余 N%，点击查看套餐与用量；仅图标模式固定短句 |

### 6.2 概览页

| 位置 | 原型值 | 字段 | 格式化规则 |
|---|---|---|---|
| .brand-badge | Go | account.plan.name | 原样 |
| .plan-name | Go | account.plan.name | 原样 |
| .plan-status | 生效中 | account.plan.status | 枚举 → 生效中 / 已过期 / 试用中 |
| .price-num | $7 | account.plan.priceMonthly | "$" + 整数（无小数） |
| .price-unit | / 月 | — | 静态文案，随计费周期切换（月 / 年） |
| .plan-meta | 年付 $84 · 11月20日到期 | account.plan.billingCycle / annualTotal / renewAt | 周期文案 + 空格 + "$" + 整数 + " · " + M月D日 + "到期"；不显示年份 |
| .ring-num + .ring-pct | 96 / % | quota.fiveHour.remainingPct | 整数；环 offset = 263.89 × (1 - pct/100) |
| .ring-cap | 5 hour | — | 静态（固定 5 小时窗口） |
| .q-big（左） | 96% | quota.fiveHour.remainingPct | 整数 + "%" |
| .bar 宽度（左） | 96% | 同上 | 同值百分比 |
| .q-meta（左） | 2 小时 24 分后重置 | quota.fiveHour.resetAt | 距现在 < 24h："H 小时 M 分后重置" |
| .q-big（右） | 89% | quota.sevenDay.remainingPct | 整数 + "%" |
| .bar 宽度（右） | 89% | 同上 | 同值百分比 |
| .q-meta（右） | 4 天 10 小时后重置 | quota.sevenDay.resetAt | 距现在 ≥ 24h："D 天 H 小时后重置" |
| .quota-foot strong | $1.00 | credit.availableUsd | "$" + 两位小数（区别于套餐价的整数规则） |
| .quota-foot .muted | 可用 | credit.status | 枚举 → 可用 / 已用尽 |
| .chart-sub | 总计 522.32M · 日均 74.62M | usage7d.totalTokens / dailyAvgTokens | Token 缩写，见 6.6 |
| 柱 title / aria-label | 10月31日 · 48.2M Token | usage7d.days[].date / tokens | M月D日 + " · " + 缩写 + " Token" |
| 柱高 | 32/41/47/58/50/64/51 | 同上 | round(tokens/1e6 × 64 ÷ 97.8)；基线 y=94；x=16+48i |
| 柱标签 | 六 日 一 二 三 四 今 | days[].weekday / isToday | 单字周几；最后一天固定 今 |
| .chip | Token | — | 静态 |

### 6.3 明细页

| 位置 | 原型值 | 字段 | 格式化 |
|---|---|---|---|
| .detail-title p | 近 7 天 · 10月31日 – 11月6日 | days[0].date / days[n-1].date | "近 7 天 · " + M月D日 + " – " + M月D日（U+2013，两侧各一空格） |
| .chip | 7 天 | days.length | "N 天" |
| .detail-big | 522.32M | usage7d.totalTokens | Token 缩写 |
| .pct-pill | Design Plan | usage7d.billingSource | 原样（额度来源标签） |
| .detail-meta | 全部请求由 Design Plan 额度抵扣 | 同上 | 模板：全部请求由 SRC 额度抵扣 |
| .res-value 输入 | 517.91M | usage7d.inputTokens | Token 缩写 |
| .res-value 输出 | 4.4M | usage7d.outputTokens | Token 缩写（4.40 去尾零留 1 位） |
| .res-value 缓存读取 | 509.8M | usage7d.cacheReadTokens | Token 缩写 |
| .res-value 缓存写入 | 30.72K | usage7d.cacheWriteTokens | Token 缩写（K 档） |
| .act-badge | DS | requests[].provider | 2 字母大写缩写 |
| .act-name | deepseek-v4.1-flash | requests[].model | 原样 |
| .act-meta | 今天 08:43 · 输入 90,251 · 输出 1,881 | requests[].at / inputTokens / outputTokens | 时间：当天 今天 HH:mm，否则 M月D日 HH:mm；token 千分位逗号 |
| .act-points | −$0.0022 | requests[].costUsd | 负号（U+2212）+ "$" + 四位小数 |
| .act-tag | Design Plan | requests[].billingMode | 枚举 → Design Plan |

### 6.4 页脚与设置

| 位置 | 原型值 | 字段 | 格式化 |
|---|---|---|---|
| #syncText | 2 分钟前同步 | sync.lastSyncAt | 相对时间 + "同步"；< 60s → 刚刚同步；刷新中 → 正在同步… |
| #connectionMeta | 上次同步 2 分钟前 · 示例工作区 | sync.lastSyncAt / account.workspaceName | "上次同步 " + 相对时间 + " · " + 工作区名；同步后变 刚刚同步 · 工作区名（原型原值为英文 示例工作区） |
| .status-pill | 正常 | account.connectionState | 枚举 → 正常 / 异常 |
| #formNote | 上次验证：2 分钟前 | account.lastVerifiedAt | "上次验证：" + 相对时间；成功后 刚刚验证 |
| .mini-avatar | RY | account.user.initials | 2 字母大写 |
| .nav-foot-name | Ryan Y | account.user.displayName | 原样 |
| .nav-foot-plan | Go · 正常 | account.plan.name + connectionState | 套餐 · 状态 |
| #aboutInterval | 15 分钟 | settings.interval | "N 分钟" |
| .version-pill | 版本 2.4.1 (2400) | app.version / app.build | 版本 semver (build) |
| #updateStatus | 上次检查：1 小时前 | update.lastCheckedAt | "上次检查：" + 相对时间；完成后 已是最新版本 · 版本号 |
| .about-facts | 仅菜单栏 / 15 分钟 / 仅本机 | 静态 + settings.interval | 同步间隔行随 interval 变化 |
| .copyright | © 2026 CoRouter | app.copyrightYear | © 年份 应用名 |

### 6.5 偏好契约（localStorage → UserDefaults）

| 键 | 类型 | 默认 | 取值域 |
|---|---|---|---|
| theme | string | system | system / light / dark |
| display | string | percent | percent / icon |
| launchAtLogin | bool | true | — |
| autoRefresh | bool | true | — |
| interval | string | "15" | "5" / "15" / "30" / "60" |
| usageAlert | bool | true | — |
| threshold | number | 80 | 50–100，步进 5 |
| renewalReminder | bool | true | — |
| weeklyDigest | bool | false | — |

### 6.6 格式化规则汇总

| 规则 | 定义 |
|---|---|
| 百分比 | 四舍五入为整数 + "%"；进度条宽度、环 offset、状态项文本、环内数字全部由同一整数派生（禁止各自取值） |
| Token 缩写 | t ≥ 1e6 → (t/1e6) 最多 2 位小数、去尾零但至少留 1 位（522.32M / 517.91M / 4.4M / 509.8M）；1e3 ≤ t < 1e6 → 同规则 + "K"（30.72K）；否则原样 |
| 千分位 | 面板请求明细分词用英文逗号（90,251 / 1,881）；CSV 内为裸数字（90251 / 1881） |
| 金额-套餐 | "$" + 整数（$7、$84） |
| 金额-余额 | "$" + 两位小数（$1.00） |
| 金额-单次消耗 | 负号 U+2212 + "$" + 四位小数（−$0.0022、−$0.0018） |
| 倒计时 | ≥ 24h → "D 天 H 小时后重置"；< 24h → "H 小时 M 分后重置"；为 0 的单位是否省略原型未覆盖，需在下游接口文档固定 |
| 到期日 | "M月D日到期"，不带年份 |
| 相对时间 | < 60s → 刚刚；< 60min → N 分钟前；< 24h → N 小时前；否则 N 天前 |
| 日期区间 | 近 7 天 · 10月31日 – 11月6日（en dash，两侧空格） |
| 星期 | 单字：日 / 一 / 二 / 三 / 四 / 五 / 六；当日写 今 |

### 6.7 CSV 契约

| 项 | 值 |
|---|---|
| 文件名 | corouter-usage-2026-11.csv |
| 编码 | UTF-8 + BOM；换行 LF；逗号分隔；无引号转义 |
| 表 1 表头 | 日期,Token 消耗 |
| 表 1 行 | 2026-10-31,48200000 / 2026-11-01,62400000 / 2026-11-02,71600000 / 2026-11-03,88100000 / 2026-11-04,76500000 / 2026-11-05,97800000 / 2026-11-06,77720000 |
| 分隔 | 一个完全空行 |
| 表 2 表头 | 结算时间,发起人,模型,输入 Token,输出 Token,缓存读取,缓存写入,消耗额度 (USD),抵扣方式 |
| 表 2 行 × 3 | 2026-11-06 08:43,示例用户,deepseek-v4.1-flash,90251,1881,89472,,-0.0022,Design Plan 额度抵扣；同结构 89520 / 682 / 88992 / -0.0018；88257 / 1248 / 87680 / -0.0022 |
| 空列 | 缓存写入列恒为空字符串 |
| 符号差异 | 面板用 U+2212 与 $，CSV 用 ASCII 连字符 "-" 且不带 $ |

---
## 7. 「桌面模拟」与真实 App 的差异清单

### 7.1 必须删除（纯模拟层）

| 元素 | 位置 | 处理 |
|---|---|---|
| div.wallpaper（含 ::before 模糊层、::after 噪点） | L184 | 删除；背景由桌面提供 |
| header.menubar 整条（30px、blur、底色） | L213 | 删除；系统菜单栏由 macOS 渲染 |
| span.apple | L1453 | 删除；不自绘系统图标 |
| span.mb-item × 5（文件 / 编辑 / 显示 / 窗口 / 帮助） | L1460 | 删除；不属于本 App 菜单 |
| span.mb-glyph.control / .wifi / 电池 | L1475–L1490 | 删除 |
| span#menuClock（含 30s 定时器） | L1491 | 删除；用系统时钟 |
| 应用下拉的锚定逻辑（top 33 / left 54 / 248 宽） | L2320 | 删除；改由 NSMenu 系统定位 |
| .window-layer 全屏遮罩 + 居中 | L858 | 删除；设置改独立 NSWindow，无遮罩 |
| .traffic 三个假红绿灯（含 .tl-red 点击关闭） | L903–L913 | 删除；用 NSWindow 标准按钮 |
| div#quitLayer + #restartApp + Tab 陷阱 | L2008 | 删除；退出即 NSApp.terminate |
| .toast 的 fixed bottom 28px 定位 | L1293 | 保留浮层则改为跟随面板窗口 |
| 6 组响应式断点（860 / 720 / 600 / 520 / 380 / 340）与 is-compact 分支 | L1354–L1434 | 删除；原生面板固定 392 宽、窗口固定 792×632（或设 minSize） |
| body 背景 #08110F、html/body height 100%、overflow hidden、.stage fixed | L145–L182 | 删除；WebView 透明承载 |
| localStorage 键 corouter.prefs.v1 | L2098 | 改 UserDefaults（同结构可直接迁移） |

### 7.2 必须映射到系统能力

| 原型元素 | 原生实现 |
|---|---|
| button#statusItem（23px 高、圆角底、hover 底） | NSStatusItem（variable length）+ NSStatusBarButton；自绘 template NSImage（环 + 可选百分比文本），随菜单栏外观自动反色；hover / 按下态由系统提供，删除自定义背景 |
| .status-ring 环形 | 与状态项同一个 NSImage 绘制；aria-label 映射 accessibilityLabel |
| #appMenu 下拉（248 宽、12 圆角、blur、分隔线、⌘, ⌘R ⌘Q） | NSMenu + NSMenuItem，keyEquivalent 分别 ","、"r"、"q"；分隔用 NSMenuItem.separator()；应用主菜单挂 NSApp.mainMenu |
| #popover（392 宽、26 圆角、caret 指状态项） | NSPanel；锚点由 statusItem.button 的 window 坐标转换得到，注意屏幕坐标原点在左下需翻转 y。**【02 spike 定案】用自定义 NSPanel，不用 NSPopover——后者无法定制 26pt 圆角与箭头几何** |
| caret 三角与 --caret-x 算法 | 删除 CSS 版；由原生 maskImage 按同一几何绘制（菱形底宽 19.8 / 高 9.9），caret 位置 = clamp 后状态项中心 |
| .app-window（792×632、圆角 20、红绿灯、标题「设置」） | NSWindow，styleMask [.titled, .closable, .miniaturizable]，title 为「设置」；圆角 / 阴影 / 红绿灯全交系统；可保留 fullSizeContentView 让内容顶到标题栏 |
| .window-bar 46px + 居中标题 | 系统 titlebar（约 28pt），需要 46px 视觉高度则用 titlebar accessory 或 toolbar |
| .window-layer 的 is-open / is-closing 动画 | NSWindow orderFront / orderOut 或 alphaValue 渐变 |
| 菜单「退出 CoRouter」 | NSApp.terminate(nil) |
| 红灯关闭设置 | performClose: |
| ⌘R / ⌘, | NSMenuItem keyEquivalent（系统级，不依赖 WebView 键盘监听） |
| ⌘Q | 标准应用菜单项指向 terminate: |
| prefers-color-scheme + data-theme | NSApp.effectiveAppearance / KVO；WebView 侧用 prefers-color-scheme 或注入变量 |
| prefers-reduced-motion | NSWorkspace.shared.accessibilityDisplayShouldReduceMotion |
| .select 自定义箭头 | NSPopUpButton（删 background-image 箭头） |
| .range 滑块 | NSSlider（保留 HTML range 则外观与系统不一致） |
| .switch 38×22 | NSSwitch（尺寸接近，动画由系统控制）或自绘按钮 |
| 表单校验与报错 | 保留 HTML 校验逻辑；原生控件化则用 NSFormatter + 内联错误文案 |
| 导出 CSV（a[download] + Blob） | NSSavePanel + 写文件；默认名 corouter-usage-YYYY-MM.csv |
| toast | 面板内浮层或 NSPanel；系统级提醒走 UNUserNotificationCenter（对应「通知」页三个开关的真实语义） |
| 时钟 / 系统图标 / 壁纸 | 全部由系统提供 |

### 7.3 保留但需改造

| 元素 | 改造要点 |
|---|---|
| 概览页 / 明细页结构 | 可 1:1 保留；392 固定宽下无需任何响应式规则 |
| 设置四页 | 侧栏 196px + 内容区可保留；macOS 惯例多用 NSToolbar 分页，坚持侧栏需自绘并避开系统 sidebar 材质 |
| --line / --line-strong | 映射 NSColor.separatorColor（自动适配明暗与强调色） |
| 主色 #0E7C63 | 想随系统强调色则用 NSColor.controlAccentColor，否则固定品牌色 |
| 全部内联 SVG 图标（1.5–2px 描边） | 换 SF Symbols：gearshape、chevron.left/right、arrow.clockwise、checkmark.circle、exclamationmark.circle、bell 等 |
| 数字字体 ui-rounded | 改显式 SF Pro Rounded 或 SF Pro Text + tabular figures，见 §8 |

---

## 8. 视觉风险点（WKWebView + NSVisualEffectView）

| # | 风险 | 涉及样式 | 失真表现 | 调整方向 |
|---|---|---|---|---|
| 1 | 双层模糊叠加 | .popover blur(36px) saturate(1.55)、.app-menu blur(34px)、.menubar blur(30px) | 面板若放在 NSVisualEffectView 上，WebView 再糊一遍：背景被糊两次、边缘发灰、saturate 叠加偏色 | 只留一层：NSVisualEffectView 出材质 + WebView 透明并删 backdrop-filter；或 WebView 全权自绘 + 底层用不透明 NSView |
| 2 | 面板底色几乎不透明 | --panel rgba(...,0.95)（明暗两套） | 95% 不透明配 36px 模糊收益极低，却让 5% 底层色透上来，深色下文字对比度不稳 | 改不透明实色，或降到 0.72–0.80 并配合 vibrancy 材质；不要停在 0.95 这种中间值 |
| 3 | 阴影叠加 | --shadow-pop / --shadow-window 各三段，第三段是 0 0 0 0.5px 描边环 | 系统弹窗 / 窗口已有阴影，再叠 CSS 阴影出现双影；0.5px 环在 Retina 上呈半物理像素脏边 | 窗口级阴影交系统；CSS 只留内阴影（如 inset 0 1px 0 高光）；删 0.5px 环，改 1px hairline 或系统 separator |
| 4 | 亚像素描边 | 0.5px（.tl）、非整数缩放下 1px border | 边框发虚、深浅不一，缩放窗口时抖动 | 统一 1 物理像素（除以 backingScaleFactor）或取消边框靠间距分隔 |
| 5 | ui-rounded 字体 | --font-num: ui-rounded, "SF Pro Rounded", … | WKWebView 支持 ui-rounded，但中文数字混排回退 PingFang；SF Pro Rounded 600 在 27px / 11.5px 上偏粗；tabular-nums 在圆体下等宽不完整 | 数字统一 SF Pro Rounded（显式 PostScript 名），中文走 PingFang SC；≤ 11.5px 改 SF Pro Text；保留 font-variant-numeric: tabular-nums |
| 6 | 负字距 | -0.035em / -0.03em / -0.025em / -0.02em | WKWebView 与 NSAttributedString 字距算法不同，换实现后排版位移；小字号中文可能粘连 | 只对纯数字 / 拉丁文本保留负字距，中文段落（pane-sub、help、setting-help）清零 |
| 7 | 极小色点 | 4.5px / 5.5px / 6px 圆点（plan-status、status-pill、sync、q-dot） | 1x 外接屏上退化成方块或消失 | 小于 8px 的元素改 SVG 或加 translateZ(0)；或统一放大到 ≥ 6px |
| 8 | 噪点混合模式 | .wallpaper::after mix-blend-mode: overlay + opacity 0.055 | 让整个 WebView 建额外合成层，滚动 / 动画掉帧；截图带脏点 | 随壁纸一起删除 |
| 9 | 大半径 filter | .wallpaper::before filter blur(4px)（520×380、700×520 两个径向渐变） | GPU 显存与首帧成本，WKWebView 首屏白闪 | 删除 |
| 10 | 100vh 与安全区 | .popover max-height calc(100vh - 54px)、.window-layer inset 30px、.app-window height min(632px, 100vh - 84px) | WKWebView 中 100vh 与窗口内容高度不一致（全屏 / 刘海屏），面板被裁或空出滚动 | 高度改由 NSPopover contentSize 或 innerHeight 计算；删 CSS 兜底避免与 JS 覆写打架 |
| 11 | caret 与 transform-origin | ::before 三角 + transform-origin var(--caret-x) 0 | 缩放 / 滚动时三角与面板边缘错位；暗色下三角描边色不一致 | 原生用 NSPopover 箭头，整套删除 |
| 12 | 动画节流 | ringFill 1100ms、barIn 850ms、7 柱 stagger 至 450ms 延迟、数字滚动 900ms | 窗口失焦时 WKWebView 降帧，动画卡一半；NSPopover 打开动画可能被打断 | 打开动画缩到 180–220ms；环 / 柱改一次性绘制；数字滚动仅在可见时执行 |
| 13 | 描边叠三层 | 卡片 border 1px + 0 0 0 0.5px 环 + 内高光 | 深色主题下边线呈两层，"发毛" | 每张卡片只留一层边界（border 与内高光二选一） |
| 14 | 硬编码色绕过主题 | #F3FAF6、#0E4337、#9AE6CB、红绿灯色、toast 色 | 切到深色时这些块不跟随，出现深色页面里的亮绿卡片 | plan-card 深绿是品牌色可保留；其余（尤其 #FFFFFF 系文字）按 appearance 出两套 |
| 15 | 字体平滑 | body 的 -webkit-font-smoothing: antialiased | 深色底上 400 / 11px 细体发灰变糊，与 NSFont 渲染不一致 | 删该属性交给 WebKit 默认，或仅浅色主题启用 |
| 16 | 96% 三处冗余 | 状态项、环、左进度条各显示一次 | 数据不同源时自相矛盾（环动画到 96 而文本已变 95） | 单一数据源 + 单一格式化函数；动画只做视觉插值，终值必须与文本一致 |

---

## 9. 验收断言（可直接转测试用例）

| # | 断言 |
|---|---|
| A1 | 视口 ≥ 520 时面板宽恒为 392px、圆角 26px，caret 尖端水平对齐状态项中心 ±1px |
| A2 | 面板顶部 = max(38, 状态项底边 + 10)，高度不低于 240px，且不超出视口底部 16px |
| A3 | 状态项文本、环 offset、左进度条宽度、环内数字四者来自同一整数 |
| A4 | 环 offset = 263.89 × (1 - pct/100)，误差 ≤ 0.01 |
| A5 | 柱状图满足 x = 16 + 48i、width 24、y + height = 94、height = round(v × 64 / 97.8) |
| A6 | 打开播放 popIn 300ms；关闭加 .is-closing 且 145ms 后 hidden，焦点回状态项 |
| A7 | ESC 关闭优先级严格为 菜单 → 面板 → 设置；退出层打开时 ESC 无效 |
| A8 | ⌘R 任意状态可刷新，重复触发被 refreshBusy 吞掉，720ms 后文案变 刚刚同步 |
| A9 | 概览 ↔ 明细切换后滚动归零，焦点分别落在返回键 / 入口键 |
| A10 | 三条校验失败文案与原型逐字一致；提交时焦点跳第一个非法字段 |
| A11 | 保存期间按钮 disabled + aria-busy，900ms 后恢复并显示成功条 |
| A12 | 检查更新 1000ms 后状态文案为 已是最新版本 · 2.4.1 |
| A13 | 导出文件名 corouter-usage-2026-11.csv，首字节为 BOM，两表之间恰好一个空行 |
| A14 | 9 项偏好重启后保持（键 corouter.prefs.v1） |
| A15 | 仅图标模式下不显示百分比但环形仍在，aria-label 切到短句 |
| A16 | prefers-reduced-motion 下所有动画 ≤ 0.01ms，环数字直出终值 |
| A17 | 设置窗口 792×632、侧栏 196px；四页切换时仅一个 pane 可见且 nav 只有一项带 aria-current |
| A18 | 退出后状态项消失、定时器全清、按钮文案复位；重启后面板恢复展开态 |
