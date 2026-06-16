import Foundation

struct BatterySample: Codable, Equatable {
    var timestamp: Date
    var percent: Int
    var isOnBattery: Bool
}

struct DisplayStateEvent: Codable, Equatable {
    var timestamp: Date
    var isOn: Bool
}

protocol BatteryHistoryStoring: AnyObject {
    var sampleCount: Int { get }
    var saveCount: Int { get }

    func record(_ snapshot: BatterySnapshot) -> BatteryStats
    func recordDisplayState(_ event: DisplayStateEvent, currentSnapshot: BatterySnapshot) -> BatteryStats
    func importSystemHistory(_ history: PMSetImportedHistory, currentSnapshot: BatterySnapshot) -> BatteryStats
}

private struct RecordedSnapshotSignature: Codable, Equatable {
    var percent: Int?
    var powerSource: PowerSourceType
    var isCharging: Bool
    var isOnBattery: Bool

    init(snapshot: BatterySnapshot) {
        self.percent = snapshot.stateOfChargePercent
        self.powerSource = snapshot.powerSource
        self.isCharging = snapshot.isCharging
        self.isOnBattery = snapshot.isOnBattery
    }
}

private struct BatteryHistoryState: Codable {
    var samples: [BatterySample] = []
    var displayEvents: [DisplayStateEvent] = []
    var unpluggedAt: Date?
    var lastRecordedSnapshot: RecordedSnapshotSignature?
}

final class BatteryHistoryStore: BatteryHistoryStoring {
    private let fileURL: URL
    private var state: BatteryHistoryState
    private let calendarWindow: TimeInterval = 48 * 60 * 60
    private(set) var saveCount = 0

    var sampleCount: Int {
        state.samples.count
    }

    init(fileURL: URL = BatteryHistoryStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.state = Self.load(from: fileURL)
    }

    func record(_ snapshot: BatterySnapshot) -> BatteryStats {
        let previousSignature = state.lastRecordedSnapshot
        let nextSignature = RecordedSnapshotSignature(snapshot: snapshot)
        let previousUnpluggedAt = state.unpluggedAt
        var didMutate = false

        if let percent = snapshot.stateOfChargePercent {
            didMutate = appendUniqueSample(
                BatterySample(
                    timestamp: snapshot.timestamp,
                    percent: percent,
                    isOnBattery: snapshot.isOnBattery
                )
            ) || didMutate
        }

        updateUnpluggedSession(using: snapshot)

        if previousSignature != nextSignature {
            state.lastRecordedSnapshot = nextSignature
            didMutate = true
        }

        didMutate = trimSamples(now: snapshot.timestamp) || didMutate
        didMutate = previousUnpluggedAt != state.unpluggedAt || didMutate
        let stats = computeStats(for: snapshot)

        if didMutate {
            save()
        }

        return stats
    }

    func importSystemHistory(_ history: PMSetImportedHistory, currentSnapshot: BatterySnapshot) -> BatteryStats {
        var didMutate = false

        for sample in history.samples {
            didMutate = appendUniqueSample(sample) || didMutate
        }

        for event in history.displayEvents {
            didMutate = appendUniqueDisplayEvent(event) || didMutate
        }

        if let percent = currentSnapshot.stateOfChargePercent {
            didMutate = appendUniqueSample(
                BatterySample(
                    timestamp: currentSnapshot.timestamp,
                    percent: percent,
                    isOnBattery: currentSnapshot.isOnBattery
                )
            ) || didMutate
        }

        updateUnpluggedSession(using: currentSnapshot)
        didMutate = trimSamples(now: currentSnapshot.timestamp) || didMutate
        state.lastRecordedSnapshot = RecordedSnapshotSignature(snapshot: currentSnapshot)
        let stats = computeStats(for: currentSnapshot)

        if didMutate {
            save()
        }

        return stats
    }

    func recordDisplayState(_ event: DisplayStateEvent, currentSnapshot: BatterySnapshot) -> BatteryStats {
        var didMutate = appendUniqueDisplayEvent(event)
        didMutate = trimSamples(now: event.timestamp) || didMutate

        var snapshot = currentSnapshot
        if snapshot.timestamp < event.timestamp {
            snapshot.timestamp = event.timestamp
        }

        let stats = computeStats(for: snapshot)

        if didMutate {
            save()
        }

        return stats
    }

