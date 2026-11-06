import AppKit
import WebKit

// 最小 spike：NSStatusItem + 无边框 NSPanel + NSVisualEffectView(mask) + 透明 WKWebView。
// 全部行为由环境变量驱动，方便脚本化取证，见 README/02-native-spike.md。
let env = ProcessInfo.processInfo.environment
func flag(_ k: String, _ d: Bool = false) -> Bool {
    guard let v = env[k] else { return d }
    return v == "1" || v == "true" || v == "yes"
}
let t0 = Date()

let PANEL_W: CGFloat = 392
let ARROW: CGFloat = 10        // 窗口顶部为箭头预留的高度（14×14 方块旋转 45° 的半对角线 ≈ 9.9）
let ARROW_HALF: CGFloat = 9.9
let RADIUS: CGFloat = 26
let MAX_H: CGFloat = 720

final class FlipView: NSView { override var isFlipped: Bool { true } }

/// 26pt 圆角矩形 + 顶部菱形箭头（14×14 方块旋转 45°，与原型 .popover::before 同几何）
func shapePath(_ size: NSSize, caret: CGFloat) -> NSBezierPath {
    let bodyH = size.height - ARROW
    let p = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size.width, height: bodyH),
                         xRadius: RADIUS, yRadius: RADIUS)
    let cy = bodyH, h = ARROW_HALF
    let d = NSBezierPath()
    d.move(to: NSPoint(x: caret, y: cy + h))
    d.line(to: NSPoint(x: caret + h, y: cy))
    d.line(to: NSPoint(x: caret, y: cy - h))
    d.line(to: NSPoint(x: caret - h, y: cy))
    d.close()
    p.append(d)
    return p
}

/// 底色层。NSVisualEffectView.maskImage 不会裁剪子视图，所以这块自己画同一个形状。
final class TintView: NSView {
    var caret: CGFloat = 300
    var color: NSColor = .clear
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        shapePath(bounds.size, caret: caret).fill()
    }
}

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

