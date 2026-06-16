import SwiftUI

struct CatBatteryIcon: View {
    var progress: Double
    var isCharging: Bool = false
    var foreground: Color = .primary
    var accent: Color = BatteryTheme.green

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let lineWidth = max(1.2, min(size.width, size.height) * 0.075)

            ZStack {
                CatHeadShape()
                    .fill(BatteryTheme.iconFill)

                CatHeadShape()
                    .fill(accent)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: size.width * clampedProgress)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .opacity(0.9)

                CatHeadShape()
                    .stroke(foreground.opacity(0.78), lineWidth: lineWidth)

                if isCharging {
                    LightningBoltShape()
                        .fill(BatteryTheme.lightText)
                        .frame(
                            width: max(8, size.width * 0.36),
                            height: max(12, size.height * 0.68)
                        )
                        .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                } else {
                    CatFaceShape()
                        .stroke(
                            foreground.opacity(0.82),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                        )
                        .padding(size.width * 0.18)
                }
            }
        }
        .aspectRatio(1.28, contentMode: .fit)
    }
}

private struct CatHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        var path = Path()
        path.move(to: CGPoint(x: 0.15 * w, y: 0.43 * h))
        path.addLine(to: CGPoint(x: 0.17 * w, y: 0.16 * h))
        path.addQuadCurve(
            to: CGPoint(x: 0.34 * w, y: 0.31 * h),
            control: CGPoint(x: 0.22 * w, y: 0.03 * h)
        )
        path.addQuadCurve(
            to: CGPoint(x: 0.66 * w, y: 0.31 * h),
            control: CGPoint(x: 0.50 * w, y: 0.20 * h)
        )
        path.addQuadCurve(
            to: CGPoint(x: 0.83 * w, y: 0.16 * h),
            control: CGPoint(x: 0.78 * w, y: 0.03 * h)
        )
        path.addLine(to: CGPoint(x: 0.85 * w, y: 0.43 * h))
        path.addQuadCurve(
            to: CGPoint(x: 0.76 * w, y: 0.88 * h),
            control: CGPoint(x: 0.98 * w, y: 0.58 * h)
        )
        path.addQuadCurve(
            to: CGPoint(x: 0.24 * w, y: 0.88 * h),
            control: CGPoint(x: 0.50 * w, y: 1.02 * h)
        )
        path.addQuadCurve(
            to: CGPoint(x: 0.15 * w, y: 0.43 * h),
            control: CGPoint(x: 0.02 * w, y: 0.58 * h)
        )
        path.closeSubpath()

        return path
    }
}

private struct CatFaceShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        var path = Path()
        path.move(to: CGPoint(x: 0.26 * w, y: 0.43 * h))
        path.addLine(to: CGPoint(x: 0.26 * w, y: 0.47 * h))
        path.move(to: CGPoint(x: 0.74 * w, y: 0.43 * h))
        path.addLine(to: CGPoint(x: 0.74 * w, y: 0.47 * h))

        path.move(to: CGPoint(x: 0.47 * w, y: 0.59 * h))
        path.addQuadCurve(
            to: CGPoint(x: 0.53 * w, y: 0.59 * h),
            control: CGPoint(x: 0.50 * w, y: 0.64 * h)
        )

        path.move(to: CGPoint(x: 0.12 * w, y: 0.61 * h))
        path.addLine(to: CGPoint(x: 0.38 * w, y: 0.65 * h))
        path.move(to: CGPoint(x: 0.62 * w, y: 0.65 * h))
        path.addLine(to: CGPoint(x: 0.88 * w, y: 0.61 * h))

        return path
    }
}

private struct LightningBoltShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        var path = Path()
        path.move(to: CGPoint(x: 0.60 * w, y: 0.02 * h))
        path.addLine(to: CGPoint(x: 0.20 * w, y: 0.52 * h))
        path.addLine(to: CGPoint(x: 0.47 * w, y: 0.52 * h))
        path.addLine(to: CGPoint(x: 0.36 * w, y: 0.98 * h))
        path.addLine(to: CGPoint(x: 0.84 * w, y: 0.39 * h))
        path.addLine(to: CGPoint(x: 0.56 * w, y: 0.39 * h))
        path.closeSubpath()

        return path
    }
}
