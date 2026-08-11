import Charts
import SwiftUI
import CodexMonitorContracts

struct MenuBarPopoverView: View {
    @ObservedObject var model: MonitorAppModel
    @ObservedObject var preferences: MonitorPreferences
    let actions: MonitorSurfaceActions

    var body: some View {
        let snapshot = model.snapshot
        GlassSurface(cornerRadius: 18, shadow: true, level: .floating) {
            VStack(alignment: .leading, spacing: 0) {
                // Block 1 — information only.
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(VisualStatePresentation.forSnapshot(snapshot).orbTone.color).frame(width: 8, height: 8).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(MonitorDisplayValue.state(snapshot)).font(.system(size: 17, weight: .semibold))
                        Text(MonitorDisplayValue.activity(snapshot)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(MonitorDisplayValue.update(snapshot)).font(.system(size: 11)).foregroundStyle(.tertiary).multilineTextAlignment(.trailing)
                }

                MonitorDivider().padding(.vertical, 14)

                // Block 2 — information only.
                VStack(alignment: .leading, spacing: 8) {
                    MonitorPopoverRow(label: L10n.tr("label.account"), value: MonitorDisplayValue.account(snapshot, hidden: preferences.hideAccountInfo))
                    MonitorPopoverRow(label: L10n.tr("label.plan"), value: MonitorDisplayValue.plan(snapshot))
                    MonitorPopoverRow(label: L10n.tr("label.quota"), value: MonitorDisplayValue.remainingQuota(snapshot))
                    MonitorPopoverRow(label: L10n.tr("label.resetCredit"), value: MonitorDisplayValue.reset(snapshot))
                }

                MonitorDivider().padding(.vertical, 14)

                // Block 3 — every row is one full-width native Button target.
                VStack(spacing: 4) {
                    if preferences.showUsageMenu { PopoverActionRow(title: L10n.tr("menu.usage"), symbol: "chart.bar", action: actions.showUsage) }
                    if preferences.showSettingsMenu { PopoverActionRow(title: L10n.tr("menu.settings"), symbol: "gearshape", action: actions.showSettings) }
                    PopoverActionRow(title: L10n.tr(preferences.showOrb ? "menu.hideFloating" : "menu.showFloating"), symbol: preferences.showOrb ? "eye.slash" : "eye", action: actions.toggleOrb)
                    PopoverActionRow(title: L10n.tr("menu.openCodex"), symbol: "arrow.up.right.square", action: actions.openCodex)
                    PopoverActionRow(title: L10n.tr("menu.quitMonitor"), symbol: "power", action: actions.quit)
                }
            }
            .padding(16)
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The shared affordance for Popover action rows. Information rows do not use
/// it and therefore never acquire hover or pressed treatment.
struct PopoverActionRow: View {
    let title: String
    let symbol: String
    var enabled = true
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 16).imageScale(.small)
                Text(title).font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: UIInteractionContract.minimumActionRowHeight, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: UIInteractionContract.actionRowCornerRadius, style: .continuous))
        }
        .buttonStyle(PopoverActionRowStyle(isHovered: hovered, enabled: enabled))
        .disabled(!enabled)
        .onHover { inside in hovered = enabled && inside }
        .accessibilityLabel(title)
        .accessibilityAddTraits(enabled ? [] : .isStaticText)
    }
}

private struct PopoverActionRowStyle: ButtonStyle {
    let isHovered: Bool
    let enabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        let state: PopoverActionVisualState = !enabled ? .disabled : (configuration.isPressed ? .pressed : (isHovered ? .hover : .rest))
        configuration.label
            .padding(.horizontal, 8)
            .foregroundStyle(enabled ? .primary : .secondary)
            .opacity(enabled ? 1 : 0.42)
            .background {
                RoundedRectangle(cornerRadius: UIInteractionContract.actionRowCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(PopoverActionFeedback.surfaceOpacity(for: state)))
            }
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

private struct MonitorPopoverRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .medium)).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct UsageWindowView: View {
    @ObservedObject var model: MonitorAppModel
    @ObservedObject var preferences: MonitorPreferences

