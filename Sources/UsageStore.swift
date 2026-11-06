import Foundation

// MARK: - 刷新 / 缓存 / 聚合

final class UsageStore {
    struct Deps {
        var api: OpenDesignAPI
        var prefs: () -> PrefsSnapshot
        var now: () -> Date
        var theme: () -> String = { "dark" }
        var version: String = "0.1.0"
        var build: String = ""
        var email: () -> String = { "" }
        var baseUrl: () -> String = { "" }
        var token: () -> String? = { nil }
    }

    var onPanelState: ((PanelState) -> Void)?

    /// StateDump 用临时目录，避免碰 App 的真实缓存
    static var cacheDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.ryan.margin", isDirectory: true)

    private let deps: Deps
    private var workspace: APIWorkspace?
    private var snapshot: APISnapshot?
    private var codingPlan: APICodingPlan?
    private var usagePage: APIUsagePage?
    private var daily: [DailyBucket] = []
    private var dailyState = "loading"
    private var offers: [APISubscriptionOffer] = []
    private var workspaceOptions: [APIWorkspaceListItem] = []

    /// 设置页用：可选工作区 + 当前工作区
    var workspaceChoices: [WorkspaceOption] {
        workspaceOptions.map {
            WorkspaceOption(id: $0.workspaceId, name: $0.workspaceName ?? $0.workspaceId,
                            kind: $0.workspaceType ?? "")
        }
    }
    var activeWorkspaceId: String { workspace?.workspaceId ?? "" }
    private var dailyFetchedAt: Date?
    private var lastSync: Date?
    private var connection = PanelState.Connection(state: "unconfigured", message: "还没有连接 OpenDesign 工作区")
    private var panel: PanelState?
    private var refreshing = false
    private var dailyInFlight = false
    /// 每次 reset 递增：在途请求回来时如果对不上就直接丢弃，避免退出登录后被旧响应写回「已连接」
    private var generation = 0

    private var emitCount = 0

    init(deps: Deps) {
        self.deps = deps
        loadCache()
    }

    func snapshotState() -> PanelState? { panel }

    /// 冷启动：先推缓存那一帧，再打三个并发请求
    func refresh(userInitiated: Bool) async {
        if refreshing { return }
        let gen = generation
        refreshing = true
        // 结束时要再 emit 一次：此时 busy 已经落回 false，否则界面会一直停在「正在同步…」
        defer {
            refreshing = false
            if gen == generation { emit() }
        }

        guard deps.api.hasToken else {
            connection = .init(state: "unconfigured", message: "还没有连接 OpenDesign 工作区")
            emit()
            return
        }
        emit()

        do {
            let list: [APIWorkspaceListItem]
            do {
                list = try await deps.api.workspaces()
            } catch {
                NSLog("margin: workspaces failed \(error.localizedDescription)")
                list = []
            }
            if !list.isEmpty { workspaceOptions = list }

            // 默认工作区以 /workspaces/current 为准；偏好里选过就用选中的那个
            let current = try await deps.api.workspace()
            let target = deps.prefs().workspaceId.flatMap { id in
                workspaceOptions.first(where: { $0.workspaceId == id })
            }
            if let target, target.workspaceId != current.workspaceId {
                if workspace?.workspaceId != target.workspaceId {
                    workspace = current
                    workspace?.workspaceId = target.workspaceId
                    workspace?.workspaceName = target.workspaceName
                    workspace?.billingState = nil
                    daily = []
                    dailyFetchedAt = nil
                }
            } else {
                if workspace?.workspaceId != current.workspaceId {
                    daily = []
                    dailyFetchedAt = nil
                }
                workspace = current
            }
            guard let workspaceId = workspace?.workspaceId, !workspaceId.isEmpty else { throw ODError.decoding }

            async let snapshotRequest = deps.api.snapshot(workspaceId: workspaceId)
            async let codingPlanRequest = deps.api.codingPlan(workspaceId: workspaceId)
            async let usageRequest = deps.api.usage(workspaceId: workspaceId, limit: 20, cursor: nil, from: nil, to: nil)
            async let offersRequest = try? deps.api.subscriptionOffers()
            let (snapshot, codingPlan, usagePage) = try await (snapshotRequest, codingPlanRequest, usageRequest)
            offers = (await offersRequest) ?? offers

            guard snapshot.workspaceId == nil || snapshot.workspaceId == workspaceId else { throw ODError.decoding }
            guard gen == generation else { return }
            self.snapshot = snapshot
            self.codingPlan = codingPlan
            self.usagePage = usagePage
            connection = .init(state: "ok", message: "")
            lastSync = deps.now()
            emit()
            saveCache()
        } catch {
            guard gen == generation else { return }
            connection = Self.classify(error)
            emit()
        }
    }

