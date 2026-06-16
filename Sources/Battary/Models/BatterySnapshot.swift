import Foundation

struct BatterySnapshot: Codable, Equatable {
    var timestamp: Date = Date()
    var powerSource: PowerSourceType = .unknown
    var isCharging: Bool = false
    var isFastCharging: Bool = false
    var isFull: Bool = false
    var stateOfChargePercent: Int?
    var timeToFullChargeMinutes: Int?
    var timeToEmptyMinutes: Int?
    var cycleCount: Int?
    var chargingPowerW: Double?
    var currentPowerW: Double?
    var isExternalPowerConnected: Bool?
    var healthDetails: BatteryHealthDetails = .empty

    var isOnBattery: Bool {
        if let isExternalPowerConnected {
            return !isExternalPowerConnected && !isCharging
        }

        if let currentPowerW, currentPowerW > 0, !isCharging {
            return true
        }

        return powerSource == .battery && !isCharging
    }

    static let placeholder = BatterySnapshot()
}
