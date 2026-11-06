import AppKit
import WebKit

final class LoginWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKHTTPCookieStoreObserver {
    private let window: NSWindow
    private let web: WKWebView
    private let apiBase: URL
    private let loginURL: URL
    private var finished = false
    private var validating = false
    private var attempts = 0

    var onToken: ((String) -> Void)?
    var onClose: (() -> Void)?

    init(apiBase: URL) {
        self.apiBase = apiBase
        self.loginURL = Self.loginURL(for: apiBase)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 660),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        web = WKWebView(frame: .zero, configuration: config)
        super.init()

        window.title = "登录 OpenDesign"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 520)
        window.center()
        window.delegate = self
        window.contentView = web

        web.navigationDelegate = self
        WKWebsiteDataStore.default().httpCookieStore.add(self)

        web.load(URLRequest(url: loginURL))
    }

    /// API 在 amr-api.open-design.ai，登录页在去掉 amr-api. 前缀的站点上（否则 404）。
    static func webBase(for apiBase: URL) -> URL {
        guard var comps = URLComponents(url: apiBase, resolvingAgainstBaseURL: false) else {
            return URL(string: "https://open-design.ai")!
        }
        var host = comps.host ?? "open-design.ai"
        for prefix in ["amr-api.", "api."] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        comps.host = host
        comps.path = ""
        comps.query = nil
        comps.fragment = nil
        return comps.url ?? URL(string: "https://open-design.ai")!
    }

    static func loginURL(for apiBase: URL) -> URL {
        webBase(for: apiBase).appendingPathComponent("cloud/login")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        WKWebsiteDataStore.default().httpCookieStore.remove(self)
        onClose?()
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        check()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        check()
    }

    /// 抓到会话 Cookie 后先用 API 验一次：有效才写 Keychain 并关窗，避免存进无效会话。
    private func check() {
        guard !finished, !validating else { return }
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self, !self.finished, !self.validating else { return }
            let candidates = cookies.filter { $0.name == "__Secure-better-auth.session_token" }
            guard let token = (candidates.first { $0.domain.contains("amr-api") } ?? candidates.first)?.value,
                  !token.isEmpty else { return }

            self.validating = true
            Task {
                do {
                    _ = try await OpenDesignAPI.validate(baseURL: self.apiBase, token: token)
                    await MainActor.run {
                        self.finished = true
                        self.onToken?(token)
                        self.close()
                    }
                } catch {
                    await MainActor.run {
                        self.validating = false
                        self.attempts += 1
                        if self.attempts >= 3 {
                            self.window.title = "登录未完成 · 请确认账号后重试"
                        }
                    }
                }
            }
        }
    }
}
