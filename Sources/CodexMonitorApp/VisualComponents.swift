import AppKit
import SwiftUI
import CodexMonitorContracts

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

private struct PersistentGlassCircle: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder var body: some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            Circle()
                .fill(.clear)
                .glassEffect(.regular, in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.42), lineWidth: 0.8)
                }
        } else if reduceTransparency {
            Circle().fill(Color(nsColor: .windowBackgroundColor))
        } else {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.40), lineWidth: 0.8)
                }
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
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        let presentation = VisualStatePresentation.forSnapshot(snapshot)
        let ringWidth = max(5.6, min(13.5, size * (7 / 90)))
        let ringDiameter = size * 0.90
        let valueSize = max(13, min(30, size * (24 / 90)))
        let ringOpacity = presentation.breathes && !reduceMotion && breathing ? 0.98 : (presentation.breathes ? 0.62 : 0.88)

        ZStack {
            PersistentGlassCircle()
            Circle()
                .stroke(presentation.orbTone.color.opacity(ringOpacity), style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .frame(width: ringDiameter, height: ringDiameter)
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
        .clipShape(Circle())
        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: L10n.tr("accessibility.orb"), MonitorDisplayValue.state(snapshot), MonitorDisplayValue.orbQuota(snapshot)))
        .accessibilityHint(L10n.tr("accessibility.orbHint"))
        .onAppear { breathing = presentation.breathes && !reduceMotion }
        .onChange(of: reduceMotion) { value in breathing = presentation.breathes && !value }
        .onChange(of: presentation.breathes) { value in breathing = value && !reduceMotion }
        .animation(
            presentation.breathes && !reduceMotion
                ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                : .easeOut(duration: 0.18),
            value: breathing
        )
    }
}

struct MenuStatusCapsuleView: View {
    @ObservedObject var model: MonitorAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        let snapshot = model.snapshot
        let presentation = VisualStatePresentation.forSnapshot(snapshot)
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
        .accessibilityLabel(String(format: L10n.tr("accessibility.menuStatus"), MonitorDisplayValue.state(snapshot)))
        .onAppear { breathing = dots.contains(where: \.breathes) && !reduceMotion }
        .onChange(of: reduceMotion) { value in breathing = dots.contains(where: \.breathes) && !value }
        .onChange(of: dots) { value in breathing = value.contains(where: \.breathes) && !reduceMotion }
        .animation(
            dots.contains(where: \.breathes) && !reduceMotion
                ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                : .easeOut(duration: 0.18),
            value: breathing
        )
    }

    private func dotView(_ presentation: VisualStateDot) -> some View {
        let activeOpacity = presentation.breathes && !reduceMotion ? (breathing ? 1.0 : 0.58) : 0.90
        return Circle()
            .fill(presentation.tone.color.opacity(presentation.tone == .inactive ? 0.32 : activeOpacity))
            .frame(width: 7, height: 7)
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
        snapshot?.sessionToken.map(tokenFormat) ?? availability(snapshot?.currentThread?.sessionTokenAvailability)
    }

    static func usage(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        snapshot?.usage.usage?.totalTokens.map { tokenFormat(Int64($0)) } ?? availability(snapshot?.usage.availability)
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
        return tokenFormat(Int64(value))
    }

    static func last30DaysUsage(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        guard snapshot?.usage.availability == .available,
              let buckets = snapshot?.usage.usage?.dailyBuckets else {
            return availability(snapshot?.usage.availability)
        }
        return tokenFormat(Int64(buckets.reduce(0) { $0 + $1.tokens }))
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

    static func tokenFormat(_ value: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return "\(formatter.string(from: NSNumber(value: value)) ?? String(value)) Token"
    }

    private static func duration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
