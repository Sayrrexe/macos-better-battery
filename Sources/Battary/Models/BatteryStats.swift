import Foundation

struct BatteryStats: Equatable {
    var sinceUnplugged: TimeInterval?
    var spentLastHourPercent: Double?
    var averageDrainPercentPerHour: Double?
    var historyEstimatedTimeRemainingMinutes: Int?
    var screenOnSinceUnplugged: TimeInterval?
    var usableSampleCount: Int = 0

    static let empty = BatteryStats()
}
