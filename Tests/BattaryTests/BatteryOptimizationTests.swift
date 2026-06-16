import Foundation
import XCTest
@testable import Battary

final class BatteryHistoryStoreTests: XCTestCase {
    func testRepeatedSamePercentDoesNotCreateNewSampleOrSaveAgain() {
        let store = BatteryHistoryStore(fileURL: temporaryHistoryURL())
        let now = Date(timeIntervalSince1970: 1_000)

        let firstStats = store.record(makeSnapshot(at: now, percent: 50))
        XCTAssertEqual(firstStats.usableSampleCount, 1)
        XCTAssertEqual(store.sampleCount, 1)
        XCTAssertEqual(store.saveCount, 1)

        let secondStats = store.record(makeSnapshot(at: now.addingTimeInterval(60), percent: 50))
        XCTAssertEqual(secondStats.usableSampleCount, 1)
        XCTAssertEqual(store.sampleCount, 1)
        XCTAssertEqual(store.saveCount, 1)
    }

    func testChangedPercentCreatesNewSampleAndKeepsDrainStatsUseful() {
        let store = BatteryHistoryStore(fileURL: temporaryHistoryURL())
        let now = Date(timeIntervalSince1970: 2_000)

        _ = store.record(makeSnapshot(at: now, percent: 80))
        let stats = store.record(makeSnapshot(at: now.addingTimeInterval(60 * 60), percent: 70))

        XCTAssertEqual(store.sampleCount, 2)
        XCTAssertEqual(store.saveCount, 2)
        XCTAssertEqual(stats.usableSampleCount, 2)
        XCTAssertEqual(stats.averageDrainPercentPerHour, 10.0)
        XCTAssertEqual(stats.historyEstimatedTimeRemainingMinutes, 420)
    }

    func testSpentLastHourDoesNotUseWholeSessionWhenFreshSampleIsMissing() {
        let store = BatteryHistoryStore(fileURL: temporaryHistoryURL())
        let start = Date(timeIntervalSince1970: 2_200)

        _ = store.record(makeSnapshot(at: start, percent: 98))
        _ = store.record(makeSnapshot(at: start.addingTimeInterval(2 * 60 * 60), percent: 63))
        let stats = store.record(makeSnapshot(at: start.addingTimeInterval(3.25 * 60 * 60), percent: 63))

        XCTAssertNil(stats.spentLastHourPercent)
    }

    func testSinceUnpluggedUsesAwakeTimeInsteadOfElapsedTime() {
        let store = BatteryHistoryStore(fileURL: temporaryHistoryURL())
        let start = Date(timeIntervalSince1970: 2_500)

        _ = store.record(makeSnapshot(at: start, percent: 90))
        _ = store.recordDisplayState(
            DisplayStateEvent(timestamp: start.addingTimeInterval(10 * 60), isOn: false),
            currentSnapshot: makeSnapshot(at: start.addingTimeInterval(10 * 60), percent: 89)
        )
        _ = store.recordDisplayState(
            DisplayStateEvent(timestamp: start.addingTimeInterval(40 * 60), isOn: true),
            currentSnapshot: makeSnapshot(at: start.addingTimeInterval(40 * 60), percent: 89)
        )

        let stats = store.record(makeSnapshot(at: start.addingTimeInterval(70 * 60), percent: 83))

        XCTAssertEqual(stats.sinceUnplugged, 40 * 60)
        XCTAssertEqual(stats.screenOnSinceUnplugged, 40 * 60)
        XCTAssertEqual(stats.averageDrainPercentPerHour, 10.5)
    }

    func testAwakeTimeDoesNotShrinkWhenHistoryWindowPassesOriginalSample() {
        let store = BatteryHistoryStore(fileURL: temporaryHistoryURL())
        let start = Date(timeIntervalSince1970: 10_000)

        _ = store.record(makeSnapshot(at: start, percent: 90))
        _ = store.recordDisplayState(
            DisplayStateEvent(timestamp: start, isOn: false),
            currentSnapshot: makeSnapshot(at: start, percent: 90)
        )
        _ = store.recordDisplayState(
            DisplayStateEvent(timestamp: start.addingTimeInterval(60 * 60), isOn: true),
            currentSnapshot: makeSnapshot(at: start.addingTimeInterval(60 * 60), percent: 89)
        )
        _ = store.recordDisplayState(
            DisplayStateEvent(timestamp: start.addingTimeInterval(5 * 60 * 60), isOn: false),
            currentSnapshot: makeSnapshot(at: start.addingTimeInterval(5 * 60 * 60), percent: 84)
        )

        let afterHistoryWindow = start.addingTimeInterval(49 * 60 * 60)
        _ = store.record(makeSnapshot(at: afterHistoryWindow, percent: 80))
        let stats = store.record(makeSnapshot(at: afterHistoryWindow.addingTimeInterval(60), percent: 80))

        XCTAssertEqual(stats.sinceUnplugged, 4 * 60 * 60)
        XCTAssertEqual(stats.screenOnSinceUnplugged, 4 * 60 * 60)
    }

