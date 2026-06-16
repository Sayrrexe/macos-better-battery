import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: BatteryMonitor?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        BattarySettings.registerDefaults()
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = CatMascotAssets.image(for: .avatar)

        let monitor = BatteryMonitor()
        self.monitor = monitor
        self.statusBarController = StatusBarController(monitor: monitor)
    }
}

@main
struct BattaryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
