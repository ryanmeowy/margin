# 02 · macOS 原生外壳 spike 结论

只回答 5 个问题，全部在 macOS 15.7.7 / arm64 / 仅 CLT / swiftc 6.1.2 上实测。代码在
[spike/](../spike/main.swift)（单文件 337 行，无第三方依赖），原型 CSS 用 [extract.py](../spike/extract.py)
整段抄进自包含 [web/panel.html](../spike/web/panel.html)，只保留 `.popover` 子树，body 透明。

复现：

```bash
cd opendesign-usage/spike && ./build.sh          # swiftc + 拼 .app + ad-hoc 签名，~2.1s
SPIKE_SHOW=1 SPIKE_DUMP=/tmp/d.json ./build/CoRouterSpike.app/Contents/MacOS/CoRouterSpike
# 关键环境变量：SPIKE_OPAQUE / SPIKE_KVC=0 / SPIKE_UNDERPAGE=0 / SPIKE_BF=1 / SPIKE_BACKDROP=#D81B60
```

数字：面板 **392×694pt**（内容 693 + 箭头 10 取整，上限 720）；WebView 加载 **336–376ms**，
进程起→面板可显示 **339–342ms**，`open` → 进程存在 **84ms**；.app **236KB**（可执行 168KB），
主进程 RSS **≈105MB**（含共享的 AppKit/WebKit 页，WebContent 是子进程另计）。

---

## A. 透明 WKWebView —— 成立，但必须用 KVC 关 `drawsBackground`（有私有 API 风险）

