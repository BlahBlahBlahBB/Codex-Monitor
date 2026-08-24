import AppKit
import SwiftUI
import CodexMonitorContracts

/// A Timeline exists only for an active presentation. Unlike a retained
/// `repeatForever` animation it is removed synchronously when the state turns
/// idle/error, so a terminal animation cannot leak into a steady state.
/// The cadence is intentionally slow: this is state indication, not a busy
/// decorative animation.
private struct PresentationBreathing: ViewModifier {
    let enabled: Bool
    let steadyOpacity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
                // Keep breathing as a quiet brightness cue. It intentionally
                // never changes geometry, scale, or adds a glow.
                let phase = (sin(timeline.date.timeIntervalSinceReferenceDate * .pi * 2 / 2.8) + 1) / 2
                content.opacity(0.72 + phase * 0.18)
            }
        } else {
            content.opacity(steadyOpacity)
        }
    }
}

private extension View {
    func presentationBreathing(_ enabled: Bool, steadyOpacity: Double = 0.90) -> some View {
        modifier(PresentationBreathing(enabled: enabled, steadyOpacity: steadyOpacity))
    }
}

extension VisualStateTone {
    var color: Color {
        switch self {
        case .green: Color(nsColor: .systemGreen)
        case .blue: Color(nsColor: .systemBlue)
        case .yellow: Color(nsColor: .systemYellow)
        case .red: Color(nsColor: .systemRed)
        case .gray, .inactive: Color(nsColor: .tertiaryLabelColor)
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let state: NSVisualEffectView.State

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        guard view.material != material || view.blendingMode != blendingMode || view.state != state else { return }
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
    }
}

enum LiquidGlassLevel { case persistent, floating }

/// macOS 26 uses the real Liquid Glass compositor. Older supported systems use
/// one restrained NSVisualEffectView fallback rather than a hand-made blur,
/// beige fill, border, and shadow imitation.
struct GlassSurface<Content: View>: View {
    let cornerRadius: CGFloat
    let shadow: Bool
    let level: LiquidGlassLevel
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(cornerRadius: CGFloat = 22, shadow: Bool = true, level: LiquidGlassLevel = .floating, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.level = level
        self.content = content()
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: 0) {
                content
                    .glassEffect(level == .persistent ? .clear : .regular, in: shape)
            }
        } else {
            content
                .background {
                    if reduceTransparency {
                        shape.fill(Color(nsColor: .windowBackgroundColor))
                    } else {
                        VisualEffectView(material: level == .persistent ? .underWindowBackground : .hudWindow, blendingMode: .behindWindow, state: .active)
                    }
                }
                .clipShape(shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5) }
                .shadow(color: shadow ? Color.black.opacity(0.12) : .clear, radius: shadow ? 14 : 0, y: shadow ? 7 : 0)
        }
    }
}

/// The floating Orb cannot use SwiftUI's glass compositor: it is mounted in
/// a transparent rectangular NSHostingView and that path can retain a
/// rectangular backing layer. This representable owns exactly one circular
/// NSVisualEffectView; its parent remains completely transparent.
struct CircularVisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let state: NSVisualEffectView.State
    let shadowInset: CGFloat

    init(material: NSVisualEffectView.Material, blendingMode: NSVisualEffectView.BlendingMode, state: NSVisualEffectView.State, shadowInset: CGFloat = 0) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
        self.shadowInset = max(0, shadowInset)
    }

    func makeNSView(context: Context) -> CircularVisualEffectHost {
        CircularVisualEffectHost(material: material, blendingMode: blendingMode, state: state, shadowInset: shadowInset)
    }

    func updateNSView(_ view: CircularVisualEffectHost, context: Context) {
        view.configure(material: material, blendingMode: blendingMode, state: state)
    }
}

final class CircularVisualEffectHost: NSView {
    private let effectView = NSVisualEffectView()
    private var lastMaskSize = NSSize.zero
    private var lastBackingScale: CGFloat = 0
    private var configuredMaterial: NSVisualEffectView.Material?
    private var configuredBlendingMode: NSVisualEffectView.BlendingMode?
    private var configuredState: NSVisualEffectView.State?
    private let shadowInset: CGFloat
    private(set) var maskGenerationCount = 0