    func testLastChargeSampleCanAnchorAwakeTimeAndAverageDrain() {
        let store = BatteryHistoryStore(fileURL: temporaryHistoryURL())
        let lastCharge = Date(timeIntervalSince1970: 20_000)
        let now = lastCharge.addingTimeInterval((4 * 60 * 60) + (24 * 60))

        let stats = store.importSystemHistory(
            PMSetImportedHistory(
                samples: [
                    BatterySample(timestamp: lastCharge, percent: 100, isOnBattery: false)
                ],
                displayEvents: [
                    DisplayStateEvent(timestamp: lastCharge, isOn: true),
                    DisplayStateEvent(timestamp: now, isOn: false)
                ]
            ),
            currentSnapshot: makeSnapshot(at: now, percent: 59)
        )

        XCTAssertEqual(stats.sinceUnplugged, ((4 * 60 * 60) + (24 * 60)))
        XCTAssertEqual(stats.screenOnSinceUnplugged, ((4 * 60 * 60) + (24 * 60)))
        XCTAssertEqual(stats.averageDrainPercentPerHour, 9.3)
    }

    func testImportedSystemHistoryDedupesSamples() {
        let store = BatteryHistoryStore(fileURL: temporaryHistoryURL())
        let now = Date(timeIntervalSince1970: 3_000)
        let first = BatterySample(timestamp: now, percent: 80, isOnBattery: true)
        let duplicate = BatterySample(timestamp: now, percent: 80, isOnBattery: true)
        let second = BatterySample(timestamp: now.addingTimeInterval(60 * 60), percent: 75, isOnBattery: true)

        let stats = store.importSystemHistory(
            PMSetImportedHistory(
                samples: [first, duplicate, second],
                displayEvents: [
                    DisplayStateEvent(timestamp: now, isOn: true),
                    DisplayStateEvent(timestamp: now, isOn: true)
                ]
            ),
            currentSnapshot: makeSnapshot(at: now.addingTimeInterval(60 * 60), percent: 75)
        )

        XCTAssertEqual(store.sampleCount, 2)
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(stats.usableSampleCount, 2)
    }
}

final class DictionaryValueAccessTests: XCTestCase {
    func testUInt64TwosComplementValuesCanBeReadAsSignedInt64() {
        let values: [String: Any] = [
            "InstantAmperage": UInt64(bitPattern: Int64(-448))
        ]

        XCTAssertEqual(values.int64("InstantAmperage"), -448)
    }
}

final class BatteryHealthDetailsTests: XCTestCase {
    func testCycleProgressDropsOnlyAfterCompletedHundreds() {
        var details = BatteryHealthDetails()
        details.cycleLimit = 1_000

        details.cycleCount = 99
        XCTAssertEqual(details.cycleSteppedProgress, 1.0)

        details.cycleCount = 100
        XCTAssertEqual(details.cycleSteppedProgress, 0.9)

        details.cycleCount = 199
        XCTAssertEqual(details.cycleSteppedProgress, 0.9)

        details.cycleCount = 200
        XCTAssertEqual(details.cycleSteppedProgress, 0.8)
    }

    func testCycleProgressUsesCompletedHundredsBeforeHiddenThreshold() {
        var details = BatteryHealthDetails()
        details.cycleLimit = 1_000
        details.cycleCount = 899

        XCTAssertEqual(details.cycleSteppedProgress, 0.2)
    }

    func testCycleProgressAndLimitHideFromNineHundredCycles() {
        var details = BatteryHealthDetails()
        details.cycleLimit = 1_000

        details.cycleCount = 899
        XCTAssertTrue(details.showsCycleLimitAndProgress)
        XCTAssertEqual(details.cycleSteppedProgress, 0.2)

        details.cycleCount = 900
        XCTAssertFalse(details.showsCycleLimitAndProgress)
        XCTAssertNil(details.cycleSteppedProgress)
    }
}

