import SwiftUI

struct SettingsView: View {
    @State private var controller = AquariumController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: controller.config.enabled ? "fish.fill" : "fish")
                Text("Aquarium")
                    .font(.headline)
                Spacer()
                Toggle("Enabled", isOn: binding(\.enabled))
                    .toggleStyle(.checkbox)
            }

            Divider()

            Toggle("Launch at Login", isOn: binding(\.launchAtLogin))
                .toggleStyle(.checkbox)

            Divider()

            Toggle("Prevent sleep when lid is closed", isOn: binding(\.preventLidSleep))
                .toggleStyle(.checkbox)
            Toggle("Turn brightness off when lid is closed", isOn: binding(\.turnOffBrightnessWhenLidClosed))
                .toggleStyle(.checkbox)

            Divider()

            Toggle("Only while selected apps or CLI processes are running", isOn: binding(\.appFilterEnabled))
                .toggleStyle(.checkbox)
            if controller.config.appFilterEnabled {
                AppSelectionPanel(controller: controller)
                    .frame(height: 104)
                CLIProcessSelectionPanel(controller: controller)
                    .frame(height: 124)

                Divider()
            }

            BatteryRow(
                title: "Only start above battery level",
                isOn: binding(\.batteryGateEnabled),
                percent: batteryPercentBinding(\.minimumBatteryPercent)
            )
            BatteryRow(
                title: "Auto-disable when battery drops below",
                isOn: binding(\.autoDisableBatteryEnabled),
                percent: batteryPercentBinding(\.autoDisableBatteryPercent)
            )

            HStack(spacing: 12) {
                Button("Reload") { controller.reload() }
                Button("Install Helper") {
                    controller.installHelperIfNeeded()
                }
                .disabled(controller.helperInstallState == .installed || controller.helperInstallState == .installing)
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(width: 420)
        .onAppear {
            controller.reload()
            controller.installHelperIfNeeded()
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AquariumConfig, Value>) -> Binding<Value> {
        Binding(
            get: { controller.config[keyPath: keyPath] },
            set: { value in
                controller.update { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func batteryPercentBinding(_ keyPath: WritableKeyPath<AquariumConfig, Int>) -> Binding<Double> {
        Binding(
            get: { Double(controller.config[keyPath: keyPath]) },
            set: { value in
                controller.update { $0[keyPath: keyPath] = Int(value.rounded()) }
            }
        )
    }
}

private struct BatteryRow: View {
    let title: String
    @Binding var isOn: Bool
    @Binding var percent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.checkbox)
            HStack(spacing: 8) {
                Slider(value: $percent, in: 1...100)
                Text("\(Int(percent))%")
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
            .disabled(!isOn)
            .opacity(isOn ? 1 : 0.35)
            .padding(.leading, 22)
        }
    }
}

private struct AppSelectionPanel: View {
    let controller: AquariumController

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(controller.config.allowedApps) { app in
                            AppSelectionRow(
                                app: app,
                                isOn: Binding(
                                    get: { app.enabled },
                                    set: { controller.setAppEnabled(app, enabled: $0) }
                                )
                            )
                            if app.id != controller.config.allowedApps.last?.id {
                                Divider()
                                    .padding(.leading, 46)
                            }
                        }
                    }
                }

                if controller.config.allowedApps.isEmpty {
                    Text("No apps selected")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 4) {
                Button {
                    controller.addApps()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 18)
                }
                .buttonStyle(.plain)
                .controlSize(.small)

                Divider().frame(height: 14)

                Button {
                    controller.removeLastApp()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 18)
                }
                .buttonStyle(.plain)
                .disabled(controller.config.allowedApps.isEmpty)
                .controlSize(.small)

                Spacer()
            }
            .padding(.horizontal, 4)
            .frame(height: 24)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

private struct CLIProcessSelectionPanel: View {
    let controller: AquariumController
    @State private var draftProcessName: String?
    @FocusState private var draftIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(controller.config.allowedCLIProcesses) { process in
                            CLIProcessRow(
                                process: process,
                                isOn: Binding(
                                    get: { process.enabled },
                                    set: { controller.setCLIProcessEnabled(process, enabled: $0) }
                                )
                            )
                            if process.id != controller.config.allowedCLIProcesses.last?.id {
                                Divider().padding(.leading, 10)
                            }
                        }

                        if draftProcessName != nil {
                            if !controller.config.allowedCLIProcesses.isEmpty {
                                Divider().padding(.leading, 10)
                            }
                            CLIProcessDraftRow(
                                name: Binding(
                                    get: { draftProcessName ?? "" },
                                    set: { draftProcessName = $0 }
                                ),
                                isFocused: $draftIsFocused,
                                onCommit: commitDraft
                            )
                        }
                    }
                }

                if controller.config.allowedCLIProcesses.isEmpty && draftProcessName == nil {
                    Text("No CLI processes selected")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                        .padding(.horizontal, 8)
                    }
                }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 4) {
                Button {
                    beginDraft()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 18)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Divider().frame(height: 14)

                Button {
                    if draftProcessName != nil {
                        draftProcessName = nil
                    } else {
                        controller.removeLastCLIProcess()
                    }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 18)
                }
                .buttonStyle(.borderless)
                .disabled(controller.config.allowedCLIProcesses.isEmpty && draftProcessName == nil)
                .controlSize(.small)

                Spacer()
            }
            .padding(.horizontal, 4)
            .frame(height: 24)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .onChange(of: draftIsFocused) { _, focused in
            guard !focused else { return }
            finishDraft()
        }
    }

    private func beginDraft() {
        if draftProcessName == nil {
            draftProcessName = ""
        }
        DispatchQueue.main.async {
            draftIsFocused = true
        }
    }

    private func commitDraft() {
        guard let draftProcessName else { return }
        controller.addCLIProcess(named: draftProcessName)
        self.draftProcessName = nil
    }

    private func finishDraft() {
        guard let draftProcessName else { return }
        if draftProcessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.draftProcessName = nil
        } else {
            commitDraft()
        }
    }
}

private struct CLIProcessRow: View {
    let process: AllowedCLIProcess
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(process.name)
                .lineLimit(1)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
    }
}

private struct CLIProcessDraftRow: View {
    @Binding var name: String
    var isFocused: FocusState<Bool>.Binding
    let onCommit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            TextField("Process name, e.g. python3", text: $name)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .onSubmit(onCommit)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
    }
}

private struct AppSelectionRow: View {
    let app: AllowedApp
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 22, height: 22)
            Text(app.name)
                .lineLimit(1)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
    }
}
