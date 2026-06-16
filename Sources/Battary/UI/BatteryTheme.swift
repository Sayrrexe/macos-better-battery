import AppKit
import SwiftUI

enum BatteryTheme {
    static let background = Color(red: 38 / 255, green: 38 / 255, blue: 39 / 255)
    static let panel = Color(red: 0.15, green: 0.15, blue: 0.18).opacity(0.82)
    static let panelRaised = Color(red: 0.17, green: 0.17, blue: 0.20).opacity(0.78)
    static let stroke = Color.white.opacity(0.12)
    static let divider = Color.white.opacity(0.15)
    static let green = Color(red: 0.00, green: 0.72, blue: 0.38)
    static let yellowGreen = Color(red: 0.78, green: 0.86, blue: 0.20)
    static let blue = Color(red: 0.05, green: 0.58, blue: 1.00)
    static let orange = Color(red: 1.00, green: 0.62, blue: 0.18)
    static let red = Color(red: 1.00, green: 0.27, blue: 0.30)
    static let lightText = Color(red: 0.94, green: 0.94, blue: 0.98)
    static let mutedText = Color(red: 0.65, green: 0.64, blue: 0.72)
    static let iconFill = Color.white.opacity(0.08)

    static func chargeColor(for percent: Int?, isCharging: Bool = false) -> Color {
        BattarySettings.color(for: BattarySettings.role(for: percent, isCharging: isCharging))
    }

    static func nsChargeColor(for percent: Int?, isCharging: Bool = false) -> NSColor {
        BattarySettings.nsColor(for: BattarySettings.role(for: percent, isCharging: isCharging))
    }
}