    /// 7 天柱状图的刷新策略（与 15 分钟一次的配额刷新解耦）：
    /// - force（⌘R / 手动刷新）：全量重算 7 天
    /// - 距上次成功不到 30 分钟：直接返回（点开面板不重复拉）
    /// - 缓存为空、或超过 24 小时没算过：全量重算
    /// - 其余情况：只重算「今天」这一桶（1–4 个请求，2 小时一次足够）
    func refreshDailySeriesIfNeeded(force: Bool = false) async {
        guard !dailyInFlight,
              let workspaceId = workspace?.workspaceId, !workspaceId.isEmpty else { return }
        let gen = generation
        let now = deps.now()
        let age = dailyFetchedAt.map { now.timeIntervalSince($0) } ?? .infinity
        if !force, age < 30 * 60, !daily.isEmpty { return }

        dailyInFlight = true
        defer { dailyInFlight = false }

        // 跨天（今天的桶还不在缓存里）时做一次全量，避免昨天末尾的几分钟永远缺
        let dayRolled = daily.last?.key != StateBuilder.dayKey(now)
        let fullRebuild = force || daily.isEmpty || age > 24 * 3600 || dayRolled
        do {
            if fullRebuild {
                let from = now.addingTimeInterval(-7 * 86_400)
                let totals = try await fetchDailyTotals(workspaceId: workspaceId, from: from, to: now, maxPages: 70)
                daily = StateBuilder.lastSevenDays(now).map {
                    DailyBucket(key: StateBuilder.dayKey($0), tokens: totals[StateBuilder.dayKey($0)] ?? 0)
                }
            } else {
                // 只有今天在变，昨天及更早的桶直接用缓存
                let startOfToday = Calendar.current.startOfDay(for: now)
                let totals = try await fetchDailyTotals(workspaceId: workspaceId, from: startOfToday, to: now, maxPages: 24)
                let todayKey = StateBuilder.dayKey(now)
                let previous = Dictionary(uniqueKeysWithValues: daily.map { ($0.key, $0.tokens) })
                daily = StateBuilder.lastSevenDays(now).map { day in
                    let key = StateBuilder.dayKey(day)
                    return DailyBucket(key: key, tokens: key == todayKey ? (totals[key] ?? 0) : (previous[key] ?? 0))
                }
            }
            guard gen == generation else { return }
            dailyFetchedAt = now
            dailyState = "ready"
            NSLog("margin: daily \(fullRebuild ? "full" : "today-only") ok")
            emit()
            saveCache()
        } catch {
            dailyState = "unavailable"
            NSLog("margin: daily failed \(error)")
            emit()
        }
    }

    /// 退出登录：清掉内存与磁盘缓存，回到「未配置」。
    /// 导出进度（0 表示空闲）
    private(set) var exporting = false
    func setExporting(_ on: Bool) {
        exporting = on
        if !on { exportCount = 0 }
        emit()
    }
    private(set) var exportCount = 0
    func reportExport(_ count: Int) {
        exportCount = count
        emit()
    }

    func reset() {
        generation += 1
        workspace = nil
        workspaceOptions = []
        snapshot = nil
        codingPlan = nil
        usagePage = nil
        offers = []
        daily = []
        dailyFetchedAt = nil
        lastSync = nil
        dailyState = "loading"
        connection = .init(state: "unconfigured", message: "还没有连接 OpenDesign 工作区")
        do {
            try FileManager.default.removeItem(at: Self.cacheURL)
        } catch CocoaError.fileNoSuchFile {
            // 本来就没有缓存，忽略
        } catch {
            NSLog("margin: cache delete failed \(error.localizedDescription)")
        }
        emit()
    }

