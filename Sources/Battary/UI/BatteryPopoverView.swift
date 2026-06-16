import AppKit
import SwiftUI
@preconcurrency import UserNotifications

struct BatteryPopoverView: View {
    @ObservedObject var monitor: BatteryMonitor
    @AppStorage(BattarySettings.languageKey) private var languageRawValue = BattaryLanguage.russian.rawValue
    @AppStorage(BattarySettings.notificationsEnabledKey) private var notificationsEnabled = true
    @AppStorage(BattarySettings.notificationThresholdsKey) private var notificationThresholdsRaw = BattarySettings.defaultNotificationThresholdsRaw
    @AppStorage(BattarySettings.notificationSoundEnabledKey) private var notificationSoundEnabled = true
    @AppStorage(BattarySettings.healthyColorKey) private var healthyColorHex = BatteryColorRole.healthy.defaultHex
    @AppStorage(BattarySettings.balancedColorKey) private var balancedColorHex = BatteryColorRole.balanced.defaultHex
    @AppStorage(BattarySettings.lowColorKey) private var lowColorHex = BatteryColorRole.low.defaultHex
    @AppStorage(BattarySettings.criticalColorKey) private var criticalColorHex = BatteryColorRole.critical.defaultHex
    @AppStorage(BattarySettings.chargingColorKey) private var chargingColorHex = BatteryColorRole.charging.defaultHex

    @State private var selectedTab: PopoverTab = .overview
    @State private var isBatteryInformationExpanded = false
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus?

    private var snapshot: BatterySnapshot {
        monitor.snapshot
    }

    private var stats: BatteryStats {
        monitor.stats
    }

    private var progress: Double {
        Double(snapshot.stateOfChargePercent ?? 0) / 100
    }

    private var chargeAccent: Color {
        BatteryTheme.chargeColor(for: snapshot.stateOfChargePercent, isCharging: snapshot.isCharging)
    }

    private var details: BatteryHealthDetails {
        snapshot.healthDetails
    }

    private var language: BattaryLanguage {
        BattaryLanguage(rawValue: languageRawValue) ?? .russian
    }

    private var copy: BatteryPopoverCopy {
        BatteryPopoverCopy(language: language)
    }

