import SwiftUI
import CodexMonitorContracts

struct MenuBarPopoverView: View {
    @ObservedObject var model: MonitorAppModel
    @ObservedObject var preferences: MonitorPreferences
    let actions: MonitorSurfaceActions

    var body: some View {
        let snapshot = model.snapshot
        GlassSurface(cornerRadius: 18, shadow: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Block 1 — runtime state and current activity.
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

                // Block 2 — account/plan/quota/reset, truthful when absent.
                VStack(alignment: .leading, spacing: 8) {
                    MonitorPopoverRow(label: "Account", value: "UNKNOWN")
                    MonitorPopoverRow(label: "Plan", value: "UNKNOWN")
                    MonitorPopoverRow(label: "Quota", value: MonitorDisplayValue.remainingQuota(snapshot))
                    MonitorPopoverRow(label: "Reset Credit", value: MonitorDisplayValue.reset(snapshot))
                }

                MonitorDivider().padding(.vertical, 14)

                // Block 3 — product actions only.
                VStack(spacing: 6) {
                    if preferences.showUsageMenu { popoverAction("Usage", symbol: "chart.bar", action: actions.showUsage) }
                    if preferences.showSettingsMenu { popoverAction("Settings", symbol: "gearshape", action: actions.showSettings) }
                    popoverAction(preferences.showOrb ? "Hide Floating Window" : "Show Floating Window", symbol: preferences.showOrb ? "eye.slash" : "eye", action: actions.toggleOrb)
                    popoverAction("Open Codex", symbol: "arrow.up.right.square", action: actions.openCodex)
                    popoverAction("Quit", symbol: "power", action: actions.quit)
                }
            }
            .padding(16)
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func popoverAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 16).imageScale(.small)
                Text(title).font(.system(size: 13))
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
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
    }
}

struct UsageWindowView: View {
    @ObservedObject var model: MonitorAppModel

    var body: some View {
        let snapshot = model.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                UsageFactSection(title: "Account") {
                    UsageFactRow(label: "Account", value: "UNKNOWN")
                    UsageFactRow(label: "Plan", value: "UNKNOWN")
                }
                UsageFactSection(title: "Session") {
                    UsageFactRow(label: "Current session", value: MonitorDisplayValue.taskTitle(snapshot))
                    UsageFactRow(label: "Session Token", value: MonitorDisplayValue.token(snapshot))
                }
                UsageFactSection(title: "Reset Credit") {
                    UsageFactRow(label: "Available", value: MonitorDisplayValue.reset(snapshot))
                    UsageFactRow(label: "Reset", value: resetTime(snapshot))
                }
                VStack(alignment: .leading, spacing: 13) {
                    MonitorSectionTitle(title: "Token Usage")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        UsageMetric(title: "Today cost", value: "$--")
                        UsageMetric(title: "Last 30 days cost", value: "$--")
                        UsageMetric(title: "Today Token", value: "UNKNOWN")
                        UsageMetric(title: "Last 30 days Token", value: MonitorDisplayValue.usage(snapshot))
                    }
                    UsageHistoryUnavailableChart()
                }
            }
            .padding(20)
        }
        .frame(minWidth: 560, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func resetTime(_ snapshot: MonitorRuntimeSnapshot?) -> String {
        let windows = [snapshot?.quota.primary, snapshot?.quota.secondary]
        guard let date = windows.compactMap({ $0?.resetsAt }).min() else { return "UNKNOWN" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct UsageFactSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            MonitorSectionTitle(title: title)
            VStack(alignment: .leading, spacing: 10) { content }
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
            Text(value).font(.system(size: 13, weight: .medium)).multilineTextAlignment(.trailing).lineLimit(2)
        }
    }
}

private struct UsageMetric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.52), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct UsageHistoryUnavailableChart: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 30 calendar days").font(.system(size: 13, weight: .medium))
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<30, id: \.self) { _ in
                    Capsule().fill(Color.secondary.opacity(0.16)).frame(maxWidth: .infinity).frame(height: 4)
                }
            }
            .frame(height: 58, alignment: .bottom)
            Text("UNAVAILABLE — no authoritative 30-day usage history")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Last 30 calendar days usage is unavailable")
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General", floating = "Floating", notifications = "Notifications", privacy = "Privacy", advanced = "Advanced", about = "About"
    var id: String { rawValue }
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
}

struct NativeSettingsWindowView: View {
    @ObservedObject var preferences: MonitorPreferences
    let showDiagnostics: () -> Void
    @State private var selection: SettingsSection? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            Group {
                switch selection ?? .general {
                case .general: UnavailableSettingsDetail(title: "General", message: "No additional General setting is currently backed by the frozen product capability contract.")
                case .floating: FloatingSettingsDetail(preferences: preferences)
                case .notifications: UnavailableSettingsDetail(title: "Notifications", message: "Notification controls are unavailable until a backed system permission and preference capability is implemented.")
                case .privacy: UnavailableSettingsDetail(title: "Privacy", message: "Privacy controls are unavailable until a backed preference capability is implemented.")
                case .advanced: AdvancedSettingsDetail(showDiagnostics: showDiagnostics)
                case .about: AboutSettingsDetail()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 600, minHeight: 420)
    }
}

private struct FloatingSettingsDetail: View {
    @ObservedObject var preferences: MonitorPreferences
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Floating").font(.system(size: 15, weight: .semibold))
            Form {
                Toggle("Show Floating Window", isOn: $preferences.showOrb).toggleStyle(.switch)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Floating Window Size")
                        Spacer()
                        Text("\(Int(preferences.orbSize)) pt").foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $preferences.orbSize, in: 72...180, step: 1)
                }
                Toggle("Show Usage in Menu", isOn: $preferences.showUsageMenu).toggleStyle(.switch)
                Toggle("Show Settings in Menu", isOn: $preferences.showSettingsMenu).toggleStyle(.switch)
            }
            .formStyle(.grouped)
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
            Text("Advanced").font(.system(size: 15, weight: .semibold))
            Text("Diagnostics is read-only and exposes no raw monitoring source controls.").font(.system(size: 13)).foregroundStyle(.secondary)
            Button("Open Diagnostics", action: showDiagnostics)
        }
        .padding(20)
    }
}

private struct AboutSettingsDetail: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About").font(.system(size: 15, weight: .semibold))
            Text("Codex Monitor\nLocal-first, read-only Codex status monitoring.").font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

struct DiagnosticsWindowView: View {
    @ObservedObject var model: MonitorAppModel
    var body: some View {
        let snapshot = model.snapshot
        Form {
            Section("Runtime") {
                LabeledContent("State", value: MonitorDisplayValue.state(snapshot))
                LabeledContent("Session", value: MonitorDisplayValue.taskTitle(snapshot))
            }
            Section("Source Health") {
                ForEach(MonitorRuntimeSource.allCases, id: \.rawValue) { source in
                    LabeledContent(MonitorDisplayValue.source(source), value: MonitorDisplayValue.availability(snapshot?.sourceHealth[source]?.availability))
                }
            }
            Section("Capabilities") {
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
