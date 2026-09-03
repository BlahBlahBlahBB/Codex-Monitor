import Charts
import AppKit
import SwiftUI
import CodexMonitorContracts

struct MenuBarPopoverView: View {
    @ObservedObject var model: MonitorAppModel
    @ObservedObject var preferences: MonitorPreferences
    let actions: MonitorSurfaceActions
    /// When native NSPopover chrome cannot fit the measured contents above or
    /// below a status item, only this interior scrolls. The popover itself is
    /// still positioned exclusively by AppKit.
    var maximumContentHeight: CGFloat?

    var body: some View {
        let snapshot = model.snapshot
        let presentation = model.presentation(using: preferences)
        Group {
            if let maximumContentHeight {
                ScrollView {
                    contents(snapshot: snapshot, presentation: presentation)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(width: 340, height: maximumContentHeight, alignment: .topLeading)
            } else {
                contents(snapshot: snapshot, presentation: presentation)
                    .padding(16)
                    .frame(width: 340)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func contents(snapshot: MonitorRuntimeSnapshot?, presentation: VisualStatePresentation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
                // Block 1 — information only.
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(presentation.orbTone.color).frame(width: 8, height: 8).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(MonitorDisplayValue.state(presentation))
                            .font(.system(size: 16, weight: .semibold))
                            .tracking(-0.1)
                        Text(MonitorDisplayValue.activity(snapshot))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(MonitorDisplayValue.update(snapshot))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.trailing)
                }

                MonitorDivider().padding(.vertical, 12)

                // Block 2 — information only.
                VStack(alignment: .leading, spacing: 9) {
                    MonitorPopoverRow(label: L10n.tr("label.account"), value: MonitorDisplayValue.account(snapshot, hidden: preferences.hideAccountInfo))
                    MonitorPopoverRow(label: L10n.tr("label.plan"), value: MonitorDisplayValue.plan(snapshot))
                    ForEach(QuotaWindowPresentation.windows(from: snapshot)) { window in
                        MonitorPopoverRow(label: window.quotaRowLabel, value: window.remainingText)
                        MonitorPopoverRow(label: window.resetRowLabel, value: window.resetDateTime())
                    }
                    MonitorPopoverRow(label: L10n.tr("label.resetCredit"), value: MonitorDisplayValue.reset(snapshot))
                    if let quotaNotice = quotaNotice(snapshot) {
                        Text(quotaNotice)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(QuotaCapsuleHealth.resolve(snapshot: snapshot, warningEnabled: preferences.quotaWarningEnabled, threshold: preferences.quotaWarningThreshold) == .exhausted ? VisualStateTone.red.color : VisualStateTone.yellow.color)
                    }
                }

                MonitorDivider().padding(.vertical, 12)

                // Block 3 — every row is one full-width native Button target.
                VStack(spacing: 2) {
                    if preferences.showUsageMenu { PopoverActionRow(title: L10n.tr("menu.usage"), symbol: "chart.bar", action: actions.showUsage) }
                    if preferences.showSettingsMenu { PopoverActionRow(title: L10n.tr("menu.settings"), symbol: "gearshape", action: actions.showSettings) }
                    PopoverActionRow(title: L10n.tr(preferences.showOrb ? "menu.hideFloating" : "menu.showFloating"), symbol: preferences.showOrb ? "eye.slash" : "eye", action: actions.toggleOrb)
                    PopoverActionRow(title: L10n.tr("menu.openCodex"), symbol: "arrow.up.right.square", action: actions.openCodex)
                    PopoverActionRow(title: L10n.tr("menu.quitMonitor"), symbol: "power", action: actions.quit)
                }
        }
    }

    private func quotaNotice(_ snapshot: MonitorRuntimeSnapshot?) -> String? {
        switch QuotaCapsuleHealth.resolve(snapshot: snapshot, warningEnabled: preferences.quotaWarningEnabled, threshold: preferences.quotaWarningThreshold) {
        case .warning:
            return String(format: L10n.tr("quota.warningActive"), MonitorDisplayValue.remainingQuota(snapshot))
        case .exhausted:
            return L10n.tr("quota.exhausted")
        case .sufficient, .unknown:
            return nil
        }
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
                Image(systemName: symbol)
                    .frame(width: 18)
                    .font(.system(size: 12.5, weight: .medium))
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                Text(title).font(.system(size: 13, weight: .medium))
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
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .frame(minWidth: 104, alignment: .trailing)
                .lineLimit(1)
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
            VStack(alignment: .leading, spacing: 18) {
                UsageFactSection(title: L10n.tr("label.account")) {
                    UsageFactRow(label: L10n.tr("label.account"), value: MonitorDisplayValue.account(snapshot, hidden: preferences.hideAccountInfo))
                    UsageFactRow(label: L10n.tr("label.plan"), value: MonitorDisplayValue.plan(snapshot))
                }
                UsageFactSection(title: L10n.tr("label.session")) {
                    UsageFactRow(label: L10n.tr("label.currentSession"), value: MonitorDisplayValue.sessionInfo(snapshot))
                    UsageFactRow(label: L10n.tr("label.sessionToken"), value: MonitorDisplayValue.token(snapshot))
                }
                UsageFactSection(title: L10n.tr("label.resetCredit")) {
                    UsageFactRow(label: L10n.tr("label.resetCredit"), value: MonitorDisplayValue.reset(snapshot))
                    UsageFactRow(label: L10n.tr("label.reset"), value: resetTime(snapshot))
                }
                VStack(alignment: .leading, spacing: 12) {
                    MonitorSectionTitle(title: L10n.tr("label.tokenUsage"))
                    UsageMetricGrid(snapshot: snapshot, localUsage: model.localUsage)
                    UsageHistoryChart(snapshot: snapshot, localUsage: model.localUsage)
                }
            }
            .padding(20)
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
            VStack(alignment: .leading, spacing: 7) { content }
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
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .frame(minHeight: 20, alignment: .center)
    }
}

private struct UsageMetricGrid: View {
    let snapshot: MonitorRuntimeSnapshot?
    let localUsage: LocalUsageLedgerSnapshot?
    var body: some View {
        let hybrid = HybridUsageComposer.compose(
            accountDailyBuckets: snapshot?.usage.usage?.dailyBuckets,
            accountAvailability: snapshot?.usage.availability ?? .unknown,
            localLedger: localUsage
        )
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0) {
            UsageMetric(title: L10n.tr("label.todayCost"), value: LocalUsagePresentation.estimatedCost(localUsage?.today?.estimatedCostUSD))
            // A partial local 30-day cost cannot truthfully occupy the
            // account-scoped 30-day cost slot.
            UsageMetric(title: L10n.tr("label.last30DaysCost"), value: LocalUsagePresentation.estimatedCost(hybrid?.headlineEstimatedCostUSD))
            UsageMetric(title: L10n.tr("label.todayToken"), value: localUsage?.today.map { MonitorDisplayValue.summaryTokenFormat($0.totalTokens) } ?? "--")
            UsageMetric(title: L10n.tr("label.last30DaysToken"), value: hybrid?.headlineTokens.map { MonitorDisplayValue.summaryTokenFormat($0) } ?? "--")
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.20), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        }
    }
}

