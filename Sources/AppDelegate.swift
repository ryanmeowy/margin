import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController!
    private var panel: PanelController!
    private var settings: SettingsWindowController?
    private var login: LoginWindowController?
    private var store: UsageStore?
    private var timer: Timer?
    private var dailyTimer: Timer?
    private var panelState: PanelState?
    private var updateStatusText = "上次检查：—"
    private var settingsBusy = false
    private var lastSyncAt: Date?
    private var lastStableSyncLabel: String?
    private var manualRefresh = false
    private lazy var export = ExportController(storeProvider: { [weak self] in self?.store })
    private lazy var authFlow = LoginCoordinator(hooks: LoginCoordinator.Hooks(
        hidePanel: { [weak self] in self?.panel.hide() },
        refreshSettings: { [weak self] in self?.pushSettingsState() },
        setSettingsBusy: { [weak self] busy in self?.settingsBusy = busy },
        refreshData: { [weak self] in await self?.refresh(userInitiated: true) },
        resetStore: { [weak self] in self?.store?.reset() },
        clearPanelState: { [weak self] in self?.panelState = nil },
        resetStatusItem: { [weak self] in
            guard let self else { return }
            self.statusItem.apply(percent: nil, display: Prefs.snapshot.display, placeholder: true)
        },
        connectionState: { [weak self] in self?.store?.snapshotState()?.connection.state }
    ))
    private var dailyTask: Task<Void, Never>?

    // MARK: 启动

    func applicationDidFinishLaunching(_ notification: Notification) {
        Theme.apply(pref: Prefs.snapshot.theme)
        Theme.startObserving()
        buildMainMenu()

        statusItem = StatusItemController()
        statusItem.apply(percent: nil, display: Prefs.snapshot.display, placeholder: true)
        statusItem.onLeftClick = { [weak self] in self?.togglePanel() }
        statusItem.onRightClick = { [weak self] button in self?.showStatusMenu(button) }

        panel = PanelController()
        panel.anchorButton = statusItem.item.button
        panel.onEvent = { [weak self] event in self?.handle(event) }

        NotificationCenter.default.addObserver(self, selector: #selector(prefsChanged), name: Prefs.changed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: Theme.changed, object: nil)

        // 开发用：从文件读会话 token 写进 Keychain（避免把 token 放进进程参数/日志）
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--seed-token-file"), index + 1 < args.count {
            let path = args[index + 1]
            if let raw = try? String(contentsOfFile: path, encoding: .utf8) {
                let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty {
                    try? CredentialStore.saveToken(token)
                    NSLog("margin: seeded session token (\(token.count) chars)")
                }
                try? FileManager.default.removeItem(atPath: path)
            }
        }

        if args.contains("--mock") {
            loadMockState()
            return
        }

        store = makeStore()
        startTimer()
        observeWake()
        syncLoginItem()

        if Prefs.snapshot.usageAlert {
            Notifier.requestAuthorization { _ in }
        }

        if let index = args.firstIndex(of: "--export-csv"), index + 1 < args.count {
            let path = args[index + 1]
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                let body = await self?.store?.exportCSV() ?? ""
                try? Data(body.utf8).write(to: URL(fileURLWithPath: path))
                NSLog("margin: exported \(body.split(separator: "\n").count) lines -> \(path)")
                NSApp.terminate(nil)
            }
        }
        if args.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.panel.show() }
        }
        if args.contains("--settings") || args.contains("--settings-pane") {
            let pane = args.firstIndex(of: "--settings-pane").flatMap { index -> String? in
                index + 1 < args.count ? args[index + 1] : nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.showSettings(pane: pane) }
        }
        if args.contains("--import-session") {
            Task {
                do {
                    let token = try await BrowserSessionImport.sessionToken()
                    NSLog("margin: import ok len=\(token.count)")
                    try? CredentialStore.saveToken(token)
                } catch {
                    NSLog("margin: import failed \(error.localizedDescription)")
                }
            }
        }
        if args.contains("--simulate-login") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self else { return }
                self.authFlow.logout()
                self.authFlow.startBrowserLogin(openBrowser: false)
            }
        }
        if args.contains("--wait-only") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.authFlow.startBrowserLogin(openBrowser: false)
            }
        }
        if args.contains("--logout") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.authFlow.logout() }
        }
        if args.contains("--login") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.showLogin() }
        }
        if args.contains("--toggle") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.togglePanel() }
        }
        if let index = args.firstIndex(of: "--eval"), index + 1 < args.count {
            let js = args[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in self?.panel.evaluate(js) }
        }

        Task { await self.refresh(userInitiated: false) }

        // 启动时如果没登录、而且不是用户主动退出的，就静默尝试一次浏览器会话
        if CredentialStore.loadToken() == nil, !UserDefaults.standard.bool(forKey: PrefsKey.didLogout) {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await self?.authFlow.importSession(interactive: false, silent: true)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dailyTask?.cancel()
        timer?.invalidate()
    }

    // MARK: Mock（无登录态时看 UI 用：--mock）

    private func loadMockState() {
        guard let url = Bundle.main.url(forResource: "state.sample", withExtension: "json", subdirectory: "web"),
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(PanelState.self, from: data) else {
            NSLog("margin: mock state missing")
            return
        }
        apply(state)
        panel.show()
    }

    // MARK: 数据

    private func makeStore() -> UsageStore {
        let base = URL(string: Prefs.baseUrl) ?? URL(string: "https://amr-api.open-design.ai")!
        let api = OpenDesignAPI(baseURL: base, token: { CredentialStore.loadToken() })
        var deps = UsageStore.Deps(api: api, prefs: { Prefs.snapshot }, now: Date.init)
        deps.theme = { Theme.current }
        deps.version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        deps.build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        deps.email = { "" }
        deps.baseUrl = { Prefs.baseUrl }
        deps.token = { CredentialStore.loadToken() }
        let store = UsageStore(deps: deps)
        store.onPanelState = { [weak self] state in
            DispatchQueue.main.async { self?.apply(state) }
        }
        return store
    }

    private func refresh(userInitiated: Bool) async {
        guard let store else { return }
        if userInitiated { manualRefresh = true }
        defer { if userInitiated { manualRefresh = false } }
        let t0 = Date()
        NSLog("margin: refresh start user=\(userInitiated)")
        await store.refresh(userInitiated: userInitiated)
        NSLog("margin: refresh quota done +\(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
        // 配额每 15 分钟刷；7 天图走自己的节奏（内部有 30 分钟节流 + 只算今天）
        await store.refreshDailySeriesIfNeeded(force: userInitiated)
        NSLog("margin: refresh daily done +\(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
        pushSettingsState()
    }

    private func apply(_ incoming: PanelState) {
        var state = incoming
        // 401 就当「没登录」处理：删掉无效 token、回到未配置，别给用户看「登录已过期」的红卡
        if state.connection.state == "expired" {
            CredentialStore.deleteToken()
            panelState = nil
            store?.reset()
            return
        }
        // 连上就结束等待（coordinator 自己处理 pending / 文案）
        authFlow.connectionDidChange(state.connection)
        authFlow.decorate(&state)
        // 后台刷新不把面板变成「正在同步…」——只有用户主动点刷新/⌘R 才显示
        if state.sync.busy, !manualRefresh, panelState != nil {
            state.sync.busy = false
            if let label = lastStableSyncLabel { state.sync.label = label }
        } else if !state.sync.busy {
            lastStableSyncLabel = state.sync.label
            lastSyncAt = Date()
        }
        NSLog("margin: busy=\(state.sync.busy) rawBusy=\(incoming.sync.busy) connection=\(state.connection.state) daily=\(state.usage.dailyState)")
        panelState = state
        let display = Prefs.snapshot.display
        let percent = state.windows.first?.remainingPercent ?? 0
        statusItem.apply(percent: state.connection.state == "ok" ? percent : nil,
                         display: display,
                         placeholder: state.connection.state != "ok")
        panel.update(state: state, animated: panel.isVisible)
        pushSettingsState()
    }

    // MARK: 面板 / 菜单

    private func togglePanel() {
        panel.toggle()
        settings?.bringForwardIfVisible()
        guard panel.isVisible else { return }
        // 60 秒内刚同步过就直接用缓存，别每次点开都发三个请求
        if let last = lastSyncAt, Date().timeIntervalSince(last) < 60 { return }
        Task { await refresh(userInitiated: false) }
    }

    private func showStatusMenu(_ button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开面板", action: #selector(menuOpenPanel), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "刷新用量", action: #selector(menuRefresh), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "从浏览器同步登录态", action: #selector(menuSyncSession), keyEquivalent: "").target = self
        menu.addItem(withTitle: "退出登录", action: #selector(menuLogout), keyEquivalent: "").target = self
        menu.addItem(withTitle: "设置…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "关于 Margin", action: #selector(menuAbout), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Margin", action: #selector(menuQuit), keyEquivalent: "q").target = self
        let point = NSPoint(x: 0, y: button.bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: button)
    }

    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Margin")
        appMenu.addItem(withTitle: "关于 Margin", action: #selector(menuAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "设置…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "刷新用量", action: #selector(menuRefresh), keyEquivalent: "r").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Margin", action: #selector(menuQuit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main
    }

    @objc private func menuOpenPanel() { panel.show() }
    @objc private func menuRefresh() { Task { await refresh(userInitiated: true) } }
    @objc private func menuSettings() { showSettings(pane: nil) }
    @objc private func menuAbout() { showSettings(pane: "about") }
    @objc private func menuSyncSession() { Task { await authFlow.importSession(interactive: true) } }
    @objc private func menuLogout() { authFlow.logout() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: 设置窗口

    private func showSettings(pane: String?) {
        panel.hide()
        if settings == nil {
            let controller = SettingsWindowController()
            controller.onEvent = { [weak self] event in self?.handle(event) }
            controller.onClose = { [weak self] in self?.settings = nil }
            settings = controller
        }
        settings?.update(makeSettingsState())
        settings?.show(pane: pane)
    }

    private func pushSettingsState() {
        guard let settings, settingsIsVisible else { return }
        settings.update(makeSettingsState())
    }

    private var settingsIsVisible: Bool { settings != nil }

    private func makeSettingsState() -> SettingsState {
        let prefs = Prefs.snapshot
        let token = CredentialStore.loadToken() ?? ""
        let masked = token.isEmpty ? "" : String(token.prefix(6)) + "••••" + String(token.suffix(4))

        let connection = panelState?.connection ?? PanelState.Connection(state: "unconfigured", message: "")
        let workspaceName = panelState?.account.workspaceName ?? "未连接"
        let ownerName = panelState?.account.ownerName ?? ""
        let displayName = ownerName.isEmpty ? workspaceName : ownerName
        // 侧栏底部的小字：未登录就说未登录，别写「异常」
        let planLabel: String = {
            guard let state = panelState else { return "未登录" }
            switch state.connection.state {
            case "ok": return "\(state.plan.label) · 正常"
            case "expired": return "登录已过期"
            case "denied": return "无权限"
            case "offline": return "离线"
            default: return "未登录"
            }
        }()
        let account = SettingsState.Account(
            baseUrl: Prefs.baseUrl,
            email: (panelState?.account.email.isEmpty == false) ? (panelState?.account.email ?? "") : ownerName,
            tokenMasked: masked,
            workspaceName: workspaceName,
            planLabel: planLabel,
            lastVerifiedLabel: {
                guard let sync = panelState?.sync else { return "尚未同步" }
                if sync.busy { return lastStableSyncLabel ?? "正在同步" }
                return sync.label
            }(),
            launchAtLoginSupported: LoginItem.isSupported,
            notificationsSupported: Notifier.isAvailable,
            displayName: displayName,
            initials: Self.initials(displayName)
        )
        let about = SettingsState.About(
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1",
            mode: "仅菜单栏",
            intervalLabel: "\(prefs.intervalMinutes) 分钟",
            credentialStorage: "仅本机",
            updateStatus: updateStatusText
        )
        let prefsView = SettingsState.PrefsView(
            theme: prefs.theme, display: prefs.display,
            launchAtLogin: prefs.launchAtLogin, autoRefresh: prefs.autoRefresh,
            interval: prefs.interval, usageAlert: prefs.usageAlert,
            threshold: prefs.threshold, renewalReminder: prefs.renewalReminder,
            weeklyDigest: prefs.weeklyDigest
        )
        return SettingsState(theme: Theme.current, prefs: prefsView, account: account,
                             connection: connection, about: about, version: about.version,
                             busy: settingsBusy, workspaceOptions: store?.workspaceChoices ?? [],
                             workspaceId: store?.activeWorkspaceId ?? "",
                             authNotice: authFlow.notice, authTone: authFlow.tone,
                             authPending: authFlow.pending)
    }

    // MARK: 事件路由

    private func handle(_ event: BridgeEvent) {
        switch event {
        case .ready:
            break
        case .panelDidShow:
            Task { await store?.refreshDailySeriesIfNeeded(force: false) }
        case .height:
            break
        case .refresh:
            Task { await refresh(userInitiated: true) }
        case .openSettings(let pane):
            showSettings(pane: pane)
        case .showDetail:
            break
        case .exportCSV:
            exportCSV()
        case .relogin, .browserLogin:
            authFlow.startBrowserLogin()
        case .embeddedLogin:
            showLogin()
        case .importSession:
            Task { await authFlow.importSession(interactive: true) }
        case .logout:
            authFlow.logout()
        case .quit:
            NSApp.terminate(nil)
        case .setWorkspace(let id):
            guard !id.isEmpty else { break }
            Prefs.set(PrefsKey.workspaceId, id)
            Task { await refresh(userInitiated: true) }
        case .setPref(let key, let value):
            applyPref(key, value)
        case .saveAccount(let baseUrl, let token):
            saveAccount(baseUrl: baseUrl, token: token)
        case .checkUpdate:
            settingsBusy = true
            pushSettingsState()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self else { return }
                self.settingsBusy = false
                self.updateStatusText = "本地构建 · 未配置更新源"
                self.pushSettingsState()
            }
        case .openLink(let url):
            if let url = URL(string: url) { NSWorkspace.shared.open(url) }
        case .unknown(let type):
            NSLog("margin: unknown bridge message \(type)")
        }
    }

    private func applyPref(_ key: String, _ value: Any) {
        switch key {
        case "theme":
            Prefs.set(PrefsKey.theme, value)
            Theme.apply(pref: Prefs.snapshot.theme)
        case "display":
            Prefs.set(PrefsKey.display, value)
            if let state = panelState { apply(state) }
        case "launchAtLogin":
            let on = (value as? Bool) ?? false
            let ok = LoginItem.set(on)
            Prefs.set(PrefsKey.launchAtLogin, ok ? on : LoginItem.isEnabled)
        case "autoRefresh":
            Prefs.set(PrefsKey.autoRefresh, value)
            startTimer()
        case "interval":
            Prefs.set(PrefsKey.interval, value)
            startTimer()
        case "usageAlert":
            let on = (value as? Bool) ?? false
            Prefs.set(PrefsKey.usageAlert, on)
            if on { Notifier.requestAuthorization { _ in } }
        case "threshold":
            Prefs.set(PrefsKey.threshold, value)
        case "renewalReminder":
            Prefs.set(PrefsKey.renewalReminder, value)
        case "weeklyDigest":
            Prefs.set(PrefsKey.weeklyDigest, value)
        default:
            NSLog("margin: unknown pref \(key)")
        }
        pushSettingsState()
    }

    private static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        if parts.count >= 2 {
            return (String(parts[0].prefix(1)) + String(parts[1].prefix(1))).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private func saveAccount(baseUrl: String, token: String) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUrl = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedUrl.isEmpty { Prefs.set(PrefsKey.baseUrl, trimmedUrl) }
        if !trimmedToken.isEmpty {
            do { try CredentialStore.saveToken(trimmedToken) } catch { NSLog("margin: keychain save failed \(error)") }
        }
        settingsBusy = true
        pushSettingsState()
        Task {
            defer { settingsBusy = false; pushSettingsState() }
            do {
                _ = try await OpenDesignAPI.validate(
                    baseURL: URL(string: Prefs.baseUrl) ?? URL(string: "https://amr-api.open-design.ai")!,
                    token: trimmedToken.isEmpty ? (CredentialStore.loadToken() ?? "") : trimmedToken
                )
                await refresh(userInitiated: true)
                updateStatusText = "连接成功"
            } catch {
                updateStatusText = "验证失败：\(error)"
            }
            pushSettingsState()
        }
    }

    private func showLogin() {
        panel.hide()
        let url = URL(string: Prefs.baseUrl) ?? URL(string: "https://amr-api.open-design.ai")!
        let controller = LoginWindowController(apiBase: url)
        controller.onToken = { [weak self] token in
            do { try CredentialStore.saveToken(token) } catch { NSLog("margin: keychain save failed \(error)") }
            self?.login = nil
            Task { await self?.refresh(userInitiated: true) }
        }
        controller.onClose = { [weak self] in self?.login = nil }
        login = controller
        controller.show()
    }

    private func exportCSV() { export.start() }


    // MARK: 偏好 / 主题 / 定时

    @objc private func prefsChanged() {
        statusItem.apply(percent: panelState?.windows.first?.remainingPercent,
                         display: Prefs.snapshot.display,
                         placeholder: panelState == nil)
        pushSettingsState()
    }

    @objc private func themeChanged() {
        if let state = panelState { panel.update(state: state, animated: false) }
        pushSettingsState()
    }

    private func startTimer() {
        timer?.invalidate()
        let prefs = Prefs.snapshot
        if prefs.autoRefresh {
            let interval = TimeInterval(max(1, prefs.intervalMinutes) * 60)
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { await self?.refresh(userInitiated: false) }
            }
        }
        // 7 天柱状图单独一条：每 2 小时只重算今天这一桶（1–4 个请求）
        dailyTimer?.invalidate()
        dailyTimer = Timer.scheduledTimer(withTimeInterval: 2 * 3600, repeats: true) { [weak self] _ in
            Task { await self?.store?.refreshDailySeriesIfNeeded(force: false) }
        }
        dailyTimer?.tolerance = 300
    }

    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // 睡眠期间定时器不跑，唤醒后补一次（内部 30 分钟节流，不会连发）
            Task { await self?.store?.refreshDailySeriesIfNeeded(force: false) }
        }
    }

    private func syncLoginItem() {
        let prefs = Prefs.snapshot
        if prefs.launchAtLogin, !LoginItem.isEnabled { LoginItem.set(true) }
    }

    // MARK: 通知

    private func evaluateAlerts() {
        guard Prefs.snapshot.usageAlert, let state = panelState, state.connection.state == "ok" else { return }
        let threshold = Prefs.snapshot.threshold
        // 「剩余额度低于阈值」——阈值就是剩余百分比本身，0% 表示不提醒
        if threshold > 0, let window = state.windows.first, window.remainingPercent <= threshold {
            Notifier.notify(title: "额度不足", body: "剩余 \(window.remainingPercent)%，低于提醒阈值 \(threshold)%")
        }
    }
}
