import Foundation

/// 离线复放 fixtures/captured 的真实响应，跑通 UsageStore → StateBuilder，断言面板关键数值。
/// swiftc -O -swift-version 5 Sources/{Contracts,Formatters,OpenDesignAPI,CredentialStore,UsageStore}.swift tools/StateDump.swift -o /tmp/statedump
@main
struct StateDump {
    static func main() async {
        var fixtures = "fixtures/captured"
        var now = Date()
        var arguments = CommandLine.arguments.dropFirst().makeIterator()
        while let argument = arguments.next() {
            switch argument {
            case "--fixtures": fixtures = arguments.next() ?? fixtures
            case "--now": now = Formatters.date(arguments.next()) ?? now
            default: print("忽略未知参数 \(argument)")
            }
        }

        let dir = URL(fileURLWithPath: fixtures)
        let series = dailySeries(dir)
        let log = RequestLog()
        let api = fixtureAPI(dir: dir, series: series, now: now, log: log)

        let cacheDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("margin-statedump-cache")
        try? FileManager.default.removeItem(at: cacheDir)
        UsageStore.cacheDirectory = cacheDir

        var deps = UsageStore.Deps(api: api, prefs: { PrefsSnapshot() }, now: { now })
        deps.theme = { "dark" }
        deps.email = { "ryan@example.com" }
        deps.baseUrl = { "https://amr-api.open-design.ai/api" }
        deps.token = { "fixture-token-0123456789" }
        let store = UsageStore(deps: deps)
        var pushed: PanelState?
        store.onPanelState = { pushed = $0 }

        await store.refresh(userInitiated: true)
        await store.refreshDailySeriesIfNeeded()

        guard let state = store.snapshotState() ?? pushed else {
            print("没有拿到 PanelState"); exit(1)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: (try? encoder.encode(state)) ?? Data(), as: UTF8.self))
        print("")

        // MARK: 断言