    private func updateUnpluggedSession(using snapshot: BatterySnapshot) {
        if snapshot.isOnBattery {
            state.unpluggedAt = currentUnpluggedStart(upTo: snapshot.timestamp) ?? snapshot.timestamp
        } else if snapshot.powerSource == .powerAdapter || snapshot.isCharging {
            state.unpluggedAt = nil
        }
    }

    private func computeStats(for snapshot: BatterySnapshot) -> BatteryStats {
        guard snapshot.isOnBattery, let currentPercent = snapshot.stateOfChargePercent else {
            return BatteryStats(usableSampleCount: state.samples.count)
        }

        let now = snapshot.timestamp
        let sessionStart = state.unpluggedAt ?? now
        let sessionBaselineSample = state.samples
            .first { $0.timestamp >= sessionStart }
        let sessionSamples = state.samples
            .filter { $0.isOnBattery && $0.timestamp >= sessionStart }

        let recentCutoff = now.addingTimeInterval(-60 * 60)
        let recentSamples = state.samples
            .filter { $0.timestamp >= max(recentCutoff, sessionStart) }

        let spentLastHour = Self.dropPercent(
            from: recentSamples.first,
            currentPercent: currentPercent,
            now: now,
            minimumSeconds: 10 * 60
        )

        let activeSinceUnplugged = screenOnDuration(from: sessionStart, to: now)
        let averageDenominator = activeSinceUnplugged.flatMap { $0 >= 10 * 60 ? $0 : nil }
            ?? sessionBaselineSample.map { now.timeIntervalSince($0.timestamp) }

        let averageDrain = Self.dropPerHour(
            from: sessionBaselineSample,
            currentPercent: currentPercent,
            now: now,
            activeSeconds: averageDenominator,
            minimumSeconds: 10 * 60
        )

        let estimatedMinutes: Int? = averageDrain.flatMap { drain in
            guard drain > 0 else { return nil }
            return Int((Double(currentPercent) / drain * 60).rounded())
        }

        return BatteryStats(
            sinceUnplugged: activeSinceUnplugged,
            spentLastHourPercent: spentLastHour,
            averageDrainPercentPerHour: averageDrain,
            historyEstimatedTimeRemainingMinutes: estimatedMinutes,
            screenOnSinceUnplugged: activeSinceUnplugged,
            usableSampleCount: sessionSamples.count
        )
    }

    private static func dropPercent(
        from sample: BatterySample?,
        currentPercent: Int,
        now: Date,
        minimumSeconds: TimeInterval
    ) -> Double? {
        guard let sample else { return nil }
        let elapsed = now.timeIntervalSince(sample.timestamp)
        guard elapsed >= minimumSeconds else { return nil }

        let drop = max(0, sample.percent - currentPercent)
        return Double(drop)
    }

    private static func dropPerHour(
        from sample: BatterySample?,
        currentPercent: Int,
        now: Date,
        activeSeconds: TimeInterval?,
        minimumSeconds: TimeInterval
    ) -> Double? {
        guard let sample else { return nil }
        let elapsed = activeSeconds ?? now.timeIntervalSince(sample.timestamp)
        guard elapsed >= minimumSeconds else { return nil }

        let drop = max(0, sample.percent - currentPercent)
        guard drop > 0 else { return 0 }

        let perHour = Double(drop) / elapsed * 60 * 60
        return (perHour * 10).rounded() / 10
    }

    private func inferCurrentUnpluggedStart(upTo now: Date) -> Date? {
        let ordered = state.samples
            .filter { $0.timestamp <= now }

        var start: Date?

        var externalPowerCandidate: Date?

        for sample in ordered {
            if sample.isOnBattery {
                if start == nil {
                    start = externalPowerCandidate ?? sample.timestamp
                }
            } else {
                externalPowerCandidate = sample.timestamp
                start = nil
            }
        }

        return start
    }

    private func currentUnpluggedStart(upTo now: Date) -> Date? {
        let inferred = inferCurrentUnpluggedStart(upTo: now)

        guard let previous = state.unpluggedAt, previous <= now else {
            return inferred
        }

        let sawExternalPowerSincePrevious = state.samples.contains {
            !$0.isOnBattery && $0.timestamp >= previous && $0.timestamp <= now
        }

        if sawExternalPowerSincePrevious {
            return inferred
        }

        guard let inferred else { return previous }
        return min(previous, inferred)
    }