    private var notificationThresholds: [Int] {
        BattarySettings.parseNotificationThresholds(notificationThresholdsRaw)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 9) {
                tabPicker

                switch selectedTab {
                case .overview:
                    heroCard
                    statsPanel
                    batteryInformationPanel
                    actionPanel
                case .settings:
                    settingsContent
                }
            }
            .padding(10)
        }
        .frame(width: 360)
        .frame(maxHeight: 640)
        .background {
            GlassPopoverBackground()
        }
    }

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            Label(copy.overviewTab, systemImage: "bolt.circle.fill")
                .tag(PopoverTab.overview)
            Label(copy.settingsTab, systemImage: "gearshape.fill")
                .tag(PopoverTab.settings)
        }
        .pickerStyle(.segmented)
    }

    private var heroCard: some View {
        VStack(spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(BatteryFormatters.percent(snapshot.stateOfChargePercent))
                            .font(.system(size: 43, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(chargeAccent)

                        Text("%")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(chargeAccent.opacity(0.78))
                    }

                    HStack(spacing: 8) {
                        CatMascotIcon(
                            percent: snapshot.stateOfChargePercent,
                            isCharging: snapshot.isCharging
                        )
                        .frame(width: 31, height: 27)

                        Text(copy.statusText(for: snapshot))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(BatteryTheme.lightText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(copy.timeTitle(for: snapshot))
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(BatteryTheme.mutedText)

                    Text(snapshot.timeValue(using: stats))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(BatteryTheme.lightText)
                        .lineLimit(1)
                }
                .padding(.top, 6)
            }

            ChargeProgressBar(
                progress: progress,
                percent: snapshot.stateOfChargePercent,
                isCharging: snapshot.isCharging
            )
                .frame(height: 12)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(BatteryTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BatteryTheme.stroke, lineWidth: 1)
        )
    }

    private var statsPanel: some View {
        VStack(spacing: 0) {
            StatRow(
                icon: "clock.arrow.circlepath",
                title: copy.awakeTime,
                value: BatteryFormatters.duration(stats.sinceUnplugged),
                accent: BatteryTheme.blue
            )

            Divider().overlay(BatteryTheme.divider).padding(.leading, 42)

            StatRow(
                icon: "drop.fill",
                title: copy.spentLastHour,
                value: copy.spent(stats.spentLastHourPercent),
                accent: BatteryTheme.green
            )

            Divider().overlay(BatteryTheme.divider).padding(.leading, 42)

            StatRow(
                icon: "speedometer",
                title: copy.averageDrain,
                value: copy.rate(stats.averageDrainPercentPerHour),
                accent: BatteryTheme.green
            )

            Divider().overlay(BatteryTheme.divider).padding(.leading, 42)

            StatRow(
                icon: "bolt.horizontal.fill",
                title: snapshot.isCharging ? copy.chargingPower : copy.currentPower,
                value: BatteryFormatters.watts(snapshot.isCharging ? snapshot.chargingPowerW : snapshot.currentPowerW),
                accent: chargeAccent
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(BatteryTheme.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BatteryTheme.stroke, lineWidth: 1)
        )
    }

    private var actionPanel: some View {
        VStack(spacing: 0) {
            ActionRow(
                icon: "slider.horizontal.3",
                title: copy.systemBatterySettings,
                accent: BatteryTheme.lightText
            ) {
                SystemLinks.openBatterySettings()
            }

            Divider().overlay(BatteryTheme.divider).padding(.leading, 42)

            ActionRow(
                icon: "arrow.clockwise",
                title: copy.refresh,
                accent: BatteryTheme.blue
            ) {
                monitor.importSystemHistoryIfNeeded(force: true)
                monitor.refresh(depth: .details, reason: .manual)
            }

            Divider().overlay(BatteryTheme.divider).padding(.leading, 42)

            ActionRow(
                icon: "power",
                title: copy.quit,
                accent: BatteryTheme.red
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(BatteryTheme.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BatteryTheme.stroke, lineWidth: 1)
        )
    }

    private var batteryInformationPanel: some View {
        VStack(spacing: 0) {
            DisclosurePanelHeader(
                icon: "battery.100",
                title: copy.batteryInformation,
                accent: BatteryTheme.blue,
                isExpanded: isBatteryInformationExpanded
            ) {
                let willExpand = !isBatteryInformationExpanded
                withAnimation(.easeInOut(duration: 0.18)) {
                    isBatteryInformationExpanded.toggle()
                }
                if willExpand {
                    monitor.refresh(depth: .details, reason: .manual)
                }
            }

            if isBatteryInformationExpanded {
                Divider().overlay(BatteryTheme.divider)

                batteryHealthBlock

                sectionDivider

                temperatureBlock

                sectionDivider

                powerElectricalBlock

                sectionDivider

                capacityBlock
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(BatteryTheme.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BatteryTheme.stroke, lineWidth: 1)
        )
    }

    private var batteryHealthBlock: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                InfoBlockTitle(icon: "checkmark.circle.fill", title: copy.batteryHealth, accent: BatteryTheme.green)

                Spacer()
            }

            HStack(alignment: .center, spacing: 10) {
                Text(details.healthPercent.map { "\($0)%" } ?? "--")
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(BatteryTheme.green)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Text(copy.healthStatus(details.healthPercent))
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(BatteryTheme.green)
                    .lineLimit(1)

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(BatteryFormatters.cycleCount(
                        details.cycleCount,
                        limit: details.showsCycleLimitAndProgress ? details.cycleLimit : nil
                    ))
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(BatteryTheme.lightText)
                        .lineLimit(1)

                    Text(copy.cycleCount)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(BatteryTheme.mutedText)
                        .lineLimit(1)
                }
            }

            if details.showsCycleLimitAndProgress {
                HealthProgressBar(progress: healthBarProgress)
                    .frame(height: 8)
            }
        }
        .padding(14)
    }

    private var temperatureBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                InfoBlockTitle(icon: "checkmark.circle.fill", title: copy.temperature, accent: BatteryTheme.green)

                Spacer()
            }

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(BatteryTheme.green)

                        Text(BatteryFormatters.temperatureC(details.temperatureCelsius))
                            .font(.system(size: 23, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(BatteryTheme.green)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Text(BatteryFormatters.temperatureF(details.temperatureFahrenheit))
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(BatteryTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(BatteryTheme.green)

                        Text(copy.temperatureStatus(details.temperatureCelsius))
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(BatteryTheme.green)
                            .lineLimit(1)
                    }

                    Text(copy.optimalPerformance)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(BatteryTheme.mutedText)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
    }

    private var powerElectricalBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                InfoBlockTitle(icon: "bolt.circle.fill", title: copy.powerElectrical, accent: BatteryTheme.orange)

                Spacer()
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 13) {
                    MetricStack(title: copy.powerUsage, value: BatteryFormatters.watts(details.powerUsageWatts))
                    MetricStack(title: copy.current, value: BatteryFormatters.milliamps(details.amperageMilliamps), trailingIcon: "arrow.down.circle.fill")
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 13) {
                    MetricStack(title: copy.voltage, value: BatteryFormatters.voltage(details.voltageVolts), alignment: .trailing)

                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: details.isDischarging == true ? "minus.circle.fill" : "plus.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(BatteryTheme.orange)

                            Text(copy.chargeDirection(details.isDischarging))
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(BatteryTheme.orange)
                                .lineLimit(1)
                        }

                        Text(copy.normalVoltage)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(BatteryTheme.green)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(14)
    }

    private var capacityBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                InfoBlockTitle(icon: "battery.100", title: copy.capacityDetails, accent: BatteryTheme.blue)

                Spacer()
            }

            VStack(spacing: 8) {
                DetailLine(
                    title: copy.remaining,
                    value: BatteryFormatters.milliampHours(details.remainingCapacityMAh),
                    accent: BatteryTheme.green
                )
                DetailLine(
                    title: copy.currentFull,
                    value: BatteryFormatters.milliampHours(details.currentFullCapacityMAh),
                    accent: BatteryTheme.blue
                )
                DetailLine(
                    title: copy.designCapacity,
                    value: BatteryFormatters.milliampHours(details.designCapacityMAh),
                    accent: BatteryTheme.mutedText
                )
            }

            Text(copy.updatesWhileOpen)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(BatteryTheme.mutedText.opacity(0.78))
                .frame(maxWidth: .infinity)
        }
        .padding(14)
    }

    private var settingsContent: some View {
        VStack(spacing: 9) {
            settingsPreviewPanel
            languageSettingsPanel
            colorSettingsPanel
            notificationSettingsPanel
            settingsActionPanel
        }
    }

    private var settingsPreviewPanel: some View {
        HStack(spacing: 13) {
            CatMascotIcon(
                percent: snapshot.stateOfChargePercent,
                isCharging: snapshot.isCharging
            )
            .frame(width: 54, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(copy.settingsTitle)
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(BatteryTheme.lightText)
                    .lineLimit(1)

                Text(copy.settingsStatus)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(BatteryTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text("\(BatteryFormatters.percent(snapshot.stateOfChargePercent))%")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(chargeAccent)
                .lineLimit(1)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(BatteryTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BatteryTheme.stroke, lineWidth: 1)
        )
    }

    private var languageSettingsPanel: some View {
        SettingsPanel(icon: "globe", title: copy.languageSection, accent: BatteryTheme.blue) {
            Picker(copy.interfaceLanguage, selection: $languageRawValue) {
                ForEach(BattaryLanguage.allCases) { language in
                    Text(language.displayName)
                        .tag(language.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var colorSettingsPanel: some View {
        SettingsPanel(icon: "paintpalette.fill", title: copy.batteryColorsSection, accent: chargeAccent) {
            VStack(spacing: 10) {
                ForEach(BatteryColorRole.allCases) { role in
                    ColorSettingRow(
                        title: copy.title(for: role),
                        fallbackHex: role.defaultHex,
                        hex: colorHexBinding(for: role)
                    )
                }

                Divider()
                    .overlay(BatteryTheme.divider)

                Button {
                    resetBatteryColors()
                } label: {
                    Label(copy.resetColors, systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(BatteryTheme.mutedText)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var notificationSettingsPanel: some View {
        let canAddNotification = BattarySettings.nextNotificationThreshold(after: notificationThresholds) != nil

        return SettingsPanel(icon: "bell.badge.fill", title: copy.notificationsSection, accent: BatteryTheme.orange) {
            VStack(alignment: .leading, spacing: 12) {
                NotificationMasterToggle(
                    title: copy.lowBatteryAlerts,
                    subtitle: copy.notificationSummary(
                        thresholds: notificationThresholds,
                        isEnabled: notificationsEnabled
                    ),
                    isOn: $notificationsEnabled
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(copy.notificationThresholdsTitle)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(BatteryTheme.lightText)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(copy.notificationThresholdsRange)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(BatteryTheme.mutedText)
                            .lineLimit(1)
                    }

                    ForEach(Array(notificationThresholds.enumerated()), id: \.offset) { index, threshold in
                        NotificationThresholdRow(
                            title: "\(copy.notificationItemTitle) \(index + 1)",
                            subtitle: copy.notificationThresholdSubtitle(at: index, total: notificationThresholds.count),
                            threshold: thresholdBinding(at: index),
                            canRemove: notificationThresholds.count > 1,
                            removeTitle: copy.removeNotification
                        ) {
                            removeNotificationThreshold(at: index)
                        }
                    }

                    Button {
                        addNotificationThreshold()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 13, weight: .bold))

                            Text(copy.addNotification)
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            if !canAddNotification {
                                Text(copy.notificationLimitReached)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(BatteryTheme.mutedText)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(BatteryTheme.blue.opacity(canAddNotification ? 0.14 : 0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(BatteryTheme.blue.opacity(canAddNotification ? 0.32 : 0.10), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(canAddNotification ? BatteryTheme.blue : BatteryTheme.mutedText.opacity(0.65))
                    .disabled(!canAddNotification)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(BatteryTheme.stroke, lineWidth: 1)
                )
                .opacity(notificationsEnabled ? 1 : 0.45)
                .disabled(!notificationsEnabled)

                NotificationToggleRow(
                    icon: notificationSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    title: copy.notificationSound,
                    subtitle: notificationSoundEnabled ? copy.notificationSoundOn : copy.notificationSoundOff,
                    accent: notificationSoundEnabled ? BatteryTheme.blue : BatteryTheme.mutedText,
                    isOn: $notificationSoundEnabled
                )
                    .opacity(notificationsEnabled ? 1 : 0.45)
                    .disabled(!notificationsEnabled)

                NotificationPermissionRow(
                    title: copy.notificationPermissionTitle,
                    status: copy.notificationPermissionStatus(notificationAuthorizationStatus),
                    actionTitle: copy.notificationPermissionActionTitle(notificationAuthorizationStatus),
                    icon: notificationPermissionIcon,
                    accent: notificationPermissionAccent,
                    showsAction: !notificationPermissionIsGranted,
                    action: requestNotificationPermission
                )
                .opacity(notificationsEnabled ? 1 : 0.45)
                .disabled(!notificationsEnabled)
            }
        }
        .onAppear {
            refreshNotificationAuthorizationStatus()
        }
        .onChange(of: notificationsEnabled) { _ in
            monitor.applyNotificationSettings()
            refreshNotificationAuthorizationStatus()
        }
        .onChange(of: notificationThresholdsRaw) { _ in
            notificationThresholdsRaw = BattarySettings.notificationThresholdsRaw(from: notificationThresholds)
            monitor.applyNotificationSettings()
            refreshNotificationAuthorizationStatus()
        }
        .onChange(of: notificationSoundEnabled) { _ in
            monitor.applyNotificationSettings()
            refreshNotificationAuthorizationStatus()
        }
    }

    private var settingsActionPanel: some View {
        VStack(spacing: 0) {
            ActionRow(
                icon: "battery.100",
                title: copy.backToOverview,
                accent: BatteryTheme.blue
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedTab = .overview
                }
            }

            Divider().overlay(BatteryTheme.divider).padding(.leading, 42)

            ActionRow(
                icon: "slider.horizontal.3",
                title: copy.systemBatterySettings,
                accent: BatteryTheme.lightText
            ) {
                SystemLinks.openBatterySettings()
            }

            Divider().overlay(BatteryTheme.divider).padding(.leading, 42)

            ActionRow(
                icon: "power",
                title: copy.quit,
                accent: BatteryTheme.red
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(BatteryTheme.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BatteryTheme.stroke, lineWidth: 1)
        )
    }

    private func thresholdBinding(at index: Int) -> Binding<Int> {
        Binding(
            get: {
                let thresholds = notificationThresholds
                guard thresholds.indices.contains(index) else {
                    return BattarySettings.defaultNotificationThreshold
                }
                return thresholds[index]
            },
            set: { nextValue in
                var thresholds = notificationThresholds
                guard thresholds.indices.contains(index) else { return }
                thresholds[index] = BattarySettings.clampNotificationThreshold(nextValue)
                notificationThresholdsRaw = BattarySettings.notificationThresholdsRaw(from: thresholds)
            }
        )
    }

    private func addNotificationThreshold() {
        guard let nextThreshold = BattarySettings.nextNotificationThreshold(after: notificationThresholds) else {
            return
        }

        var thresholds = notificationThresholds
        thresholds.append(nextThreshold)
        notificationThresholdsRaw = BattarySettings.notificationThresholdsRaw(from: thresholds)
    }

    private func removeNotificationThreshold(at index: Int) {
        var thresholds = notificationThresholds
        guard thresholds.count > 1, thresholds.indices.contains(index) else { return }

        thresholds.remove(at: index)
        notificationThresholdsRaw = BattarySettings.notificationThresholdsRaw(from: thresholds)
    }

    private var notificationPermissionIsGranted: Bool {
        switch notificationAuthorizationStatus {
        case .authorized, .provisional:
            return true
        default:
            return false
        }
    }

    private var notificationPermissionIcon: String {
        switch notificationAuthorizationStatus {
        case .authorized, .provisional:
            return "checkmark.shield.fill"
        case .denied:
            return "exclamationmark.triangle.fill"
        case .notDetermined:
            return "shield.lefthalf.filled"
        case nil:
            return "shield"
        @unknown default:
            return "questionmark.shield.fill"
        }
    }

    private var notificationPermissionAccent: Color {
        switch notificationAuthorizationStatus {
        case .authorized, .provisional:
            return BatteryTheme.green
        case .denied:
            return BatteryTheme.red
        case .notDetermined:
            return BatteryTheme.orange
        case nil:
            return BatteryTheme.mutedText
        @unknown default:
            return BatteryTheme.orange
        }
    }

    private func requestNotificationPermission() {
        if notificationAuthorizationStatus == .denied {
            SystemLinks.openNotificationSettings()
        } else {
            monitor.applyNotificationSettings()
        }

        refreshNotificationAuthorizationStatus()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            refreshNotificationAuthorizationStatus()
        }
    }

    private func refreshNotificationAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                notificationAuthorizationStatus = settings.authorizationStatus
            }
        }
    }

    private func colorHexBinding(for role: BatteryColorRole) -> Binding<String> {
        switch role {
        case .healthy:
            return $healthyColorHex
        case .balanced:
            return $balancedColorHex
        case .low:
            return $lowColorHex
        case .critical:
            return $criticalColorHex
        case .charging:
            return $chargingColorHex
        }
    }

    private func resetBatteryColors() {
        healthyColorHex = BatteryColorRole.healthy.defaultHex
        balancedColorHex = BatteryColorRole.balanced.defaultHex
        lowColorHex = BatteryColorRole.low.defaultHex
        criticalColorHex = BatteryColorRole.critical.defaultHex
        chargingColorHex = BatteryColorRole.charging.defaultHex
    }

    private var sectionDivider: some View {
        Divider()
            .overlay(BatteryTheme.divider)
            .padding(.horizontal, 14)
    }

    private var healthBarProgress: Double {
        details.cycleSteppedProgress ?? Double(details.healthPercent ?? 0) / 100
    }
}

private enum PopoverTab {
    case overview
    case settings
}

private struct SettingsPanel<Content: View>: View {
    var icon: String
    var title: String
    var accent: Color
    @ViewBuilder var content: Content

    init(icon: String, title: String, accent: Color, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(BatteryTheme.lightText)
                    .lineLimit(1)

                Spacer()
            }

            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(BatteryTheme.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BatteryTheme.stroke, lineWidth: 1)
        )
    }
}

private struct NotificationMasterToggle: View {
    var title: String
    var subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BatteryTheme.orange.opacity(0.16))

                Image(systemName: isOn ? "bell.badge.fill" : "bell.slash.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(BatteryTheme.orange)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(BatteryTheme.lightText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(BatteryTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.065))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BatteryTheme.stroke, lineWidth: 1)
        )
    }
}

private struct NotificationToggleRow: View {
    var icon: String
    var title: String
    var subtitle: String
    var accent: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(BatteryTheme.lightText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(BatteryTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BatteryTheme.stroke, lineWidth: 1)
        )
    }
}

private struct NotificationPermissionRow: View {
    var title: String
    var status: String
    var actionTitle: String
    var icon: String
    var accent: Color
    var showsAction: Bool
    var action: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(BatteryTheme.lightText)
                    .lineLimit(1)

                Text(status)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if showsAction {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(
                            Capsule(style: .continuous)
                                .fill(BatteryTheme.blue.opacity(0.16))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(BatteryTheme.blue.opacity(0.32), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(BatteryTheme.blue)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(BatteryTheme.green)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BatteryTheme.stroke, lineWidth: 1)
        )
    }
}

private struct NotificationThresholdRow: View {
    var title: String
    var subtitle: String
    @Binding var threshold: Int
    var canRemove: Bool
    var removeTitle: String
    var remove: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(BatteryTheme.orange.opacity(0.16))

                    Image(systemName: "bell.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(BatteryTheme.orange)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(BatteryTheme.lightText)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(BatteryTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("\(threshold)%")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(BatteryTheme.orange)
                    .frame(width: 48, alignment: .trailing)

                Stepper("", value: $threshold, in: 5...50, step: 1)
                    .labelsHidden()
                    .frame(width: 52)

                if canRemove {
                    Button(action: remove) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(BatteryTheme.red)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(removeTitle)
                }
            }

            Slider(value: sliderValue, in: 5...50, step: 1)
                .tint(BatteryTheme.orange)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BatteryTheme.stroke, lineWidth: 1)
        )
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: {
                Double(threshold)
            },
            set: { nextValue in
                threshold = Int(nextValue.rounded())
            }
        )
    }
}

