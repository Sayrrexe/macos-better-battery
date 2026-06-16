import AppKit
import Foundation
import SwiftUI

enum BattarySettings {
    static let languageKey = "settings.language"
    static let notificationsEnabledKey = "settings.notifications.enabled"
    static let notificationThresholdKey = "settings.notifications.threshold"
    static let notificationThresholdsKey = "settings.notifications.thresholds"
    static let notificationSoundEnabledKey = "settings.notifications.soundEnabled"

    static let healthyColorKey = "settings.colors.healthy"
    static let balancedColorKey = "settings.colors.balanced"
    static let lowColorKey = "settings.colors.low"
    static let criticalColorKey = "settings.colors.critical"
    static let chargingColorKey = "settings.colors.charging"

    static let defaultNotificationThreshold = 20
    static let defaultNotificationThresholds = [20]
    static let defaultNotificationThresholdsRaw = "20"

    static func registerDefaults() {
        migrateSingleNotificationThresholdIfNeeded()

        UserDefaults.standard.register(defaults: [
            languageKey: BattaryLanguage.russian.rawValue,
            notificationsEnabledKey: true,
            notificationThresholdKey: defaultNotificationThreshold,
            notificationThresholdsKey: defaultNotificationThresholdsRaw,
            notificationSoundEnabledKey: true,
            healthyColorKey: BatteryColorRole.healthy.defaultHex,
            balancedColorKey: BatteryColorRole.balanced.defaultHex,
            lowColorKey: BatteryColorRole.low.defaultHex,
            criticalColorKey: BatteryColorRole.critical.defaultHex,
            chargingColorKey: BatteryColorRole.charging.defaultHex
        ])
    }

    static func language(defaults: UserDefaults = .standard) -> BattaryLanguage {
        BattaryLanguage(rawValue: defaults.string(forKey: languageKey) ?? "") ?? .russian
    }

    static func notificationsEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: notificationsEnabledKey) as? Bool ?? true
    }

    static func notificationSoundEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: notificationSoundEnabledKey) as? Bool ?? true
    }

    static func notificationThreshold(defaults: UserDefaults = .standard) -> Int {
        notificationThresholds(defaults: defaults).first ?? defaultNotificationThreshold
    }

    static func notificationThresholds(defaults: UserDefaults = .standard) -> [Int] {
        if let rawValue = defaults.string(forKey: notificationThresholdsKey) {
            let thresholds = parseNotificationThresholds(rawValue)
            if !thresholds.isEmpty {
                return thresholds
            }
        }

        let storedValue = defaults.object(forKey: notificationThresholdKey) as? Int
        return normalizedNotificationThresholds([storedValue ?? defaultNotificationThreshold])
    }

    static func notificationThresholdsRaw(from thresholds: [Int]) -> String {
        normalizedNotificationThresholds(thresholds)
            .map(String.init)
            .joined(separator: ",")
    }

    static func parseNotificationThresholds(_ rawValue: String) -> [Int] {
        normalizedNotificationThresholds(
            rawValue
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
    }

    static func normalizedNotificationThresholds(_ values: [Int]) -> [Int] {
        Array(Set(values.map(clampNotificationThreshold)))
            .sorted(by: >)
    }

    static func nextNotificationThreshold(after thresholds: [Int]) -> Int? {
        let usedValues = Set(normalizedNotificationThresholds(thresholds))
        let fallbackValue = (thresholds.min() ?? 30) - 10
        let preferredValue = clampNotificationThreshold(fallbackValue)

        if !usedValues.contains(preferredValue) {
            return preferredValue
        }

        return stride(from: 50, through: 5, by: -5)
            .first { !usedValues.contains($0) }
    }

    static func clampNotificationThreshold(_ value: Int) -> Int {
        min(max(value, 5), 50)
    }

    static func role(for percent: Int?, isCharging: Bool) -> BatteryColorRole {
        if isCharging { return .charging }

        switch normalizedPercent(percent) {
        case 50...100:
            return .healthy
        case 30...49:
            return .balanced
        case 10...29:
            return .low
        default:
            return .critical
        }
    }

    static func color(for role: BatteryColorRole, defaults: UserDefaults = .standard) -> Color {
        Color(hex: defaults.string(forKey: role.defaultsKey), fallback: role.defaultHex)
    }

    static func nsColor(for role: BatteryColorRole, defaults: UserDefaults = .standard) -> NSColor {
        NSColor(hex: defaults.string(forKey: role.defaultsKey), fallback: role.defaultHex)
    }

    static func hexString(from color: Color, fallback: String) -> String {
        guard
            let cgColor = color.cgColor,
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let converted = cgColor.converted(to: colorSpace, intent: .defaultIntent, options: nil)
        else {
            return fallback
        }

        let components = converted.components ?? []
        let red = components[safe: 0] ?? 0
        let green = components[safe: 1] ?? red
        let blue = components[safe: 2] ?? red

        return String(
            format: "#%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }

    private static func normalizedPercent(_ percent: Int?) -> Int {
        min(max(percent ?? 100, 0), 100)
    }

    private static func migrateSingleNotificationThresholdIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: notificationThresholdsKey) == nil else { return }
        guard let storedValue = defaults.object(forKey: notificationThresholdKey) as? Int else { return }

        defaults.set(notificationThresholdsRaw(from: [storedValue]), forKey: notificationThresholdsKey)
    }
}

enum BattaryLanguage: String, CaseIterable, Identifiable {
    case russian = "ru"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .russian:
            return "Русский"
        case .english:
            return "English"
        }
    }
}

enum BatteryColorRole: String, CaseIterable, Identifiable {
    case healthy
    case balanced
    case low
    case critical
    case charging

    var id: String { rawValue }

    var defaultsKey: String {
        switch self {
        case .healthy:
            return BattarySettings.healthyColorKey
        case .balanced:
            return BattarySettings.balancedColorKey
        case .low:
            return BattarySettings.lowColorKey
        case .critical:
            return BattarySettings.criticalColorKey
        case .charging:
            return BattarySettings.chargingColorKey
        }
    }

    var defaultHex: String {
        switch self {
        case .healthy:
            return "#00B861"
        case .balanced:
            return "#C7DB33"
        case .low:
            return "#FF9E2E"
        case .critical:
            return "#FF454D"
        case .charging:
            return "#0D94FF"
        }
    }
}

extension Color {
    init(hex: String?, fallback: String) {
        self.init(nsColor: NSColor(hex: hex, fallback: fallback))
    }
}

extension NSColor {
    convenience init(hex: String?, fallback: String) {
        let parsed = Self.rgbComponents(from: hex) ?? Self.rgbComponents(from: fallback) ?? (0, 0, 0)
        self.init(
            calibratedRed: parsed.red,
            green: parsed.green,
            blue: parsed.blue,
            alpha: 1
        )
    }

    private static func rgbComponents(from hex: String?) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return nil
        }

        return (
            CGFloat((value >> 16) & 0xFF) / 255,
            CGFloat((value >> 8) & 0xFF) / 255,
            CGFloat(value & 0xFF) / 255
        )
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
