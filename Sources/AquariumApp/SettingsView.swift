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
    @State private var selectedAppID: String?
    private var hasValidAppSelection: Bool {
        selectedAppID != nil && controller.config.allowedApps.contains { $0.id == selectedAppID }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(controller.config.allowedApps) { app in
                            AppSelectionRow(
                                app: app,
                                isSelected: selectedAppID == app.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedAppID = (selectedAppID == app.id) ? nil : app.id
                            }
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
                    if let id = selectedAppID {
                        controller.removeApp(id: id)
                        selectedAppID = nil
                    }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 18)
                }
                .buttonStyle(.plain)
                .disabled(!hasValidAppSelection)
                .controlSize(.small)

                Spacer()
            }
            .padding(.horizontal, 4)
            .frame(height: 24)
        }
        .onAppear {
            if let selectedAppID, !controller.config.allowedApps.contains(where: { $0.id == selectedAppID }) {
                self.selectedAppID = nil
            }
        }
        .onChange(of: controller.config.allowedApps) { _, apps in
            if let selectedAppID, !apps.contains(where: { $0.id == selectedAppID }) {
                self.selectedAppID = nil
            }
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
    @State private var selectedProcessID: String?
    @FocusState private var draftIsFocused: Bool
    private var hasValidProcessSelection: Bool {
        selectedProcessID != nil && controller.config.allowedCLIProcesses.contains { $0.id == selectedProcessID }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(controller.config.allowedCLIProcesses) { process in
                            CLIProcessRow(
                                process: process,
                                isSelected: selectedProcessID == process.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedProcessID = (selectedProcessID == process.id) ? nil : process.id
                            }
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
                        if let id = selectedProcessID {
                            controller.removeCLIProcess(id: id)
                            selectedProcessID = nil
                        }
                    }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 18)
                }
                .buttonStyle(.borderless)
                .disabled(draftProcessName != nil ? false : !hasValidProcessSelection)
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
        .onAppear {
            if let selectedProcessID, !controller.config.allowedCLIProcesses.contains(where: { $0.id == selectedProcessID }) {
                self.selectedProcessID = nil
            }
        }
        .onChange(of: controller.config.allowedCLIProcesses) { _, processes in
            if let selectedProcessID, !processes.contains(where: { $0.id == selectedProcessID }) {
                self.selectedProcessID = nil
            }
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
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(process.name)
                .lineLimit(1)
            Spacer()
        }
        .padding(6)
        .frame(height: 30)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        .padding(.horizontal, 8)
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
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 22, height: 22)
            Text(app.name)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
    }
}
