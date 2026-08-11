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
                let phase = (sin(timeline.date.timeIntervalSinceReferenceDate * .pi * 2 / 2.4) + 1) / 2
                content.opacity(0.62 + phase * 0.36)
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

    func makeNSView(context: Context) -> CircularVisualEffectHost {
        CircularVisualEffectHost(material: material, blendingMode: blendingMode, state: state)
    }

    func updateNSView(_ view: CircularVisualEffectHost, context: Context) {
        view.configure(material: material, blendingMode: blendingMode, state: state)
    }
}

final class CircularVisualEffectHost: NSView {
    private let effectView = NSVisualEffectView()
    private let circularMask = CAShapeLayer()

    init(material: NSVisualEffectView.Material, blendingMode: NSVisualEffectView.BlendingMode, state: NSVisualEffectView.State) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        effectView.wantsLayer = true
        effectView.layer?.backgroundColor = NSColor.clear.cgColor
        effectView.layer?.masksToBounds = true
        effectView.layer?.mask = circularMask
        addSubview(effectView)
        configure(material: material, blendingMode: blendingMode, state: state)
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        let diameter = min(bounds.width, bounds.height)
        let circle = NSRect(
            x: bounds.midX - diameter / 2,
            y: bounds.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
        circularMask.path = CGPath(ellipseIn: circle, transform: nil)
        effectView.layer?.cornerRadius = diameter / 2
    }

    func configure(material: NSVisualEffectView.Material, blendingMode: NSVisualEffectView.BlendingMode, state: NSVisualEffectView.State) {
        effectView.material = material
        effectView.blendingMode = blendingMode
        effectView.state = state
    }
}

private struct PersistentOrbMaterial: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder var body: some View {
        if reduceTransparency {
            Circle().fill(Color(nsColor: .windowBackgroundColor))
        } else {
            CircularVisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)
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
            PersistentOrbMaterial()
                .frame(width: size, height: size)
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.40), lineWidth: 0.8)
                }
                // The shadow belongs to the circular material itself, never
                // to the transparent rectangular floating-panel root.
                .shadow(color: Color.black.opacity(0.10), radius: 8, y: 4)
            Circle()
                .stroke(presentation.orbTone.color, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .frame(width: ringDiameter, height: ringDiameter)
                .presentationBreathing(presentation.breathes, steadyOpacity: 0.88)
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.7)
                        .frame(width: ringDiameter, height: ringDiameter)
                }
            Text(MonitorDisplayValue.orbQuota(snapshot))
                .font(.system(size: valueSize, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.72)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: L10n.tr("accessibility.orb"), MonitorDisplayValue.state(presentation), MonitorDisplayValue.orbQuota(snapshot)))
        .accessibilityHint(L10n.tr("accessibility.orbHint"))
    }
}

struct MenuStatusCapsuleView: View {
    @ObservedObject var model: MonitorAppModel

    var body: some View {
        let presentation = model.presentation
        let dots = presentation.dots
        HStack(spacing: 5) {
            ForEach(Array(dots.enumerated()), id: \.offset) { _, dot in
                dotView(dot)
            }
        }
        .frame(width: 48, height: 22)
        .background(PersistentGlassCapsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.74), lineWidth: 0.7))
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
        Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
    }
}

struct MonitorDivider: View {
    var body: some View { Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1) }
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

    static func todayUsage(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        guard snapshot?.usage.availability == .available,
              let value = snapshot?.usage.usage?.dailyBuckets?.last?.tokens else {
            return availability(snapshot?.usage.availability)
        }
        return summaryTokenFormat(Int64(value))
    }

    static func last30DaysUsage(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        guard snapshot?.usage.availability == .available,
              let buckets = snapshot?.usage.usage?.dailyBuckets else {
            return availability(snapshot?.usage.availability)
        }
        return summaryTokenFormat(Int64(buckets.reduce(0) { $0 + $1.tokens }))
    }

    static func remainingQuota(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        let windows: [(RateLimitWindow?, MonitorDataAvailability)] = [
            (snapshot?.quota.primary, snapshot?.quota.primaryAvailability ?? .unavailable),
            (snapshot?.quota.secondary, snapshot?.quota.secondaryAvailability ?? .unavailable)
        ]
        let remaining = windows.compactMap { window, availability -> Double? in
            guard availability == .available, let used = window?.usedPercent else { return nil }
            return min(max(100 - used, 0), 100)
        }.min()
        return remaining.map { String(format: "%.0f%%", $0) } ?? availability(snapshot?.quota.primaryAvailability)
    }

    static func orbQuota(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        let value = remainingQuota(snapshot)
        return value.hasSuffix("%") ? value : "--"
    }

    static func reset(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        snapshot?.resetInformation.count.map(String.init) ?? availability(snapshot?.resetInformation.countAvailability)
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

    static func taskTitle(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        taskTitleForPresentation(snapshot?.currentThread?.taskTitle)
    }

    /// Desktop-provided titles are presentation data, not trusted source text.
    /// Reject known transcript/prompt fragments rather than displaying internal
    /// agent history in a user-facing surface.
    static func taskTitleForPresentation(_ rawTitle: String?) -> String {
        guard let rawTitle else { return L10n.tr("activity.noSession") }
        let title = rawTitle
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return L10n.tr("activity.noSession") }

        let lowered = title.lowercased()
        let internalMarkers = [
            "the following is codex agent history",
            "codex agent history",
            "system prompt",
            "developer prompt",
            "internal transcript",
            "tool instruction",
            "you are codex"
        ]
        guard !internalMarkers.contains(where: lowered.contains) else {
            return L10n.tr("activity.currentTask")
        }
        return String(title.prefix(120))
    }

    static func modelRuntime(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        let model = snapshot?.currentThread?.model ?? String(format: L10n.tr("model.unknown"), L10n.unknown)
        guard let since = snapshot?.currentStateSince else { return "\(model) · \(L10n.tr("runtime.unknown"))" }
        let seconds = max(0, Int(Date().timeIntervalSince(since)))
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