@MainActor
final class BatteryMonitorRefreshPolicyTests: XCTestCase {
    func testClosedMonitorUsesSummaryReads() {
        let reader = SpyBatteryReader(snapshots: [
            makeSnapshot(at: Date(timeIntervalSince1970: 4_000), percent: 55),
            makeSnapshot(at: Date(timeIntervalSince1970: 4_060), percent: 55)
        ])
        let monitor = BatteryMonitor(
            reader: reader,
            historyStore: SpyHistoryStore(),
            pmsetLogReader: SpySystemHistoryReader(),
            startsAutomatically: false
        )

        XCTAssertEqual(reader.depths, [.summary])

        monitor.refresh(reason: .fallback)
        XCTAssertEqual(reader.depths, [.summary, .summary])
    }

    func testOpenPopoverUsesDetailsReads() {
        let reader = SpyBatteryReader(snapshots: [
            makeSnapshot(at: Date(timeIntervalSince1970: 5_000), percent: 55),
            makeSnapshot(at: Date(timeIntervalSince1970: 5_001), percent: 55)
        ])
        let monitor = BatteryMonitor(
            reader: reader,
            historyStore: SpyHistoryStore(),
            pmsetLogReader: SpySystemHistoryReader(),
            startsAutomatically: false
        )

        monitor.setPopoverVisible(true)

        XCTAssertEqual(Array(reader.depths.prefix(2)), [.summary, .details])
    }

    func testFallbackRefreshDoesNotSaveWithoutMeaningfulChange() {
        let store = BatteryHistoryStore(fileURL: temporaryHistoryURL())
        let reader = SpyBatteryReader(snapshots: [
            makeSnapshot(at: Date(timeIntervalSince1970: 6_000), percent: 64),
            makeSnapshot(at: Date(timeIntervalSince1970: 6_060), percent: 64)
        ])
        let monitor = BatteryMonitor(
            reader: reader,
            historyStore: store,
            pmsetLogReader: SpySystemHistoryReader(),
            startsAutomatically: false
        )

        XCTAssertEqual(store.saveCount, 1)

        monitor.refresh(reason: .fallback)
        XCTAssertEqual(store.saveCount, 1)
    }

    func testSummaryRefreshKeepsPreviouslyLoadedDetails() {
        let reader = SpyBatteryReader(snapshots: [
            makeSnapshot(at: Date(timeIntervalSince1970: 7_000), percent: 64),
            makeSnapshot(
                at: Date(timeIntervalSince1970: 7_001),
                percent: 64,
                details: BatteryHealthDetails(
                    healthPercent: 96,
                    cycleCount: 42,
                    cycleLimit: 1_000,
                    temperatureCelsius: 31.2,
                    voltageVolts: 12.08,
                    amperageMilliamps: -300,
                    powerUsageWatts: 3.6,
                    remainingCapacityMAh: 3_000,
                    currentFullCapacityMAh: 4_500,
                    designCapacityMAh: 4_700,
                    isDischarging: true
                )
            ),
            makeSnapshot(at: Date(timeIntervalSince1970: 7_060), percent: 64)
        ])
        let monitor = BatteryMonitor(
            reader: reader,
            historyStore: SpyHistoryStore(),
            pmsetLogReader: SpySystemHistoryReader(),
            startsAutomatically: false
        )

        monitor.setPopoverVisible(true)
        monitor.setPopoverVisible(false)
        monitor.refresh(reason: .fallback)

        XCTAssertEqual(monitor.snapshot.healthDetails.healthPercent, 96)
        XCTAssertEqual(monitor.snapshot.healthDetails.temperatureCelsius, 31.2)
        XCTAssertEqual(monitor.snapshot.healthDetails.designCapacityMAh, 4_700)
    }

    func testLowBatteryWarningSendsAtTwentyPercentOnBattery() {
        let notifier = SpyLowBatteryNotifier()
        let reader = SpyBatteryReader(snapshots: [
            makeSnapshot(at: Date(timeIntervalSince1970: 8_000), percent: 25),
            makeSnapshot(at: Date(timeIntervalSince1970: 8_060), percent: 20)
        ])
        let monitor = BatteryMonitor(
            reader: reader,
            historyStore: SpyHistoryStore(),
            pmsetLogReader: SpySystemHistoryReader(),
            lowBatteryNotifier: notifier,
            startsAutomatically: false
        )

        monitor.refresh(reason: .fallback)

        XCTAssertEqual(notifier.warningPercents, [20])
    }

