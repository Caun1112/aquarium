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
        menu.addItem(menuItem("Open Settings", action: #selector(openSettings)))
        menu.addItem(menuItem("Enable", action: #selector(enable)))
        menu.addItem(menuItem("Disable", action: #selector(disable)))
        menu.addItem(.separator())
        menu.addItem(menuItem("GitHub", action: #selector(openGitHub)))
        menu.addItem(versionMenuItem())
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Aquarium", action: #selector(NSApplication.terminate(_:)), target: NSApp))
        menu.items.forEach { $0.target = self }
        return menu
    }

    private func menuItem(_ title: String, action: Selector, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuActionRow(title: title, target: target ?? self, action: action)
        return item
    }

    private func versionMenuItem() -> NSMenuItem {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        let suffix = build.map { " (\($0))" } ?? ""
        let item = NSMenuItem()
        item.view = MenuRowLabel(title: "Version \(version)\(suffix)")
        return item
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

    @objc private func openGitHub() {
        guard let url = URL(string: "https://github.com/ZimengXiong/aquarium") else { return }
        NSWorkspace.shared.open(url)
    }
}

private final class MenuActionRow: NSView {
    private let title: String
    private weak var target: AnyObject?
    private let action: Selector
    private var isHighlighted = false {
        didSet { needsDisplay = true }
    }

    init(title: String, target: AnyObject, action: Selector) {
        self.title = title
        self.target = target
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 38))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self))
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.controlAccentColor.setFill()
            bounds.insetBy(dx: 6, dy: 2).roundedPath(radius: 8).fill()
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: isHighlighted ? NSColor.selectedMenuItemTextColor : NSColor.labelColor
        ]
        let attributedTitle = NSAttributedString(string: title, attributes: attributes)
        let textRect = NSRect(
            x: 14,
            y: floor((bounds.height - attributedTitle.size().height) / 2),
            width: bounds.width - 28,
            height: attributedTitle.size().height
        )
        attributedTitle.draw(in: textRect)
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
    }

    override func mouseDown(with event: NSEvent) {
        guard let target else { return }
        NSApp.sendAction(action, to: target, from: self)
    }
}

private final class MenuRowLabel: NSTextField {
    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 32))
        stringValue = title
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        alignment = .left
        font = .systemFont(ofSize: NSFont.systemFontSize)
        textColor = .disabledControlTextColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private extension NSRect {
    func roundedPath(radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: self, xRadius: radius, yRadius: radius)
    }
}
