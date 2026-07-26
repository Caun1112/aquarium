import SwiftUI

struct SettingsView: View {
    @State private var controller = AquariumController.shared
    @State private var selectedFilterItem: FilterSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(nsImage: CoffeeCupIcon.settingsImage(isFull: controller.config.enabled))
                    .resizable()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.primary)
                    .accessibilityLabel(controller.config.enabled ? "满杯咖啡" : "空杯咖啡")
                Text("Aquarium")
                    .font(.headline)
                Text(appVersionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("启用", isOn: binding(\.enabled))
                    .toggleStyle(.checkbox)
            }

            Divider()

            Toggle("登录时启动", isOn: binding(\.launchAtLogin))
                .toggleStyle(.checkbox)

            Divider()

            Toggle("合盖时保持唤醒", isOn: binding(\.preventLidSleep))
                .toggleStyle(.checkbox)
            Toggle("合盖时关闭亮度", isOn: binding(\.turnOffBrightnessWhenLidClosed))
                .toggleStyle(.checkbox)
            Toggle("启用时防止空闲锁屏", isOn: binding(\.preventScreenLockWhenLidClosed))
                .toggleStyle(.checkbox)

            Divider()

            Toggle("仅在选定的应用或进程运行时", isOn: binding(\.appFilterEnabled))
                .toggleStyle(.checkbox)
            if controller.config.appFilterEnabled {
                AppSelectionPanel(controller: controller, selectedFilterItem: $selectedFilterItem)
                    .frame(height: 104)
                CLIProcessSelectionPanel(controller: controller, selectedFilterItem: $selectedFilterItem)
                    .frame(height: 124)

                Divider()
            }

            BatteryRow(
                title: "仅在电池电量高于",
                isOn: binding(\.batteryGateEnabled),
                percent: batteryPercentBinding(\.minimumBatteryPercent)
            )
            BatteryRow(
                title: "电池电量低于时自动禁用",
                isOn: binding(\.autoDisableBatteryEnabled),
                percent: batteryPercentBinding(\.autoDisableBatteryPercent)
            )

            Divider()

            DiagnosticsPanel(controller: controller)

            HStack(spacing: 12) {
                Button("重新加载") {
                    controller.reload()
                    controller.refreshDiagnostics()
                }
                Button("安装助手") {
                    controller.installHelperIfNeeded()
                }
                .disabled(controller.helperInstallState == .installed || controller.helperInstallState == .installing)
                Spacer()
                Button("GitHub", systemImage: "chevron.left.forwardslash.chevron.right") {
                    openGitHub()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("打开 GitHub")
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(width: 460)
        .onAppear {
            controller.reload()
            controller.refreshDiagnostics()
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
        guard let url = URL(string: "https://github.com/Caun1112/aquarium") else { return }
        NSWorkspace.shared.open(url)
    }
}

private enum FilterSelection: Equatable {
    case app(String)
    case cliProcess(String)
    case cliDraft
}

private struct DiagnosticsPanel: View {
    let controller: AquariumController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("状态诊断")
                .font(.subheadline)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                DiagnosticRow(title: "助手", value: helperStatusText)
                DiagnosticRow(title: "启动服务", value: controller.helperDiagnostics.launchdState)
                DiagnosticRow(title: "助手文件", value: controller.helperDiagnostics.helperMatchesBundle ? "已安装且匹配" : "缺失或版本不匹配")
                DiagnosticRow(title: "禁用合盖睡眠", value: enabledText(controller.helperDiagnostics.clamshellSleepDisabled))
                DiagnosticRow(title: "防止显示器休眠", value: enabledText(controller.helperDiagnostics.preventsDisplaySleep))
                DiagnosticRow(title: "防止系统空闲睡眠", value: enabledText(controller.helperDiagnostics.preventsSystemSleep))
                DiagnosticRow(title: "用户活跃声明", value: enabledText(controller.helperDiagnostics.declaresUserActive))
                if let latestLogLine = controller.helperDiagnostics.latestLogLine {
                    DiagnosticRow(title: "最近日志", value: latestLogLine)
                }
            }

            if shouldShowWarning {
                Text(warningText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var helperStatusText: String {
        switch controller.helperInstallState {
        case .unknown:
            return "检查中"
        case .installed:
            return "运行中"
        case .missing:
            return "需要修复"
        case .installing:
            return "正在安装"
        case .failed(let message):
            return "安装失败：\(message)"
        }
    }

    private var shouldShowWarning: Bool {
        controller.config.enabled && !controller.helperDiagnostics.lockProtectionActive
    }

    private var warningText: String {
        controller.helperDiagnostics.installedAndRunning
            ? "Aquarium 已启用，但空闲锁屏防护尚未全部生效。"
            : "Aquarium 已启用，但助手未正常运行；应用会尝试自动修复。"
    }

    private func enabledText(_ enabled: Bool) -> String {
        enabled ? "生效" : "未生效"
    }
}

private struct DiagnosticRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
            Text(value)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.caption)
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
                    Text("未选择应用")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 4) {
                Button("添加应用", systemImage: "plus") {
                    controller.addApps()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("添加应用")

                Divider().frame(height: 14)

                Button("移除选定的应用", systemImage: "minus") {
                    if case .app(let id) = selectedFilterItem {
                        controller.removeApp(id: id)
                        selectedFilterItem = nil
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(!hasValidAppSelection)
                .controlSize(.small)
                .help("移除选定的应用")

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
                    Text("未选择进程")
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
                Button("添加进程", systemImage: "plus") {
                    beginDraft()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("添加进程")

                Divider().frame(height: 14)

                Button("移除选定的进程", systemImage: "minus") {
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
                .help("移除选定的进程")

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
            TextField("进程名称，例如 python3", text: $name)
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
