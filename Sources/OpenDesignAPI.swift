import Foundation

enum ODError: Error {
    case unauthorized, forbidden, rateLimited, server(Int), decoding, network
}

/// OpenDesign 只读 API 客户端（docs/03 全部实测字段）
struct OpenDesignAPI {
    /// 唯一注入点：StateDump 用 fixtures 复放，App 用 live
    var send: (URLRequest) async throws -> (Data, Int) = OpenDesignAPI.live

    private let apiBase: URL
    private let token: () -> String?

    init(baseURL: URL, token: @escaping () -> String?) {
        self.apiBase = OpenDesignAPI.apiBase(from: baseURL)
        self.token = token
    }

    /// 用户填的是 https://amr-api.open-design.ai，API 实际挂在 /api 下；已带 /api 的不重复加。
    static func apiBase(from url: URL) -> URL {
        var text = url.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        if !text.hasSuffix("/api") { text += "/api" }
        return URL(string: text) ?? url
    }

    var hasToken: Bool { !(token() ?? "").isEmpty }

    func workspaces() async throws -> [APIWorkspaceListItem] {
        struct Envelope: Codable { var items: [APIWorkspaceListItem]? }
        let envelope: Envelope = try await get("v1/workspaces")
        return envelope.items ?? []
    }

    func workspace() async throws -> APIWorkspace {
        try await get("v1/workspaces/current")
    }

    func snapshot(workspaceId: String) async throws -> APISnapshot {
        try await get("v1/workspaces/\(workspaceId)/billing/snapshot", workspaceId: workspaceId)
    }

    func codingPlan(workspaceId: String) async throws -> APICodingPlan {
        try await get("v1/workspaces/\(workspaceId)/billing/coding-plan-usage", workspaceId: workspaceId)
    }

    /// limit 上限 100；from/to 必须是 ISO 8601 datetime（docs/03 §2.4）
    func usage(workspaceId: String, limit: Int, cursor: String?, from: Date?, to: Date?) async throws -> APIUsagePage {
        var query = [URLQueryItem(name: "limit", value: String(min(limit, 100)))]
        if let cursor, !cursor.isEmpty { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let from { query.append(URLQueryItem(name: "from", value: Formatters.iso(from))) }
        if let to { query.append(URLQueryItem(name: "to", value: Formatters.iso(to))) }
        return try await get("v1/workspaces/\(workspaceId)/billing/usage", workspaceId: workspaceId, query: query)
    }

    func billingSummary() async throws -> APIBillingSummary {
        try await get("v1/billing/summary")
    }

    /// 官方价目：每个档位按月/年各一条，含折后价（finalPriceUsd）。
    func subscriptionOffers() async throws -> [APISubscriptionOffer] {
        let page: APISubscriptionOffers = try await get("v1/billing/subscription/offers")
        return page.offers ?? []
    }

    static func validate(baseURL: URL, token: String) async throws -> APIWorkspace {
        let api = OpenDesignAPI(baseURL: baseURL, token: { token })
        return try await api.workspace()
    }

    // MARK: - 传输

    /// 带退避的重试：429 / 5xx / 网络抖动的请求会重试 3 次（250ms → 500ms → 1s）
    private func get<T: Decodable>(_ path: String, workspaceId: String? = nil, query: [URLQueryItem] = []) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await performGet(path, workspaceId: workspaceId, query: query)
            } catch let error as ODError {
                attempt += 1
                let retriable: Bool
                switch error {
                case .rateLimited, .network:
                    retriable = true
                case .server(let code):
                    retriable = code >= 500
                default:
                    retriable = false
                }
                guard retriable, attempt <= 3 else { throw error }
                let delay = UInt64(pow(2.0, Double(attempt - 1)) * 250_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    private func performGet<T: Decodable>(_ path: String, workspaceId: String? = nil, query: [URLQueryItem] = []) async throws -> T {
        guard let token = token(), !token.isEmpty else { throw ODError.unauthorized }
        var comps = URLComponents(string: apiBase.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + path)
        if !query.isEmpty { comps?.queryItems = query }
        guard let url = comps?.url else { throw ODError.network }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("__Secure-better-auth.session_token=\(token)", forHTTPHeaderField: "Cookie")
        if let workspaceId { request.setValue(workspaceId, forHTTPHeaderField: "X-Vela-Workspace-Id") }

        await apiGate.acquire()
        let result: (Data, Int)
        do {
            result = try await send(request)
        } catch {
            await apiGate.release()
            throw error
        }
        await apiGate.release()
        let (data, status) = result
        switch status {
        case 200..<300: break
        case 401: throw ODError.unauthorized
        case 403: throw ODError.forbidden
        case 429: throw ODError.rateLimited
        default: throw ODError.server(status)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)   // 字段即 camelCase，未知字段忽略
        } catch {
            throw ODError.decoding
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    static let live: (URLRequest) async throws -> (Data, Int) = { request in
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw ODError.network
        }
    }
}
