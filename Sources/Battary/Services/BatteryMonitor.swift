import AppKit
import Combine
import Foundation
import IOKit.ps

enum BatteryRefreshReason: Equatable {
    case startup
    case powerSourceChange
    case wake
    case fallback
    case activePopover
    case popoverOpened
    case manual
    case historyImported
}

protocol SystemHistoryReading {
    func readRecentHistory(since cutoff: Date) -> PMSetImportedHistory
}

@MainActor
final class BatteryMonitor: ObservableObject {
    static let activeSampleInterval: TimeInterval = 60
    static let fallbackSampleInterval: TimeInterval = 60 * 60
    private static let systemHistoryImportInterval: TimeInterval = 5 * 60
    private static let systemHistoryImportWindow: TimeInterval = 48 * 60 * 60

    @Published private(set) var snapshot: BatterySnapshot = .placeholder
    @Published private(set) var stats: BatteryStats = .empty

    private let reader: any BatterySnapshotReading
    private let historyStore: any BatteryHistoryStoring
    private let pmsetLogReader: any SystemHistoryReading
    private let lowBatteryNotifier: any LowBatteryNotifying
    private let usesSystemScheduling: Bool

    private var fallbackTimer: Timer?
    private var activePopoverTimer: Timer?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isPopoverVisible = false
    private var hasPublishedSnapshot = false
    private var shownLowBatteryThresholds = Set<Int>()
    private var lastSystemHistoryImportAt: Date?
    private var isImportingSystemHistory = false

    init(
        reader: any BatterySnapshotReading = IOKitBatteryReader(),
        historyStore: any BatteryHistoryStoring = BatteryHistoryStore(),
        pmsetLogReader: any SystemHistoryReading = PMSetLogReader(),
        lowBatteryNotifier: (any LowBatteryNotifying)? = nil,
        startsAutomatically: Bool = true
    ) {
        self.reader = reader
        self.historyStore = historyStore
        self.pmsetLogReader = pmsetLogReader
        if let lowBatteryNotifier {
            self.lowBatteryNotifier = lowBatteryNotifier
        } else if startsAutomatically {
            self.lowBatteryNotifier = LowBatteryNotifier()
        } else {
            self.lowBatteryNotifier = NoOpLowBatteryNotifier()
        }
        self.usesSystemScheduling = startsAutomatically

        if startsAutomatically, BattarySettings.notificationsEnabled() {
            self.lowBatteryNotifier.requestAuthorizationIfNeeded()
        }

        refresh(depth: .summary, reason: .startup)

        guard startsAutomatically else { return }

        startPowerSourceNotifications()
        startWorkspaceNotifications()
        scheduleFallbackTimer()
    }

    deinit {
        fallbackTimer?.invalidate()
        activePopoverTimer?.invalidate()

        if let powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
        }

        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    @discardableResult
    func refresh(
        depth requestedDepth: BatteryReadDepth? = nil,
        reason: BatteryRefreshReason = .manual
    ) -> BatterySnapshot {
        let depth = requestedDepth ?? (isPopoverVisible ? .details : .summary)
        let nextSnapshot = snapshotForPublishing(
            reader.readSnapshot(depth: depth),
            depth: depth
        )
        let nextStats = historyStore.record(nextSnapshot)
        let shouldPublishSnapshot = shouldPublish(nextSnapshot, depth: depth)
        let shouldPublishStats = isPopoverVisible || shouldPublishSnapshot

        handleLowBatteryWarning(for: nextSnapshot)

        if shouldPublishSnapshot {
            snapshot = nextSnapshot
            hasPublishedSnapshot = true
        }

        if shouldPublishStats, stats != nextStats {
            stats = nextStats
        }

        return nextSnapshot
    }

    func setPopoverVisible(_ isVisible: Bool) {
        guard isPopoverVisible != isVisible else { return }

        isPopoverVisible = isVisible

        if isVisible {
            scheduleActivePopoverTimer()
            refresh(depth: .details, reason: .popoverOpened)
            importSystemHistoryIfNeeded()
        } else {
            activePopoverTimer?.invalidate()
            activePopoverTimer = nil
        }
    }

    func importSystemHistoryIfNeeded(force: Bool = false) {
        guard !isImportingSystemHistory else { return }

        let now = Date()
        if !force,
           let lastSystemHistoryImportAt,
           now.timeIntervalSince(lastSystemHistoryImportAt) < Self.systemHistoryImportInterval {
            return
        }

        isImportingSystemHistory = true
        let reader = pmsetLogReader
        let cutoff = now.addingTimeInterval(-Self.systemHistoryImportWindow)

        Task { [weak self, reader, cutoff] in
            let history = await Task.detached(priority: .utility) {
                reader.readRecentHistory(since: cutoff)
            }.value

            await MainActor.run {
                guard let self else { return }

                self.lastSystemHistoryImportAt = Date()
                self.isImportingSystemHistory = false
                let nextStats = self.historyStore.importSystemHistory(
                    history,
                    currentSnapshot: self.snapshot
                )

                if self.isPopoverVisible, self.stats != nextStats {
                    self.stats = nextStats
                }

                if self.isPopoverVisible {
                    self.refresh(depth: .details, reason: .historyImported)
                }
            }
        }
    }

    func applyNotificationSettings() {
        let currentThresholds = Set(BattarySettings.notificationThresholds())
        shownLowBatteryThresholds = shownLowBatteryThresholds.intersection(currentThresholds)

        if BattarySettings.notificationsEnabled() {
            lowBatteryNotifier.requestAuthorizationIfNeeded()
        }

        refresh(depth: .summary, reason: .manual)
    }

