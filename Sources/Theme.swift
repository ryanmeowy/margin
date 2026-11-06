import AppKit

enum Theme {
    static let changed = Notification.Name("margin.theme.changed")

    static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    static var current: String { isDark ? "dark" : "light" }

    /// 原型 --panel（暖陶）：浅色 #FAF9F5 / 深色 #30302E，压到系统材质上保一点透感。
    static var panelFill: NSColor {
        isDark
            ? NSColor(srgbRed: 48 / 255, green: 48 / 255, blue: 46 / 255, alpha: 0.92)
            : NSColor(srgbRed: 250 / 255, green: 249 / 255, blue: 245 / 255, alpha: 0.92)
    }

    /// 面板外沿的 hairline：深色用浅线，浅色用极淡的暗线（原型那圈奶油色描边在浅色里看不见）
    static var panelBorder: NSColor {
        isDark ? NSColor(srgbRed: 250 / 255, green: 249 / 255, blue: 245 / 255, alpha: 0.12)
               : NSColor(srgbRed: 20 / 255, green: 20 / 255, blue: 19 / 255, alpha: 0.08)
    }

    static func apply(pref: String) {
        switch pref {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    static func startObserving() {
        DistributedNotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { _ in
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }
}
