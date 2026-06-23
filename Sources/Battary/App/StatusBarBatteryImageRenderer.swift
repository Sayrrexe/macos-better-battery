import AppKit

enum StatusBarBatteryImageRenderer {
    static func image(percent: Int?, progress: Double, isCharging: Bool, appearance: NSAppearance) -> NSImage {
        let size = NSSize(width: 39, height: 16)
        let image = NSImage(size: size)

        appearance.performAsCurrentDrawingAppearance {
            image.lockFocus()
            defer { image.unlockFocus() }

            NSGraphicsContext.current?.imageInterpolation = .high

            let bodyRect = NSRect(x: 0.5, y: 1.25, width: 34.8, height: 13.5)
            let capRect = NSRect(x: 36.45, y: 5.85, width: 2.05, height: 4.3)
            let innerRect = bodyRect.insetBy(dx: 2.05, dy: 1.95)
            let clampedProgress = min(max(progress, 0), 1)
            let fillWidth = max(5.8, innerRect.width * clampedProgress)

            NSColor.clear.setFill()
            NSRect(origin: .zero, size: size).fill()

            let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 4.8, yRadius: 4.8)
            NSColor.controlBackgroundColor.withAlphaComponent(0.18).setFill()
            bodyPath.fill()

            let fillRect = NSRect(
                x: innerRect.minX,
                y: innerRect.minY,
                width: fillWidth,
                height: innerRect.height
            )
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 3.0, yRadius: 3.0)
            let fillColor = BatteryTheme.nsChargeColor(for: percent, isCharging: isCharging)
                .withAlphaComponent(isCharging ? 0.76 : 0.80)
            fillColor.setFill()
            fillPath.fill()

            NSColor.labelColor.withAlphaComponent(0.56).setStroke()
            bodyPath.lineWidth = 1.15
            bodyPath.stroke()

            let capPath = NSBezierPath(roundedRect: capRect, xRadius: 1.1, yRadius: 1.1)
            NSColor.labelColor.withAlphaComponent(0.48).setFill()
            capPath.fill()

            let text = BatteryFormatters.percent(percent) as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10.4, weight: .heavy),
                .foregroundColor: NSColor.labelColor
            ]
            let textSize = text.size(withAttributes: attributes)
            let textCenterX = isCharging ? bodyRect.midX + 6.0 : bodyRect.midX
            let textRect = NSRect(
                x: textCenterX - textSize.width / 2,
                y: bodyRect.midY - textSize.height / 2 - 0.2,
                width: textSize.width,
                height: textSize.height
            )

            if isCharging {
                let boltRect = NSRect(x: 5.6, y: 3.25, width: 6.4, height: 9.5)
                drawChargingBolt(in: boltRect)
            }

            text.draw(in: textRect, withAttributes: attributes)
        }

        image.isTemplate = false
        return image
    }

    private static func drawChargingBolt(in rect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + rect.width * 0.60, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.20, y: rect.minY + rect.height * 0.48))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.47, y: rect.minY + rect.height * 0.48))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.36, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.61))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.56, y: rect.minY + rect.height * 0.61))
        path.close()

        NSColor.white.withAlphaComponent(0.96).setFill()
        path.fill()
    }
}
