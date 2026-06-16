import Darwin
import Foundation
import IOKit
import IOKit.ps

struct AdapterInfo {
    var name: String?
    var manufacturer: String?
}

struct BatteryMetrics {
    var cycleCount: Int?
    var stateOfChargePercent: Int?
    var chargingPowerW: Double?
    var currentPowerW: Double?
    var isExternalPowerConnected: Bool?
    var healthDetails: BatteryHealthDetails = .empty
}

protocol BatterySnapshotReading {
    func readSnapshot(depth: BatteryReadDepth) -> BatterySnapshot
}

struct IOKitBatteryReader {
    private static let fastChargePowerThresholdW = 50.0
    static let minimumVisibleWatts = 0.1

    private struct PowerReadingContext {
        let isCharging: Bool
        let isExternalPowerConnected: Bool
        let powerSource: PowerSourceType
    }

    private static let acPower = kIOPSACPowerValue as String
    private static let batteryPower = kIOPSBatteryPowerValue as String

    private static let keyTransportType = kIOPSTransportTypeKey as String
    private static let keyPSType = kIOPSTypeKey as String
    private static let keyIsCharging = kIOPSIsChargingKey as String
    private static let keyTimeToFull = kIOPSTimeToFullChargeKey as String
    private static let keyTimeToEmpty = kIOPSTimeToEmptyKey as String
    private static let keyCurrentCapacity = kIOPSCurrentCapacityKey as String

    func readSnapshot(depth: BatteryReadDepth = .details) -> BatterySnapshot {
        let context = readPowerSourcesContext()
        let powerSource = mapPowerSource(context?.providingPowerSourceType) ?? .unknown
        let internalBattery = context?.internalBattery
        let isCharging = internalBattery?.bool(Self.keyIsCharging) ?? false
        let metrics: BatteryMetrics

        switch depth {
        case .summary:
            metrics = BatteryMetrics(
                stateOfChargePercent: readStateOfCharge(internalBattery: internalBattery),
                isExternalPowerConnected: powerSource == .powerAdapter
            )
        case .details:
            metrics = readBatteryMetrics(
                internalBattery: internalBattery,
                powerSource: powerSource,
                isCharging: isCharging
            )
        }

        var snapshot = BatterySnapshot()
        snapshot.timestamp = Date()
        snapshot.powerSource = powerSource
        snapshot.isCharging = isCharging
        snapshot.isFastCharging = (metrics.chargingPowerW ?? 0) >= Self.fastChargePowerThresholdW
        snapshot.isFull = isFull(metrics.stateOfChargePercent)
        snapshot.cycleCount = metrics.cycleCount
        snapshot.stateOfChargePercent = metrics.stateOfChargePercent
        snapshot.timeToFullChargeMinutes = readTimeToFullChargeMinutes(internalBattery: internalBattery)
        snapshot.timeToEmptyMinutes = readTimeToEmptyMinutes(internalBattery: internalBattery)
        snapshot.chargingPowerW = metrics.chargingPowerW
        snapshot.currentPowerW = metrics.currentPowerW
        snapshot.isExternalPowerConnected = metrics.isExternalPowerConnected
        snapshot.healthDetails = metrics.healthDetails
        return snapshot
    }

    private struct PowerSourcesContext {
        let providingPowerSourceType: String?
        let internalBattery: [String: Any]?
    }

    private func readPowerSourcesContext() -> PowerSourcesContext? {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let internalBattery = list
            .compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
            .first(where: isInternalBattery)

        return PowerSourcesContext(
            providingPowerSourceType: providing,
            internalBattery: internalBattery
        )
    }

    private func mapPowerSource(_ raw: String?) -> PowerSourceType? {
        switch raw {
        case Self.acPower:
            return .powerAdapter
        case Self.batteryPower:
            return .battery
        default:
            return nil
        }
    }

    private func isInternalBattery(_ desc: [String: Any]) -> Bool {
        if desc.string(Self.keyTransportType) == (kIOPSInternalType as String) {
            return true
        }
        return desc.string(Self.keyPSType) == (kIOPSInternalBatteryType as String)
    }

    private func readTimeToFullChargeMinutes(internalBattery: [String: Any]?) -> Int? {
        guard
            let internalBattery,
            let minutes = internalBattery.int(Self.keyTimeToFull),
            minutes > 0
        else { return nil }
        return minutes
    }

    private func readTimeToEmptyMinutes(internalBattery: [String: Any]?) -> Int? {
        guard
            let internalBattery,
            let minutes = internalBattery.int(Self.keyTimeToEmpty),
            minutes > 0
        else { return nil }
        return minutes
    }

    private func readBatteryMetrics(
        internalBattery: [String: Any]?,
        powerSource: PowerSourceType,
        isCharging: Bool
    ) -> BatteryMetrics {
        guard let props = readSmartBatteryProperties() else {
            return BatteryMetrics(
                stateOfChargePercent: readStateOfCharge(internalBattery: internalBattery),
                isExternalPowerConnected: powerSource == .powerAdapter
            )
        }

        let stateOfCharge = readStateOfCharge(internalBattery: internalBattery) ?? props.int("StateOfCharge")
        let externalPowerConnected = readExternalPowerConnected(props: props, powerSource: powerSource)
        let power = readPower(
            props: props,
            context: PowerReadingContext(
                isCharging: isCharging,
                isExternalPowerConnected: externalPowerConnected,
                powerSource: powerSource
            )
        )

        return BatteryMetrics(
            cycleCount: props.int("CycleCount"),
            stateOfChargePercent: stateOfCharge,
            chargingPowerW: power?.charging,
            currentPowerW: power?.current,
            isExternalPowerConnected: externalPowerConnected,
            healthDetails: readHealthDetails(props: props, power: power)
        )
    }