private struct ColorSettingRow: View {
    var title: String
    var fallbackHex: String
    @Binding var hex: String

    @State private var isExpanded = false

    private var normalizedHex: String {
        normalize(hex)
    }

    private var paletteHexes: [String] {
        var values = [normalize(fallbackHex)]
        values.append(contentsOf: Self.basePalette)
        return values.reduce(into: []) { uniqueValues, nextValue in
            if !uniqueValues.contains(nextValue) {
                uniqueValues.append(nextValue)
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(hex: normalizedHex, fallback: fallbackHex))
                        .frame(width: 30, height: 22)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                        )

                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(BatteryTheme.lightText)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(normalizedHex)
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(BatteryTheme.mutedText)
                        .lineLimit(1)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(BatteryTheme.mutedText)
                        .frame(width: 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                LazyVGrid(columns: swatchColumns, spacing: 8) {
                    ForEach(paletteHexes, id: \.self) { swatchHex in
                        Button {
                            hex = swatchHex
                            withAnimation(.easeInOut(duration: 0.16)) {
                                isExpanded = false
                            }
                        } label: {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(hex: swatchHex, fallback: fallbackHex))
                                .frame(width: 32, height: 24)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(
                                            swatchHex == normalizedHex ? BatteryTheme.lightText : Color.white.opacity(0.16),
                                            lineWidth: swatchHex == normalizedHex ? 2 : 1
                                        )
                                )
                                .overlay {
                                    if swatchHex == normalizedHex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .black))
                                            .foregroundStyle(BatteryTheme.lightText)
                                            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(BatteryTheme.stroke, lineWidth: 1)
                )
            }
        }
    }

    private var swatchColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(32), spacing: 8), count: 7)
    }

    private func normalize(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .uppercased()

        if cleaned.count == 6, Int(cleaned, radix: 16) != nil {
            return "#\(cleaned)"
        }

        return fallbackHex.uppercased()
    }

    private static let basePalette = [
        "#00B861", "#32D74B", "#A6E22E", "#C7DB33", "#FFD60A", "#FF9E2E", "#FF6B2E",
        "#FF454D", "#FF375F", "#BF5AF2", "#8E8DFF", "#5E5CE6", "#0D94FF", "#64D2FF",
        "#40C8E0", "#30D5C8", "#AC8E68", "#8E8E93", "#F2F2F7", "#1C1C1E", "#FFFFFF"
    ]
}

