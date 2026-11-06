import Foundation

enum PrefsKey {
    static let theme = "theme"
    static let display = "display"
    static let launchAtLogin = "launchAtLogin"
    static let autoRefresh = "autoRefresh"
    static let interval = "interval"
    static let usageAlert = "usageAlert"
    static let threshold = "threshold"
    static let renewalReminder = "renewalReminder"
    static let weeklyDigest = "weeklyDigest"
    static let baseUrl = "baseUrl"
    static let didLogout = "didLogout"
    static let workspaceId = "workspaceId"
}

enum Prefs {
    static let changed = Notification.Name("margin.prefs.changed")
    private static var d: UserDefaults { .standard }

    static var snapshot: PrefsSnapshot {
        var p = PrefsSnapshot()
        p.theme = d.string(forKey: PrefsKey.theme) ?? "system"
        p.display = d.string(forKey: PrefsKey.display) ?? "percent"
        p.launchAtLogin = d.object(forKey: PrefsKey.launchAtLogin) == nil ? true : d.bool(forKey: PrefsKey.launchAtLogin)
        p.autoRefresh = d.object(forKey: PrefsKey.autoRefresh) == nil ? true : d.bool(forKey: PrefsKey.autoRefresh)
        p.interval = d.string(forKey: PrefsKey.interval) ?? "15"
        p.usageAlert = d.object(forKey: PrefsKey.usageAlert) == nil ? true : d.bool(forKey: PrefsKey.usageAlert)
        p.threshold = d.object(forKey: PrefsKey.threshold) == nil ? 80 : d.integer(forKey: PrefsKey.threshold)
        p.renewalReminder = d.object(forKey: PrefsKey.renewalReminder) == nil ? true : d.bool(forKey: PrefsKey.renewalReminder)
        p.weeklyDigest = d.object(forKey: PrefsKey.weeklyDigest) == nil ? false : d.bool(forKey: PrefsKey.weeklyDigest)
        p.workspaceId = d.string(forKey: PrefsKey.workspaceId)
        return p
    }

    static var baseUrl: String {
        d.string(forKey: PrefsKey.baseUrl) ?? "https://amr-api.open-design.ai"
    }

    static func set(_ key: String, _ value: Any) {
        d.set(value, forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func apply(_ updates: [String: Any]) {
        for (k, v) in updates { d.set(v, forKey: k) }
        NotificationCenter.default.post(name: changed, object: nil)
    }
}