四组对照，垫一层纯色窗口(#D81B60)后抓屏取样：

| 组合 | 面板底色像素 | 圆角外 alpha |
|---|---|---|
| CSS 全透明 + 不关 KVC + 不设 underPageBackgroundColor | (30,30,30) 不透明 | **255 不透明**（白/灰底连圆角都盖住了）|
| CSS 全透明 + 只设 `underPageBackgroundColor = .clear` | (30,30,30) 不透明 | 255 |
| CSS 全透明 + 只关 KVC | 透出材质 | 0 ✅ |
| CSS 全透明 + KVC + underPageBackgroundColor | 透出材质 | 0 ✅ |

`underPageBackgroundColor` 是公开 API 但只管「页面下方回弹区」，**文档底色压不住**；真正起作用的是
KVC。HTML 侧还必须 `html,body{background:transparent}`（原型 `body{background:#08110F}` 要覆盖）。

```swift
web.setValue(false, forKey: "drawsBackground")   // 关键；KVC 访问私有属性
web.underPageBackgroundColor = .clear           // 公开 API，但这组实验里它单独不够
panel.isOpaque = false; panel.backgroundColor = .clear
```

**风险**：`drawsBackground` 是 WKWebView 私有属性，KVC 字符串在运行时解析，App Store 审核与未来
系统升级都可能出问题。要兜底就判 `web.responds(to: NSSelectorFromString("drawsBackground"))`，
失败时退回「不透明面板 + CSS 自己画底色」。

## B. 26pt 圆角 + 箭头 mask —— 轮廓成立；**系统投影没拿到**

`NSVisualEffectView.maskImage` 画一把路径：26pt 圆角矩形 + 顶部菱形（原型 `.popover::before` 是
14×14 方块转 45°，实际可见底宽 ≈19.8pt、高 ≈9.9pt，我按这个几何还原，见
[spike-panel.png](spike-panel.png)）。窗口 `hasShadow = true`，但**实测没有投影**：在纯色垫底上沿面板
左边缘向外扫 36pt，像素恒定 (197,49,97)→(197,49,97)，1/255 的差都不到；换到真实桌面同样只有 1–2px
的描边暗边。可能原因是 borderless + 全透明窗口 + mask 三者叠加时 window server 不生成阴影，或
`addChildWindow(ordered:.below)` 的垫底窗口压住了阴影。生产要么自绘（host view 的 layer.shadowPath
用同一条路径），要么直接用 NSPopover 的 chrome。

```swift
func shapePath(_ s: NSSize, caret: CGFloat) -> NSBezierPath {
    let bodyH = s.height - ARROW                      // ARROW = 10
    let p = NSBezierPath(roundedRect: .init(x: 0, y: 0, width: s.width, height: bodyH),
                         xRadius: 26, yRadius: 26)
    p.append(diamond(center: (caret, bodyH), half: 9.9))  // 与 .popover::before 同几何
    return p
}
effect.maskImage = mask(size:caret:)   // 同一路径画成白色 mask 图
```

注意 **`maskImage` 不裁剪子视图**：想在材质上压一层底色，得自绘（`TintView.draw` 用同一条路径），
否则那层色会铺满整个矩形窗口、把箭头区域一起涂掉。

## C. NSPanel 行为 —— 全部成立

`[.borderless, .nonactivatingPanel]` + 子类 `canBecomeKey = true`：

- **成为 key**：`isKeyWindow = true`，`firstResponder = WKWebView`；
- **能输入**（真键盘，不是合成事件）：AX 已授权的机器上用 `osascript ... keystroke "abc"`，Web 里
  `keydown` 依次收到 `a`/`b`/`c`；
- **不抢焦点**：同一时刻系统前台应用仍是 Google Chrome（`osascript` 与 `NSWorkspace` 双重确认）；
  只有 `NSApp.isActive` 在 accessory 应用里会瞬时变 true，前台应用本身没换；
- **ESC 关闭**：`NSEvent.addLocalMonitorForEvents(matching: .keyDown)` 里判 `keyCode == 53`；
- **点外面关闭**：`NSWindow.didResignKeyNotification` 里关（真实鼠标点击面板外实测触发
  `PANEL_RESIGN_KEY → CLOSED`，`addGlobalMonitorForEvents` 也会触发，但它是兜底）；
- **对齐**：面板顶 = `screen.visibleFrame.maxY`（屏 1920×1080，菜单栏 25pt，实测面板顶正好压在
  菜单栏下沿）；x 先按 `状态项中心 − 300` 摆，再 clamp 进 `visibleFrame`，caret 用 clamp 后的实际值
  反推，屏幕边缘不会把箭头挤歪。

```swift
final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
panel = Panel(contentRect: r, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.level = .statusBar
```

## D. `-webkit-backdrop-filter` —— 生效但是**空转**，不糊白；建议删

`getComputedStyle(...).backdropFilter` 返回 `blur(36px) saturate(1.55)`（WebKit 认这条），但同一画面
开/关两次抓屏**逐像素完全相同**（面板底色、卡片、按钮取样点全等）。原因很简单：backdrop-filter 只能
糊「Web 内容里该元素背后的东西」，而面板的 Web 内容背后是透明窗口，没有可采样的层——它压根看不到桌面
和系统材质。既不会糊白/灰，也没有任何收益，只多一个合成层。

**建议：删掉 `.popover` 上的 backdrop-filter**，透感只靠 NSVisualEffectView；两份都留着的项目里，用
`navigator.userAgent`/宿主注入的标记在原生壳里关掉它。

## E. 手工 .app —— 双击/open 都能起，菜单栏图标正常

只用 CLT，不碰 xcodebuild：

```bash
mkdir -p CoRouterSpike.app/Contents/{MacOS,Resources}
cp Info.plist  CoRouterSpike.app/Contents/Info.plist
cp web/panel.html CoRouterSpike.app/Contents/Resources/
swiftc -O main.swift -o CoRouterSpike.app/Contents/MacOS/CoRouterSpike -framework AppKit -framework WebKit
codesign --force --deep --sign - CoRouterSpike.app
```

Info.plist 必须有 `LSUIElement=1`（不占 Dock）、`CFBundleExecutable`、`NSPrincipalClass=NSApplication`；
补 `CFBundleIdentifier/CFBundlePackageType=APPL/LSMinimumSystemVersion`。`codesign --verify` 通过
（ad-hoc，「valid on disk / satisfies its Designated Requirement」）。`open build/CoRouterSpike.app`
→ 84ms 进程起来、菜单栏出现 `chart.pie.fill` 图标（与退出后截图逐像素 diff 确认是我们的）。
构建 2.1s，产物 236KB，无 xattr 隔离属性，所以不弹 Gatekeeper。

---

## 面板底色为什么是「中灰 + 近黑卡片」（Lead 问的 #2）

看到的中灰来自 **`screencapture -l <windowid>` 这个抓法本身**，不是渲染问题：
`.behindWindow` 材质是 window server 合成时采样的，单窗口截图拿不到背后，于是被渲染成材质的兜底
纯色。同一个窗口换三种材质抓出来分别是 popover **102,102,101**、sidebar 74、hudWindow 131——
三块死色，证明是截图伪影。改用**整屏截图再裁**，同一面板在洋红垫底上是 `(127,35,71)`，明显带底色
色调；换蓝色垫底是 `(30,41,48)`。所以材质透光是真的，只是 `-l` 看不出来。

`:root` 变量一个都没丢（`--panel: rgba(249,251,249,.95)` / 暗色 `rgba(24,30,27,.95)` 都在
`[data-theme="dark"]` 里，JS 按 `prefers-color-scheme` 打的标记也生效）。我那张 95% 底色的基线截图
里量到的面板底色是 `(29,33,31)`，正好等于 `0.95×(24,30,27) + 0.05×材质(102)` —— **95% 底色没被
材质压成灰，它本来就是这个色**。中灰只出现在我把 CSS 底色关掉（`background: transparent`）做问题 A
对照的那几张。

**结论（实测对比，不建议再验证）**：95% 底色 + 材质 = 几乎等于不透明（5% 的透光肉眼区分不出来，
差 1–2 个色阶）。要么

1. **要原生质感**：保留 NSVisualEffectView，但把底色降到 **~78%**（我在 `TintView` 里用的值），
   此时洋红垫底会明显透上来（`(48,31,37)` 对比 95% 时的 `(29,33,31)`），且文字对比度仍然够；
2. **要像素级还原原型**：直接不透明面板，把 NSVisualEffectView 去掉——少一层合成、少一个
   `maskImage`、也不吃私有 API；代价是系统浅色/深色切换时底色要自己跟。

我推荐 **1**：材质保留带来的好处是窗口边角、描边和系统外观跟随都免费，78% 是个能两全的值。

## 面板高度自适应用什么信号（Lead 问的 #3）

`document.body.getBoundingClientRect().height`，**配 `setTimeout` 而不是 `requestAnimationFrame`**。
我第一版用 rAF 测量，面板永远不出现：面板此时还没 orderFront，WKWebView 是离屏的，**rAF 被节流不
触发**（这是踩过的坑，写进文档）。scrollHeight 也能用，但它把 html/body 的 margin、滚动容器溢出一并
算进来，容易多出几像素；`getBoundingClientRect().height` 给的是 `#popover` 自己的布局高，加箭头
预留 10pt 就是窗口高，693 精确复现。

更稳的是**双通道**：HTML 里 `setTimeout(measure, 60)` 发一次，原生侧 `didFinish` 里再
`evaluateJavaScript` 量一次兜底（我两个都留了，原生那次先到）。明细页/设置页更高时，在页面切换后
再发一次同样的消息，原生按 `min(h, 720)` 收口、超出部分交给 `.pop-body` 自己滚。

```js
const measure = () => post({h: Math.ceil(popover.getBoundingClientRect().height + 10)});
setTimeout(measure, 60);              // 不能用 rAF：离屏 WKWebView 会节流
```

## 生产结构建议

```
NSStatusItem
└─ NSPanel [.borderless,.nonactivatingPanel], level .statusBar, isOpaque=false
   └─ NSVisualEffectView(.popover, .behindWindow, .active)  ← maskImage = shapePath（圆角+箭头）
      ├─ TintView  同一条路径自绘 78% 底色（maskImage 不裁子视图，必须自绘）
      └─ WKWebView 铺满窗口；html/body 透明；drawsBackground=false（KVC，带 responds 兜底）
```

- 面板高度只由 JS 报数决定，原生 `min(h,720)`，超出滚动；
- 关面板只认 `didResignKey`（点到别的 App/桌面都会 resign），ESC 走 local monitor；
- 底色、圆角、箭头全部**只在一处定义**（Swift 里那条 `shapePath`），CSS 不再画圆角/箭头/投影，避免
  两套几何打架；
- 主题跟随：暗色用 `effect.effectiveAppearance` 判断，别在 CSS 里硬编码深色底。

## 还剩什么风险

1. **`drawsBackground` 是私有 KVC** —— 唯一挡路的点。上架有审核风险；系统升级可能失效。兜底方案：
   检测不到就退回不透明面板。
2. **窗口投影没拿到**（B），实际观感比原生 popover 平。可以直接自绘 `layer.shadowPath`，或换
   NSPopover（但 NSPopover 的形状/箭头不可定制，和 26pt + 自定义箭头冲突）。
3. **`maskImage` 在 Retina 上的边缘**：截图看圆角是干净的，但没在非 Retina/多显示器缩放组合下验证。
4. **多屏**：`NSScreen.main` ≠ 状态项所在屏，必须用 `statusItem.button.window.screen`（我第一版就栽在
   这，面板跑到了另一块屏）。
5. **本机是深色模式**，浅色模式只用 CSS `[data-theme=light]` 逻辑保证，没实机截过图。