private struct BatteryPopoverCopy {
    var language: BattaryLanguage

    var overviewTab: String { language == .russian ? "Обзор" : "Overview" }
    var settingsTab: String { language == .russian ? "Настройки" : "Settings" }

    var awakeTime: String { language == .russian ? "Время работы" : "Awake Time" }
    var spentLastHour: String { language == .russian ? "За последний час" : "Spent Last Hour" }
    var averageDrain: String { language == .russian ? "Средний расход" : "Average Drain" }
    var chargingPower: String { language == .russian ? "Мощность зарядки" : "Charging Power" }
    var currentPower: String { language == .russian ? "Текущая мощность" : "Current Power" }

    var systemBatterySettings: String { language == .russian ? "Настройки батареи" : "Battery Settings" }
    var refresh: String { language == .russian ? "Обновить" : "Refresh" }
    var quit: String { language == .russian ? "Выйти из Better Battery" : "Quit Better Battery" }
    var batteryInformation: String { language == .russian ? "Информация о батарее" : "Battery Information" }

    var batteryHealth: String { language == .russian ? "Состояние батареи" : "Battery Health" }
    var cycleCount: String { language == .russian ? "Циклы" : "Cycle Count" }
    var temperature: String { language == .russian ? "Температура" : "Temperature" }
    var optimalPerformance: String { language == .russian ? "Оптимальная работа" : "Optimal performance" }
    var powerElectrical: String { language == .russian ? "Питание" : "Power & Electrical" }
    var powerUsage: String { language == .russian ? "Расход" : "Power Usage" }
    var current: String { language == .russian ? "Ток" : "Current" }
    var voltage: String { language == .russian ? "Напряжение" : "Voltage" }
    var normalVoltage: String { language == .russian ? "Норма" : "Normal voltage" }
    var capacityDetails: String { language == .russian ? "Емкость" : "Capacity Details" }
    var remaining: String { language == .russian ? "Осталось" : "Remaining" }
    var currentFull: String { language == .russian ? "Полная сейчас" : "Current Full" }
    var designCapacity: String { language == .russian ? "Проектная" : "Design Capacity" }
    var updatesWhileOpen: String { language == .russian ? "Обновляется, пока открыто" : "Updates while open" }

