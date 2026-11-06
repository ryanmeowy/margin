import AppKit
import WebKit

/// 登录 / 导入 / 退出：从 AppDelegate 里拆出来的独立状态机。
/// 只通过 hooks 触碰界面，自己只管「等待 → 导入 → 成功/失败」这条线。
final class LoginCoordinator {
    struct Hooks {
        var hidePanel: () -> Void
        var refreshSettings: () -> Void
        var setSettingsBusy: (Bool) -> Void
        var refreshData: () async -> Void
        var resetStore: () -> Void
        var clearPanelState: () -> Void
        var resetStatusItem: () -> Void
        var connectionState: () -> String?
    }

    private let hooks: Hooks
    private var watch: Task<Void, Never>?
    private var importing = false

    /// 正在等浏览器登录（界面显示「等待登录…」）
    private(set) var pending = false
    private(set) var notice = ""
    private(set) var tone = "ok"

    init(hooks: Hooks) { self.hooks = hooks }

    // MARK: 对外

    /// 用系统默认浏览器登录；之后自动把浏览器里的会话同步过来
    func startBrowserLogin(openBrowser: Bool = true) {
        hooks.hidePanel()
        let apiBase = URL(string: Prefs.baseUrl) ?? URL(string: "https://amr-api.open-design.ai")!
        if openBrowser {
            NSWorkspace.shared.open(LoginWindowController.loginURL(for: apiBase))
        }
        pending = true
        notice = "已在浏览器打开登录页，登录完成后会自动同步…"
        tone = "ok"
        NSApp.activate(ignoringOtherApps: true)
        hooks.refreshSettings()
        beginWatch()
    }

    /// 退出登录：删 token、清 WebView Cookie、重置内存与缓存
    func logout() {
        watch?.cancel()
        watch = nil
        pending = false
        CredentialStore.deleteToken()
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                modifiedSince: .distantPast) { }
        hooks.resetStore()
        hooks.clearPanelState()
        hooks.resetStatusItem()
        UserDefaults.standard.set(true, forKey: PrefsKey.didLogout)
        notice = "已退出登录"
        tone = "ok"
        hooks.refreshSettings()
    }

    /// 面板状态变化时调用：连上就结束等待
    func connectionDidChange(_ connection: PanelState.Connection) {
        guard pending, connection.state == "ok" else { return }
        pending = false
        notice = "登录成功"
        tone = "ok"
        watch?.cancel()
        watch = nil
        UserDefaults.standard.set(false, forKey: PrefsKey.didLogout)
    }

    /// 等待期间把面板顶部连接条也改成等待文案
    func decorate(_ state: inout PanelState) {
        if pending, state.connection.state != "ok" {
            state.connection.message = "等待浏览器登录…"
        }
    }

    // MARK: 导入

    @discardableResult
    func importSession(interactive: Bool, silent: Bool = false) async -> Bool {
        // 等待期间由后台轮询独占；并发导入直接丢弃
        if pending, !silent { return false }
        if importing { return false }
        importing = true
        defer { importing = false }

        hooks.setSettingsBusy(!silent)
        if silent, pending {
            notice = "正在读取浏览器会话…"
            tone = "ok"
        }
        hooks.refreshSettings()
        defer {
            hooks.setSettingsBusy(false)
            hooks.refreshSettings()
        }

        let apiBase = URL(string: Prefs.baseUrl) ?? URL(string: "https://amr-api.open-design.ai")!
        do {
            let token = try await BrowserSessionImport.sessionToken()
            // 先验证再落盘：浏览器里可能只有匿名/过期 cookie
            _ = try await OpenDesignAPI.validate(baseURL: apiBase, token: token)
            do {
                try CredentialStore.saveToken(token)
            } catch {
                NSLog("margin: saveToken failed \(error)")
            }
            await hooks.refreshData()

            // 会话已验证过：refresh 只是拉数据，网络抖动不该把 token 删掉
            let state = hooks.connectionState()
            guard state == "ok" || state == "offline" else {
                clearInvalidSession()
                guard !silent else { return false }
                pending = false
                notice = "浏览器里的会话还没生效，完成登录后再试"
                tone = "error"
                return false
            }
            pending = false
            notice = "登录成功"
            tone = "ok"
            UserDefaults.standard.set(false, forKey: PrefsKey.didLogout)
            NSLog("margin: imported browser session")
            return true
        } catch {
            NSLog("margin: import failed \(error.localizedDescription)")
            if let od = error as? ODError {
                switch od {
                case .unauthorized, .forbidden:
                    clearInvalidSession()
                default:
                    break
                }
            }
            guard !silent else {
                if pending {
                    notice = "已在浏览器打开登录页，登录完成后会自动同步…"
                    hooks.refreshSettings()
                }
                return false
            }
            pending = false
            notice = "浏览器里的会话还没生效，完成登录后再试"
            tone = "error"
            return false
        }
    }

    private func clearInvalidSession() {
        CredentialStore.deleteToken()
        hooks.resetStore()
        hooks.clearPanelState()
    }

    // MARK: 等待循环

    private func beginWatch() {
        watch?.cancel()
        watch = Task { [weak self] in
            guard let self else { return }
            var fingerprint = BrowserSessionImport.cookieFingerprint()

            // 已经登录过的情况：0.8 秒后先试一次
            try? await Task.sleep(nanoseconds: 800_000_000)
            if Task.isCancelled { return }
            if await self.importSession(interactive: false, silent: true) { return }

            let deadline = Date().addingTimeInterval(10 * 60)   // 给足登录时间
            var lastAttempt = Date()
            while !Task.isCancelled && Date() < deadline {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { return }
                if self.hooks.connectionState() == "ok" { return }
                let current = BrowserSessionImport.cookieFingerprint()
                let due = Date().timeIntervalSince(lastAttempt) >= 20   // 兜底每 20 秒强试一次
                guard current != fingerprint || due else { continue }
                fingerprint = current
                lastAttempt = Date()
                if await self.importSession(interactive: false, silent: true) { return }
            }
            guard !Task.isCancelled else { return }
            self.pending = false
            if self.notice.hasPrefix("已在浏览器打开登录页") {
                self.notice = "没有检测到浏览器登录，可以再试一次"
                self.tone = "error"
            }
            self.hooks.refreshSettings()
        }
    }
}