    init(material: NSVisualEffectView.Material, blendingMode: NSVisualEffectView.BlendingMode, state: NSVisualEffectView.State, shadowInset: CGFloat = 0) {
        self.shadowInset = max(0, shadowInset)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        // The panel remains transparent and shadow-free. Depth belongs only
        // to this explicitly circular host, never to its rectangular window.
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.12
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.masksToBounds = false
        effectView.wantsLayer = true
        effectView.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(effectView)
        configure(material: material, blendingMode: blendingMode, state: state)
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        let glassBounds = bounds.insetBy(dx: shadowInset, dy: shadowInset)
        effectView.frame = glassBounds
        layer?.shadowPath = CGPath(ellipseIn: glassBounds, transform: nil)
        let size = effectView.bounds.size
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        guard size != lastMaskSize || scale != lastBackingScale else { return }
        lastMaskSize = size
        lastBackingScale = scale
        effectView.maskImage = circleMaskImage(for: size)
        maskGenerationCount += 1
    }

    func configure(material: NSVisualEffectView.Material, blendingMode: NSVisualEffectView.BlendingMode, state: NSVisualEffectView.State) {
        guard configuredMaterial != material || configuredBlendingMode != blendingMode || configuredState != state else { return }
        effectView.material = material
        effectView.blendingMode = blendingMode
        effectView.state = state
        configuredMaterial = material
        configuredBlendingMode = blendingMode
        configuredState = state
    }

    var maskGenerationCountForTesting: Int { maskGenerationCount }
    var circularShadowPathForTesting: CGPath? { layer?.shadowPath }
    var circularShadowOpacityForTesting: Float { layer?.shadowOpacity ?? 0 }
    var circularShadowOffsetForTesting: CGSize { layer?.shadowOffset ?? .zero }
    var circularShadowMasksToBoundsForTesting: Bool { layer?.masksToBounds ?? true }
    var circularGlassBoundsForTesting: CGRect { effectView.frame }

    /// `NSVisualEffectView` owns a separate compositing path, so a regular
    /// CALayer mask does not reliably clip its material. Its documented
    /// `maskImage` API applies this opaque circular image at every size.
    private func circleMaskImage(for size: NSSize) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        let diameter = min(size.width, size.height)
        let circle = NSRect(
            x: (size.width - diameter) / 2,
            y: (size.height - diameter) / 2,
            width: diameter,
            height: diameter
        )
        NSColor.white.setFill()
        NSBezierPath(ovalIn: circle).fill()
        return image
    }
}

private struct PersistentOrbMaterial: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder var body: some View {
        if reduceTransparency {
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: size, height: size)
        } else {
            CircularVisualEffectView(
                material: .hudWindow,
                blendingMode: .behindWindow,
                state: .active,
                shadowInset: FloatingOrbSurfaceConfiguration.shadowInset
            )
            .frame(
                width: size + FloatingOrbSurfaceConfiguration.shadowInset * 2,
                height: size + FloatingOrbSurfaceConfiguration.shadowInset * 2
            )
        }
    }
}

/// A single, low-contrast highlight gives the glass body a sense of ambient
/// depth without adding a border, a second ring, or a rectangular shadow.
/// The highlight is deliberately omitted when transparency is reduced.
private struct OrbDepthHighlight: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    var body: some View {
        if reduceTransparency {
            EmptyView()
        } else {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.06), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: max(1, size * 0.82)
                    )
                )
                .frame(width: size, height: size)
                .allowsHitTesting(false)
        }
    }
}

private struct PersistentGlassCapsule: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder var body: some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            Capsule().fill(.clear).glassEffect(.clear, in: Capsule())
        } else if reduceTransparency {
            Capsule().fill(Color(nsColor: .windowBackgroundColor))
        } else {
            Capsule().fill(.ultraThinMaterial)
        }
    }
}

struct MonitorOrbView: View {
    let snapshot: MonitorRuntimeSnapshot?
    let presentation: VisualStatePresentation
    let size: CGFloat