final class App: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    var statusItem: NSStatusItem!
    var panel: Panel!
    var effect: NSVisualEffectView!
    var tintView: TintView!
    var web: WKWebView!
    var backdrop: NSWindow?
    var contentH: CGFloat = 560
    var panelH: CGFloat = 560
    var shown = false
    var closing = false
    var loadMs = 0.0, readyMs = 0.0
    var caret: CGFloat = 300
    var keyTest = ""
    var screenRect = NSRect.zero

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let img = NSImage(systemSymbolName: "chart.pie.fill", accessibilityDescription: "CoRouter")
        img?.isTemplate = true
        statusItem.button?.image = img
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        statusItem.button?.toolTip = "CoRouter 用量 spike"

        if let hex = env["SPIKE_BACKDROP"] { makeBackdrop(hex) }
        buildPanel()

        if flag("SPIKE_SHOW") { pendingShow = true }
        if let s = env["SPIKE_EXIT"], let sec = Double(s) {
            DispatchQueue.main.asyncAfter(deadline: .now() + sec) { NSApp.terminate(nil) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            log("FRONTMOST_AFTER_3S \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
        }
    }

    var pendingShow = false

    func makeBackdrop(_ hex: String) {
        // 纯色垫底窗口：给透明/材质测试一个确定颜色（截图后像素取样用）
        var v: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        let c = NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
                        blue: CGFloat(v & 255) / 255, alpha: 1)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 800),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.backgroundColor = c
        w.isOpaque = true
        w.level = .normal
        w.collectionBehavior = [.canJoinAllSpaces]
        backdrop = w
    }

    func buildPanel() {
        panel = Panel(contentRect: NSRect(x: 0, y: 0, width: PANEL_W, height: panelH),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.becomesKeyOnlyIfNeeded = false

        let root = FlipView(frame: NSRect(x: 0, y: 0, width: PANEL_W, height: panelH))
        root.autoresizingMask = [.width, .height]

        effect = NSVisualEffectView(frame: root.bounds)
        let mats: [String: NSVisualEffectView.Material] = ["popover": .popover, "sidebar": .sidebar, "hud": .hudWindow,
            "menu": .menu, "underWindow": .underWindowBackground, "content": .contentBackground, "headerView": .headerView]
        effect.material = mats[env["SPIKE_MATERIAL"] ?? "popover"] ?? .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        root.addSubview(effect)

        // 底色层：放在材质之上、Web 之下，这样面板主体和箭头(mask 出来的那块)是同一个颜色。
        // 放 CSS 里给 .popover 上底色的话，箭头区域只有材质、会浅一块。
        let tint = TintView(frame: effect.bounds)
        tint.autoresizingMask = [.width, .height]
        let dark = effect.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        tint.color = flag("SPIKE_NOTINT") ? .clear : (dark ? NSColor(srgbRed: 24 / 255, green: 30 / 255, blue: 27 / 255, alpha: 0.78)
                                                        : NSColor(srgbRed: 249 / 255, green: 251 / 255, blue: 249 / 255, alpha: 0.78))
        tintView = tint
        root.addSubview(tint)

        let cfg = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        ucc.add(self, name: "spike")
        cfg.userContentController = ucc
        cfg.suppressesIncrementalRendering = false

        web = WKWebView(frame: root.bounds, configuration: cfg)
        web.navigationDelegate = self
        web.autoresizingMask = [.width, .height]
        web.allowsMagnification = false
        // 问题 A 的三个手段：KVC 关闭绘制底色（有私有 API 依赖风险）、公开 API underPageBackgroundColor
        if flag("SPIKE_KVC", true) { web.setValue(false, forKey: "drawsBackground") }
        if flag("SPIKE_UNDERPAGE", true) { web.underPageBackgroundColor = .clear }
        if !flag("SPIKE_NOWEB") { root.addSubview(web) }   // 隔离实验：只留材质层
        panel.contentView = root

        var url = Bundle.main.url(forResource: "panel", withExtension: "html")
        if let p = env["SPIKE_HTML"] { url = URL(fileURLWithPath: p) }
        var qs = ""
        if flag("SPIKE_OPAQUE") { qs = "?opaque=1" }
        if flag("SPIKE_BF") { qs = (qs.isEmpty ? "?" : "&") + "bf=1" }
        if flag("SPIKE_CLEAR") { qs = (qs.isEmpty ? "?" : "&") + "clear=1" }
        var comps = URLComponents(url: url!, resolvingAgainstBaseURL: false)!
        if !qs.isEmpty { comps.query = String(qs.dropFirst()) }
        web.loadFileURL(url!, allowingReadAccessTo: url!.deletingLastPathComponent())
        if !qs.isEmpty {
            web.load(URLRequest(url: comps.url!))
        }

        NotificationCenter.default.addObserver(self, selector: #selector(didResignKey),
                                               name: NSWindow.didResignKeyNotification, object: panel)
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            log("GLOBAL_MOUSE_DOWN")
            self?.close()
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { log("LOCAL_ESC"); self?.close(); return nil }
            return e
        }
    }

    @objc func didResignKey() {
        guard !closing, shown else { return }
        log("PANEL_RESIGN_KEY")
        close()
    }

    func userContentController(_ ucc: WKUserContentController, didReceive msg: WKScriptMessage) {
        guard let d = msg.body as? [String: Any] else { return }
        if let h = d["h"] as? Double { if !shown { applySize(h: CGFloat(h), raw: CGFloat(h)) } }
        if let k = d["key"] as? String { log("JS_KEY \(k)") }
    }

    func webView(_ w: WKWebView, didFinish nav: WKNavigation!) {
        loadMs = Date().timeIntervalSince(t0) * 1000
        log(String(format: "WEB_LOAD_MS %.0f", loadMs))
        // 离屏 WKWebView 会节流 requestAnimationFrame，这里直接用原生侧测量兜底
        w.evaluateJavaScript("(function(){const a=parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--arrow-h'))||10;return [document.body.getBoundingClientRect().height, a]})()") { [self] v, e in
            guard let a = v as? [Double], a.count == 2 else { log("MEASURE_FAIL \(String(describing: e))"); return }
            applySize(h: a[0] + (a[1] > 0 ? 0 : 0), raw: a[0])
        }
    }

    func applySize(h: CGFloat, raw: CGFloat) {
        contentH = h
        panelH = min(contentH, MAX_H)
        log("MEASURED body=\(Int(raw)) panel=\(Int(panelH))")
        readyMs = Date().timeIntervalSince(t0) * 1000
        if pendingShow { pendingShow = false; show() }
        if flag("SPIKE_KBD") { keyboardSelfTest() }
        web.evaluateJavaScript("getComputedStyle(document.getElementById('popover')).backdropFilter") { [self] v, _ in
            log("CSS_BACKDROP_FILTER=\(v ?? "nil")")
        }
    }
    func webView(_ w: WKWebView, didFail nav: WKNavigation!, withError e: Error) { log("NAV_FAIL \(e)") }

    // MARK: 形状（问题 B）
    func mask(size: NSSize, caret: CGFloat) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.white.setFill()
        shapePath(size, caret: caret).fill()
        img.unlockFocus()
        return img
    }

    func show() {
        guard let screen = statusItem.button?.window?.screen ?? NSScreen.screens.first ?? NSScreen.main else { return }
        let vf = screen.visibleFrame
        var anchorX = vf.midX
        if let b = statusItem.button, let bw = b.window {
            anchorX = bw.convertToScreen(b.convert(b.bounds, to: nil)).midX
        }
        screenRect = screen.frame
        var x = anchorX - 300                                  // 原型 caret 默认 300
        x = min(max(x, vf.minX + 8), vf.maxX - PANEL_W - 8)    // 屏幕边缘 clamp
        caret = min(max(anchorX - x, RADIUS + ARROW_HALF), PANEL_W - RADIUS - ARROW_HALF)
        let topY = vf.maxY                                     // 菜单栏下沿
        panel.setFrame(NSRect(x: x, y: topY - panelH, width: PANEL_W, height: panelH), display: true)
        if !flag("SPIKE_NOMASK") { effect.maskImage = mask(size: NSSize(width: PANEL_W, height: panelH), caret: caret) }
        tintView.frame = NSRect(x: 0, y: 0, width: PANEL_W, height: panelH)
        tintView.caret = caret
        tintView.needsDisplay = true
        web.frame = tintView.frame
        panel.invalidateShadow()
        if let bg = backdrop {                                   // 纯色垫底：给材质取样一个确定颜色
            bg.setFrame(panel.frame.insetBy(dx: -120, dy: -160).offsetBy(dx: 0, dy: -40), display: true)
            panel.addChildWindow(bg, ordered: .below)
            bg.orderFront(nil)
        }
        web.evaluateJavaScript("document.documentElement.style.setProperty('--caret-x','\(caret)px')") { _, _ in }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(web)
        shown = true
        log("SHOW frame=\(panel.frame) caret=\(Int(caret)) win=\(panel.windowNumber) key=\(panel.isKeyWindow) appActive=\(NSApp.isActive) reduceTransparency=\(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency) appearance=\(panel.effectiveAppearance.name.rawValue)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
            log("AFTER_SHOW key=\(panel.isKeyWindow) appActive=\(NSApp.isActive) front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?") first=\(String(describing: panel.firstResponder?.className))")
            dump()
        }
    }

    func close() {
        guard shown else { return }
        closing = true
        shown = false
        if let bg = backdrop { panel.removeChildWindow(bg); bg.orderOut(nil) }
        panel.orderOut(nil)
        closing = false
        log("CLOSED")
    }

    @objc func toggle() {
        if shown { close() } else { show() }
    }

    // 合成键盘事件：验证 key window → 响应链 → Web 内容这条输入链路
    func keyboardSelfTest() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
            guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: panel.windowNumber, context: nil,
                                           characters: "a", charactersIgnoringModifiers: "a",
                                           isARepeat: false, keyCode: 0) else { return }
            NSApp.postEvent(e, atStart: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                web.evaluateJavaScript("window.__keys.join(',')") { [self] v, _ in
                    log("KEYS_SEEN \(v ?? "nil")")
                    dump()
                }
            }
            // ESC 走本地监听器关闭
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [self] in
                guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: panel.windowNumber, context: nil,
                                               characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                               isARepeat: false, keyCode: 53) else { return }
                NSApp.postEvent(e, atStart: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
                    log("ESC_CLOSED visible=\(panel.isVisible)")
                    dump()
                }
            }
        }
    }

    func dump() {
        guard let p = env["SPIKE_DUMP"] else { return }
        let d: [String: Any] = [
            "windowNumber": panel.windowNumber,
            "frame": "\(Int(panel.frame.minX)),\(Int(panel.frame.minY)),\(Int(panel.frame.width)),\(Int(panel.frame.height))",
            "panelH": Int(panelH), "contentH": Int(contentH), "caret": Int(caret),
            "isKey": panel.isKeyWindow, "isVisible": panel.isVisible,
            "appActive": NSApp.isActive,
            "frontmost": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?",
            "loadMs": Int(loadMs), "readyMs": Int(readyMs),
            "kvc": flag("SPIKE_KVC", true), "underPage": flag("SPIKE_UNDERPAGE", true),
            "firstResponder": panel.firstResponder.map { $0.className } ?? "nil",
            "screen": "\(Int(screenRect.minX)),\(Int(screenRect.minY)),\(Int(screenRect.width)),\(Int(screenRect.height))",
            "screenH": Int(screenRect.height), "screenMinY": Int(screenRect.minY),
            "scale": NSScreen.screens.first?.backingScaleFactor ?? 2,
            // screencapture -R 用主屏左上为原点、y 向下的全局坐标
            "captureRect": "\(Int(panel.frame.minX)),\(Int((NSScreen.screens.first?.frame.maxY ?? 0) - panel.frame.maxY)),\(Int(panel.frame.width)),\(Int(panel.frame.height))",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: p))
        }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.run()