    private func readHealthDetails(
        props: [String: Any],
        power: (charging: Double?, current: Double?)?
    ) -> BatteryHealthDetails {
        let designCapacity = props.int("DesignCapacity")
        let rawMaxCapacity = props.int("AppleRawMaxCapacity")
            ?? props.int("NominalChargeCapacity")
        let remainingCapacity = props.int("AppleRawCurrentCapacity")
        let amperageMA = props.int("InstantAmperage")
            ?? props.int("Amperage")
        let voltageMV = props.int("AppleRawBatteryVoltage")
            ?? props.int("Voltage")
        let temperatureRaw = props.int("Temperature")

        let healthPercent: Int? = {
            guard
                let rawMaxCapacity,
                let designCapacity,
                designCapacity > 0
            else { return nil }

            let value = Double(rawMaxCapacity) / Double(designCapacity) * 100
            return min(100, max(0, Int(value.rounded())))
        }()

        let temperatureCelsius = temperatureRaw.map { Double($0) / 100.0 }
        let voltageVolts = voltageMV.map { Double($0) / 1_000.0 }
        let isDischarging = amperageMA.map { $0 < 0 }

        return BatteryHealthDetails(
            healthPercent: healthPercent,
            cycleCount: props.int("CycleCount"),
            cycleLimit: props.int("DesignCycleCount9C") ?? 1_000,
            temperatureCelsius: temperatureCelsius.map(round1),
            voltageVolts: voltageVolts.map(round2),
            amperageMilliamps: amperageMA,
            powerUsageWatts: power?.current ?? power?.charging,
            remainingCapacityMAh: remainingCapacity,
            currentFullCapacityMAh: rawMaxCapacity,
            designCapacityMAh: designCapacity,
            isDischarging: isDischarging
        )
    }

    private func readStateOfCharge(internalBattery: [String: Any]?) -> Int? {
        internalBattery?.int(Self.keyCurrentCapacity)
    }

    private func readPower(
        props: [String: Any],
        context: PowerReadingContext
    ) -> (charging: Double?, current: Double?)? {
        guard
            let amperageMA = props.int64("InstantAmperage"),
            let voltageMV = props.int64("Voltage")
        else { return nil }

        let batteryPowerW = Double(amperageMA) * Double(voltageMV) / 1_000_000.0
        let batteryDrawW = readBatteryDrawW(props: props, batteryPowerW: batteryPowerW)

        let chargingPowerW: Double? = {
            guard context.isCharging else { return nil }
            let value = batteryPowerW
            return value >= Self.minimumVisibleWatts ? round2(value) : nil
        }()

        let currentPowerW: Double? = {
            if !context.isExternalPowerConnected || context.powerSource == .battery {
                return batteryDrawW
            }

            if let systemPowerW = readSystemPowerW(
                props: props,
                isExternalPowerConnected: context.isExternalPowerConnected,
                chargingPowerW: chargingPowerW
            ) {
                return visibleWatts(systemPowerW)
            }

            return nil
        }()

        return (chargingPowerW, currentPowerW)
    }

    private func readBatteryDrawW(props: [String: Any], batteryPowerW: Double) -> Double? {
        if let telemetry = props.dictionary("PowerTelemetryData"),
           let telemetryBatteryPower = readPowerValueAbs(props: telemetry, key: "BatteryPower"),
           let visible = visibleWatts(telemetryBatteryPower) {
            return visible
        }

        return visibleWatts(-batteryPowerW)
    }

    private func readSystemPowerW(
        props: [String: Any],
        isExternalPowerConnected: Bool,
        chargingPowerW: Double?
    ) -> Double? {
        if let value = readPowerValueAbs(props: props, key: "SystemPower"),
           value >= Self.minimumVisibleWatts {
            return value
        }
        if let value = readPowerValueAbs(props: props, key: "AvgSystemPower"),
           value >= Self.minimumVisibleWatts {
            return value
        }
        if let value = readPowerValueAbs(props: props, key: "AverageSystemPower"),
           value >= Self.minimumVisibleWatts {
            return value
        }

        guard let telemetry = props.dictionary("PowerTelemetryData") else {
            return nil
        }

        if let value = readPowerValueAbs(props: telemetry, key: "SystemPower"),
           value >= Self.minimumVisibleWatts {
            return value
        }

        if isExternalPowerConnected,
           let systemPowerIn = readPowerValueAbs(props: telemetry, key: "SystemPowerIn"),
           systemPowerIn >= Self.minimumVisibleWatts {
            let charging = chargingPowerW ?? 0
            let withoutCharge = systemPowerIn - charging
            return withoutCharge >= Self.minimumVisibleWatts ? withoutCharge : systemPowerIn
        }

        return nil
    }

    private func readExternalPowerConnected(props: [String: Any], powerSource: PowerSourceType) -> Bool {
        if let connected = props.bool("ExternalConnected") { return connected }
        if let connected = props.bool("AppleRawExternalConnected") { return connected }
        return powerSource == .powerAdapter
    }

    private func readPowerValueAbs(props: [String: Any], key: String) -> Double? {
        guard let mW = props.int64(key) else { return nil }
        return Double(abs(mW)) / 1_000.0
    }

    private func visibleWatts(_ value: Double) -> Double? {
        value >= Self.minimumVisibleWatts ? round2(value) : nil
    }

    private func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private func isFull(_ soc: Int?) -> Bool {
        guard let soc, (0...100).contains(soc) else { return false }
        return soc >= 100
    }

    private func readSmartBatteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)

        guard
            result == KERN_SUCCESS,
            let dict = unmanaged?.takeRetainedValue() as? [String: Any]
        else { return nil }

        return dict
    }
}

extension IOKitBatteryReader: BatterySnapshotReading {}
