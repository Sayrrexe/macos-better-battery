import Foundation

struct BatteryHealthDetails: Codable, Equatable {
    var healthPercent: Int?
    var cycleCount: Int?
    var cycleLimit: Int?
    var temperatureCelsius: Double?
    var voltageVolts: Double?
    var amperageMilliamps: Int?
    var powerUsageWatts: Double?
    var remainingCapacityMAh: Int?
    var currentFullCapacityMAh: Int?
    var designCapacityMAh: Int?
    var isDischarging: Bool?

    static let empty = BatteryHealthDetails()
}

extension BatteryHealthDetails {
    private static let cycleProgressStep = 100
    private static let cycleProgressHiddenThreshold = 900

    var temperatureFahrenheit: Double? {
        temperatureCelsius.map { ($0 * 9 / 5) + 32 }
    }

    var showsCycleLimitAndProgress: Bool {
        guard let cycleCount else { return true }
        return cycleCount < Self.cycleProgressHiddenThreshold
    }

    var cycleSteppedProgress: Double? {
        guard
            showsCycleLimitAndProgress,
            let cycleCount,
            let cycleLimit,
            cycleLimit > 0
        else { return nil }

        let completedSteps = max(cycleCount, 0) / Self.cycleProgressStep
        let usedCycles = completedSteps * Self.cycleProgressStep
        let remainingCycles = max(cycleLimit - usedCycles, 0)
        return min(max(Double(remainingCycles) / Double(cycleLimit), 0), 1)
    }

    var hasAnyValue: Bool {
        healthPercent != nil
            || cycleCount != nil
            || cycleLimit != nil
            || temperatureCelsius != nil
            || voltageVolts != nil
            || amperageMilliamps != nil
            || powerUsageWatts != nil
            || remainingCapacityMAh != nil
            || currentFullCapacityMAh != nil
            || designCapacityMAh != nil
            || isDischarging != nil
    }

    func fillingMissingValues(from fallback: BatteryHealthDetails) -> BatteryHealthDetails {
        BatteryHealthDetails(
            healthPercent: healthPercent ?? fallback.healthPercent,
            cycleCount: cycleCount ?? fallback.cycleCount,
            cycleLimit: cycleLimit ?? fallback.cycleLimit,
            temperatureCelsius: temperatureCelsius ?? fallback.temperatureCelsius,
            voltageVolts: voltageVolts ?? fallback.voltageVolts,
            amperageMilliamps: amperageMilliamps ?? fallback.amperageMilliamps,
            powerUsageWatts: powerUsageWatts ?? fallback.powerUsageWatts,
            remainingCapacityMAh: remainingCapacityMAh ?? fallback.remainingCapacityMAh,
            currentFullCapacityMAh: currentFullCapacityMAh ?? fallback.currentFullCapacityMAh,
            designCapacityMAh: designCapacityMAh ?? fallback.designCapacityMAh,
            isDischarging: isDischarging ?? fallback.isDischarging
        )
    }
}
