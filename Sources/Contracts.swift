import Foundation

// MARK: - API DTO（字段全部容忍缺失；未知字段忽略）

struct APIWorkspaceListItem: Codable {
    var workspaceId: String
    var workspaceName: String?
    var workspaceType: String?
    var role: String?
}

struct APIWorkspace: Codable {
    var workspaceId: String
    var workspaceMemberId: String
    var workspaceName: String?
    var workspaceType: String?
    var role: String?
    var planId: String?
    var billingState: String?
    var memberCount: Int?
}

struct APIWindow: Codable {
    var kind: String?              // "5h" / "7d"
    var windowStart: String?
    var resetsAt: String?
    var remainingCredits: String?
    var limitCredits: String?
    var durationSeconds: Int?
    var usedCredits: String?
    var resetMode: String?
}

struct APIPlan: Codable {
    var tier: String?
    var interval: String?          // "month" / "year"
    var currentPeriodStart: String?
    var currentPeriodEnd: String?
    var cancelAtPeriodEnd: Bool?
    var status: String?
}

struct APIWallet: Codable {
    var balanceUsd: String?
    var expiresAt: String?
    var updatedAt: String?
}

struct APISnapshot: Codable {
    var workspaceId: String?
    var workspaceMemberId: String?
    var billingMode: String?
    var billing: Billing?
    var plan: APIPlan?
    var owner: Owner?
    var wallet: APIWallet?
    var designPlanWindows: [APIWindow]?

    struct Billing: Codable {
        var billingState: String?
        var planId: String?
    }

    struct Owner: Codable {
        var workspaceMemberId: String?
        var displayName: String?
    }
}

struct APICodingPlan: Codable {
    var eligible: Bool?
    var tier: String?
    var windows: [APIWindow]?
}

struct APIUsageSummary: Codable {
    var inputTokens: Int?
    var outputTokens: Int?
    var cacheReadTokens: Int?
    var cacheWriteTokens: Int?
}

struct APIUsageEntry: Codable {
    var id: String?
    var type: String?
    var amountUsd: String?
    var listChargedUsd: String?
    var detail: String?
    var initiator: String?
    var runtime: String?
    var model: String?
    var createdAt: String?
    var inputTokens: Int?
    var outputTokens: Int?
    var cacheReadTokens: Int?
    var cacheWriteTokens: Int?
    var usageType: String?
}

struct APIUsagePage: Codable {
    var workspaceId: String?
    var entries: [APIUsageEntry]?
    var summary: APIUsageSummary?
    var totalCount: Int?
    var nextCursor: String?
    var hasMore: Bool?
}

struct APISubscriptionOffer: Codable {
    var membershipTier: String?
    var billingInterval: String?    // monthly | yearly
    var currency: String?
    var originalPriceUsd: String?   // "10.00"
    var finalPriceUsd: String?      // 折后价，通常等于 original
}

struct APISubscriptionOffers: Codable {
    var offers: [APISubscriptionOffer]?
}

struct APIBillingSummary: Codable {
    var balanceUsd: String?
    var membershipTier: String?
    var billingInterval: String?   // "monthly" / "yearly"
    var subscriptionStatus: String?
    var subscriptionCurrentPeriodEnd: String?
    var subscriptionCancelAtPeriodEnd: Bool?
}

// MARK: - 推到 Web 的视图状态（键名即 JS 读到的键名，见 fixtures/state.sample.json）

struct WorkspaceOption: Codable {
    var id: String
    var name: String
    var kind: String
}

struct PanelState: Codable {
    var theme: String
    var animate: Bool
    var version: String
    var connection: Connection
    var prefs: PrefsView
    var plan: PlanView
    var windows: [WindowView]
    var wallet: WalletView
    var usage: UsageView
    var sync: SyncView
    var account: AccountView
    var exporting: Bool = false
    var exportCount: Int = 0

    struct Connection: Codable { var state: String; var message: String }
    struct PrefsView: Codable { var display: String; var threshold: Int }
    struct PlanView: Codable {
        var tier: String; var label: String; var badge: String
        var intervalLabel: String; var priceLabel: String; var priceUnit: String
        var stateLabel: String; var periodLabel: String
    }
    struct WindowView: Codable {
        var kind: String; var label: String; var remainingPercent: Int; var resetLabel: String
    }
    struct WalletView: Codable { var label: String; var caption: String }
    struct UsageView: Codable {
        var totalLabel: String; var dailyAvgLabel: String
        var windowLabel: String; var rangeLabel: String
        var inputLabel: String; var outputLabel: String
        var cacheReadLabel: String; var cacheWriteLabel: String
        var dailyState: String          // ready | loading | unavailable
        var dailyFallbackText: String
        var daily: [DailyView]
        var recent: [RecentView]
    }
    struct DailyView: Codable {
        var key: String; var weekday: String; var label: String
        var tokensLabel: String; var ratio: Double; var isToday: Bool
    }
    struct RecentView: Codable {
        var model: String; var badge: String; var when: String
        var inputLabel: String; var outputLabel: String
        var costLabel: String; var tag: String; var tagKind: String
    }
    struct SyncView: Codable { var label: String; var busy: Bool }
    struct AccountView: Codable {
        var workspaceName: String
        var email: String
        var planLabel: String
        var ownerName: String = ""
    }
}

struct PrefsSnapshot {
    var theme: String = "system"
    var display: String = "percent"
    var launchAtLogin: Bool = true
    var autoRefresh: Bool = true
    var interval: String = "15"
    var usageAlert: Bool = true
    var threshold: Int = 80
    var renewalReminder: Bool = true
    var weeklyDigest: Bool = false
    var workspaceId: String? = nil

    var intervalMinutes: Int { Int(interval) ?? 15 }
}

struct SettingsState: Codable {
    var theme: String
    var prefs: PrefsView
    var account: Account
    var connection: PanelState.Connection
    var about: About
    var version: String
    var busy: Bool = false
    var workspaceOptions: [WorkspaceOption] = []
    var workspaceId: String = ""
    var authNotice: String = ""
    var authTone: String = "ok"
    var authPending: Bool = false

    struct PrefsView: Codable {
        var theme: String           // system | light | dark
        var display: String         // percent | icon
        var launchAtLogin: Bool
        var autoRefresh: Bool
        var interval: String        // "5" | "15" | "30" | "60"
        var usageAlert: Bool
        var threshold: Int
        var renewalReminder: Bool
        var weeklyDigest: Bool
    }
    struct Account: Codable {
        var baseUrl: String
        var email: String
        var tokenMasked: String
        var workspaceName: String
        var planLabel: String
        var lastVerifiedLabel: String
        var launchAtLoginSupported: Bool
        var notificationsSupported: Bool
        var displayName: String = ""
        var initials: String = ""
    }
    struct About: Codable {
        var version: String
        var build: String
        var mode: String
        var intervalLabel: String
        var credentialStorage: String
        var updateStatus: String
    }
}