    var body: some View {
        let snapshot = model.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                UsageFactSection(title: L10n.tr("label.account")) {
                    UsageFactRow(label: L10n.tr("label.account"), value: MonitorDisplayValue.account(snapshot, hidden: preferences.hideAccountInfo))
                    UsageFactRow(label: L10n.tr("label.plan"), value: MonitorDisplayValue.plan(snapshot))
                }
                UsageFactSection(title: L10n.tr("label.session")) {
                    UsageFactRow(label: L10n.tr("label.currentSession"), value: MonitorDisplayValue.taskTitle(snapshot))
                    UsageFactRow(label: L10n.tr("label.sessionToken"), value: MonitorDisplayValue.token(snapshot))
                }
                UsageFactSection(title: L10n.tr("label.resetCredit")) {
                    UsageFactRow(label: L10n.tr("label.resetCredit"), value: MonitorDisplayValue.reset(snapshot))
                    UsageFactRow(label: L10n.tr("label.reset"), value: resetTime(snapshot))
                }
                VStack(alignment: .leading, spacing: 12) {
                    MonitorSectionTitle(title: L10n.tr("label.tokenUsage"))
                    UsageMetricGrid(snapshot: snapshot)
                    UsageHistoryChart(snapshot: snapshot)
                }
            }
            .padding(18)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(minWidth: 500, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func resetTime(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        let windows = [snapshot?.quota.primary, snapshot?.quota.secondary]
        return UsagePresentation.resetTime(windows.compactMap { $0?.resetsAt }.min())
    }
}

private struct UsageFactSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitorSectionTitle(title: title)
            VStack(alignment: .leading, spacing: 8) { content }
                .padding(.vertical, 2)
        }
    }
}

private struct UsageFactRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value).font(.system(size: 13, weight: .medium)).multilineTextAlignment(.trailing).lineLimit(1)
        }
    }
}

private struct UsageMetricGrid: View {
    let snapshot: MonitorRuntimeSnapshot?
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0) {
            UsageMetric(title: L10n.tr("label.todayCost"), value: "$--")
            UsageMetric(title: L10n.tr("label.last30DaysCost"), value: "$--")
            UsageMetric(title: L10n.tr("label.todayToken"), value: MonitorDisplayValue.todayUsage(snapshot))
            UsageMetric(title: L10n.tr("label.last30DaysToken"), value: MonitorDisplayValue.last30DaysUsage(snapshot))
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct UsageMetric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 20, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(.horizontal, 15)
        .overlay(alignment: .trailing) { Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1) }
    }
}

private struct UsageHistoryChart: View {
    let snapshot: MonitorRuntimeSnapshot?
    @State private var selectedBucket: AccountUsageDailyBucket?

