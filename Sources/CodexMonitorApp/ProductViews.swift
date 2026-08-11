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
                    Circle().fill(MonitorVisualPalette.forSnapshot(snapshot).tint).frame(width: 8, height: 8).padding(.top, 5)
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
                    MonitorPopoverRow(label: L10n.tr("label.account"), value: MonitorDisplayValue.account(snapshot))
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

    var body: some View {
        let snapshot = model.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                UsageFactSection(title: L10n.tr("label.account")) {
                    UsageFactRow(label: L10n.tr("label.account"), value: MonitorDisplayValue.account(snapshot))
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
    var body: some View {
        let buckets = snapshot?.usage.availability == .available ? snapshot?.usage.usage?.dailyBuckets : nil
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("label.last30CalendarDays")).font(.system(size: 13, weight: .medium))
            if let buckets {
                let peak = max(1, buckets.map(\.tokens).max() ?? 0)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(buckets) { bucket in
                        UsageDayBar(bucket: bucket, peak: peak)
                    }
                }
                .frame(height: 22, alignment: .bottom)
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
}

private struct UsageDayBar: View {
    let bucket: AccountUsageDailyBucket
    let peak: Int
    @State private var hovered = false

    var body: some View {
        Capsule()
            .fill(Color.accentColor.opacity(hovered ? 0.88 : 0.58))
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(hovered ? 0.58 : 0), lineWidth: 0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: max(3, CGFloat(bucket.tokens) / CGFloat(peak) * 22))
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .help(UsagePresentation.tooltip(for: bucket))
            .accessibilityLabel(UsagePresentation.tooltip(for: bucket))
            .animation(.easeInOut(duration: 0.14), value: hovered)
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

    private static func displayDate(_ raw: String, languageCode: String?) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: raw) else { return raw }
        return date.formatted(
            .dateTime.year().month(.abbreviated).day().locale(Locale(identifier: languageCode ?? Locale.preferredLanguages.first ?? "en"))
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

struct NativeSettingsWindowView: View {
    @ObservedObject var preferences: MonitorPreferences
    @ObservedObject var presentation: SettingsPresentationModel
    let showDiagnostics: () -> Void

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
            UnavailableSettingsDetail(title: section.title, message: L10n.tr("settings.noneGeneral"))
        case .floating:
            FloatingSettingsDetail(preferences: preferences)
        case .notifications:
            UnavailableSettingsDetail(title: section.title, message: L10n.tr("settings.noneNotifications"))
        case .privacy:
            UnavailableSettingsDetail(title: section.title, message: L10n.tr("settings.nonePrivacy"))
        case .advanced:
            AdvancedSettingsDetail(showDiagnostics: showDiagnostics)
        case .about:
            AboutSettingsDetail()
        }
    }
}

private struct FloatingSettingsDetail: View {
    @ObservedObject var preferences: MonitorPreferences
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.tr("settings.floating")).font(.system(size: 15, weight: .semibold))
            // Deliberately not a Form: its grouped style inserts an orphan
            // separator beneath Slider in a system Settings scene.
            VStack(alignment: .leading, spacing: 16) {
                Toggle(L10n.tr("settings.showFloating"), isOn: $preferences.showOrb).toggleStyle(.switch)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.tr("settings.floatingSize"))
                        Spacer()
                        Text("\(Int(preferences.orbSize)) pt").foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $preferences.orbSize, in: 72...180, step: 1)
                }
                Toggle(L10n.tr("settings.showUsageMenu"), isOn: $preferences.showUsageMenu).toggleStyle(.switch)
                Toggle(L10n.tr("settings.showSettingsMenu"), isOn: $preferences.showSettingsMenu).toggleStyle(.switch)
            }
        }
        .padding(20)
    }
}

private struct UnavailableSettingsDetail: View {
    let title: String
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(message).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }
}

private struct AdvancedSettingsDetail: View {
    let showDiagnostics: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("settings.advanced")).font(.system(size: 15, weight: .semibold))
            Text(L10n.tr("settings.advancedDescription")).font(.system(size: 13)).foregroundStyle(.secondary)
            Button(L10n.tr("settings.openDiagnostics"), action: showDiagnostics).buttonStyle(.bordered)
        }
        .padding(20)
    }
}

private struct AboutSettingsDetail: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("settings.about")).font(.system(size: 15, weight: .semibold))
            Text("Codex Monitor\n\(L10n.tr("about.description"))").font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(20)
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