    var body: some View {
        let ringWidth = max(5.6, min(13.5, size * (7 / 90)))
        let ringDiameter = size * 0.90
        let valueSize = max(13, min(30, size * (24 / 90)))

        ZStack {
            PersistentOrbMaterial(size: size)
            OrbDepthHighlight(size: size)
            Circle()
                .stroke(presentation.orbTone.color, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .frame(width: ringDiameter, height: ringDiameter)
                .presentationBreathing(presentation.breathes, steadyOpacity: 0.88)
            Text(MonitorDisplayValue.orbQuota(snapshot))
                .font(.system(size: valueSize, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .tracking(-0.15)
                .minimumScaleFactor(0.72)
        }
        .frame(
            width: size + FloatingOrbSurfaceConfiguration.shadowInset * 2,
            height: size + FloatingOrbSurfaceConfiguration.shadowInset * 2
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: L10n.tr("accessibility.orb"), MonitorDisplayValue.state(presentation), MonitorDisplayValue.orbQuota(snapshot)))
        .accessibilityHint(L10n.tr("accessibility.orbHint"))
    }
}

struct MenuStatusCapsuleView: View {
    @ObservedObject var model: MonitorAppModel
    @ObservedObject var preferences: MonitorPreferences

    var body: some View {
        let presentation = model.presentation(using: preferences)
        let dots = presentation.dots
        HStack(spacing: 6) {
            ForEach(Array(dots.enumerated()), id: \.offset) { _, dot in
                dotView(dot)
            }
        }
        .frame(width: 48, height: 22)
        .background(PersistentGlassCapsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: L10n.tr("accessibility.menuStatus"), MonitorDisplayValue.state(presentation)))
    }

    private func dotView(_ presentation: VisualStateDot) -> some View {
        return Circle()
            .fill(presentation.tone.color)
            .frame(width: 7, height: 7)
            .presentationBreathing(presentation.breathes, steadyOpacity: presentation.tone == .inactive ? 0.32 : 0.90)
    }
}

struct MonitorValueRow: View {
    let title: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}

struct MonitorSectionTitle: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .tracking(-0.08)
            .foregroundStyle(.primary)
    }
}

struct MonitorDivider: View {
    var body: some View { Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.60)).frame(height: 0.5) }
}

enum MonitorDisplayValue {
    static func availability(_ availability: MonitorDataAvailability?) -> String {
        switch availability {
        case .available: return L10n.tr("value.available")
        case .stale: return L10n.tr("value.stale")
        case .unknown: return L10n.unknown
        case .unavailable, .none: return L10n.unavailable
        }
    }

    static func token(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        snapshot?.sessionToken.map(preciseTokenFormat) ?? availability(snapshot?.currentThread?.sessionTokenAvailability)
    }

    static func usage(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        snapshot?.usage.usage?.totalTokens.map { summaryTokenFormat(Int64($0)) } ?? availability(snapshot?.usage.availability)
    }

    static func account(_ snapshot: MonitorRuntimeSnapshot?, hidden: Bool = false) -> String {
        guard !hidden else { return L10n.tr("value.hidden") }
        guard let kind = snapshot?.account.accountKind else { return availability(snapshot?.account.availability) }
        return kind.caseInsensitiveCompare("chatgpt") == .orderedSame ? "ChatGPT" : kind.capitalized
    }

    static func plan(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        snapshot?.account.plan?.capitalized ?? availability(snapshot?.account.availability)
    }

    /// "Today" is a local calendar day and is read from the exact same
    /// normalized daily bucket collection rendered by the 30-day chart.
    /// Do not substitute a rolling-session or lifetime summary here.
    static func todayUsage(
        _ snapshot: MonitorRuntimeSnapshot?,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        languageCode: String? = nil
    ) -> String {
        guard snapshot?.usage.availability == .available,
              let buckets = snapshot?.usage.usage?.dailyBuckets else {
            return availability(snapshot?.usage.availability)
        }
        let localToday = LocalUsageDateKey.value(for: now, calendar: calendar)
        guard let bucket = buckets.first(where: { $0.startDate == localToday }),
              let tokens = bucket.authoritativeTokens else {
            return "--"
        }
        return summaryTokenFormat(Int64(tokens), languageCode: languageCode)
    }

    static func last30DaysUsage(_ snapshot: MonitorRuntimeSnapshot?, languageCode: String? = nil) -> String {
        guard snapshot?.usage.availability == .available,
              let buckets = snapshot?.usage.usage?.dailyBuckets else {
            return availability(snapshot?.usage.availability)
        }
        return summaryTokenFormat(Int64(buckets.compactMap(\.authoritativeTokens).reduce(0, +)), languageCode: languageCode)
    }

    static func remainingQuota(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        guard let selected = selectedQuotaWindow(snapshot) else {
            return availability(snapshot?.quota.primaryAvailability)
        }
        return String(format: "%.0f%%", selected.remaining)
    }

    static func orbQuota(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        let value = remainingQuota(snapshot)
        return value.hasSuffix("%") ? value : "--"
    }

    static func reset(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        snapshot?.resetInformation.count.map(String.init) ?? availability(snapshot?.resetInformation.countAvailability)
    }