    func testLowBatteryWarningDoesNotRepeatWhileStillLow() {
        let notifier = SpyLowBatteryNotifier()
        let reader = SpyBatteryReader(snapshots: [
            makeSnapshot(at: Date(timeIntervalSince1970: 9_000), percent: 25),
            makeSnapshot(at: Date(timeIntervalSince1970: 9_060), percent: 20),
            makeSnapshot(at: Date(timeIntervalSince1970: 9_120), percent: 19),
            makeSnapshot(at: Date(timeIntervalSince1970: 9_180), percent: 18)
        ])
        let monitor = BatteryMonitor(
            reader: reader,
            historyStore: SpyHistoryStore(),
            pmsetLogReader: SpySystemHistoryReader(),
            lowBatteryNotifier: notifier,
            startsAutomatically: false
        )

        monitor.refresh(reason: .fallback)
        monitor.refresh(reason: .fallback)
        monitor.refresh(reason: .fallback)

        XCTAssertEqual(notifier.warningPercents, [20])
    }

    func testLowBatteryWarningResetsAfterChargeRisesAboveThreshold() {
        let notifier = SpyLowBatteryNotifier()
        let reader = SpyBatteryReader(snapshots: [
            makeSnapshot(at: Date(timeIntervalSince1970: 10_000), percent: 25),
            makeSnapshot(at: Date(timeIntervalSince1970: 10_060), percent: 20),
            makeSnapshot(at: Date(timeIntervalSince1970: 10_120), percent: 50),
            makeSnapshot(at: Date(timeIntervalSince1970: 10_180), percent: 20)
        ])
        let monitor = BatteryMonitor(
            reader: reader,
            historyStore: SpyHistoryStore(),
            pmsetLogReader: SpySystemHistoryReader(),
            lowBatteryNotifier: notifier,
            startsAutomatically: false
        )

        monitor.refresh(reason: .fallback)
        monitor.refresh(reason: .fallback)
        monitor.refresh(reason: .fallback)

        XCTAssertEqual(notifier.warningPercents, [20, 20])
    }

    func testCustomLowBatteryWarningSendsBeforeDefaultThreshold() {
        withNotificationThresholds([40, 20]) {
            let notifier = SpyLowBatteryNotifier()
            let reader = SpyBatteryReader(snapshots: [
                makeSnapshot(at: Date(timeIntervalSince1970: 11_000), percent: 45),
                makeSnapshot(at: Date(timeIntervalSince1970: 11_060), percent: 35)
            ])
            let monitor = BatteryMonitor(
                reader: reader,
                historyStore: SpyHistoryStore(),
                pmsetLogReader: SpySystemHistoryReader(),
                lowBatteryNotifier: notifier,
                startsAutomatically: false
            )

            monitor.refresh(reason: .fallback)

            XCTAssertEqual(notifier.warningPercents, [35])
        }
    }

    func testApplyingNotificationSettingsDoesNotRepeatAlreadyShownCustomThreshold() {
        withNotificationThresholds([40, 20]) {
            let notifier = SpyLowBatteryNotifier()
            let reader = SpyBatteryReader(snapshots: [
                makeSnapshot(at: Date(timeIntervalSince1970: 12_000), percent: 45),
                makeSnapshot(at: Date(timeIntervalSince1970: 12_060), percent: 35),
                makeSnapshot(at: Date(timeIntervalSince1970: 12_120), percent: 35)
            ])
            let monitor = BatteryMonitor(
                reader: reader,
                historyStore: SpyHistoryStore(),
                pmsetLogReader: SpySystemHistoryReader(),
                lowBatteryNotifier: notifier,
                startsAutomatically: false
            )

            monitor.refresh(reason: .fallback)
            monitor.applyNotificationSettings()

            XCTAssertEqual(notifier.warningPercents, [35])
        }
    }

