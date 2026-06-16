import AppKit
import SwiftUI

enum CatMascotState: String {
    case healthy
    case balanced
    case low
    case critical
    case charging
    case avatar

    var resourceName: String {
        "cat-\(rawValue)"
    }

    static func state(for percent: Int?, isCharging: Bool) -> CatMascotState {
        if isCharging {
            return .charging
        }

        switch BattarySettings.role(for: percent, isCharging: false) {
        case .healthy:
            return .healthy
        case .balanced:
            return .balanced
        case .low:
            return .low
        case .critical:
            return .critical
        case .charging:
            return .charging
        }
    }
}

enum CatMascotAssets {
    static func image(for state: CatMascotState) -> NSImage? {
        guard let url = Bundle.main.url(
            forResource: state.resourceName,
            withExtension: "png",
            subdirectory: "Mascots"
        ) else {
            return nil
        }

        return NSImage(contentsOf: url)
    }
}

struct CatMascotIcon: View {
    var percent: Int?
    var isCharging: Bool

    private var state: CatMascotState {
        CatMascotState.state(for: percent, isCharging: isCharging)
    }

    private var progress: Double {
        Double(percent ?? 0) / 100
    }

    var body: some View {
        if let image = CatMascotAssets.image(for: state) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            CatBatteryIcon(
                progress: progress,
                isCharging: isCharging,
                foreground: BatteryTheme.lightText,
                accent: BatteryTheme.chargeColor(for: percent, isCharging: isCharging)
            )
        }
    }
}