    private func screenOnDuration(from start: Date, to end: Date) -> TimeInterval? {
        guard end > start else { return nil }

        let ordered = state.displayEvents
            .filter { $0.timestamp <= end }

        var isOn = ordered.last(where: { $0.timestamp <= start })?.isOn ?? true
        var cursor = start
        var total: TimeInterval = 0

        for event in ordered where event.timestamp >= start {
            if isOn {
                total += max(0, event.timestamp.timeIntervalSince(cursor))
            }

            isOn = event.isOn
            cursor = event.timestamp
        }

        if isOn {
            total += max(0, end.timeIntervalSince(cursor))
        }

        return max(0, total)
    }

    private func trimSamples(now: Date) -> Bool {
        let previousSampleCount = state.samples.count
        let previousDisplayEventCount = state.displayEvents.count
        let rollingCutoff = now.addingTimeInterval(-calendarWindow)
        let cutoff = state.unpluggedAt.map { min(rollingCutoff, $0) } ?? rollingCutoff
        state.samples.removeAll { $0.timestamp < cutoff }
        state.displayEvents.removeAll { $0.timestamp < cutoff }

        if state.samples.count > 1_500 {
            state.samples = Array(state.samples.suffix(1_500))
        }

        if state.displayEvents.count > 1_500 {
            state.displayEvents = Array(state.displayEvents.suffix(1_500))
        }

        return previousSampleCount != state.samples.count
            || previousDisplayEventCount != state.displayEvents.count
    }

    private func appendUniqueSample(_ sample: BatterySample) -> Bool {
        guard !state.samples.contains(where: { $0.historyKey == sample.historyKey }) else {
            return false
        }

        if let last = state.samples.last,
           sample.timestamp >= last.timestamp,
           last.percent == sample.percent,
           last.isOnBattery == sample.isOnBattery {
            return false
        }

        let index = insertionIndex(
            for: sample.timestamp,
            in: state.samples.map(\.timestamp)
        )
        state.samples.insert(sample, at: index)
        return true
    }

    private func appendUniqueDisplayEvent(_ event: DisplayStateEvent) -> Bool {
        guard !state.displayEvents.contains(where: { $0.historyKey == event.historyKey }) else {
            return false
        }

        let index = insertionIndex(
            for: event.timestamp,
            in: state.displayEvents.map(\.timestamp)
        )
        state.displayEvents.insert(event, at: index)
        return true
    }

    private func insertionIndex(for timestamp: Date, in timestamps: [Date]) -> Int {
        var low = 0
        var high = timestamps.count

        while low < high {
            let mid = (low + high) / 2
            if timestamps[mid] <= timestamp {
                low = mid + 1
            } else {
                high = mid
            }
        }

        return low
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: .atomic)
            saveCount += 1
        } catch {}
    }

    private static func load(from url: URL) -> BatteryHistoryState {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return normalize(try decoder.decode(BatteryHistoryState.self, from: data))
        } catch {
            return BatteryHistoryState()
        }
    }

    private static func normalize(_ state: BatteryHistoryState) -> BatteryHistoryState {
        var normalized = state
        var sampleKeys = Set<String>()
        normalized.samples = state.samples
            .sorted { $0.timestamp < $1.timestamp }
            .filter { sample in
                sampleKeys.insert(sample.historyKey).inserted
            }

        var displayKeys = Set<String>()
        normalized.displayEvents = state.displayEvents
            .sorted { $0.timestamp < $1.timestamp }
            .filter { event in
                displayKeys.insert(event.historyKey).inserted
            }

        return normalized
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser

        return base
            .appendingPathComponent(AppMetadata.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("battery-history.json")
    }
}

private extension BatterySample {
    var historyKey: String {
        "\(Int(timestamp.timeIntervalSince1970))-\(percent)-\(isOnBattery)"
    }
}

private extension DisplayStateEvent {
    var historyKey: String {
        "\(Int(timestamp.timeIntervalSince1970))-\(isOn)"
    }
}
