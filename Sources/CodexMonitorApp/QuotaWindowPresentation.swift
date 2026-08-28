import Foundation
import CodexMonitorContracts

/// A display-ready, authoritative quota window. This deliberately starts from
/// the concrete rate-limit windows returned by Codex rather than account-plan
/// names, so a future window cadence is presented without a plan mapping.
struct QuotaWindowPresentation: Equatable, Identifiable {
    enum Slot: Int, Hashable {
        case primary
        case secondary
    }

    let slot: Slot
    let durationMinutes: Int?
    let remainingPercent: Double?
    let resetsAt: Date?
    let availability: MonitorDataAvailability
    let displayLabel: String
    let languageCode: String

    var id: Slot { slot }

    static func quickViewHeight(for windowCount: Int) -> CGFloat {
        214 + CGFloat(max(windowCount - 1, 0)) * 20
    }

    var remainingText: String {
        guard let remainingPercent else { return "--" }
        return String(format: "%.0f%%", remainingPercent)
    }

    func resetDateTime(timeZone: TimeZone = .current, languageCode: String? = nil) -> String {
        guard let resetsAt, resetsAt >= Self.earliestValidReset else { return "--" }
        let locale = Locale(identifier: languageCode ?? L10n.resolvedLanguage)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = timeZone
        dateFormatter.setLocalizedDateFormatFromTemplate("MMMd")

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = timeZone
        // `j` follows the user's system 12/24-hour preference where
        // Foundation supports it; it is intentionally not a hard-coded clock.
        timeFormatter.setLocalizedDateFormatFromTemplate("jmm")

        return "\(dateFormatter.string(from: resetsAt)) · \(timeFormatter.string(from: resetsAt))"
    }

    var quotaRowLabel: String {
        String(format: L10n.tr("quota.window.remaining", languageCode: languageCode), displayLabel)
    }

    var resetRowLabel: String {
        String(format: L10n.tr("quota.window.reset", languageCode: languageCode), displayLabel)
    }

    func quickViewLine(timeZone: TimeZone = .current, languageCode: String? = nil) -> String {
        let language = languageCode ?? self.languageCode
        return String(format: L10n.tr("quota.window.quickView", languageCode: language), quotaRowLabel, remainingText, resetDateTime(timeZone: timeZone, languageCode: language))
    }

    static func windows(from snapshot: MonitorRuntimeSnapshot?, languageCode: String? = nil) -> [Self] {
        windows(
            primary: snapshot?.quota.primary,
            primaryAvailability: snapshot?.quota.primaryAvailability ?? .unknown,
            secondary: snapshot?.quota.secondary,
            secondaryAvailability: snapshot?.quota.secondaryAvailability ?? .unknown,
            languageCode: languageCode
        )
    }

    static func windows(
        primary: RateLimitWindow?,
        primaryAvailability: MonitorDataAvailability = .available,
        secondary: RateLimitWindow?,
        secondaryAvailability: MonitorDataAvailability = .available,
        languageCode: String? = nil
    ) -> [Self] {
        let language = languageCode ?? L10n.resolvedLanguage
        let candidates: [(Slot, RateLimitWindow?, MonitorDataAvailability)] = [
            (.primary, primary, primaryAvailability),
            (.secondary, secondary, secondaryAvailability)
        ]
        return candidates.compactMap { slot, window, availability in
            guard availability == .available, let window else { return nil }
            let remaining = window.usedPercent.map { min(max(100 - $0, 0), 100) }
            return Self(
                slot: slot,
                durationMinutes: window.windowDurationMinutes,
                remainingPercent: remaining,
                resetsAt: window.resetsAt,
                availability: availability,
                displayLabel: durationLabel(minutes: window.windowDurationMinutes, languageCode: language),
                languageCode: language
            )
        }
        .sorted {
            let lhsDuration = $0.durationMinutes ?? Int.max
            let rhsDuration = $1.durationMinutes ?? Int.max
            return lhsDuration == rhsDuration ? $0.slot.rawValue < $1.slot.rawValue : lhsDuration < rhsDuration
        }
    }

    static func durationLabel(minutes: Int?, languageCode: String? = nil) -> String {
        guard let minutes, minutes > 0 else { return L10n.tr("label.quota", languageCode: languageCode) }
        let language = languageCode ?? L10n.resolvedLanguage
        if (9_900...10_260).contains(minutes) {
            return quantity(1, singularKey: "quota.unit.week", pluralKey: "quota.unit.weeks", languageCode: language)
        }
        if (40_000...46_000).contains(minutes) {
            return quantity(1, singularKey: "quota.unit.month", pluralKey: "quota.unit.months", languageCode: language)
        }
        if minutes % 1_440 == 0, minutes >= 2_880 {
            return quantity(minutes / 1_440, singularKey: "quota.unit.day", pluralKey: "quota.unit.days", languageCode: language)
        }
        if minutes % 60 == 0 {
            return quantity(minutes / 60, singularKey: "quota.unit.hour", pluralKey: "quota.unit.hours", languageCode: language)
        }
        return quantity(minutes, singularKey: "quota.unit.minute", pluralKey: "quota.unit.minutes", languageCode: language)
    }

    private static let earliestValidReset = Date(timeIntervalSince1970: 1_577_836_800) // 2020-01-01 UTC

    private static func quantity(_ value: Int, singularKey: String, pluralKey: String, languageCode: String) -> String {
        let unit = L10n.tr(value == 1 ? singularKey : pluralKey, languageCode: languageCode)
        return "\(value) \(unit)"
    }
}
