import Foundation

enum BatteryFormatters {
    static func percent(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value)"
    }

    static func time(minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "--" }
        let hours = minutes / 60
        let mins = minutes % 60

        if hours > 0 {
            return "\(hours)h \(mins)m"
        }

        return "\(mins)m"
    }

    static func duration(_ interval: TimeInterval?) -> String {
        guard let interval, interval >= 60 else { return "--" }
        let minutes = Int(interval / 60)
        return time(minutes: minutes)
    }

    static func rate(_ value: Double?) -> String {
        guard let value else { return "Learning" }
        return String(format: "%.1f%%/h", value)
    }

    static func spent(_ value: Double?) -> String {
        guard let value else { return "Learning" }
        if value.rounded() == value {
            return String(format: "%.0f%%", value)
        }
        return String(format: "%.1f%%", value)
    }

    static func watts(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f W", value)
    }

    static func temperatureC(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f°C", value)
    }

    static func temperatureF(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f°F", value)
    }

    static func voltage(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.2f V", value)
    }

    static func milliamps(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(abs(value)) mA"
    }

    static func milliampHours(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(grouped(value)) mAh"
    }

    static func cycleCount(_ count: Int?, limit: Int?) -> String {
        guard let count else { return "--" }
        if let limit {
            return "\(count)/\(limit)"
        }
        return "\(count)"
    }

    static func healthStatus(_ value: Int?) -> String {
        guard let value else { return "--" }
        switch value {
        case 90...:
            return "Good"
        case 80..<90:
            return "Fair"
        default:
            return "Service"
        }
    }

    static func temperatureStatus(_ value: Double?) -> String {
        guard let value else { return "--" }
        switch value {
        case ..<10:
            return "Cool"
        case 10..<38:
            return "Normal"
        case 38..<45:
            return "Warm"
        default:
            return "Hot"
        }
    }

    static func chargeDirection(_ isDischarging: Bool?) -> String {
        guard let isDischarging else { return "--" }
        return isDischarging ? "Discharging" : "Charging"
    }

    private static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

extension BatterySnapshot {
    func statusText() -> String {
        if isFull { return "Charged" }
        if isCharging { return isFastCharging ? "Fast Charging" : "Charging" }
        if isOnBattery { return "On Battery" }
        if powerSource == .powerAdapter { return "On Adapter" }
        return "Battery"
    }

    func statusSymbolName() -> String {
        if isCharging { return "bolt.fill" }
        if isOnBattery { return "battery.100" }
        return "powerplug.fill"
    }

    func timeTitle() -> String {
        if isCharging { return "TIME TO FULL" }
        return "TIME LEFT"
    }

    func timeValue(using stats: BatteryStats) -> String {
        if isCharging {
            return BatteryFormatters.time(minutes: timeToFullChargeMinutes)
        }

        if let timeToEmptyMinutes {
            return BatteryFormatters.time(minutes: timeToEmptyMinutes)
        }

        return BatteryFormatters.time(minutes: stats.historyEstimatedTimeRemainingMinutes)
    }
}
