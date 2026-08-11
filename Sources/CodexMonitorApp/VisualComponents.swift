import AppKit
import SwiftUI
import CodexMonitorContracts

struct MonitorVisualPalette {
    let tint: Color
    let usesBreathing: Bool
    let breathingDuration: Double

    static func forSnapshot(_ snapshot: MonitorRuntimeSnapshot?) -> MonitorVisualPalette {
        guard let snapshot else {
            return MonitorVisualPalette(tint: Color(nsColor: .systemGray), usesBreathing: false, breathingDuration: 3.2)
        }
        if snapshot.sourceHealth[.desktopLocal]?.availability == .unavailable {
            return MonitorVisualPalette(tint: Color(nsColor: .systemGray), usesBreathing: false, breathingDuration: 3.2)
        }
        switch snapshot.currentState {
        case .thinking:
            return MonitorVisualPalette(tint: Color(nsColor: .systemGreen), usesBreathing: true, breathingDuration: 2.8)
        case .working:
            return MonitorVisualPalette(tint: Color(nsColor: .systemGreen), usesBreathing: true, breathingDuration: 3.6)
        case .waitingApproval:
            return MonitorVisualPalette(tint: Color(nsColor: .systemYellow), usesBreathing: true, breathingDuration: 3.2)
        case .failed, .interrupted, .systemError:
            return MonitorVisualPalette(tint: Color(nsColor: .systemRed), usesBreathing: false, breathingDuration: 3.2)
        case .completed, .idle:
            return MonitorVisualPalette(tint: Color(nsColor: .systemGreen), usesBreathing: false, breathingDuration: 3.2)
        case .disconnected, .paused:
            return MonitorVisualPalette(tint: Color(nsColor: .systemGray), usesBreathing: false, breathingDuration: 3.2)
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

struct GlassSurface<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(cornerRadius: CGFloat = 22, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                    .overlay(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.16 : 0.26))
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.42), lineWidth: 0.7)
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.34 : 0.16), radius: 24, y: 12)
    }
}

struct MonitorOrbView: View {
    let snapshot: MonitorRuntimeSnapshot?
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        let palette = MonitorVisualPalette.forSnapshot(snapshot)
        let ringWidth = min(11, max(5.5, size * 0.075))
        let textSize = min(21, max(10, size * 0.145))
        let ringOpacity = palette.usesBreathing && !reduceMotion ? (breathing ? 0.96 : 0.65) : 0.84

        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .fill(palette.tint.opacity(0.11))
            Circle()
                .stroke(palette.tint.opacity(0.18), lineWidth: 1)
            Circle()
                .stroke(palette.tint.opacity(ringOpacity), lineWidth: ringWidth)
            Text(statusLabel)
                .font(.system(size: textSize, weight: .semibold, design: .rounded))
                .tracking(size < 100 ? 0 : -0.1)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineSpacing(-1)
                .minimumScaleFactor(0.72)
                .padding(size * 0.18)
        }
        .frame(width: size, height: size)
        .shadow(color: palette.tint.opacity(0.18), radius: 13, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codex status \(statusLabel.replacingOccurrences(of: "\n", with: " "))")
        .accessibilityHint("Click to open Quick View. Drag to move.")
        .onAppear {
            breathing = palette.usesBreathing && !reduceMotion
        }
        .onChange(of: reduceMotion) { value in
            breathing = palette.usesBreathing && !value
        }
        .animation(
            palette.usesBreathing && !reduceMotion
                ? .easeInOut(duration: palette.breathingDuration).repeatForever(autoreverses: true)
                : .easeOut(duration: 0.18),
            value: breathing
        )
    }

    private var statusLabel: String {
        guard let snapshot else { return "CODEX\nUNAVAILABLE" }
        if snapshot.sourceHealth[.desktopLocal]?.availability == .unavailable {
            return "SOURCE\nUNAVAILABLE"
        }
        if snapshot.currentState == .disconnected {
            return "CODEX\nUNAVAILABLE"
        }
        return snapshot.currentState.rawValue.replacingOccurrences(of: "_", with: "\n")
    }
}

struct MonitorStatusCapsule: View {
    let snapshot: MonitorRuntimeSnapshot?

    var body: some View {
        HStack(spacing: 7) {
            statusDot(MonitorVisualPalette.forSnapshot(snapshot).tint, label: "State")
            statusDot(activityColor, label: "Activity")
            statusDot(sourceColor, label: "Source")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.84)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.62), lineWidth: 0.7))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Monitor status indicators")
    }

    private func statusDot(_ color: Color, label: String) -> some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.35), radius: 3)
            .accessibilityLabel(label)
    }

    private var activityColor: Color {
        switch snapshot?.currentActivity {
        case .thinking, .tool, .fileChange, .agentResponse: Color(nsColor: .systemGreen)
        case .waitingApproval: Color(nsColor: .systemYellow)
        case .failed, .interrupted, .systemError: Color(nsColor: .systemRed)
        case .completed, .idle: Color(nsColor: .systemGreen)
        case .disconnected, .none: Color(nsColor: .systemGray)
        }
    }

    private var sourceColor: Color {
        guard let health = snapshot?.sourceHealth[.desktopLocal] else { return Color(nsColor: .systemGray) }
        return health.availability == .available ? Color(nsColor: .systemGreen) : Color(nsColor: .systemGray)
    }
}

struct MonitorValueRow: View {
    let title: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
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
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(.secondary)
    }
}

struct MonitorDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(height: 1)
    }
}

enum MonitorDisplayValue {
    static func availability(_ availability: MonitorDataAvailability?) -> String {
        availability?.rawValue.uppercased() ?? "UNAVAILABLE"
    }

    static func token(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        snapshot?.sessionToken.map(String.init) ?? availability(snapshot?.currentThread?.sessionTokenAvailability)
    }

    static func usage(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        snapshot?.usage.usage?.totalTokens.map(String.init) ?? availability(snapshot?.usage.availability)
    }

    static func quota(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        snapshot?.quota.primary?.usedPercent.map { String(format: "%.0f%% used", $0) } ?? availability(snapshot?.quota.primaryAvailability)
    }

    static func reset(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        snapshot?.resetInformation.count.map(String.init) ?? availability(snapshot?.resetInformation.countAvailability)
    }

    static func state(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        snapshot?.currentState.rawValue.replacingOccurrences(of: "_", with: " ") ?? "UNAVAILABLE"
    }

    static func activity(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        guard let activity = snapshot?.currentActivity else { return "No runtime snapshot" }
        switch activity {
        case .thinking: return "Thinking"
        case .tool: return "Working"
        case .fileChange: return "File Change"
        case .agentResponse: return "Agent Response"
        case .waitingApproval: return "Waiting Approval"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .interrupted: return "Interrupted"
        case .systemError: return "System Error"
        case .idle: return "Idle"
        case .disconnected: return "Codex Unavailable"
        }
    }

    static func source(_ source: MonitorRuntimeSource) -> String {
        switch source {
        case .desktopLocal: return "Desktop Local"
        case .approvalLocal: return "Approval Local"
        case .account: return "Account"
        }
    }

    static func capability(_ capability: MonitorRuntimeCapability) -> String {
        switch capability {
        case .currentState: return "Current State"
        case .sessionThreadAttribution: return "Session / Thread"
        case .waitingApproval: return "Waiting Approval"
        case .approvalResolution: return "Approval Resolution"
        case .sessionToken: return "Session Token"
        case .usage: return "Usage"
        case .quota: return "Quota"
        case .resetInformation: return "Reset Information"
        }
    }
}
