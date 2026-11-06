import AppKit
import WebKit

final class PanelController: NSObject, NSWindowDelegate {
    private let panel: MarginPanel
    private let effect = NSVisualEffectView()
    private let tint = TintView()
    private let web: WKWebView
    private let bridge = Bridge()

    private(set) var contentHeight: CGFloat = PanelMetrics.maxHeight - PanelMetrics.contentInset - 43
    private var constrained = false
    private let maxPanelHeight: CGFloat = PanelMetrics.maxHeight
    private var caretX: CGFloat = 196
    private var visible = false
    private var closing = false
    private var lastState: PanelState?
    private var pageReady = false

    var onEvent: ((BridgeEvent) -> Void)?
    weak var anchorButton: NSStatusBarButton?

    override init() {
        panel = MarginPanel(contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.width, height: PanelMetrics.initialHeight),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        web = Bridge.makeWebView(bridge: bridge)
        super.init()

        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.delegate = self

        let root = NSView(frame: NSRect(x: 0, y: 0, width: PanelMetrics.width, height: PanelMetrics.initialHeight))
        root.autoresizingMask = [.width, .height]

        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        effect.frame = root.bounds
        root.addSubview(effect)

        tint.autoresizingMask = [.width, .height]
        tint.frame = root.bounds
        root.addSubview(tint)

        web.autoresizingMask = [.width, .height]
        web.frame = root.bounds
        root.addSubview(web)
        panel.contentView = root

        bridge.handler = { [weak self] event in
            guard let self else { return }
            if case .height(let h) = event { self.updateHeight(h); return }
            if case .ready = event { self.pageReady = true; self.pushState(animated: false) }
            self.onEvent?(event)
        }

        if let url = Bundle.main.url(forResource: "popover", withExtension: "html", subdirectory: "web") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            NSLog("margin: popover.html missing")
        }
        applyChrome()
    }

    // MARK: 显示 / 隐藏

    func toggle() { visible ? hide() : show() }

    func show() {
        guard !visible else { return }
        visible = true
        closing = false
        applyChrome()
        position()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            panel.animator().alphaValue = 1
        }
        pushState(animated: true)
        onEvent?(.panelDidShow)
    }

    func hide() {
        guard visible, !closing else { return }
        closing = true
        visible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.closing = false
            self.panel.alphaValue = 1
        })
    }

    var isVisible: Bool { visible }

    // MARK: 状态

    func update(state: PanelState, animated: Bool) {
        lastState = state
        pushState(animated: animated)
    }

    private func pushState(animated: Bool) {
        guard pageReady, var state = lastState else { return }
        state.animate = animated
        state.theme = Theme.current
        Bridge.push(state, function: "window.margin.applyState", into: web)
    }

    func evaluate(_ js: String) { Bridge.call(js, on: web) }

    func pushSettingsState(_ state: SettingsState) {
        Bridge.push(state, function: "window.margin.applySettings", into: web)
    }

    // MARK: 高度 / 定位

    private func updateHeight(_ reported: CGFloat) {
        // 已在约束态时，要明显低于上限才解除，避免在阈值附近来回翻转（界面抖动）
        let shouldConstrain = constrained ? reported > maxPanelHeight - 12 : reported > maxPanelHeight
        if shouldConstrain != constrained {
            constrained = shouldConstrain
            // 超屏时把面板钉在 maxPanelHeight，页面改为「头部/底部固定、只滚内容区」
            Bridge.call("window.margin.setConstrained(\(shouldConstrain))", on: web)
        }
        let height = min(max(reported.rounded(), PanelMetrics.minHeight), maxPanelHeight)
        guard abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        guard visible else {
            panel.setContentSize(NSSize(width: PanelMetrics.width, height: height))
            return
        }
        let top = panel.frame.maxY
        panel.setFrame(NSRect(x: panel.frame.minX, y: top - height, width: PanelMetrics.width, height: height),
                       display: true, animate: false)
        applyChrome()
        panel.invalidateShadow()
    }

    /// 状态项窗口在菜单栏完成布局前 frame 会是 (0, -29.5)，此时不要定位。
    private func anchorRect() -> (rect: NSRect, screen: NSScreen)? {
        guard let button = anchorButton, let window = button.window else { return nil }
        guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else { return nil }
        let frame = window.frame
        let converted = window.convertToScreen(button.convert(button.bounds, to: nil))
        NSLog("margin.anchor frame=\(frame) converted=\(converted)")
        if converted.origin.y > 0 { return (converted, screen) }
        if frame.origin.y > 0, frame.width > 0 { return (frame, screen) }
        return nil
    }

    private var positionRetried = false

    /// 以状态项按钮为锚点摆放：面板水平居中于按钮，caret 跟随，越界时 clamp 到屏幕内。
    func position() {
        guard let anchor = anchorRect() else {
            if !positionRetried {
                positionRetried = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.position() }
            }
            return
        }
        positionRetried = false
        let buttonRect = anchor.rect
        let screen = anchor.screen
        let width: CGFloat = PanelMetrics.width
        let height = contentHeight
        let visibleFrame = screen.visibleFrame

        var x = buttonRect.midX - width / 2
        var caret = width / 2
        let minX = visibleFrame.minX + 8
        let maxX = visibleFrame.maxX - width - 8
        if x < minX { caret -= (minX - x); x = minX }
        if x > maxX { caret -= (x - maxX); x = maxX }
        caret = min(max(caret, 26), width - 26)

        var top = buttonRect.minY - 6
        if top - height < visibleFrame.minY + 8 { top = visibleFrame.minY + 8 + height }

        panel.setFrame(NSRect(x: x.rounded(), y: top - height, width: width, height: height),
                       display: true, animate: false)

        caretX = caret
        applyChrome()
        if visible { panel.invalidateShadow() }
    }

    private func applyChrome() {
        let size = panel.frame.size
        effect.maskImage = PanelShape.maskImage(size: size, caretX: caretX)
        tint.frame = NSRect(origin: .zero, size: size)
        tint.caretX = caretX
        tint.fillColor = Theme.panelFill
        tint.borderColor = Theme.panelBorder
        tint.needsDisplay = true
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard visible, !closing else { return }
        // 点状态项本身时会先 resign 再由按钮 action 切回，这里放行交给 toggle
        if let button = anchorButton, let buttonWindow = button.window {
            let rect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            if rect.contains(NSEvent.mouseLocation) { return }
        }
        hide()
    }
}
