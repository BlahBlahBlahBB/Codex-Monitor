import SwiftUI
import CodexMonitorContracts

struct MonitorMainView: View {
    @ObservedObject var model: MonitorAppModel

    var body: some View {
        let snapshot = model.snapshot
        GlassSurface(cornerRadius: 28) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header(snapshot)
                    MonitorDivider()
                    currentTask(snapshot)
                    MonitorDivider()
                    accountSection(snapshot)

                    if snapshot?.currentState == .waitingApproval {
                        MonitorDivider()
                        Label("Waiting Approval", systemImage: "hand.raised.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .systemYellow))
                    }

                    MonitorDivider()
                    diagnostics(snapshot)
                }
                .padding(30)
            }
            .scrollIndicators(.hidden)
        }
        .padding(18)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.22))
        .frame(minWidth: 560, minHeight: 600)
    }

    private func header(_ snapshot: MonitorRuntimeSnapshot?) -> some View {
        HStack(alignment: .center, spacing: 18) {
            MonitorOrbView(snapshot: snapshot, size: 104)
            VStack(alignment: .leading, spacing: 6) {
                Text(MonitorDisplayValue.state(snapshot))
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .tracking(-0.45)
                Text(MonitorDisplayValue.activity(snapshot))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                Text("Codex Monitor")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            MonitorStatusCapsule(snapshot: snapshot)
        }
    }

    private func currentTask(_ snapshot: MonitorRuntimeSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitorSectionTitle(title: "Current Task")
            Text(snapshot?.currentThread?.taskTitle ?? MonitorDisplayValue.activity(snapshot))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
            if let thread = snapshot?.currentThread, let model = thread.model {
                Text(model)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func accountSection(_ snapshot: MonitorRuntimeSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitorSectionTitle(title: "Session & Account")
            MonitorValueRow(title: "Session Token", value: MonitorDisplayValue.token(snapshot))
            MonitorValueRow(title: "Usage", value: MonitorDisplayValue.usage(snapshot))
            MonitorValueRow(title: "Quota", value: MonitorDisplayValue.quota(snapshot))
            MonitorValueRow(title: "Reset", value: MonitorDisplayValue.reset(snapshot))
        }
    }

    private func diagnostics(_ snapshot: MonitorRuntimeSnapshot?) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                MonitorValueRow(title: "Thread", value: compactID(snapshot?.currentSessionThread?.threadID.rawID))
                MonitorValueRow(title: "Turn", value: compactID(snapshot?.currentSessionThread?.activeTurnID?.rawID))
                MonitorSectionTitle(title: "Source Health")
                ForEach(MonitorRuntimeSource.allCases, id: \.rawValue) { source in
                    MonitorValueRow(title: MonitorDisplayValue.source(source), value: MonitorDisplayValue.availability(snapshot?.sourceHealth[source]?.availability))
                }
                MonitorSectionTitle(title: "Capabilities")
                ForEach(MonitorRuntimeCapability.allCases, id: \.rawValue) { capability in
                    let value = snapshot?.capabilities[capability]
                    MonitorValueRow(title: MonitorDisplayValue.capability(capability), value: MonitorDisplayValue.availability(value?.availability))
                }
            }
            .padding(.top, 12)
        } label: {
            Text("Advanced Diagnostics")
                .font(.system(size: 13, weight: .medium))
        }
        .tint(.secondary)
    }

    private func compactID(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "UNAVAILABLE" }
        guard value.count > 18 else { return value }
        return "\(value.prefix(8))…\(value.suffix(6))"
    }
}

struct MonitorSettingsView: View {
    @ObservedObject var preferences: MonitorPreferences

    var body: some View {
        GlassSurface(cornerRadius: 22) {
            Form {
                Section {
                    Toggle("Show Floating Window", isOn: $preferences.showOrb)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Floating Window Size")
                            Spacer()
                            Text("\(Int(preferences.orbSize)) pt")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $preferences.orbSize, in: 72...180, step: 1)
                    }
                }
                Section {
                    Toggle("Show Usage in Menu", isOn: $preferences.showUsageMenu)
                    Toggle("Show Settings in Menu", isOn: $preferences.showSettingsMenu)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(18)
        }
        .padding(18)
        .frame(width: 440, height: 320)
    }
}
