import Foundation

/// 7 天柱状图的一天（只存裸数值，标签在 StateBuilder 里格式化）
struct DailyBucket: Codable {
    var key: String      // yyyy-MM-dd，本地时区
    var tokens: Int
}

// MARK: - DTO → 视图状态（纯函数，原生壳直接调）

enum StateBuilder {
    struct Inputs {
        var theme: String
        var prefs: PrefsSnapshot
        var now: Date
        var version: String = "0.1.0"
        var animate: Bool = true
        var busy: Bool = false
        var connection: PanelState.Connection = .init(state: "ok", message: "")
        var workspace: APIWorkspace? = nil
        var snapshot: APISnapshot? = nil
        var codingPlan: APICodingPlan? = nil
        var usage: APIUsagePage? = nil
        var daily: [DailyBucket] = []
        var dailyState: String = "loading"
        var email: String = ""
        var lastSync: Date? = nil
        var offers: [APISubscriptionOffer] = []
    }

    static func panelState(_ i: Inputs) -> PanelState {
        let plan = planView(i)
        return PanelState(
            theme: i.theme,
            animate: i.animate,
            version: i.version,
            connection: i.connection,
            prefs: .init(display: i.prefs.display, threshold: i.prefs.threshold),
            plan: plan,
            windows: windowViews(i),
            wallet: walletView(i),
            usage: usageView(i),
            sync: .init(label: syncLabel(i), busy: i.busy),
            account: .init(workspaceName: i.workspace?.workspaceName ?? "",
                           email: i.email,
                           planLabel: "\(plan.label) · \(i.connection.state == "ok" ? "正常" : "异常")",
                           ownerName: i.snapshot?.owner?.displayName ?? ""))
    }

    // MARK: 套餐

    static func planView(_ i: Inputs) -> PanelState.PlanView {
        let tier = tier(i)
        let label = tier.isEmpty ? "—" : tier.capitalized
        let yearly = isYearly(i.snapshot?.plan?.interval)
        // 价格只信官方 offers（同档位 + 同计费周期）；拿不到就不显示价格
        let offer = i.offers.first {
            ($0.membershipTier ?? "").lowercased() == tier && isYearly($0.billingInterval) == yearly
        }
        let priceLabel = offer.flatMap { usdLabel($0.finalPriceUsd ?? $0.originalPriceUsd) } ?? ""
        let intervalLabel = priceLabel.isEmpty ? "" : "\(yearly ? "年付" : "月付") \(priceLabel)"
        let periodEnd = Formatters.date(i.snapshot?.plan?.currentPeriodEnd ?? i.snapshot?.wallet?.expiresAt)
        // 月付时价格行已经写了 "$10 / 月"，这里不再重复「月付 $10」；年付才把「年付 $84」放进期间行
        let periodLabel: String = {
            let day = periodEnd.map { Formatters.monthDay($0) + "到期" } ?? ""
            if yearly, !priceLabel.isEmpty {
                return ["年付 \(priceLabel)", day].filter { !$0.isEmpty }.joined(separator: " · ")
            }
            return day.isEmpty ? intervalLabel : day
        }()
        // 没拿到任何订阅信息时不要写「已过期」——那是「没登录」不是「过期了」
        let billingState = (i.snapshot?.billing?.billingState ?? i.workspace?.billingState ?? "").lowercased()
        let stateLabel: String
        switch billingState {
        case "": stateLabel = "未连接"
        case "active": stateLabel = i.snapshot?.plan?.cancelAtPeriodEnd == true ? "期末取消" : "生效中"
        case "free", "trial", "trialing": stateLabel = "免费"
        case "canceled", "expired", "past_due", "unpaid": stateLabel = "已过期"
        default: stateLabel = "未订阅"
        }
        return .init(tier: tier, label: label, badge: label,
                     intervalLabel: intervalLabel, priceLabel: priceLabel,
                     priceUnit: yearly ? "/ 年" : "/ 月",
                     stateLabel: stateLabel, periodLabel: periodLabel)
    }

    /// snapshot 是主数据源，缺了才退到 coding-plan（两个接口点数量一致）
    static func windowViews(_ i: Inputs) -> [PanelState.WindowView] {
        let raw = i.snapshot?.designPlanWindows ?? i.codingPlan?.windows ?? []
        var seen = Set<String>()
        let views: [PanelState.WindowView] = raw.compactMap { w in
            let kind = w.kind ?? w.durationSeconds.map { $0 == 604_800 ? "7d" : "\($0 / 3_600)h" } ?? ""
            guard !kind.isEmpty, !seen.contains(kind),
                  let limit = Int(w.limitCredits ?? ""), limit > 0,
                  let remaining = Int(w.remainingCredits ?? ""), remaining >= 0, remaining <= limit
            else { return nil }                       // limit 0 / 剩余超限 / kind 重复 → 该窗口不可用
            seen.insert(kind)
            return .init(kind: kind,
                         label: kind == "5h" ? "5 hour" : kind,
                         remainingPercent: (remaining * 100 + limit / 2) / limit,
                         resetLabel: Formatters.date(w.resetsAt).map { Formatters.resetLabel(until: $0, now: i.now) } ?? "")
        }
        return views.sorted { rank($0.kind) < rank($1.kind) }
    }

    static func walletView(_ i: Inputs) -> PanelState.WalletView {
        let balance = Decimal(string: i.snapshot?.wallet?.balanceUsd ?? "") ?? 0
        return .init(label: Formatters.usd(balance, fractionDigits: 2), caption: balance > 0 ? "可用" : "已用尽")
    }

