import Foundation
@preconcurrency import UserNotifications

@MainActor
protocol LowBatteryNotifying: AnyObject {
    func requestAuthorizationIfNeeded()
    func showLowBatteryWarning(percent: Int)
}

@MainActor
final class LowBatteryNotifier: NSObject, LowBatteryNotifying {
    private let notificationCenter: UNUserNotificationCenter
    private var hasRequestedAuthorization = false

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
        super.init()
        notificationCenter.delegate = self
    }

    func requestAuthorizationIfNeeded() {
        guard !hasRequestedAuthorization else { return }

        hasRequestedAuthorization = true
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func showLowBatteryWarning(percent: Int) {
        let request = makeWarningRequest(percent: percent)
        let notificationCenter = notificationCenter

        notificationCenter.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                notificationCenter.add(request)
            case .notDetermined:
                notificationCenter.requestAuthorization(options: [.alert, .sound]) { isGranted, _ in
                    guard isGranted else { return }
                    notificationCenter.add(request)
                }
            case .denied:
                return
            @unknown default:
                return
            }
        }
    }

    private func makeWarningRequest(percent: Int) -> UNNotificationRequest {
        let language = BattarySettings.language()
        let content = UNMutableNotificationContent()
        content.title = language == .russian ? "Осталось \(percent)%" : "\(percent)% Remaining"
        content.body = language == .russian ? "Подключите зарядку в ближайшее время." : "Connect your charger soon."

        if BattarySettings.notificationSoundEnabled() {
            content.sound = .default
        }

        return UNNotificationRequest(
            identifier: AppMetadata.lowBatteryNotificationIdentifier(percent: percent),
            content: content,
            trigger: nil
        )
    }
}

extension LowBatteryNotifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