        var checks: [(String, Bool, String)] = []
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            checks.append((name, ok, detail))
        }
        func expect(_ name: String, _ actual: String, _ expected: String) {
            check(name, actual == expected, "期望 \(expected)，实际 \(actual)")
        }

        let fiveHour = state.windows.first { $0.kind == "5h" }
        let sevenDay = state.windows.first { $0.kind == "7d" }
        expect("5h 剩余 90%", "\(fiveHour?.remainingPercent ?? -1)", "90")
        expect("7d 剩余 86%", "\(sevenDay?.remainingPercent ?? -1)", "86")
        expect("5h 标题", fiveHour?.label ?? "", "5 hour")
        check("重置文案含「小时」", state.windows.map { $0.resetLabel }.joined().contains("小时"),
              state.windows.map { $0.resetLabel }.joined(separator: " / "))
        expect("钱包 $1.00", state.wallet.label, "$1.00")
        expect("钱包 caption", state.wallet.caption, "可用")
        expect("总计 539.39M", state.usage.totalLabel, "539.39M")
        expect("日均 77.06M", state.usage.dailyAvgLabel, "77.06M")
        expect("输入 534.66M", state.usage.inputLabel, "534.66M")
        expect("输出 4.73M", state.usage.outputLabel, "4.73M")
        expect("缓存读 526.19M", state.usage.cacheReadLabel, "526.19M")
        expect("缓存写 30.72K", state.usage.cacheWriteLabel, "30.72K")
        expect("日期区间", state.usage.rangeLabel, "10月31日 – 11月6日")
        expect("最近请求条数", "\(state.usage.recent.count)", "3")
        expect("单条金额 −$0.0022", state.usage.recent.first?.costLabel ?? "", "−$0.0022")
        expect("单条模型", state.usage.recent.first?.model ?? "", "deepseek-v4.1-flash")
        expect("单条徽标", state.usage.recent.first?.badge ?? "", "DS")
        expect("单条时间", state.usage.recent.first?.when ?? "", "今天 01:52")
        expect("单条输入 435", state.usage.recent.first?.inputLabel ?? "", "435")
        expect("单条输出 1,731", state.usage.recent.first?.outputLabel ?? "", "1,731")
        expect("单条标签", state.usage.recent.first?.tag ?? "", "Design Plan")
        expect("单条标签类型", state.usage.recent.first?.tagKind ?? "", "plan")
        expect("第二条金额", state.usage.recent.dropFirst().first?.costLabel ?? "", "−$0.0008")
        expect("套餐名 Go", state.plan.label, "Go")
        expect("套餐徽标", state.plan.badge, "Go")
        expect("套餐状态", state.plan.stateLabel, "生效中")
        expect("套餐价 $7", state.plan.priceLabel, "$7")
        expect("套餐价单位", state.plan.priceUnit, "/ 月")
        expect("计费周期", state.plan.intervalLabel, "月付 $7")
        expect("到期行", state.plan.periodLabel, "月付 $7 · 11月20日到期")
        expect("连接状态", state.connection.state, "ok")
        expect("工作区名", state.account.workspaceName, "示例工作区")
        expect("所属人", state.account.ownerName, "示例用户")
        expect("账号套餐行", state.account.planLabel, "Go · 正常")
        expect("同步文案", state.sync.label, "刚刚同步")
        expect("柱状图状态", state.usage.dailyState, "ready")
        expect("柱子根数", "\(state.usage.daily.count)", "7")
        expect("最后一天是今天", "\(state.usage.daily.last?.isToday ?? false)", "true")
        expect("今天星期", state.usage.daily.last?.weekday ?? "", "今")
        expect("11-03 用量", state.usage.daily.first { $0.key == "2026-11-03" }?.tokensLabel ?? "", "84.88M")
        expect("峰值柱 ratio", "\(state.usage.daily.first { $0.key == "2026-11-03" }?.ratio ?? 0)", "1.0")
        expect("降级文案为空", state.usage.dailyFallbackText, "")

        let asked = log.all
        check("Cookie 头齐全", asked.allSatisfy { $0.cookie == "__Secure-better-auth.session_token=fixture-token-0123456789" },
              "请求数 \(asked.count)")
        check("工作区接口带 X-Vela-Workspace-Id",
              asked.filter { $0.path.contains("/workspaces/czvhyl") }.allSatisfy { $0.workspace == "ws_example_personal" },
              asked.map { $0.path }.joined(separator: " | "))
        check("聚合用 limit=100 + from/to",
              asked.contains { $0.query.contains("limit=100") && $0.query.contains("from=") && $0.query.contains("to=") },
              asked.last?.query ?? "")

        // 错误分类：401/403/429/5xx 都要落到 connection.state
        for (status, expected) in [(401, "expired"), (403, "denied"), (429, "offline"), (503, "offline")] {
            var failing = OpenDesignAPI(baseURL: URL(string: "https://fixture.local/api")!, token: { "fixture-token" })
            failing.send = { _ in (Data("{}".utf8), status) }
            let store = UsageStore(deps: UsageStore.Deps(api: failing, prefs: { PrefsSnapshot() }, now: { now }))
            await store.refresh(userInitiated: true)
            expect("HTTP \(status) → connection.\(expected)", store.snapshotState()?.connection.state ?? "nil", expected)
        }

        let csv = store.csv()
        check("CSV 表头", csv.hasPrefix("日期,Token 消耗"), csv.split(separator: "\n").first.map(String.init) ?? "")
        check("CSV 结算表", csv.contains("结算时间,发起人,模型,输入 Token,输出 Token,缓存读取,缓存写入,消耗额度 (USD),抵扣方式"))
        check("CSV 金额 ASCII 负号无 $", csv.contains(",-0.0022,Design Plan 额度抵扣"))

        let reloaded = UsageStore(deps: deps).snapshotState()
        check("缓存冷启动可读", reloaded?.usage.totalLabel == state.usage.totalLabel,
              reloaded.map { "total=\($0.usage.totalLabel)" } ?? "缓存为空")

        print("==== 断言 ====")
        for (name, ok, detail) in checks {
            print("\(ok ? "PASS" : "FAIL")  \(name)\(ok || detail.isEmpty ? "" : "  →  \(detail)")")
        }
        let failed = checks.filter { !$0.1 }.count
        print("")
        print(failed == 0 ? "全部通过（\(checks.count) 项）" : "失败 \(failed) 项 / 共 \(checks.count) 项")
        if failed > 0 { exit(1) }
    }

    // MARK: fixtures 复放

    static func fixture(_ dir: URL, _ name: String) -> Data {
        (try? Data(contentsOf: dir.appendingPathComponent(name))) ?? Data()
    }

    /// usage.mock.json 的 dailySeries（4 天真实量级），用来造两页聚合响应
    static func dailySeries(_ dir: URL) -> [(daysAgo: Int, tokens: Int)] {
        let candidates = [dir.appendingPathComponent("usage.mock.json"),
                          dir.deletingLastPathComponent().appendingPathComponent("usage.mock.json")]
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let series = object["dailySeries"] as? [[String: Any]] else { continue }
            return series.compactMap { item in
                guard let daysAgo = item["daysAgo"] as? Int, let tokens = item["tokens"] as? Int else { return nil }
                return (daysAgo, tokens)
            }
        }
        return []
    }

    static func fixtureAPI(dir: URL, series: [(daysAgo: Int, tokens: Int)], now: Date, log: RequestLog) -> OpenDesignAPI {
        var api = OpenDesignAPI(baseURL: URL(string: "https://fixture.local/api")!, token: { "fixture-token-0123456789" })
        api.send = { request in
            let url = request.url!
            let path = url.path
            let query = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
            log.add(path: path, query: query,
                    cookie: request.value(forHTTPHeaderField: "Cookie"),
                    workspace: request.value(forHTTPHeaderField: "X-Vela-Workspace-Id"))

            if path.hasSuffix("/v1/workspaces/current") {
                return (fixture(dir, "workspaces.current.json"), 200)
            }
            if path.hasSuffix("/billing/snapshot") {
                return (fixture(dir, "billing.snapshot.json"), 200)
            }
            if path.hasSuffix("/billing/coding-plan-usage") {
                return (fixture(dir, "billing.coding-plan-usage.json"), 200)
            }
            if path.hasSuffix("/v1/billing/summary") {
                return (fixture(dir, "billing.summary.json"), 200)
            }
            if path.hasSuffix("/billing/usage") {
                if query.contains("from=") {
                    return (aggregatePage(series, cursor: query.contains("cursor=") ? "next" : nil, now: now), 200)
                }
                return (fixture(dir, "billing.usage.json"), 200)
            }
            return (Data(), 404)
        }
        return api
    }

    /// 两页：新的一天先来，第二页给出更早的两天并 hasMore=false
    static func aggregatePage(_ series: [(daysAgo: Int, tokens: Int)], cursor: String?, now: Date) -> Data {
        let picks = series.filter { cursor == nil ? $0.daysAgo <= 1 : $0.daysAgo >= 2 }
        let entries = picks.map { item -> String in
            let at = Formatters.iso(now.addingTimeInterval(Double(-item.daysAgo) * 86_400))
            return """
            {"id":"fixture-\(item.daysAgo)","type":"model_usage","createdAt":"\(at)",\
            "model":"deepseek-v4.1-flash","runtime":"deepseek-v4.1-flash","usageType":"design_plan",\
            "inputTokens":\(item.tokens),"outputTokens":0,"listChargedUsd":"0.0000"}
            """
        }
        let json = """
        {"workspaceId":"ws_example_personal","entries":[\(entries.joined(separator: ","))],\
        "totalCount":5211,"hasMore":\(cursor == nil ? "true" : "false"),\
        "nextCursor":\(cursor == nil ? "\"fixture-page-2\"" : "null")}
        """
        return Data(json.utf8)
    }
}

final class RequestLog {
    struct Entry { var path: String; var query: String; var cookie: String?; var workspace: String? }

    private let lock = NSLock()
    private var entries: [Entry] = []

    func add(path: String, query: String, cookie: String?, workspace: String?) {
        lock.lock()
        entries.append(Entry(path: path, query: query, cookie: cookie, workspace: workspace))
        lock.unlock()
    }

    var all: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}