    private func startPowerSourceNotifications() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard
            let source = IOPSNotificationCreateRunLoopSource({ context in
                guard let context else { return }
                let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()

                Task { @MainActor in
                    monitor.refresh(depth: .summary, reason: .powerSourceChange)
                }
            }, context)?.takeRetainedValue()
        else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSourceRunLoopSource = source
    }

    private func startWorkspaceNotifications() {
        let center = NSWorkspace.shared.notificationCenter

        let wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recordDisplayState(isOn: true)
                self?.refresh(depth: .summary, reason: .wake)
                self?.importSystemHistoryIfNeeded()
            }
        }

        let sleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recordDisplayState(isOn: false)
                self?.activePopoverTimer?.invalidate()
                self?.activePopoverTimer = nil
            }
        }

        let screensWakeObserver = center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recordDisplayState(isOn: true)
                self?.importSystemHistoryIfNeeded()

                if self?.isPopoverVisible == true {
                    self?.scheduleActivePopoverTimer()
                    self?.refresh(depth: .details, reason: .wake)
                }
            }
        }

        let screensSleepObserver = center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recordDisplayState(isOn: false)
                self?.activePopoverTimer?.invalidate()
                self?.activePopoverTimer = nil
            }
        }

        workspaceObservers = [
            wakeObserver,
            sleepObserver,
            screensWakeObserver,
            screensSleepObserver
        ]
    }

    private func recordDisplayState(isOn: Bool) {
        let nextStats = historyStore.recordDisplayState(
            DisplayStateEvent(timestamp: Date(), isOn: isOn),
            currentSnapshot: snapshot
        )

        if isPopoverVisible, stats != nextStats {
            stats = nextStats
        }
    }

    private func scheduleFallbackTimer() {
        fallbackTimer?.invalidate()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: Self.fallbackSampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(depth: .summary, reason: .fallback)
            }
        }
        fallbackTimer?.tolerance = Self.fallbackSampleInterval * 0.5
    }

    private func scheduleActivePopoverTimer() {
        activePopoverTimer?.invalidate()

        guard usesSystemScheduling else { return }

        activePopoverTimer = Timer.scheduledTimer(withTimeInterval: Self.activeSampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(depth: .details, reason: .activePopover)
            }
        }
        activePopoverTimer?.tolerance = Self.activeSampleInterval * 0.25
    }

    private func handleLowBatteryWarning(for nextSnapshot: BatterySnapshot) {
        guard BattarySettings.notificationsEnabled() else {
            shownLowBatteryThresholds.removeAll()
            return
        }

        guard nextSnapshot.isOnBattery, let percent = nextSnapshot.stateOfChargePercent else {
            shownLowBatteryThresholds.removeAll()
            return
        }

        let thresholds = BattarySettings.notificationThresholds()
        let reachedThresholds = Set(thresholds.filter { percent <= $0 })
        shownLowBatteryThresholds = shownLowBatteryThresholds
            .intersection(Set(thresholds))
            .filter { percent <= $0 }

        guard !reachedThresholds.isEmpty else {
            return
        }

        let pendingThresholds = reachedThresholds.subtracting(shownLowBatteryThresholds)
        guard !pendingThresholds.isEmpty else { return }

        lowBatteryNotifier.showLowBatteryWarning(percent: percent)
        shownLowBatteryThresholds.formUnion(reachedThresholds)
    }

    private func shouldPublish(_ nextSnapshot: BatterySnapshot, depth: BatteryReadDepth) -> Bool {
        guard hasPublishedSnapshot else { return true }
        if isPopoverVisible || depth == .details { return true }
        return !snapshot.isBackgroundEquivalent(to: nextSnapshot)
    }

    private func snapshotForPublishing(
        _ nextSnapshot: BatterySnapshot,
        depth: BatteryReadDepth
    ) -> BatterySnapshot {
        guard hasPublishedSnapshot else { return nextSnapshot }

        var merged = nextSnapshot
        let previous = snapshot

        switch depth {
        case .summary:
            merged.cycleCount = previous.cycleCount
            merged.chargingPowerW = previous.chargingPowerW
            merged.currentPowerW = previous.currentPowerW
            merged.healthDetails = previous.healthDetails
        case .details:
            merged.cycleCount = nextSnapshot.cycleCount ?? previous.cycleCount
            merged.healthDetails = nextSnapshot.healthDetails.fillingMissingValues(
                from: previous.healthDetails
            )

            if nextSnapshot.powerSource == previous.powerSource,
               nextSnapshot.isCharging == previous.isCharging {
                merged.chargingPowerW = nextSnapshot.chargingPowerW ?? previous.chargingPowerW
                merged.currentPowerW = nextSnapshot.currentPowerW ?? previous.currentPowerW
            }
        }

        return merged
    }
}

private extension BatterySnapshot {
    func isBackgroundEquivalent(to other: BatterySnapshot) -> Bool {
        powerSource == other.powerSource
            && isCharging == other.isCharging
            && isFastCharging == other.isFastCharging
            && isFull == other.isFull
            && stateOfChargePercent == other.stateOfChargePercent
            && isExternalPowerConnected == other.isExternalPowerConnected
    }
}

@MainActor
private final class NoOpLowBatteryNotifier: LowBatteryNotifying {
    func requestAuthorizationIfNeeded() {}
    func showLowBatteryWarning(percent: Int) {}
}