private struct UsageMetric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .padding(.horizontal, 14)
        .overlay(alignment: .trailing) { Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.30)).frame(width: 0.5) }
    }
}

private struct UsageHistoryChart: View {
    let snapshot: MonitorRuntimeSnapshot?
    let localUsage: LocalUsageLedgerSnapshot?
    @State private var selectedBucket: HybridUsageDay?

    var body: some View {
        let buckets = HybridUsageComposer.compose(
            accountDailyBuckets: snapshot?.usage.usage?.dailyBuckets,
            accountAvailability: snapshot?.usage.availability ?? .unknown,
            localLedger: localUsage
        )?.days
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("label.last30CalendarDays"))
                .font(.system(size: 13, weight: .medium))
            if let buckets {
                interactiveChart(buckets)
                UsageModelBreakdown(day: localDay(for: selectedBucket ?? buckets.last))
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

    private func localDay(for selected: HybridUsageDay?) -> LocalUsageDay? {
        guard let selected,
              localUsage?.availability == .available,
              let local = localUsage?.day(named: selected.dateKey),
              !local.models.isEmpty else { return nil }
        return local
    }

    @ViewBuilder
    private func interactiveChart(_ buckets: [HybridUsageDay]) -> some View {
        Chart(buckets) { bucket in
            BarMark(
                x: .value("Date", bucket.dateKey),
                y: .value("Token", bucket.chartTokens)
            )
            .foregroundStyle(chartColor(for: bucket))
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                }
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
                            let selected: HybridUsageDay?
                            if let date: String = proxy.value(atX: plotX, as: String.self),
                               let exact = buckets.first(where: { $0.dateKey == date }) {
                                selected = exact
                            } else {
                                selected = UsagePresentation.bucket(closestTo: plotX, plotWidth: geometry.size.width, buckets: buckets)
                            }
                            if selectedBucket?.id != selected?.id, let selected {
                                DiagnosticEvent.record(.usageChart, ["event": "bucketSelected", "bucket": selected.dateKey, "tokens": String(selected.chartTokens), "provenance": selected.provenance.rawValue])
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
                                tooltipSize: UsagePresentation.tooltipSize,
                                bounds: CGRect(origin: .zero, size: geometry.size)
                            )
                            UsageChartTooltip(bucket: selectedBucket)
                                .frame(width: UsagePresentation.tooltipSize.width, height: UsagePresentation.tooltipSize.height, alignment: .leading)
                                .offset(x: frame.minX, y: frame.minY)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .frame(height: 164)
        HStack {
            Text(UsagePresentation.axisDate(buckets.first?.dateKey))
            Spacer()
            Text(UsagePresentation.axisDate(buckets.last?.dateKey))
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        Text(L10n.tr("usage.hoverHint"))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    private func chartColor(for bucket: HybridUsageDay) -> Color {
        switch bucket.provenance {
        case .authoritativeAccount:
            return Color.accentColor.opacity(selectedBucket?.id == bucket.id ? 0.92 : 0.58)
        case .localRealtimeProvisional:
            return Color.accentColor.opacity(selectedBucket?.id == bucket.id ? 0.74 : 0.42)
        case .sourceAbsent:
            return Color.secondary.opacity(0.16)
        }
    }
}

private struct UsageChartTooltip: View {
    let bucket: HybridUsageDay
    var body: some View {
        Text(HybridUsagePresentation.tooltip(for: bucket))
            .font(.system(size: 11, weight: .medium))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.46), lineWidth: 0.5))
            .lineLimit(3)
    }
}

