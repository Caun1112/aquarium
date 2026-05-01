import Foundation
import ServiceManagement

enum LaunchAtLoginManager {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static func apply(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Configuration writes are authoritative; login item registration may fail in
            // restrictive environments (eg. first-run permissions). Best effort.
        }
    }

    static func sync(with value: Bool) {
        let shouldBeEnabled = value
        if isEnabled != shouldBeEnabled {
            apply(shouldBeEnabled)
        }
    }
}
