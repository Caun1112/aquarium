import SwiftUI

struct SettingsView: View {
    @State private var controller = AquariumController.shared
    @State private var selectedFilterItem: FilterSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: controller.config.enabled ? "fish.fill" : "fish")
                Text("Aquarium")
                    .font(.headline)
                Text(appVersionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

            Toggle("Only while selected apps or processes are running", isOn: binding(\.appFilterEnabled))
                .toggleStyle(.checkbox)
            if controller.config.appFilterEnabled {
                AppSelectionPanel(controller: controller, selectedFilterItem: $selectedFilterItem)
                    .frame(height: 104)
                CLIProcessSelectionPanel(controller: controller, selectedFilterItem: $selectedFilterItem)
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
                Button("GitHub", systemImage: "chevron.left.forwardslash.chevron.right") {
                    openGitHub()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Open GitHub")
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

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build.map { "v\(version) (\($0))" } ?? "v\(version)"
    }

    private func openGitHub() {
        guard let url = URL(string: "https://github.com/ZimengXiong/aquarium") else { return }
        NSWorkspace.shared.open(url)
    }
}

private enum FilterSelection: Equatable {
    case app(String)
    case cliProcess(String)
    case cliDraft
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
    @Binding var selectedFilterItem: FilterSelection?
    private var hasValidAppSelection: Bool {
        guard case .app(let selectedAppID) = selectedFilterItem else { return false }
        return controller.config.allowedApps.contains { $0.id == selectedAppID }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(controller.config.allowedApps) { app in
                            AppSelectionRow(
                                app: app,
                                isSelected: selectedFilterItem == .app(app.id)
                            )
                            .contentShape(Rectangle())
                            .simultaneousGesture(TapGesture().onEnded {
                                selectedFilterItem = .app(app.id)
                            })
                            if app.id != controller.config.allowedApps.last?.id {
                                Divider()
                                    .padding(.leading, 38)
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
                Button("Add application", systemImage: "plus") {
                    controller.addApps()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Add application")

                Divider().frame(height: 14)

                Button("Remove selected application", systemImage: "minus") {
                    if case .app(let id) = selectedFilterItem {
                        controller.removeApp(id: id)
                        selectedFilterItem = nil
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(!hasValidAppSelection)
                .controlSize(.small)
                .help("Remove selected application")

                Spacer()
            }
            .padding(.horizontal, 4)
            .frame(height: 24)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .onAppear {
            if case .app(let selectedAppID) = selectedFilterItem,
               !controller.config.allowedApps.contains(where: { $0.id == selectedAppID }) {
                selectedFilterItem = nil
            }
        }
        .onChange(of: controller.config.allowedApps) { _, apps in
            if case .app(let selectedAppID) = selectedFilterItem,
               !apps.contains(where: { $0.id == selectedAppID }) {
                selectedFilterItem = nil
            }
        }
    }
}

private struct CLIProcessSelectionPanel: View {
    let controller: AquariumController
    @Binding var selectedFilterItem: FilterSelection?
    @State private var draftProcessName: String?
    @FocusState private var draftIsFocused: Bool
    private var hasValidProcessSelection: Bool {
        guard case .cliProcess(let selectedProcessID) = selectedFilterItem else { return false }
        return controller.config.allowedCLIProcesses.contains { $0.id == selectedProcessID }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(controller.config.allowedCLIProcesses) { process in
                            CLIProcessRow(
                                process: process,
                                isSelected: selectedFilterItem == .cliProcess(process.id)
                            )
                            .contentShape(Rectangle())
                            .simultaneousGesture(TapGesture().onEnded {
                                draftProcessName = nil
                                selectedFilterItem = .cliProcess(process.id)
                            })
                            if process.id != controller.config.allowedCLIProcesses.last?.id {
                                Divider().padding(.leading, 34)
                            }
                        }

                        if draftProcessName != nil {
                            if !controller.config.allowedCLIProcesses.isEmpty {
                                Divider().padding(.leading, 34)
                            }
                            CLIProcessDraftRow(
                                name: Binding(
                                    get: { draftProcessName ?? "" },
                                    set: { draftProcessName = $0 }
                                ),
                                isSelected: selectedFilterItem == .cliDraft,
                                isFocused: $draftIsFocused,
                                onCommit: commitDraft
                            )
                        }
                    }
                }

                if controller.config.allowedCLIProcesses.isEmpty && draftProcessName == nil {
                    Text("No processes selected")
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
                Button("Add process", systemImage: "plus") {
                    beginDraft()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Add process")

                Divider().frame(height: 14)

                Button("Remove selected process", systemImage: "minus") {
                    if selectedFilterItem == .cliDraft {
                        draftProcessName = nil
                        selectedFilterItem = nil
                    } else if case .cliProcess(let id) = selectedFilterItem {
                        controller.removeCLIProcess(id: id)
                        selectedFilterItem = nil
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(selectedFilterItem == .cliDraft ? false : !hasValidProcessSelection)
                .controlSize(.small)
                .help("Remove selected process")

                Spacer()
            }
            .padding(.horizontal, 4)
            .frame(height: 24)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .onAppear {
            if case .cliProcess(let selectedProcessID) = selectedFilterItem,
               !controller.config.allowedCLIProcesses.contains(where: { $0.id == selectedProcessID }) {
                selectedFilterItem = nil
            }
        }
        .onChange(of: selectedFilterItem) { _, selection in
            if selection != .cliDraft {
                draftProcessName = nil
            }
        }
        .onChange(of: controller.config.allowedCLIProcesses) { _, processes in
            if case .cliProcess(let selectedProcessID) = selectedFilterItem,
               !processes.contains(where: { $0.id == selectedProcessID }) {
                selectedFilterItem = nil
            }
        }
    }

    private func beginDraft() {
        if draftProcessName == nil {
            draftProcessName = ""
        }
        selectedFilterItem = .cliDraft
        DispatchQueue.main.async {
            draftIsFocused = true
        }
    }

    private func commitDraft() {
        guard let rawName = draftProcessName else { return }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.draftProcessName = nil
        draftIsFocused = false

        guard !name.isEmpty else {
            selectedFilterItem = nil
            return
        }

        controller.addCLIProcess(named: name)
        selectedFilterItem = .cliProcess(name)
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
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
    }
}

private struct CLIProcessDraftRow: View {
    @Binding var name: String
    let isSelected: Bool
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
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
    }
}

private struct AppSelectionRow: View {
    let app: AllowedApp
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
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
