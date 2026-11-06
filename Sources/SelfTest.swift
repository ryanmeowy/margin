import Foundation

/// 纯函数自测：`Margin --self-test`。不依赖网络与 UI，几毫秒跑完。
enum SelfTest {
    private static var failures = 0

    private static func check(_ name: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("  ✓ " + name)
        } else {
            failures += 1
            print("  ✗ " + name)
        }
    }

    static func run() -> Int32 {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 12))!

        print("StateBuilder.lastSevenDays")
        let days = StateBuilder.lastSevenDays(now)
        check("返回 7 天", days.count == 7)
        check("最后一天是今天", StateBuilder.dayKey(days.last!) == "2026-11-06")
        check("第一天是 10-31", StateBuilder.dayKey(days.first!) == "2026-10-31")

        print("dayKey")
        check("yyyy-MM-dd 格式", StateBuilder.dayKey(now).range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil)

        print("planView")
        let offers = [
            APISubscriptionOffer(membershipTier: "go", billingInterval: "monthly", currency: "USD",
                                 originalPriceUsd: "10.00", finalPriceUsd: "10.00"),
            APISubscriptionOffer(membershipTier: "go", billingInterval: "yearly", currency: "USD",
                                 originalPriceUsd: "84.00", finalPriceUsd: "84.00")
        ]
        var monthly = APISnapshot(billing: .init(billingState: "active", planId: "go"),
                                  plan: APIPlan(tier: "go", interval: "month"))
        var inputs = StateBuilder.Inputs(theme: "light", prefs: PrefsSnapshot(), now: now)
        inputs.snapshot = monthly
        inputs.offers = offers
        var plan = StateBuilder.planView(inputs)
        check("月付价 10 美元", plan.priceLabel == "$10")
        check("状态 生效中", plan.stateLabel == "生效中")
        check("没有到期日时周期行退化成计费方式", plan.periodLabel == "月付 $10")

        monthly.plan?.interval = "year"
        inputs.snapshot = monthly
        plan = StateBuilder.planView(inputs)
        check("年付价 84 美元", plan.priceLabel == "$84")

        // 拿不到同档位 offer 时不显示价格
        inputs.offers = []
        plan = StateBuilder.planView(inputs)
        check("无 offer 时隐藏价格", plan.priceLabel.isEmpty)

        // free 计划
        var free = StateBuilder.Inputs(theme: "light", prefs: PrefsSnapshot(), now: now)
        free.snapshot = APISnapshot(billing: .init(billingState: "free", planId: "free"),
                                    plan: APIPlan(tier: "free", interval: nil))
        check("free 显示「免费」", StateBuilder.planView(free).stateLabel == "免费")

        // 未登录
        let empty = StateBuilder.Inputs(theme: "light", prefs: PrefsSnapshot(), now: now)
        check("无数据时状态「未连接」", StateBuilder.planView(empty).stateLabel == "未连接")
        check("无数据时计划名占位", StateBuilder.planView(empty).label == "—")

        print("syncLabel")
        var syncing = StateBuilder.Inputs(theme: "light", prefs: PrefsSnapshot(), now: now)
        syncing.busy = true
        check("busy 时是同步文案", StateBuilder.syncLabel(syncing).contains("同步"))

        print(failures == 0 ? "全部通过" : "\(failures) 项失败")
        return failures == 0 ? 0 : 1
    }
}
