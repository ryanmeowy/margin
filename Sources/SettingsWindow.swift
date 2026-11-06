import AppKit
import WebKit

private final class DragOverlay: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let web: WKWebView
    private let bridge = Bridge()
    private var pageReady = false
    private var pendingState: SettingsState?
    private var pendingPane: String?

    var onEvent: ((BridgeEvent) -> Void)?
    var onClose: (() -> Void)?

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 792, height: 632),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        web = Bridge.makeWebView(bridge: bridge)
        super.init()

        window.title = "设置"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 700, height: 540)
        window.isMovableByWindowBackground = false
        window.center()
        window.setFrameAutosaveName("MarginSettingsWindow")
        // 像普通窗口一样参与 Mission Control 窗口循环，否则点缩略图不会把它带到前面
        window.collectionBehavior = [.managed, .participatesInCycle]
        ensureOnScreen()
        window.delegate = self
        window.backgroundColor = NSColor.windowBackgroundColor

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 792, height: 632))
        web.frame = container.bounds
        web.autoresizingMask = [.width, .height]
        container.addSubview(web)

        let drag = DragOverlay(frame: NSRect(x: 0, y: 632 - 46, width: 792, height: 46))
        drag.autoresizingMask = [.width, .minYMargin]
        container.addSubview(drag)
        window.contentView = container

        bridge.handler = { [weak self] event in
            guard let self else { return }
            if case .ready = event {
                self.pageReady = true
                self.flush()
                self.applyPendingPane()
            }
            self.onEvent?(event)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(appActiveChanged),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appActiveChanged),
                                               name: NSApplication.didResignActiveNotification, object: nil)
        // 在调度中心/Exposé 里点窗口、或从别的 App 点回来时，窗口成为 key 就把它提到最前
        NotificationCenter.default.addObserver(self, selector: #selector(windowBecameKey),
                                               name: NSWindow.didBecomeKeyNotification, object: window)

        if let url = Bundle.main.url(forResource: "settings", withExtension: "html", subdirectory: "web") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            NSLog("margin: settings.html missing")
        }
    }

    /// 双屏/换分辨率后，autosave 恢复出来的 frame 可能落在屏幕外，先纠回可见区域。
    private func ensureOnScreen() {
        let frame = window.frame
        let visible = NSScreen.screens.contains { screen in
            let hit = screen.visibleFrame.intersection(frame)
            return !hit.isNull && hit.width > 80 && hit.height > 80
        }
        guard !visible else { return }
        let target = NSScreen.main ?? NSScreen.screens.first
        guard let area = target?.visibleFrame else { return }
        let size = frame.size
        let origin = NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    func show(pane: String?) {
        // 设置窗口开着期间切成普通 App：Dock 有图标、Cmd-Tab 能看到，
        // 否则纯菜单栏 App 没有「切回来」的入口，窗口只能被压在别的 App 后面
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        ensureOnScreen()
        if !window.isVisible { window.center() }
        // 只在 App 激活期间临时置顶：accessory App 的 activate 在 14+ 不可靠，
        // 但常驻 .floating 会压住其他应用，所以失活就降回普通层级
        lastRaisedAt = Date()
        window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        pendingPane = pane
        applyPendingPane()
    }

    private func applyPendingPane() {
        guard pageReady, let pane = pendingPane else { return }
        pendingPane = nil
        Bridge.call("window.margin.showPane(\"\(pane)\")", on: web)
    }

    func update(_ state: SettingsState) {
        pendingState = state
        flush()
    }

    private func flush() {
        guard pageReady, let state = pendingState else { return }
        Bridge.push(state, function: "window.margin.applySettings", into: web)
    }

    /// 最近一次「主动把窗口叫到前面」的时间，用来区分「刚打开时的失活」和「用户真的切走了」
    private var lastRaisedAt = Date.distantPast

    @objc private func appActiveChanged() {
        guard window.isVisible else { return }
        if NSApp.isActive {
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            // Mission Control 的切换动画结束后再补一次，点缩略图回来时窗口才真的浮上来
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, NSApp.isActive, self.window.isVisible else { return }
                self.window.makeKeyAndOrderFront(nil)
                self.window.orderFrontRegardless()
            }
            return
        }
        // 立刻下沉：之前延迟 0.3 秒确认，肉眼能看到窗口「先卡一下再沉」
        window.level = .normal
    }

    @objc private func windowBecameKey() {
        lastRaisedAt = Date()
        window.level = .floating
        window.orderFrontRegardless()
    }

    /// 面板/状态栏被点开时，如果设置窗口还开着，也把它带到前面
    func bringForwardIfVisible() {
        guard window.isVisible else { return }
        lastRaisedAt = Date()
        window.level = .floating
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        window.level = .normal
        // 关掉设置就退回菜单栏 App，别一直占着 Dock
        DispatchQueue.main.async {
            if NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        onClose?()
    }
}