    /// 翻页取一段窗口内的 Token 总量（100/页、250ms 间隔、跨过窗口起点就停）
    /// 按天切窗并行取：7 天 = 7 条独立分页链，整体时间约为串行的 1/5
    private func fetchDailyTotals(workspaceId: String, from: Date, to: Date, maxPages: Int) async throws -> [String: Int] {
        let calendar = Calendar.current
        var windows: [(Date, Date)] = []
        var dayStart = calendar.startOfDay(for: from)
        while dayStart < to {
            let next = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? to
            let start = max(dayStart, from)
            let end = min(next, to)
            if start < end { windows.append((start, end)) }
            dayStart = next
        }
        if windows.isEmpty { windows = [(from, to)] }

        return try await withThrowingTaskGroup(of: [String: Int].self) { group in
            for (start, end) in windows {
                group.addTask {
                    try await self.fetchWindowTotals(workspaceId: workspaceId, from: start, to: end,
                                                     maxPages: min(maxPages, 16))
                }
            }
            var merged: [String: Int] = [:]
            for try await part in group {
                for (key, value) in part { merged[key, default: 0] += value }
            }
            return merged
        }
    }

    /// 单日窗口内的分页聚合
    private func fetchWindowTotals(workspaceId: String, from: Date, to: Date, maxPages: Int) async throws -> [String: Int] {
        var totals: [String: Int] = [:]
        var cursor: String?
        var pages = 0
        while pages < maxPages {
            let page = try await deps.api.usage(workspaceId: workspaceId, limit: 100,
                                                cursor: cursor, from: from, to: to)
            pages += 1
            for entry in page.entries ?? [] {
                guard let at = Formatters.date(entry.createdAt), at >= from, at <= to else { continue }
                totals[StateBuilder.dayKey(at), default: 0] += (entry.inputTokens ?? 0) + (entry.outputTokens ?? 0)
            }
            guard page.hasMore == true, let next = page.nextCursor, !next.isEmpty else { break }
            cursor = next
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        return totals
    }

    /// 两张表：逐日用量 + 结算明细（docs/01 §6.7）
    /// 导出近 N 天：汇总 + 全量明细（翻页取完，而不是面板里那一页）
    func exportCSV(days: Int = 7, progress: ((Int) -> Void)? = nil) async -> String {
        let entries = await allEntries(days: days, progress: progress)

        // 汇总直接由明细算，避免缓存的 daily 少算早期天数
        var totals: [String: Int] = [:]
        for entry in entries {
            guard let at = Formatters.date(entry.createdAt) else { continue }
            totals[StateBuilder.dayKey(at), default: 0] += (entry.inputTokens ?? 0) + (entry.outputTokens ?? 0)
        }
        var lines = ["日期,Token 消耗"]
        for key in totals.keys.sorted() { lines.append("\(key),\(totals[key] ?? 0)") }
        lines.append("")
        lines.append("结算时间,发起人,模型,输入 Token,输出 Token,缓存读取,缓存写入,消耗额度 (USD),抵扣方式")
        for entry in entries {
            let cost = Decimal(string: entry.listChargedUsd ?? entry.amountUsd ?? "") ?? 0
            let at: String = Formatters.date(entry.createdAt).map(csvTime) ?? ""
            let model: String = entry.model ?? entry.runtime ?? ""
            let cacheRead: String = entry.cacheReadTokens.map(String.init) ?? ""
            let cacheWrite: String = entry.cacheWriteTokens.map(String.init) ?? ""
            let tag: String = entry.usageType == "design_plan" ? "Design Plan 额度抵扣" : (entry.usageType ?? "")
            let cells: [String] = [at, entry.initiator ?? "", model,
                                   String(entry.inputTokens ?? 0), String(entry.outputTokens ?? 0),
                                   cacheRead, cacheWrite,
                                   Formatters.plain(cost < 0 ? cost : -cost, fractionDigits: 4), tag]
            lines.append(cells.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    /// 按天并行把窗口内的明细取回来（去重、按时间倒序）
    private func allEntries(days: Int, progress: ((Int) -> Void)? = nil) async -> [APIUsageEntry] {
        guard let workspaceId = workspace?.workspaceId, !workspaceId.isEmpty else {
            return usagePage?.entries ?? []
        }
        let calendar = Calendar.current
        let now = deps.now()
        let startOfToday = calendar.startOfDay(for: now)
        let from = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) ?? startOfToday

        var windows: [(Date, Date)] = []
        var dayStart = from
        while dayStart < now {
            let next = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now
            windows.append((dayStart, min(next, now)))
            dayStart = next
        }

        var collected: [APIUsageEntry] = []
        await withTaskGroup(of: [APIUsageEntry].self) { group in
            for (start, end) in windows {
                group.addTask { await Self.entriesInWindow(api: self.deps.api, workspaceId: workspaceId, from: start, to: end) }
            }
            for await part in group {
                collected.append(contentsOf: part)
                progress?(collected.count)
            }
        }

        var seen = Set<String>()
        var result: [APIUsageEntry] = []
        for entry in collected {
            let key = entry.id ?? "\(entry.createdAt ?? "")-\(entry.inputTokens ?? 0)-\(entry.outputTokens ?? 0)"
            if seen.insert(key).inserted { result.append(entry) }
        }
        result.sort { (Formatters.date($0.createdAt) ?? .distantPast) > (Formatters.date($1.createdAt) ?? .distantPast) }
        NSLog("margin: export \(result.count) entries over \(windows.count) days")
        return result
    }

    /// 单日窗口的分页抓取（最多 20 页 ≈ 2000 条/天）
    private static func entriesInWindow(api: OpenDesignAPI, workspaceId: String,
                                        from: Date, to: Date) async -> [APIUsageEntry] {
        var result: [APIUsageEntry] = []
        var cursor: String?
        var pages = 0
        while pages < 20 {
            guard let page = try? await api.usage(workspaceId: workspaceId, limit: 100,
                                                  cursor: cursor, from: from, to: to) else { break }
            let batch = page.entries ?? []
            pages += 1
            result.append(contentsOf: batch)
            guard page.hasMore == true, let next = page.nextCursor, !next.isEmpty, !batch.isEmpty else { break }
            cursor = next
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        return result
    }

    // MARK: 内部

    private func emit() {
        let now = deps.now()
        let prefs = deps.prefs()
        let theme = deps.theme()
        var state = StateBuilder.panelState(.init(
            theme: theme, prefs: prefs, now: now, version: deps.version, busy: refreshing,
            connection: connection, workspace: workspace, snapshot: snapshot, codingPlan: codingPlan,
            usage: usagePage, daily: daily, dailyState: dailyState, email: deps.email(), lastSync: lastSync,
            offers: offers))
        state.exporting = exporting
        state.exportCount = exportCount
        panel = state
        DispatchQueue.main.async {          // 面板在 WebView 里，只能主线程推
            self.onPanelState?(state)
        }
    }

    private static func classify(_ error: Error) -> PanelState.Connection {
        switch error {
        case ODError.unauthorized: return .init(state: "expired", message: "登录已过期")
        case ODError.forbidden: return .init(state: "denied", message: "当前工作区无计费查看权限")
        case ODError.rateLimited: return .init(state: "offline", message: "请求过于频繁，稍后重试")
        case ODError.server(let code): return .init(state: "offline", message: "服务异常（HTTP \(code)）")
        case ODError.decoding: return .init(state: "offline", message: "响应解析失败")
        default: return .init(state: "offline", message: "网络不可用 · 显示上次数据")
        }
    }

    private func csvTime(_ date: Date) -> String { Self.csvFormatter.string(from: date) }

    private static let csvFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    // MARK: 磁盘缓存

    private struct Cached: Codable {
        var fetchedAt: Date?
        var dailyFetchedAt: Date?
        var workspace: APIWorkspace?
        var snapshot: APISnapshot?
        var codingPlan: APICodingPlan?
        var usagePage: APIUsagePage?
        var daily: [DailyBucket]?
        var offers: [APISubscriptionOffer]?
    }

    private static var cacheURL: URL { cacheDirectory.appendingPathComponent("cache.json") }

    private func saveCache() {
        let cached = Cached(fetchedAt: lastSync, dailyFetchedAt: dailyFetchedAt, workspace: workspace,
                            snapshot: snapshot, codingPlan: codingPlan, usagePage: usagePage, daily: daily,
                            offers: offers)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cached) else {
            NSLog("margin: cache encode failed")
            return
        }
        do {
            try FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: Self.cacheURL, options: .atomic)
        } catch {
            NSLog("margin: cache write failed \(error.localizedDescription)")
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL) else {
            NSLog("margin: no cache to load")
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let cached = try? decoder.decode(Cached.self, from: data) else { return }
        workspace = cached.workspace
        snapshot = cached.snapshot
        codingPlan = cached.codingPlan
        usagePage = cached.usagePage
        daily = cached.daily ?? []
        offers = cached.offers ?? []
        dailyFetchedAt = cached.dailyFetchedAt
        lastSync = cached.fetchedAt
        dailyState = daily.isEmpty ? "loading" : "ready"
        if snapshot != nil { connection = .init(state: "ok", message: "") }
        emit()          // 冷启动第一帧就走缓存，别等网络
    }
}
