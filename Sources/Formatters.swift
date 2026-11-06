import Foundation

/// 数字/金额/时间只在这里格式化，Web 端原样显示（docs/01 §6.6）
enum Formatters {
    static func percent(_ v: Int) -> String { "\(v)%" }

    /// 522.32M / 4.4M / 30.72K / 1,731
    static func tokens(_ v: Int) -> String {
        let a = abs(v)
        if a >= 1_000_000 { return abbreviated(a, unit: 1_000_000) + "M" }
        if a >= 1_000 { return abbreviated(a, unit: 1_000) + "K" }
        return grouped(v)
    }

    /// 逗号千分位（面板行内 token 用；CSV 用裸数字）
    static func grouped(_ v: Int) -> String {
        var out = ""
        for (index, digit) in String(abs(v)).reversed().enumerated() {
            if index > 0, index % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return (v < 0 ? "-" : "") + String(out.reversed())
    }

    /// $1.00 / $0.0022
    static func usd(_ v: Decimal, fractionDigits: Int) -> String {
        "$" + plain(v, fractionDigits: fractionDigits)
    }

    /// 不带货币符号的定点数（CSV 内的 ASCII 负号走这里）
    static func plain(_ v: Decimal, fractionDigits: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.roundingMode = .halfUp
        f.minimumFractionDigits = fractionDigits
        f.maximumFractionDigits = fractionDigits
        return f.string(from: NSDecimalNumber(decimal: v)) ?? "0"
    }

    /// −$0.0022，负号是 U+2212
    static func costLabel(_ v: Decimal) -> String {
        "−" + usd(v < 0 ? -v : v, fractionDigits: 4)
    }

    /// ≥24h → "4 天 18 小时后重置"；≥1h → "1 小时 12 分后重置"；否则 "39 分钟后重置"；≤0 → "即将重置"
    static func resetLabel(until: Date, now: Date) -> String {
        let s = Int(until.timeIntervalSince(now).rounded(.down))
        if s <= 0 { return "即将重置" }
        if s >= 86_400 { return "\(s / 86_400) 天 \((s % 86_400) / 3_600) 小时后重置" }
        if s >= 3_600 { return "\(s / 3_600) 小时 \((s % 3_600) / 60) 分后重置" }
        return "\(max(1, s / 60)) 分钟后重置"
    }

    static func relative(_ date: Date, now: Date) -> String {
        let s = now.timeIntervalSince(date)
        if s < 60 { return "刚刚" }
        if s < 3_600 { return "\(Int(s / 60)) 分钟前" }
        if s < 86_400 { return "\(Int(s / 3_600)) 小时前" }
        return "\(Int(s / 86_400)) 天前"
    }

    /// "今天 01:52" / "11月5日 22:10"
    static func clock(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let hm = String(format: "%02d:%02d", cal.component(.hour, from: date), cal.component(.minute, from: date))
        return cal.isDate(date, inSameDayAs: now) ? "今天 \(hm)" : "\(monthDay(date)) \(hm)"
    }

    /// "11月20日"
    static func monthDay(_ date: Date) -> String {
        let cal = Calendar.current
        return "\(cal.component(.month, from: date))月\(cal.component(.day, from: date))日"
    }

    /// "日/一/二/三/四/五/六"，今天为 "今"
    static func weekdayShort(_ date: Date, now: Date = Date()) -> String {
        if Calendar.current.isDate(date, inSameDayAs: now) { return "今" }
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        return names[(Calendar.current.component(.weekday, from: date) - 1) % 7]
    }

    static func iso(_ date: Date) -> String { isoOut.string(from: date) }

    static func date(_ string: String?) -> Date? {
        guard let s = string, !s.isEmpty else { return nil }
        return isoFull.date(from: s) ?? isoOut.date(from: s)
    }

    /// 两位小数、去尾零但至少留一位：522.32 / 4.4 / 30.72
    private static func abbreviated(_ a: Int, unit: Int) -> String {
        let hundredths = (a * 100 + unit / 2) / unit
        let frac = hundredths % 100
        let tail = frac % 10 == 0 ? "\(frac / 10)" : String(format: "%02d", frac)
        return "\(hundredths / 100).\(tail)"
    }

    private static let isoOut: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