    var settingsTitle: String { language == .russian ? "Настройки" : "Settings" }
    var settingsStatus: String { AppMetadata.displayName }
    var languageSection: String { language == .russian ? "Язык" : "Language" }
    var interfaceLanguage: String { language == .russian ? "Язык интерфейса" : "Interface Language" }
    var batteryColorsSection: String { language == .russian ? "Цвета батарейки" : "Battery Colors" }
    var resetColors: String { language == .russian ? "Сбросить цвета" : "Reset Colors" }
    var notificationsSection: String { language == .russian ? "Уведомления" : "Notifications" }
    var lowBatteryAlerts: String { language == .russian ? "Предупреждать о низком заряде" : "Low battery alerts" }
    var warningAt: String { language == .russian ? "Предупреждать при" : "Warn at" }
    var notificationItemTitle: String { language == .russian ? "Порог" : "Alert" }
    var addNotification: String { language == .russian ? "Добавить уведомление" : "Add Alert" }
    var notificationLimitReached: String { language == .russian ? "Все пороги" : "All levels" }
    var removeNotification: String { language == .russian ? "Удалить уведомление" : "Remove Alert" }
    var notificationThresholdsTitle: String { language == .russian ? "Пороги срабатывания" : "Alert Levels" }
    var notificationThresholdsRange: String { language == .russian ? "5-50%" : "5-50%" }
    var notificationSound: String { language == .russian ? "Звук уведомления" : "Notification sound" }
    var notificationSoundOn: String { language == .russian ? "Со звуком" : "Sound on" }
    var notificationSoundOff: String { language == .russian ? "Без звука" : "Silent" }
    var notificationPermissionTitle: String { language == .russian ? "Системные уведомления" : "System Notifications" }
    var requestNotificationAccess: String { language == .russian ? "Разрешить уведомления" : "Allow Notifications" }
    var openNotificationSettings: String { language == .russian ? "Открыть" : "Open" }
    var backToOverview: String { language == .russian ? "Вернуться к обзору" : "Back to Overview" }

