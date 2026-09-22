import Foundation

/// This fork never follows the upstream updater or shares its preference domain.
enum PersonalEdition {
    static let bundleID = "com.vinicius.codenotch.personal"
    static var isEnabled: Bool { Bundle.main.bundleIdentifier == bundleID }
    static let migrationKey = "personalEditionAppearanceImported"
    static let appearanceKeys: Set<String> = [
        "accountDisplayNames", "usageDisplayMode", "notchQuota", "claudeCoralIcon", "appLanguage",
        "connectedProviders", "seenProviders", "disconnectedProviders", "providerOrder",
        "notchVisibility", "notchEdge", "notchSize", "notchDisplay", "notchScope",
        "notchSurfaceStyle", "showsMoveHandle", "appPresence", "accentColor", "weeklyRing",
        "weeklyRingDashed", "resetTimeFormat", "watchLimit", "criticalLimit",
        "notchOffset.top", "notchOffset.bottom", "notchOffset.left", "notchOffset.right",
        "NSWindow Frame usageDashboardFrame", "usesCustomNotchScale", "customNotchScale"
    ]

    /// Copies presentation choices once. Never copies credentials, cookies, readings,
    /// account registries, update settings or background-service permissions.
    static func importAppearance(from old: [String: Any], into defaults: UserDefaults) {
        guard !defaults.bool(forKey: migrationKey) else { return }
        for key in appearanceKeys where defaults.object(forKey: key) == nil {
            if let value = old[key] { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: migrationKey)
    }
}
