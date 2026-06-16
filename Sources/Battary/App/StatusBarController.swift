import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let monitor: BatteryMonitor
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellables = Set<AnyCancellable>()
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var lastStatusImageKey: StatusImageKey?
    private var lastToolTip: String?

    private static let dismissEventMask: NSEvent.EventTypeMask = [
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown
    ]

    init(monitor: BatteryMonitor) {
        self.monitor = monitor
        self.statusItem = NSStatusBar.system.statusItem(withLength: 40)
        self.popover = NSPopover()

        super.init()

        configureStatusItem()
        configurePopover()
        observeAppActivation()
        bindMonitor()
        updateStatusImage(snapshot: monitor.snapshot)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.title = ""
        button.toolTip = AppMetadata.displayName
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 640)
        resetPopoverContent()
    }

    private func observeAppActivation() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(closePopoverAfterAppDeactivation),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    private func resetPopoverContent() {
        popover.contentViewController = NSHostingController(
            rootView: BatteryPopoverView(monitor: monitor)
        )
    }

    private func startEventMonitoring() {
        stopEventMonitoring()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.dismissEventMask) { [weak self] event in
            guard let self else { return event }

            if self.shouldClosePopover(for: event) {
                self.closePopoverIfShown()
            }

            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.dismissEventMask) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopoverIfShown()
            }
        }
    }

    private func stopEventMonitoring() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func shouldClosePopover(for event: NSEvent) -> Bool {
        guard popover.isShown else { return false }

        let location = screenLocation(for: event)
        if popoverScreenFrame()?.contains(location) == true {
            return false
        }
        if statusButtonScreenFrame()?.contains(location) == true {
            return false
        }

        return true
    }

    private func closePopoverIfShown() {
        guard popover.isShown else { return }

        popover.performClose(nil)
    }

    private func screenLocation(for event: NSEvent) -> NSPoint {
        guard let window = event.window else {
            return event.locationInWindow
        }

        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private func popoverScreenFrame() -> NSRect? {
        popover.contentViewController?.view.window?.frame
    }

    private func statusButtonScreenFrame() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else {
            return nil
        }

        let buttonRect = button.convert(button.bounds, to: nil)
        return window.convertToScreen(buttonRect)
    }

    private func bindMonitor() {
        monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.updateStatusImage(snapshot: snapshot)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }

                self.lastStatusImageKey = nil
                self.updateStatusImage(snapshot: self.monitor.snapshot)
            }
            .store(in: &cancellables)
    }

    private func updateStatusImage(snapshot: BatterySnapshot) {
        guard let button = statusItem.button else { return }

        let imageKey = StatusImageKey(
            percent: snapshot.stateOfChargePercent,
            isCharging: snapshot.isCharging,
            appearanceName: button.effectiveAppearance.statusImageCacheName
        )

        if lastStatusImageKey != imageKey {
            button.image = StatusBarBatteryImageRenderer.image(
                percent: snapshot.stateOfChargePercent,
                progress: Double(snapshot.stateOfChargePercent ?? 0) / 100,
                isCharging: snapshot.isCharging
            )
            lastStatusImageKey = imageKey
        }

        let toolTip = "\(BatteryFormatters.percent(snapshot.stateOfChargePercent))% - \(snapshot.statusText())"
        if lastToolTip != toolTip {
            button.toolTip = toolTip
            lastToolTip = toolTip
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            closePopoverIfShown()
        } else {
            resetPopoverContent()
            monitor.setPopoverVisible(true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            startEventMonitoring()
        }
    }

    @objc private func closePopoverAfterAppDeactivation() {
        closePopoverIfShown()
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.stopEventMonitoring()
            self?.monitor.setPopoverVisible(false)
        }
    }
}

private struct StatusImageKey: Equatable {
    var percent: Int?
    var isCharging: Bool
    var appearanceName: String
}

private extension NSAppearance {
    var statusImageCacheName: String {
        bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])?.rawValue
            ?? name.rawValue
    }
}