    func notificationSummary(thresholds: [Int], isEnabled: Bool) -> String {
        guard isEnabled else {
            return language == .russian ? "Выключены" : "Off"
        }

        let values = thresholds.map { "\($0)%" }.joined(separator: ", ")
        return language == .russian ? "Активны: \(values)" : "Active: \(values)"
    }

    func notificationThresholdSubtitle(at index: Int, total: Int) -> String {
        if language == .russian {
            if index == 0 { return "Первое предупреждение" }
            if index == total - 1 { return "Финальный порог" }
            return "Дополнительный порог"
        }

        if index == 0 { return "First warning" }
        if index == total - 1 { return "Final level" }
        return "Extra level"
    }

    func notificationPermissionActionTitle(_ status: UNAuthorizationStatus?) -> String {
        status == .denied ? openNotificationSettings : requestNotificationAccess
    }

    func notificationPermissionStatus(_ status: UNAuthorizationStatus?) -> String {
        switch status {
        case .authorized:
            return language == .russian ? "Разрешены" : "Allowed"
        case .provisional:
            return language == .russian ? "Разрешены тихо" : "Quietly allowed"
        case .denied:
            return language == .russian ? "Запрещены в macOS" : "Blocked in macOS"
        case .notDetermined:
            return language == .russian ? "Нужно разрешение" : "Permission needed"
        case nil:
            return language == .russian ? "Проверяем" : "Checking"
        @unknown default:
            return language == .russian ? "Неизвестный статус" : "Unknown status"
        }
    }