    var body: some View {
        let buckets = snapshot?.usage.availability == .available ? snapshot?.usage.usage?.dailyBuckets : nil
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("label.last30CalendarDays")).font(.system(size: 13, weight: .medium))
            if let buckets {
                interactiveChart(buckets)
            } else {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<30, id: \.self) { _ in Capsule().fill(Color.secondary.opacity(0.16)).frame(maxWidth: .infinity).frame(height: 3) }
                }
                .frame(height: 22, alignment: .bottom)
                Text(L10n.tr("usage.historyUnavailable")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(buckets == nil ? L10n.tr("usage.historyUnavailable") : L10n.tr("label.last30CalendarDays"))
    }

    @ViewBuilder
    private func interactiveChart(_ buckets: [AccountUsageDailyBucket]) -> some View {
        Chart(buckets) { bucket in
            BarMark(
                x: .value("Date", bucket.startDate),
                y: .value("Token", bucket.tokens)
            )
            .foregroundStyle(Color.accentColor.opacity(selectedBucket?.id == bucket.id ? 0.92 : 0.58))
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let plotX = location.x
                            let selected: AccountUsageDailyBucket?
                            if let date: String = proxy.value(atX: plotX, as: String.self),
                               let exact = buckets.first(where: { $0.startDate == date }) {
                                selected = exact
                            } else {
                                selected = UsagePresentation.bucket(closestTo: plotX, plotWidth: geometry.size.width, buckets: buckets)
                            }
                            if selectedBucket?.id != selected?.id, let selected {
                                DiagnosticEvent.record(.usageChart, ["event": "bucketSelected", "bucket": selected.startDate, "tokens": String(selected.tokens)])
                            }
                            selectedBucket = selected
                        case .ended:
                            selectedBucket = nil
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if let selectedBucket {
                            let desired = CGPoint(x: UsagePresentation.tooltipOffset(for: selectedBucket, buckets: buckets, width: geometry.size.width), y: 8)
                            let frame = UsagePresentation.tooltipFrame(
                                desiredOrigin: desired,
                                tooltipSize: CGSize(width: 132, height: 62),
                                bounds: CGRect(origin: .zero, size: geometry.size)
                            )
                            UsageChartTooltip(bucket: selectedBucket)
                                .frame(width: 132)
                                .offset(x: frame.minX, y: frame.minY)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .frame(height: 164)
        HStack {
            Text(UsagePresentation.axisDate(buckets.first?.startDate))
            Spacer()
            Text(UsagePresentation.axisDate(buckets.last?.startDate))
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        Text(L10n.tr("usage.hoverHint"))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }
}

private struct UsageChartTooltip: View {
    let bucket: AccountUsageDailyBucket
    var body: some View {
        Text(UsagePresentation.tooltip(for: bucket))
            .font(.system(size: 11, weight: .medium))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .fixedSize()
    }
}

enum UsagePresentation {
    /// A reset date before modern Codex account service dates is a decoded
    /// epoch/default value, not user-facing reset information.
    private static let earliestValidReset = Date(timeIntervalSince1970: 1_577_836_800) // 2020-01-01 UTC

    static func resetTime(_ date: Date?, languageCode: String? = nil) -> String {
        guard let date, date >= earliestValidReset else {
            return L10n.tr("value.unavailable", languageCode: languageCode)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func tooltip(for bucket: AccountUsageDailyBucket, languageCode: String? = nil) -> String {
        String(
            format: L10n.tr("usage.tooltip", languageCode: languageCode),
            displayDate(bucket.startDate, languageCode: languageCode),
            MonitorDisplayValue.tokenFormat(Int64(bucket.tokens))
        )
    }

    static func bucket(closestTo x: CGFloat, plotWidth: CGFloat, buckets: [AccountUsageDailyBucket]) -> AccountUsageDailyBucket? {
        guard !buckets.isEmpty, plotWidth > 0 else { return nil }
        let progress = min(max(x / plotWidth, 0), 0.999_999)
        return buckets[min(Int(progress * CGFloat(buckets.count)), buckets.count - 1)]
    }

    static func tooltipOffset(for bucket: AccountUsageDailyBucket, buckets: [AccountUsageDailyBucket], width: CGFloat) -> CGFloat {
        guard let index = buckets.firstIndex(where: { $0.id == bucket.id }) else { return 0 }
        let point = (CGFloat(index) + 0.5) / CGFloat(max(1, buckets.count)) * width
        return min(max(point - 62, 0), max(0, width - 124))
    }

    static func tooltipFrame(desiredOrigin: CGPoint, tooltipSize: CGSize, bounds: CGRect, padding: CGFloat = 6) -> CGRect {
        let x = min(max(desiredOrigin.x, bounds.minX + padding), bounds.maxX - tooltipSize.width - padding)
        let y = min(max(desiredOrigin.y, bounds.minY + padding), bounds.maxY - tooltipSize.height - padding)
        return CGRect(origin: CGPoint(x: x, y: y), size: tooltipSize)
    }

    static func axisDate(_ raw: String?, languageCode: String? = nil) -> String {
        guard let raw else { return L10n.unavailable }
        return displayDate(raw, languageCode: languageCode)
    }

    private static func displayDate(_ raw: String, languageCode: String?) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: raw) else { return raw }
        return date.formatted(
            .dateTime.year().month(.abbreviated).day().locale(Locale(identifier: languageCode ?? L10n.resolvedLanguage))
        )
    }
}

enum SettingsSection: CaseIterable, Identifiable {
    case general, floating, notifications, privacy, advanced, about
    var id: Self { self }
    var title: String {
        switch self {
        case .general: L10n.tr("settings.general")
        case .floating: L10n.tr("settings.floating")
        case .notifications: L10n.tr("settings.notifications")
        case .privacy: L10n.tr("settings.privacy")
        case .advanced: L10n.tr("settings.advanced")
        case .about: L10n.tr("settings.about")
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .floating: "circle.dotted"
        case .notifications: "bell"
        case .privacy: "hand.raised"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }
    static let defaultSection: SettingsSection = .floating
}

@MainActor
final class SettingsPresentationModel: ObservableObject {
    @Published var selection: SettingsSection = .defaultSection
}

struct SettingsSystemActions {
    let refresh: () -> Void
    let openCodex: () -> Void
    let openLogsFolder: () -> Void
    let setMonitoringPaused: (Bool) -> Void
    let requestNotificationPermission: (NotificationPreference) -> Void
    let exportDiagnostics: () -> Void
    let loginItem: LoginItemController
    let showDiagnostics: () -> Void
}

struct NativeSettingsWindowView: View {
    @ObservedObject var preferences: MonitorPreferences
    @ObservedObject var presentation: SettingsPresentationModel
    let actions: SettingsSystemActions

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $presentation.selection) {
                ForEach(SettingsSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol).tag(section)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180, idealWidth: 200, maxWidth: 220)

            Divider()

            settingsDetail(for: presentation.selection)
                .id(presentation.selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 600, minHeight: 420)
    }

    @ViewBuilder
    private func settingsDetail(for section: SettingsSection) -> some View {
        switch section {
        case .general:
            GeneralSettingsDetail(preferences: preferences, actions: actions)
        case .floating:
            FloatingSettingsDetail(preferences: preferences)
        case .notifications:
            NotificationSettingsDetail(preferences: preferences, actions: actions)
        case .privacy:
            PrivacySettingsDetail(preferences: preferences)
        case .advanced:
            AdvancedSettingsDetail(actions: actions)
        case .about:
            AboutSettingsDetail()
        }
    }
}

private struct SettingsDetail<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title).font(.system(size: 15, weight: .semibold))
                VStack(spacing: 0) { content }
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control
    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .layoutPriority(1)
            Spacer(minLength: 16)
            control
                .frame(width: 220, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
    }
}

