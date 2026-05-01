import SwiftUI

@main
struct AquariumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let controller = AquariumController.shared
    private var settingsWindow: NSWindow?
    private var configPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureStatusIcon(for: item)
        item.menu = makeMenu()
        statusItem = item
        configPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.controller.reload()
                self?.refreshStatusIcon()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.openSettings()
            self.controller.installHelperIfNeeded()
            if #available(macOS 13.0, *) {
                LaunchAtLoginManager.sync(with: self.controller.config.launchAtLogin)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        configPollTimer?.invalidate()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Enable", action: #selector(enable), keyEquivalent: "e"))
        menu.addItem(NSMenuItem(title: "Disable", action: #selector(disable), keyEquivalent: "d"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Aquarium", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        return menu
    }

    private func configureStatusIcon(for item: NSStatusItem) {
        item.button?.title = ""
        refreshStatusIcon(item: item)
    }

    private func refreshStatusIcon(item: NSStatusItem? = nil) {
        let item = item ?? statusItem
        let imageName = controller.config.enabled ? "fish.fill" : "fish"
        let image = NSImage(systemSymbolName: imageName, accessibilityDescription: "Aquarium")
            ?? NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "Aquarium")
        image?.isTemplate = true
        item?.button?.image = image
        item?.button?.imagePosition = .imageOnly
        item?.button?.toolTip = controller.config.enabled ? "Aquarium is enabled" : "Aquarium is disabled"
        item?.button?.contentTintColor = controller.config.enabled ? .controlAccentColor : .secondaryLabelColor
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView()
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Aquarium"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func enable() {
        controller.update { config in
            config.enabled = true
        }
        refreshStatusIcon()
    }

    @objc private func disable() {
        controller.update { config in
            config.enabled = false
        }
        refreshStatusIcon()
    }
}