    func title(for role: BatteryColorRole) -> String {
        switch role {
        case .healthy:
            return language == .russian ? "Высокий заряд" : "Healthy"
        case .balanced:
            return language == .russian ? "Средний заряд" : "Balanced"
        case .low:
            return language == .russian ? "Низкий заряд" : "Low"
        case .critical:
            return language == .russian ? "Критический" : "Critical"
        case .charging:
            return language == .russian ? "Зарядка" : "Charging"
        }
    }

    func statusText(for snapshot: BatterySnapshot) -> String {
        switch language {
        case .russian:
            if snapshot.isFull { return "Заряжена" }
            if snapshot.isCharging { return snapshot.isFastCharging ? "Быстрая зарядка" : "Заряжается" }
            if snapshot.isOnBattery { return "От батареи" }
            if snapshot.powerSource == .powerAdapter { return "От адаптера" }
            return "Батарея"
        case .english:
            return snapshot.statusText()
        }
    }

    func timeTitle(for snapshot: BatterySnapshot) -> String {
        switch language {
        case .russian:
            return snapshot.isCharging ? "ДО ПОЛНОГО" : "ОСТАЛОСЬ"
        case .english:
            return snapshot.timeTitle()
        }
    }

    func rate(_ value: Double?) -> String {
        guard let value else { return language == .russian ? "Обучение" : "Learning" }
        return String(format: "%.1f%%/h", value)
    }

