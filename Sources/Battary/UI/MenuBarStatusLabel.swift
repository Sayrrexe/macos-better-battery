import SwiftUI

struct MenuBarStatusLabel: View {
    var snapshot: BatterySnapshot

    private var progress: Double {
        Double(snapshot.stateOfChargePercent ?? 0) / 100
    }

    var body: some View {
        MenuBarBatteryPill(
            percent: snapshot.stateOfChargePercent,
            progress: progress,
            isCharging: snapshot.isCharging
        )
        .frame(width: 42, height: 20)
        .padding(.horizontal, 2)
    }
}

private struct MenuBarBatteryPill: View {
    var percent: Int?
    var progress: Double
    var isCharging: Bool

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var fillColor: Color {
        BatteryTheme.chargeColor(for: percent, isCharging: isCharging)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let capWidth = size.width * 0.08
            let bodyWidth = size.width - capWidth - 1
            let radius = size.height * 0.30

            HStack(spacing: 1) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.18))

                    RoundedRectangle(cornerRadius: radius * 0.72, style: .continuous)
                        .fill(fillColor.opacity(isCharging ? 0.82 : 0.68))
                        .frame(width: max(8, (bodyWidth - 6) * clampedProgress))
                        .padding(3)

                    Text(BatteryFormatters.percent(percent))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Color.primary.opacity(0.58), lineWidth: 1.4)
                }
                .frame(width: bodyWidth, height: size.height)

                Capsule()
                    .fill(Color.primary.opacity(0.48))
                    .frame(width: capWidth, height: size.height * 0.43)
            }
        }
    }
}