    // MARK: 用量

    static func usageView(_ i: Inputs) -> PanelState.UsageView {
        let summary = i.usage?.summary
        let input = summary?.inputTokens ?? 0
        let output = summary?.outputTokens ?? 0
        let days = lastSevenDays(i.now)
        return .init(
            totalLabel: Formatters.tokens(input + output),
            dailyAvgLabel: Formatters.tokens((input + output) / 7),
            windowLabel: "近 7 天",
            rangeLabel: "\(Formatters.monthDay(days[0])) – \(Formatters.monthDay(days[6]))",
            inputLabel: Formatters.tokens(input),
            outputLabel: Formatters.tokens(output),
            cacheReadLabel: Formatters.tokens(summary?.cacheReadTokens ?? 0),
            cacheWriteLabel: Formatters.tokens(summary?.cacheWriteTokens ?? 0),
            dailyState: i.dailyState,
            dailyFallbackText: fallbackText(i.dailyState),
            daily: dailyViews(days, i),
            recent: recentViews(i))
    }

    static func dailyViews(_ days: [Date], _ i: Inputs) -> [PanelState.DailyView] {
        let byKey = Dictionary(i.daily.map { ($0.key, $0.tokens) }, uniquingKeysWith: +)
        let maxTokens = max(1, byKey.values.max() ?? 0)
        return days.map { day in
            let key = dayKey(day)
            let tokens = byKey[key] ?? 0
            let isToday = Calendar.current.isDate(day, inSameDayAs: i.now)
            return .init(key: key,
                         weekday: Formatters.weekdayShort(day, now: i.now),
                         label: isToday ? "今天" : Formatters.monthDay(day),
                         tokensLabel: Formatters.tokens(tokens),
                         ratio: (Double(tokens) / Double(maxTokens) * 100).rounded() / 100,
                         isToday: isToday)
        }
    }

    /// 最近 3 条；金额用 listChargedUsd（amountUsd 对 design_plan 恒为 -0.0000）
    static func recentViews(_ i: Inputs) -> [PanelState.RecentView] {
        let entries = (i.usage?.entries ?? [])
            .sorted { (Formatters.date($0.createdAt) ?? .distantPast) > (Formatters.date($1.createdAt) ?? .distantPast) }
            .prefix(3)
        return entries.map { entry in
            let model = entry.model ?? entry.runtime ?? entry.detail ?? ""
            let onPlan = entry.usageType == "design_plan"
            return .init(model: model,
                         badge: badge(model),
                         when: Formatters.date(entry.createdAt).map { Formatters.clock($0, now: i.now) } ?? "",
                         inputLabel: Formatters.grouped(entry.inputTokens ?? 0),
                         outputLabel: Formatters.grouped(entry.outputTokens ?? 0),
                         costLabel: Formatters.costLabel(Decimal(string: entry.listChargedUsd ?? "") ?? 0),
                         tag: onPlan ? "Design Plan" : (entry.usageType ?? ""),
                         tagKind: onPlan ? "plan" : "other")
        }
    }

    static func syncLabel(_ i: Inputs) -> String {
        if i.busy { return "正在同步…" }
        guard let lastSync = i.lastSync else { return "尚未同步" }
        return Formatters.relative(lastSync, now: i.now) + "同步"
    }

    static func fallbackText(_ dailyState: String) -> String {
        switch dailyState {
        case "ready": return ""
        case "unavailable": return "近 7 天逐日统计暂不可用，上方为累计用量。"
        default: return "正在统计近 7 天用量…"
        }
    }

    // MARK: 设置

    // MARK: 小工具

    static func dayKey(_ date: Date) -> String { keyFormatter.string(from: date) }

    /// 最近 7 个自然日（含今天），柱状图固定 7 根
    static func lastSevenDays(_ now: Date) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private static func tier(_ i: Inputs) -> String {
        (i.snapshot?.plan?.tier ?? i.snapshot?.billing?.planId ?? i.workspace?.planId ?? i.codingPlan?.tier ?? "").lowercased()
    }

    private static func isYearly(_ interval: String?) -> Bool {
        ["year", "yearly", "annual"].contains((interval ?? "").lowercased())
    }

    /// "10.00" -> "$10"，"10.50" -> "$10.50"
    private static func usdLabel(_ raw: String?) -> String? {
        guard let raw, let value = Double(raw), value > 0 else { return nil }
        if value.rounded() == value { return "$" + String(Int(value)) }
        return String(format: "$%.2f", value)
    }

    private static func rank(_ kind: String) -> Int { ["5h": 0, "7d": 1][kind] ?? 9 }

    private static func badge(_ model: String) -> String {
        let families: [String: String] = ["deepseek": "DS", "claude": "CH", "glm": "GL",
                                          "gpt": "GP", "gemini": "GE", "llama": "LL", "qwen": "QW"]
        let lower = model.lowercased()
        for (prefix, badge) in families where lower.hasPrefix(prefix) { return badge }
        return String(lower.prefix(2)).uppercased()
    }

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

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
            let list = (try? await deps.api.workspaces()) ?? []
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
        try? FileManager.default.removeItem(at: Self.cacheURL)
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
        guard let data = try? encoder.encode(cached) else { return }
        try? FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: Self.cacheURL, options: .atomic)
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL) else { return }
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
