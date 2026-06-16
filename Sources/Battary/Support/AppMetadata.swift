enum AppMetadata {
    static let displayName = "Better Battery"
    static let bundleIdentifier = "dev.sayrrexe.BetterBattery"
    static let applicationSupportDirectoryName = "Better Battery"

    static func lowBatteryNotificationIdentifier(percent: Int) -> String {
        "\(bundleIdentifier).lowBattery.\(percent)"
    }
}
