import Foundation

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

    /// 连接条右侧按钮：文案 + 点击动作，一处定义
    static func connectionCta(for state: String) -> (label: String, action: String) {
        switch state {
        case "unconfigured": return ("去登录", "relogin")
        case "offline": return ("重试", "refresh")
        case "denied": return ("重新登录", "relogin")
        default: return ("重新登录", "relogin")
        }
    }

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