private struct GeneralSettingsDetail: View {
    @ObservedObject var preferences: MonitorPreferences
    let actions: SettingsSystemActions
    @State private var launchAtLoginError: String?

    var body: some View {
        SettingsDetail(title: L10n.tr("settings.general")) {
            SettingsRow(title: L10n.tr("settings.language")) {
                Picker(L10n.tr("settings.language"), selection: $preferences.interfaceLanguage) {
                    Text(L10n.tr("settings.followSystem")).tag(InterfaceLanguage.system)
                    Text(L10n.tr("settings.simplifiedChinese")).tag(InterfaceLanguage.simplifiedChinese)
                    Text(L10n.tr("settings.english")).tag(InterfaceLanguage.english)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            SettingsRow(title: L10n.tr("settings.launchAtLogin")) {
                Toggle(L10n.tr("settings.launchAtLogin"), isOn: Binding(
                    get: { actions.loginItem.isEnabled },
                    set: { enabled in
                        do { try actions.loginItem.setEnabled(enabled) }
                        catch { actions.loginItem.reconcile(); launchAtLoginError = error.localizedDescription }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
        .alert(L10n.tr("settings.launchAtLogin"), isPresented: Binding(get: { launchAtLoginError != nil }, set: { if !$0 { launchAtLoginError = nil } })) {
            Button("OK", role: .cancel) { launchAtLoginError = nil }
        } message: { Text(launchAtLoginError ?? "") }
    }
}

private struct FloatingSettingsDetail: View {
    @ObservedObject var preferences: MonitorPreferences
    var body: some View {
        SettingsDetail(title: L10n.tr("settings.floating")) {
            SettingsRow(title: L10n.tr("settings.showFloating")) { Toggle("", isOn: $preferences.showOrb).labelsHidden().toggleStyle(.switch) }
            SettingsRow(title: L10n.tr("settings.alwaysOnTop")) { Toggle("", isOn: $preferences.alwaysOnTop).labelsHidden().toggleStyle(.switch) }
            SettingsRow(title: L10n.tr("settings.lockPosition")) { Toggle("", isOn: $preferences.lockPosition).labelsHidden().toggleStyle(.switch) }
            SettingsRow(title: L10n.tr("settings.floatingSize")) {
                HStack(spacing: 10) {
                    Slider(value: $preferences.orbSize, in: 72...180, step: 1)
                    Text("\(Int(preferences.orbSize)) pt").foregroundStyle(.secondary).monospacedDigit().frame(width: 48, alignment: .trailing)
                }
            }
            SettingsRow(title: L10n.tr("settings.showUsageMenu")) { Toggle("", isOn: $preferences.showUsageMenu).labelsHidden().toggleStyle(.switch) }
            SettingsRow(title: L10n.tr("settings.showSettingsMenu")) { Toggle("", isOn: $preferences.showSettingsMenu).labelsHidden().toggleStyle(.switch) }
        }
        .onAppear { DiagnosticEvent.record(.settings, ["event": "floatingPresented", "slider": "nativeSingleTrack", "customSliderDecoration": "false"]) }
    }
}

private struct NotificationSettingsDetail: View {
    @ObservedObject var preferences: MonitorPreferences
    let actions: SettingsSystemActions
    var body: some View {
        SettingsDetail(title: L10n.tr("settings.notifications")) {
            SettingsRow(title: L10n.tr("settings.pauseMonitoring")) {
                Toggle("", isOn: Binding(get: { preferences.pauseMonitoring }, set: { preferences.pauseMonitoring = $0; actions.setMonitoringPaused($0) }))
                    .labelsHidden().toggleStyle(.switch)
            }
            SettingsRow(title: L10n.tr("settings.waitingApprovalNotification")) {
                Toggle("", isOn: notificationBinding(.waitingApproval, preferences: preferences, actions: actions))
                    .labelsHidden().toggleStyle(.switch)
            }
            SettingsRow(title: L10n.tr("settings.taskCompletedNotification")) {
                Toggle("", isOn: notificationBinding(.taskCompleted, preferences: preferences, actions: actions))
                    .labelsHidden().toggleStyle(.switch)
            }
        }
    }

    private func notificationBinding(_ preference: NotificationPreference, preferences: MonitorPreferences, actions: SettingsSystemActions) -> Binding<Bool> {
        Binding(
            get: { preference == .waitingApproval ? preferences.waitingApprovalNotifications : preferences.taskCompletedNotifications },
            set: { enabled in
                if !enabled {
                    if preference == .waitingApproval { preferences.waitingApprovalNotifications = false }
                    else { preferences.taskCompletedNotifications = false }
                } else {
                    actions.requestNotificationPermission(preference)
                }
            }
        )
    }
}

private struct PrivacySettingsDetail: View {
    @ObservedObject var preferences: MonitorPreferences
    var body: some View {
        SettingsDetail(title: L10n.tr("settings.privacy")) {
            SettingsRow(title: L10n.tr("settings.hideAccountInfo")) { Toggle("", isOn: $preferences.hideAccountInfo).labelsHidden().toggleStyle(.switch) }
        }
    }
}

private struct AdvancedSettingsDetail: View {
    let actions: SettingsSystemActions
    var body: some View {
        SettingsDetail(title: L10n.tr("settings.advanced")) {
            SettingsRow(title: L10n.tr("settings.refresh")) { Button(L10n.tr("settings.refresh"), action: actions.refresh).buttonStyle(.bordered) }
            SettingsRow(title: L10n.tr("settings.openCodex")) { Button(L10n.tr("settings.openCodex"), action: actions.openCodex).buttonStyle(.bordered) }
            SettingsRow(title: L10n.tr("settings.openLogsFolder")) { Button(L10n.tr("settings.openLogsFolder"), action: actions.openLogsFolder).buttonStyle(.bordered) }
            SettingsRow(title: L10n.tr("settings.openDiagnostics")) { Button(L10n.tr("settings.openDiagnostics"), action: actions.showDiagnostics).buttonStyle(.bordered) }
#if DEBUG
            SettingsRow(title: L10n.tr("settings.exportDiagnostics")) { Button(L10n.tr("settings.exportDiagnostics"), action: actions.exportDiagnostics).buttonStyle(.bordered) }
#endif
        }
    }
}

private struct AboutSettingsDetail: View {
    var body: some View {
        SettingsDetail(title: L10n.tr("settings.about")) {
            SettingsRow(title: L10n.tr("settings.productName")) { Text("Codex Monitor").foregroundStyle(.secondary) }
            SettingsRow(title: L10n.tr("settings.version")) { Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0").foregroundStyle(.secondary).monospacedDigit() }
            SettingsRow(title: L10n.tr("settings.build")) { Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev").foregroundStyle(.secondary).monospacedDigit() }
        }
    }
}

struct DiagnosticsWindowView: View {
    @ObservedObject var model: MonitorAppModel
    var body: some View {
        let snapshot = model.snapshot
        Form {
            Section(L10n.tr("diagnostics.runtime")) {
                LabeledContent(L10n.tr("diagnostics.state"), value: MonitorDisplayValue.state(snapshot))
                LabeledContent(L10n.tr("label.session"), value: MonitorDisplayValue.taskTitle(snapshot))
            }
            Section(L10n.tr("diagnostics.sourceHealth")) {
                ForEach(MonitorRuntimeSource.allCases, id: \.rawValue) { source in
                    LabeledContent(MonitorDisplayValue.source(source), value: MonitorDisplayValue.availability(snapshot?.sourceHealth[source]?.availability))
                }
            }
            Section(L10n.tr("diagnostics.capabilities")) {
                ForEach(MonitorRuntimeCapability.allCases, id: \.rawValue) { capability in
                    LabeledContent(MonitorDisplayValue.capability(capability), value: MonitorDisplayValue.availability(snapshot?.capabilities[capability]?.availability))
                }
            }
        }
        .formStyle(.grouped)
        .padding(14)
        .frame(minWidth: 460, minHeight: 400)
    }
}