    /// Presentation-only counterpart to the Orb's existing "most restricted"
    /// quota rule. Keeping the actual selected window here makes every quota
    /// surface (including its reset time) refer to one authoritative window.
    static func selectedQuotaWindow(_ snapshot: MonitorRuntimeSnapshot?) -> (window: RateLimitWindow, remaining: Double)? {
        let candidates: [(window: RateLimitWindow, remaining: Double, order: Int)] = [
            (snapshot?.quota.primary, snapshot?.quota.primaryAvailability ?? .unavailable),
            (snapshot?.quota.secondary, snapshot?.quota.secondaryAvailability ?? .unavailable)
        ].enumerated().compactMap { index, candidate in
            guard candidate.1 == .available,
                  let window = candidate.0,
                  let used = window.usedPercent else { return nil }
            return (window, min(max(100 - used, 0), 100), index)
        }
        guard let selected = candidates.min(by: {
            $0.remaining == $1.remaining ? $0.order < $1.order : $0.remaining < $1.remaining
        }) else { return nil }
        return (selected.window, selected.remaining)
    }

    static func quotaResetDate(_ snapshot: MonitorRuntimeSnapshot?, now: Date = Date(), languageCode: String? = nil) -> String {
        QuotaResetPresentation.text(for: selectedQuotaWindow(snapshot)?.window, now: now, languageCode: languageCode)
    }

    static func state(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        L10n.tr(VisualStatePresentation.forSnapshot(snapshot).stateTextKey)
    }

    static func state(_ presentation: VisualStatePresentation) -> String {
        L10n.tr(presentation.stateTextKey)
    }

    static func activity(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        guard let activity = snapshot?.currentActivity else { return L10n.tr("activity.noSnapshot") }
        switch activity {
        case .thinking: return L10n.tr("state.thinking")
        case .tool: return L10n.tr("state.working")
        case .fileChange: return L10n.tr("activity.changingFiles")
        case .agentResponse: return L10n.tr("activity.responding")
        case .waitingApproval: return L10n.tr("activity.waitingConfirmation")
        case .completed: return L10n.tr("state.completed")
        case .failed: return L10n.tr("state.failed")
        case .interrupted: return L10n.tr("state.interrupted")
        case .systemError: return L10n.tr("state.systemError")
        case .idle: return L10n.tr("state.idle")
        case .disconnected: return L10n.tr("state.codexUnavailable")
        }
    }

    /// The sole user-facing Conversation Display Title resolver. Both Usage
    /// and Quick View intentionally delegate here so they cannot acquire
    /// different fallback rules or accidentally surface runtime provenance.
    static func resolvedConversationDisplayTitle(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        guard let currentThread = snapshot?.currentThread else {
            return L10n.tr("activity.noSession")
        }
        return trustedConversationDisplayName(currentThread.conversationName)
            ?? L10n.tr("activity.currentTask")
    }

    static func conversationName(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        resolvedConversationDisplayTitle(snapshot)
    }

    static func sessionInfo(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        resolvedConversationDisplayTitle(snapshot)
    }

    static func quickViewTaskTitle(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        resolvedConversationDisplayTitle(snapshot)
    }

    /// A persisted sidebar conversation name is the only admitted title
    /// source. This predicate is a narrow presentation safeguard for values
    /// that unmistakably look like
    /// internal source material, identifiers, or filesystem locations. It
    /// deliberately does not reject a slash by itself: titles such as
    /// "UI/UX redesign" are valid Conversation Display Titles.
    private static func trustedConversationDisplayName(_ rawName: String?) -> String? {
        guard let rawName else { return nil }
        let title = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let lowered = title.lowercased()
        let internalMarkers = [
            "the following is codex agent history",
            "codex agent history",
            "system prompt",
            "developer prompt",
            "internal transcript",
            "tool instruction",
            "tool metadata",
            "you are codex",
            "# files pasted by the user",
            "# files mentioned by the user"
        ]
        guard !internalMarkers.contains(where: lowered.contains),
              !isFilesystemLike(title),
              !isUUIDLike(title) else {
            return nil
        }
        return String(title.prefix(120))
    }

    private static func isFilesystemLike(_ value: String) -> Bool {
        let patterns = [
            "(?i)^file://",
            "^/(?:Users|Volumes|Applications|Library|System|private|tmp)(?:/|$)",
            "^\\\\?~/(?:Desktop|\\.codex)(?:/|$)"
        ]
        return patterns.contains { value.range(of: $0, options: .regularExpression) != nil }
    }

