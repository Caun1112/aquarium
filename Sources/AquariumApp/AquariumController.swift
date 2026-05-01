import Foundation
import AppKit
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
final class AquariumController {
    static let shared = AquariumController()

    var config: AquariumConfig
    var statusMessage: String = ""
    var helperInstallState: HelperInstallState = .unknown

    private let path = AquariumConfig.defaultPath
    private var installStarted = false

    private init() {
        config = (try? AquariumConfigStore.load()) ?? AquariumConfig()
    }

    func reload() {
        helperInstallState = PrivilegedHelperInstaller.isInstalled() ? .installed : .missing
        do {
            config = try AquariumConfigStore.load(path: path)
            syncLaunchAtLogin()
            statusMessage = "Loaded helper configuration."
        } catch {
            statusMessage = helperInstallState == .installed ? "Waiting for helper configuration." : "Helper is not installed."
        }
    }

    func installHelperIfNeeded() {
        guard !installStarted else { return }
        reload()
        guard helperInstallState != .installed else { return }

        installStarted = true
        helperInstallState = .installing
        statusMessage = "Installing helper..."

        Task.detached(priority: .userInitiated) {
            let result: Result<Void, Error>
            do {
                try PrivilegedHelperInstaller.installFromBundle()
                result = .success(())
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                self.installStarted = false
                switch result {
                case .success:
                    self.helperInstallState = .installed
                    self.reload()
                    self.statusMessage = "Helper installed."
                case .failure(let error):
                    self.helperInstallState = .failed(error.localizedDescription)
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    func save() {
        update { _ in }
    }

    func update(_ change: (inout AquariumConfig) -> Void) {
        let previous = (try? AquariumConfigStore.load(path: path)) ?? config
        var next = config
        change(&next)
        next.normalizeForSave(previous: previous)

        do {
            try AquariumConfigStore.save(next, path: path)
            config = next
            syncLaunchAtLogin()
            statusMessage = next.enabled ? "Aquarium mode is active." : "Aquarium mode is off."
        } catch {
            statusMessage = "Could not write helper configuration."
            installHelperIfNeeded()
        }
    }

    func addApps() {
        let panel = NSOpenPanel()
        panel.title = "Choose Applications"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return }
        update { config in
            for url in panel.urls {
                guard let app = AllowedApp(url: url) else { continue }
                config.allowedApps.removeAll { $0.executableName == app.executableName }
                config.allowedApps.append(app)
            }
        }
    }

    func removeApps(at offsets: IndexSet) {
        update { config in
            for index in offsets.sorted(by: >) {
                config.allowedApps.remove(at: index)
            }
        }
    }

    func removeLastApp() {
        guard !config.allowedApps.isEmpty else { return }
        update { config in
            _ = config.allowedApps.popLast()
        }
    }

    func setAppEnabled(_ app: AllowedApp, enabled: Bool) {
        update { config in
            guard let index = config.allowedApps.firstIndex(where: { $0.executableName == app.executableName }) else { return }
            config.allowedApps[index].enabled = enabled
        }
    }

    func addCLIProcess(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        update { config in
            config.allowedCLIProcesses.removeAll { $0.name == name }
            config.allowedCLIProcesses.append(AllowedCLIProcess(name: name))
        }
    }

    func removeLastCLIProcess() {
        guard !config.allowedCLIProcesses.isEmpty else { return }
        update { config in
            _ = config.allowedCLIProcesses.popLast()
        }
    }

    func setCLIProcessEnabled(_ process: AllowedCLIProcess, enabled: Bool) {
        update { config in
            guard let index = config.allowedCLIProcesses.firstIndex(where: { $0.name == process.name }) else { return }
            config.allowedCLIProcesses[index].enabled = enabled
        }
    }

    private func syncLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            LaunchAtLoginManager.sync(with: config.launchAtLogin)
        }
    }
}

private extension AllowedApp {
    init?(url: URL) {
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let executableName = (bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String)
            ?? url.deletingPathExtension().lastPathComponent

        self.init(
            name: name,
            bundleIdentifier: bundle?.bundleIdentifier,
            executableName: executableName,
            path: url.path,
            enabled: true
        )
    }
}
