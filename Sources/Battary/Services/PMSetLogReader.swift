import Foundation

struct PMSetImportedHistory: Equatable {
    var samples: [BatterySample] = []
    var displayEvents: [DisplayStateEvent] = []
}

struct PMSetLogReader {
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter
    }()

    private let chargeRegex = try? NSRegularExpression(
        pattern: #"Using\s+(AC|Batt|BATT).*Charge:?\s*(\d+)"#,
        options: [.caseInsensitive]
    )

    func readRecentHistory(since cutoff: Date = Date().addingTimeInterval(-24 * 60 * 60)) -> PMSetImportedHistory {
        let output = runPMSetLog()
        guard !output.isEmpty else { return PMSetImportedHistory() }

        var history = PMSetImportedHistory()
        var lastPowerSource: String?
        var lastCharge: Int?

        output.enumerateLines { line, _ in
            guard
                let timestamp = parseTimestamp(in: line),
                timestamp >= cutoff
            else { return }

            if let sample = parseBatterySample(
                in: line,
                timestamp: timestamp,
                lastPowerSource: &lastPowerSource,
                lastCharge: &lastCharge
            ) {
                history.samples.append(sample)
            }

            let isFullWake = (line.contains("Wake from") || line.contains("Wake reason"))
                && !line.contains("DarkWake")

            if line.contains("Display is turned on") || isFullWake {
                history.displayEvents.append(DisplayStateEvent(timestamp: timestamp, isOn: true))
            } else if line.contains("Display is turned off")
                || line.contains("Entering Sleep state")
                || line.contains("Entering DarkWake state") {
                history.displayEvents.append(DisplayStateEvent(timestamp: timestamp, isOn: false))
            }
        }

        return history
    }

    private func runPMSetLog() -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "log"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private func parseTimestamp(in line: String) -> Date? {
        guard line.count >= 25 else { return nil }
        let raw = String(line.prefix(25))
        return dateFormatter.date(from: raw)
    }

    private func parseBatterySample(
        in line: String,
        timestamp: Date,
        lastPowerSource: inout String?,
        lastCharge: inout Int?
    ) -> BatterySample? {
        guard
            let chargeRegex,
            let match = chargeRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
            let sourceRange = Range(match.range(at: 1), in: line),
            let chargeRange = Range(match.range(at: 2), in: line),
            let percent = Int(line[chargeRange])
        else { return nil }

        let rawSource = String(line[sourceRange]).uppercased()
        let isOnBattery = rawSource.contains("BATT")

        defer {
            lastPowerSource = rawSource
            lastCharge = percent
        }

        if lastPowerSource == rawSource, let lastCharge, abs(percent - lastCharge) < 1 {
            return nil
        }

        return BatterySample(
            timestamp: timestamp,
            percent: percent,
            isOnBattery: isOnBattery
        )
    }
}

extension PMSetLogReader: SystemHistoryReading {}