    private static func isUUIDLike(_ value: String) -> Bool {
        value.range(
            of: "(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
            options: .regularExpression
        ) != nil
    }

    static func modelRuntime(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        let model = snapshot?.currentThread?.model ?? String(format: L10n.tr("model.unknown"), L10n.unknown)
        guard let since = snapshot?.currentStateSince else { return "\(model) · \(L10n.tr("runtime.unknown"))" }
        let seconds = snapshot?.currentState == .idle ? 0 : max(0, Int(Date().timeIntervalSince(since)))
        return "\(model) · \(L10n.tr("runtime.label")) \(duration(seconds))"
    }

    static func update(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        guard let snapshot, snapshot.sourceHealth[.desktopLocal]?.availability == .available else { return L10n.tr("state.sourceUnavailable") }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return String(format: L10n.tr("update.updated"), formatter.string(from: snapshot.capturedAt))
    }

    static func source(_ source: MonitorRuntimeSource) -> String {
        switch source {
        case .desktopLocal: return "Desktop Local"
        case .approvalLocal: return "Approval Local"
        case .approvalAccessibility: return "Approval Accessibility"
        case .account: return "Account"
        }
    }

    static func capability(_ capability: MonitorRuntimeCapability) -> String {
        capability.rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
    }

    /// Exact values are reserved for places where a user inspects a single
    /// datapoint (session attribution and chart tooltips).
    static func preciseTokenFormat(_ value: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return "\(formatter.string(from: NSNumber(value: value)) ?? String(value)) Token"
    }

    /// Summary metrics may be compact, while preserving a separate exact
    /// formatter for tooltips. Chinese follows the native 万/亿 convention;
    /// English uses K/M/B suffixes.
    static func summaryTokenFormat(_ value: Int64, languageCode: String? = nil) -> String {
        let language = languageCode ?? L10n.resolvedLanguage
        let locale = Locale(identifier: language)
        let number = Double(value)
        let rendered: String
        if language.hasPrefix("zh") {
            if value >= 100_000_000 {
                rendered = String(format: "%.2f亿", locale: locale, number / 100_000_000)
            } else if value >= 10_000 {
                rendered = String(format: "%.2f万", locale: locale, number / 10_000)
            } else {
                rendered = preciseNumber(value, locale: locale)
            }
        } else if value >= 1_000_000_000 {
            rendered = String(format: "%.2fB", locale: locale, number / 1_000_000_000)
        } else if value >= 1_000_000 {
            rendered = String(format: "%.2fM", locale: locale, number / 1_000_000)
        } else if value >= 1_000 {
            rendered = String(format: "%.2fK", locale: locale, number / 1_000)
        } else {
            rendered = preciseNumber(value, locale: locale)
        }
        return "\(rendered) Token"
    }

    private static func preciseNumber(_ value: Int64, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func duration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

enum QuotaResetPresentation {
    /// An epoch/default value is not an authoritative reset date.
    private static let earliestValidReset = Date(timeIntervalSince1970: 1_577_836_800) // 2020-01-01 UTC

    static func text(for window: RateLimitWindow?, now: Date = Date(), languageCode: String? = nil) -> String {
        guard let window, let resetAt = window.resetsAt, resetAt >= earliestValidReset else { return "--" }
        let language = languageCode ?? L10n.resolvedLanguage
        let label = windowLabel(minutes: window.windowDurationMinutes, languageCode: language)
        let date = resetDate(resetAt, now: now, languageCode: language)
        guard let label else { return date }
        return "\(label) · \(date)"
    }

    private static func windowLabel(minutes: Int?, languageCode: String) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        switch minutes {
        case 1_380...1_500:
            return L10n.tr("quota.window.daily", languageCode: languageCode)
        case 9_900...10_260:
            return L10n.tr("quota.window.weekly", languageCode: languageCode)
        case 40_000...46_000:
            return L10n.tr("quota.window.monthly", languageCode: languageCode)
        case 1..<1_440 where minutes % 60 == 0:
            return String(format: L10n.tr("quota.window.hours", languageCode: languageCode), minutes / 60)
        default:
            return nil
        }
    }

    private static func resetDate(_ date: Date, now: Date, languageCode: String) -> String {
        let locale = Locale(identifier: languageCode)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .current
        if Calendar.current.isDate(date, inSameDayAs: now) {
            formatter.setLocalizedDateFormatFromTemplate("Hm")
        } else if languageCode.hasPrefix("zh") {
            formatter.dateFormat = "MM.dd"
        } else {
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
        }
        return formatter.string(from: date)
    }
}