    func testJumpBelowMultipleCustomThresholdsDoesNotWarnAgainWhenReadingRises() {
        withNotificationThresholds([40, 20]) {
            let notifier = SpyLowBatteryNotifier()
            let reader = SpyBatteryReader(snapshots: [
                makeSnapshot(at: Date(timeIntervalSince1970: 13_000), percent: 45),
                makeSnapshot(at: Date(timeIntervalSince1970: 13_060), percent: 15),
                makeSnapshot(at: Date(timeIntervalSince1970: 13_120), percent: 25)
            ])
            let monitor = BatteryMonitor(
                reader: reader,
                historyStore: SpyHistoryStore(),
                pmsetLogReader: SpySystemHistoryReader(),
                lowBatteryNotifier: notifier,
                startsAutomatically: false
            )

            monitor.refresh(reason: .fallback)
            monitor.refresh(reason: .fallback)

            XCTAssertEqual(notifier.warningPercents, [15])
        }
    }
}

private final class SpyBatteryReader: BatterySnapshotReading {
    private var snapshots: [BatterySnapshot]
    private(set) var depths: [BatteryReadDepth] = []

    init(snapshots: [BatterySnapshot]) {
        self.snapshots = snapshots
    }

    func readSnapshot(depth: BatteryReadDepth) -> BatterySnapshot {
        depths.append(depth)
        guard !snapshots.isEmpty else {
            return makeSnapshot(at: Date(), percent: 50)
        }
        return snapshots.removeFirst()
    }
}

private final class SpyHistoryStore: BatteryHistoryStoring {
    var sampleCount = 0
    var saveCount = 0
    private var recordCount = 0

    func record(_ snapshot: BatterySnapshot) -> BatteryStats {
        recordCount += 1
        sampleCount = recordCount
        return BatteryStats(usableSampleCount: sampleCount)
    }

    func recordDisplayState(_ event: DisplayStateEvent, currentSnapshot: BatterySnapshot) -> BatteryStats {
        BatteryStats(usableSampleCount: sampleCount)
    }

    func importSystemHistory(_ history: PMSetImportedHistory, currentSnapshot: BatterySnapshot) -> BatteryStats {
        BatteryStats(usableSampleCount: sampleCount)
    }
}

private struct SpySystemHistoryReader: SystemHistoryReading {
    func readRecentHistory(since cutoff: Date) -> PMSetImportedHistory {
        PMSetImportedHistory()
    }
}

private final class SpyLowBatteryNotifier: LowBatteryNotifying {
    private(set) var didRequestAuthorization = false
    private(set) var warningPercents: [Int] = []

    func requestAuthorizationIfNeeded() {
        didRequestAuthorization = true
    }

    func showLowBatteryWarning(percent: Int) {
        warningPercents.append(percent)
    }
}

private func temporaryHistoryURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("BattaryTests-\(UUID().uuidString)")
        .appendingPathExtension("json")
}

private func withNotificationThresholds(_ thresholds: [Int], operation: () -> Void) {
    let defaults = UserDefaults.standard
    let previousThresholds = defaults.object(forKey: BattarySettings.notificationThresholdsKey)
    let previousNotificationsEnabled = defaults.object(forKey: BattarySettings.notificationsEnabledKey)

    defaults.set(BattarySettings.notificationThresholdsRaw(from: thresholds), forKey: BattarySettings.notificationThresholdsKey)
    defaults.set(true, forKey: BattarySettings.notificationsEnabledKey)

    defer {
        restore(previousThresholds, forKey: BattarySettings.notificationThresholdsKey, defaults: defaults)
        restore(previousNotificationsEnabled, forKey: BattarySettings.notificationsEnabledKey, defaults: defaults)
    }

    operation()
}

private func restore(_ value: Any?, forKey key: String, defaults: UserDefaults) {
    if let value {
        defaults.set(value, forKey: key)
    } else {
        defaults.removeObject(forKey: key)
    }
}

private func makeSnapshot(
    at date: Date,
    percent: Int,
    isOnBattery: Bool = true,
    isCharging: Bool = false,
    powerSource: PowerSourceType = .battery,
    details: BatteryHealthDetails = .empty
) -> BatterySnapshot {
    var snapshot = BatterySnapshot()
    snapshot.timestamp = date
    snapshot.powerSource = powerSource
    snapshot.isCharging = isCharging
    snapshot.stateOfChargePercent = percent
    snapshot.isExternalPowerConnected = !isOnBattery
    snapshot.cycleCount = details.cycleCount
    snapshot.currentPowerW = details.powerUsageWatts
    snapshot.healthDetails = details
    return snapshot
}