private struct UsageModelBreakdown: View {
    let day: LocalUsageDay?
    var body: some View {
        guard let day else {
            return AnyView(Text(L10n.tr("usage.noLocalModelAttribution"))
                .font(.system(size: 12)).foregroundStyle(.secondary))
        }
        return AnyView(VStack(alignment: .leading, spacing: 7) {
            Text(L10n.tr("usage.modelBreakdown"))
                .font(.system(size: 13, weight: .medium))
            Text(L10n.tr("usage.localAttribution"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if day.models.isEmpty {
                Text(L10n.tr("usage.historyUnavailable")).font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ForEach(day.models) { model in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(model.displayName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(MonitorDisplayValue.summaryTokenFormat(model.totalTokens)).font(.system(size: 12)).monospacedDigit()
                        Text(LocalUsagePresentation.estimatedCost(model.estimatedCostUSD)).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            Text(L10n.tr("usage.estimateNote"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        })
    }
}

enum LocalUsagePresentation {
    static func estimatedCost(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return String(format: "≈$%.2f", value)
    }

    static func tooltip(for day: LocalUsageDay, languageCode: String? = nil) -> String {
        let date = UsagePresentation.axisDate(day.dateKey, languageCode: languageCode)
        let token = MonitorDisplayValue.preciseTokenFormat(day.totalTokens)
        let costLabel = L10n.tr("label.todayCost", languageCode: languageCode)
        return "\(date)\nToken: \(token)\n\(costLabel): \(estimatedCost(day.estimatedCostUSD))"
    }
}

enum HybridUsagePresentation {
    static func tooltip(for day: HybridUsageDay, languageCode: String? = nil) -> String {
        let date = UsagePresentation.axisDate(day.dateKey, languageCode: languageCode)
        let token = day.tokens.map(MonitorDisplayValue.preciseTokenFormat) ?? "--"
        let source = switch day.provenance {
        case .authoritativeAccount: L10n.tr("usage.accountUsage", languageCode: languageCode)
        case .localRealtimeProvisional: L10n.tr("usage.localRealtime", languageCode: languageCode)
        case .sourceAbsent: L10n.tr("usage.accountSourceAbsent", languageCode: languageCode)
        }
        return "\(date)\nToken: \(token)\n\(source)"
    }
}

enum UsagePresentation {
    /// A reset date before modern Codex account service dates is a decoded
    /// epoch/default value, not user-facing reset information.
    private static let earliestValidReset = Date(timeIntervalSince1970: 1_577_836_800) // 2020-01-01 UTC
    /// This is the tooltip's rendered frame, not a guessed clamp width. Long
    /// token totals wrap within the same compact native-material surface.
    static let tooltipSize = CGSize(width: 206, height: 76)

    static func resetTime(_ date: Date?, languageCode: String? = nil) -> String {
        guard let date, date >= earliestValidReset else {
            return L10n.tr("value.unavailable", languageCode: languageCode)
        }
        return date.formatted(
            .dateTime.year().month(.abbreviated).day().hour().minute()
                .locale(Locale(identifier: languageCode ?? L10n.resolvedLanguage))
        )
    }

    static func tooltip(for bucket: AccountUsageDailyBucket, languageCode: String? = nil) -> String {
        String(
            format: L10n.tr("usage.tooltip", languageCode: languageCode),
            displayDate(bucket.startDate, languageCode: languageCode),
            bucket.authoritativeTokens.map { MonitorDisplayValue.preciseTokenFormat(Int64($0)) } ?? "--"
        )
    }

    static func bucket(closestTo x: CGFloat, plotWidth: CGFloat, buckets: [AccountUsageDailyBucket]) -> AccountUsageDailyBucket? {
        guard !buckets.isEmpty, plotWidth > 0 else { return nil }
        let progress = min(max(x / plotWidth, 0), 0.999_999)
        return buckets[min(Int(progress * CGFloat(buckets.count)), buckets.count - 1)]
    }

    static func bucket(closestTo x: CGFloat, plotWidth: CGFloat, buckets: [LocalUsageDay]) -> LocalUsageDay? {
        guard !buckets.isEmpty, plotWidth > 0 else { return nil }
        let progress = min(max(x / plotWidth, 0), 0.999_999)
        return buckets[min(Int(progress * CGFloat(buckets.count)), buckets.count - 1)]
    }

    static func bucket(closestTo x: CGFloat, plotWidth: CGFloat, buckets: [HybridUsageDay]) -> HybridUsageDay? {
        guard !buckets.isEmpty, plotWidth > 0 else { return nil }
        let progress = min(max(x / plotWidth, 0), 0.999_999)
        return buckets[min(Int(progress * CGFloat(buckets.count)), buckets.count - 1)]
    }

    static func tooltipOffset(for bucket: AccountUsageDailyBucket, buckets: [AccountUsageDailyBucket], width: CGFloat) -> CGFloat {
        guard let index = buckets.firstIndex(where: { $0.id == bucket.id }) else { return 0 }
        let point = (CGFloat(index) + 0.5) / CGFloat(max(1, buckets.count)) * width
        return point - tooltipSize.width / 2
    }

    static func tooltipOffset(for bucket: LocalUsageDay, buckets: [LocalUsageDay], width: CGFloat) -> CGFloat {
        guard let index = buckets.firstIndex(where: { $0.id == bucket.id }) else { return 0 }
        let point = (CGFloat(index) + 0.5) / CGFloat(max(1, buckets.count)) * width
        return point - tooltipSize.width / 2
    }

    static func tooltipOffset(for bucket: HybridUsageDay, buckets: [HybridUsageDay], width: CGFloat) -> CGFloat {
        guard let index = buckets.firstIndex(where: { $0.id == bucket.id }) else { return 0 }
        let point = (CGFloat(index) + 0.5) / CGFloat(max(1, buckets.count)) * width
        return point - tooltipSize.width / 2
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
        let values = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard values.count == 3,
              let year = Int(values[0]),
              let month = Int(values[1]),
              let day = Int(values[2]) else { return raw }

        // Usage buckets are calendar days, not midnight UTC instants. Keep
        // parsing and formatting in one fixed calendar/timezone so west-of-UTC
        // users never see an authoritative 2026-08-11 bucket as August 10.
        let timezone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timezone
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return raw }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timezone
        formatter.locale = Locale(identifier: languageCode ?? L10n.resolvedLanguage)
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }
}

enum SettingsSection: CaseIterable, Identifiable {
    case general, floating, notifications, privacy, advanced, maintenance, about
    var id: Self { self }
    var title: String {
        switch self {
        case .general: L10n.tr("settings.general")
        case .floating: L10n.tr("settings.floating")
        case .notifications: L10n.tr("settings.notifications")
        case .privacy: L10n.tr("settings.privacy")
        case .advanced: L10n.tr("settings.advanced")
        case .maintenance: L10n.tr("settings.maintenance")
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
        case .maintenance: "wrench.and.screwdriver"
        case .about: "info.circle"
        }
    }
    static let defaultSection: SettingsSection = .floating
}

@MainActor
final class SettingsPresentationModel: ObservableObject {
    @Published var selection: SettingsSection = .defaultSection
}

@MainActor
struct SettingsSystemActions {
    let refresh: () -> Void
    let openCodex: () -> Void
    let openLogsFolder: () -> Void
    let setMonitoringPaused: (Bool) -> Void
    let requestNotificationPermission: (NotificationPreference) -> Void
    let exportDiagnostics: (@escaping @MainActor (Result<URL, DiagnosticsExportFailure>) -> Void) -> Void
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
            .frame(minWidth: 192, idealWidth: 204, maxWidth: 224)

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
            AdvancedSettingsDetail(preferences: preferences, actions: actions)
        case .maintenance:
            MaintenanceSettingsDetail(actions: actions)
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
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.1)
                VStack(spacing: 0) { content }
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.18), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                    }
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
                .frame(width: 204, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) {
            MonitorDivider().padding(.leading, 16)
        }
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
                HStack(spacing: 8) {
                    Slider(value: $preferences.orbSize, in: 72...180)
                    Text("\(Int(preferences.orbSize.rounded())) pt")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
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
            QuotaWarningSettingsRow(preferences: preferences)
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

private struct QuotaWarningSettingsRow: View {
    @ObservedObject var preferences: MonitorPreferences
    @State private var dragValue: Double = QuotaWarningThreshold.defaultValue
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow(title: L10n.tr("settings.quotaWarning")) {
                Toggle("", isOn: $preferences.quotaWarningEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            Text(String(format: L10n.tr("settings.quotaWarningDescription"), Int(preferences.quotaWarningThreshold)))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            HStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { isEditing ? dragValue : preferences.quotaWarningThreshold },
                        set: { value in
                            dragValue = value
                            preferences.quotaWarningThreshold = QuotaWarningThreshold.snap(value)
                        }
                    ),
                    in: QuotaWarningThreshold.allowedValues.first!...QuotaWarningThreshold.allowedValues.last!,
                    onEditingChanged: { editing in
                        isEditing = editing
                        if !editing {
                            let snapped = QuotaWarningThreshold.snap(dragValue)
                            preferences.quotaWarningThreshold = snapped
                            dragValue = snapped
                        }
                    }
                )
                .controlSize(.small)
                Text("\(Int(preferences.quotaWarningThreshold))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .onAppear { dragValue = preferences.quotaWarningThreshold }
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
    @ObservedObject var preferences: MonitorPreferences
    let actions: SettingsSystemActions
    var body: some View {
        SettingsDetail(title: L10n.tr("settings.advanced")) {
            VStack(alignment: .leading, spacing: 6) {
                SettingsRow(title: L10n.tr("settings.experimentalApprovalYellow")) {
                    HStack(spacing: 8) {
                        Text(L10n.tr("settings.beta"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Toggle("", isOn: $preferences.experimentalApprovalYellowEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
                Text(L10n.tr("settings.experimentalApprovalYellowDescription"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
            SettingsRow(title: L10n.tr("settings.refresh")) { Button(L10n.tr("settings.refresh"), action: actions.refresh).buttonStyle(.bordered) }
            SettingsRow(title: L10n.tr("settings.openCodex")) { Button(L10n.tr("settings.openCodex"), action: actions.openCodex).buttonStyle(.bordered) }
#if !CODEX_MONITOR_RELEASE
            // These local troubleshooting controls are deliberately omitted from
            // the distributable product. The QA build continues to expose them.
            SettingsRow(title: L10n.tr("settings.openLogsFolder")) { Button(L10n.tr("settings.openLogsFolder"), action: actions.openLogsFolder).buttonStyle(.bordered) }
            SettingsRow(title: L10n.tr("settings.openDiagnostics")) { Button(L10n.tr("settings.openDiagnostics"), action: actions.showDiagnostics).buttonStyle(.bordered) }
#endif
        }
    }
}

private struct MaintenanceSettingsDetail: View {
    let actions: SettingsSystemActions
    @State private var exportState: ExportState = .idle

    var body: some View {
        SettingsDetail(title: L10n.tr("settings.maintenance")) {
            SettingsRow(title: L10n.tr("settings.exportDiagnostics")) {
                Button(L10n.tr("settings.exportDiagnostics")) {
                    exportState = .exporting
                    actions.exportDiagnostics { result in
                        exportState = switch result {
                        case .success: .success
                        case .failure(let failure): .failure(failure)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(exportState == .exporting)
            }
            if let message = exportState.message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(exportState.isFailure ? .red : .secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
    }

    private enum ExportState: Equatable {
        case idle, exporting, success, failure(DiagnosticsExportFailure)

        var isFailure: Bool {
            if case .failure = self { return true }
            return false
        }

        var message: String? {
            switch self {
            case .idle: nil
            case .exporting: L10n.tr("settings.diagnosticsExporting")
            case .success: L10n.tr("settings.diagnosticsExported")
            case .failure(let failure):
                switch failure {
                case .downloadsUnavailable: L10n.tr("settings.diagnosticsDownloadsUnavailable")
                case .writeFailed, .noAvailableFilename: L10n.tr("settings.diagnosticsExportFailed")
                }
            }
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
        let presentation = model.presentation
        Form {
            Section(L10n.tr("diagnostics.runtime")) {
                LabeledContent(L10n.tr("diagnostics.state"), value: MonitorDisplayValue.state(presentation))
                LabeledContent(L10n.tr("label.session"), value: MonitorDisplayValue.conversationName(snapshot))
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