    func spent(_ value: Double?) -> String {
        guard let value else { return language == .russian ? "Обучение" : "Learning" }
        if value.rounded() == value {
            return String(format: "%.0f%%", value)
        }
        return String(format: "%.1f%%", value)
    }

    func healthStatus(_ value: Int?) -> String {
        guard let value else { return "--" }

        switch value {
        case 90...:
            return language == .russian ? "Хорошо" : "Good"
        case 80..<90:
            return language == .russian ? "Нормально" : "Fair"
        default:
            return language == .russian ? "Сервис" : "Service"
        }
    }

    func temperatureStatus(_ value: Double?) -> String {
        guard let value else { return "--" }

        switch value {
        case ..<10:
            return language == .russian ? "Прохладно" : "Cool"
        case 10..<38:
            return language == .russian ? "Норма" : "Normal"
        case 38..<45:
            return language == .russian ? "Тепло" : "Warm"
        default:
            return language == .russian ? "Горячо" : "Hot"
        }
    }

    func chargeDirection(_ isDischarging: Bool?) -> String {
        guard let isDischarging else { return "--" }

        if language == .russian {
            return isDischarging ? "Разряжается" : "Заряжается"
        }

        return isDischarging ? "Discharging" : "Charging"
    }
}

private struct GlassPopoverBackground: View {
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            BatteryTheme.background.opacity(0.72)
        }
    }
}

private struct DisclosurePanelHeader: View {
    var icon: String?
    var title: String
    var accent: Color
    var isExpanded: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 21)
                } else {
                    Color.clear
                        .frame(width: 21)
                }

                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(BatteryTheme.lightText)

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(BatteryTheme.mutedText)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
    }
}

private struct InfoBlockTitle: View {
    var icon: String
    var title: String
    var accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 21)

            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(BatteryTheme.lightText)
                .lineLimit(1)
        }
    }
}

private struct MetricStack: View {
    var title: String
    var value: String
    var trailingIcon: String?
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(BatteryTheme.mutedText)
                .lineLimit(1)

            HStack(spacing: 7) {
                if alignment == .trailing {
                    Spacer(minLength: 0)
                }

                Text(value)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(BatteryTheme.lightText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(BatteryTheme.orange)
                }
            }
        }
    }
}

private struct DetailLine: View {
    var title: String
    var value: String
    var accent: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(BatteryTheme.mutedText)
                .lineLimit(1)

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
        }
    }
}

private struct HealthProgressBar: View {
    var progress: Double

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fillWidth = clampedProgress > 0
                ? min(width, max(8, width * clampedProgress))
                : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))

                if fillWidth > 0 {
                    Capsule()
                        .fill(BatteryTheme.green)
                        .frame(width: fillWidth)
                }
            }
        }
    }
}

private struct ChargeProgressBar: View {
    var progress: Double
    var percent: Int?
    var isCharging: Bool

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var accent: Color {
        BatteryTheme.chargeColor(for: percent, isCharging: isCharging)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.72),
                                accent
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(10, width * clampedProgress))

                HStack(spacing: 0) {
                    Spacer()
                    tick
                    Spacer()
                    tick
                    Spacer()
                    tick
                    Spacer()
                }
            }
        }
    }

    private var tick: some View {
        Rectangle()
            .fill(Color.white.opacity(0.20))
            .frame(width: 1, height: 18)
    }
}

private struct StatRow: View {
    var icon: String
    var title: String
    var value: String
    var accent: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 22)

            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(BatteryTheme.lightText)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(BatteryTheme.mutedText)
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
    }
}

private struct ActionRow: View {
    var icon: String
    var title: String
    var accent: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(BatteryTheme.lightText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(BatteryTheme.mutedText)
            }
            .padding(.horizontal, 13)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private enum SystemLinks {
    static func openBatterySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Battery-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.energysaver"
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    static func openNotificationSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
