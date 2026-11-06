import AppKit
import Foundation

/// 从本机已登录的 Chrome 里同步 OpenDesign 会话：
/// 复制一份 profile 到临时目录 → 起一个隐藏的 headless Chrome → CDP 读 Cookie → 关掉并删临时目录。
/// 不碰钥匙串、不需要辅助功能权限；只在用户主动点「从浏览器同步」时跑。
enum BrowserSessionImport {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct Browser {
        let name: String
        let executable: String
        let supportDir: String
    }

    private static let candidates: [Browser] = [
        Browser(name: "Chrome", executable: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                supportDir: "Google/Chrome"),
        Browser(name: "Edge", executable: "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
                supportDir: "Microsoft Edge"),
        Browser(name: "Brave", executable: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
                supportDir: "BraveSoftware/Brave-Browser")
    ]

    /// 各浏览器（含 Profile 1/2…）Cookie 库 + journal 的修改时间指纹。
    /// 变了说明浏览器刚写过 Cookie —— 多半是登录完成。
    static func cookieFingerprint() -> String {
        var parts: [String] = []
        for browser in candidates {
            let support = supportDirectory(for: browser)
            for profile in profileDirectories(in: support) {
                for name in ["Cookies", "Cookies-journal", "Network/Cookies"] {
                    let url = profile.appendingPathComponent(name)
                    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                          let date = attrs[.modificationDate] as? Date else { continue }
                    parts.append("\(url.path):\(Int(date.timeIntervalSince1970))")
                }
            }
        }
        return parts.joined(separator: "|")
    }

    private static func supportDirectory(for browser: Browser) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(browser.supportDir, isDirectory: true)
    }

    /// Default / Profile 1 / Profile 2 …，只留真正有 Cookies 的
    private static func profileDirectories(in support: URL) -> [URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: support.path) else { return [] }
        return names
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .map { support.appendingPathComponent($0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Cookies").path) }
    }

    /// 选最近写过 Cookie 的那个 profile
    private static func newestProfile(in support: URL) -> URL? {
        profileDirectories(in: support).max { a, b in
            let da = (try? FileManager.default.attributesOfItem(atPath: a.appendingPathComponent("Cookies").path)[.modificationDate] as? Date) ?? nil
            let db = (try? FileManager.default.attributesOfItem(atPath: b.appendingPathComponent("Cookies").path)[.modificationDate] as? Date) ?? nil
            return (da ?? .distantPast) < (db ?? .distantPast)
        }
    }

    static func sessionToken() async throws -> String {
        guard let browser = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.executable) }) else {
            throw Failure(message: "没找到 Chrome / Edge / Brave，无法自动同步")
        }
        let support = supportDirectory(for: browser)
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("margin-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let defaultDir = temp.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: defaultDir, withIntermediateDirectories: true)

        // 只复制读 Cookie 需要的两样东西，避免整份 profile
        try copy(support.appendingPathComponent("Local State"), to: temp.appendingPathComponent("Local State"))
        guard let profile = newestProfile(in: support) else {
            throw Failure(message: "\(browser.name) 里没有可读的 Cookie 数据库")
        }
        try copy(profile.appendingPathComponent("Cookies"), to: defaultDir.appendingPathComponent("Cookies"))
        let journal = profile.appendingPathComponent("Cookies-journal")
        if FileManager.default.fileExists(atPath: journal.path) {
            try? copy(journal, to: defaultDir.appendingPathComponent("Cookies-journal"))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: browser.executable)
        process.arguments = [
            "--headless=new", "--remote-debugging-port=0",
            "--user-data-dir=\(temp.path)",
            "--no-first-run", "--no-default-browser-check", "--disable-gpu",
            "--disable-sync", "--no-service-autorun",
            "--disable-component-update", "--disable-background-networking",
            "--disable-default-apps", "--disable-extensions",
            "--disable-features=ComponentUpdater,OptimizationHints,Translate",
            "about:blank"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }

        let portFile = temp.appendingPathComponent("DevToolsActivePort")
        var port: Int?
        var browserPath = "/devtools/browser"
        for _ in 0..<60 {
            if let text = try? String(contentsOf: portFile, encoding: .utf8) {
                let lines = text.split(separator: "\n").map(String.init)
                if let first = lines.first, let value = Int(first.trimmingCharacters(in: .whitespaces)) {
                    port = value
                    if lines.count > 1 { browserPath = lines[1] }
                    break
                }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let port else { throw Failure(message: "\(browser.name) 启动超时") }

        let cookies = try await fetchCookies(port: port, browserPath: browserPath)
        guard let token = cookies.first(where: { $0.name == "__Secure-better-auth.session_token" && $0.domain.contains("amr-api") })?.value
                ?? cookies.first(where: { $0.name == "__Secure-better-auth.session_token" })?.value,
              !token.isEmpty else {
            throw Failure(message: "\(browser.name) 里没有找到 OpenDesign 登录态，先在浏览器里登录一次")
        }
        return token
    }

    private static func copy(_ from: URL, to: URL) throws {
        if FileManager.default.fileExists(atPath: to.path) { try FileManager.default.removeItem(at: to) }
        try FileManager.default.copyItem(at: from, to: to)
    }

    // MARK: CDP

    private struct Cookie: Decodable {
        let name: String
        let value: String
        let domain: String
    }

    private struct CookieResponse: Decodable {
        struct Result: Decodable { let cookies: [Cookie] }
        let result: Result
    }

    private static func fetchCookies(port: Int, browserPath: String) async throws -> [Cookie] {
        let path = browserPath.hasPrefix("/") ? browserPath : "/" + browserPath
        guard let url = URL(string: "ws://127.0.0.1:\(port)\(path)") else {
            throw Failure(message: "调试端口地址无效")
        }
        let socket = URLSession.shared.webSocketTask(with: url)
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }

        let request = #"{"id":1,"method":"Storage.getCookies","params":{}}"#
        try await socket.send(.string(request))
        let message = try await withTimeout(seconds: 6) { try await socket.receive() }
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let raw): data = raw
        @unknown default: throw Failure(message: "调试通道返回了未知帧")
        }
        return try JSONDecoder().decode(CookieResponse.self, from: data).result.cookies
    }

    private static func withTimeout<T>(seconds: Double, _ body: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw Failure(message: "读取浏览器 Cookie 超时")
            }
            guard let first = try await group.next() else { throw Failure(message: "读取浏览器 Cookie 失败") }
            group.cancelAll()
            return first
        }
    }
}
