import Foundation

enum HelperInstallState: Equatable {
    case unknown
    case installed
    case missing
    case installing
    case failed(String)
}

enum PrivilegedHelperInstaller {
    static let label = "com.aquarium.helper"
    static let helperDestination = "/Library/PrivilegedHelperTools/com.aquarium.helper"
    static let daemonPlistDestination = "/Library/LaunchDaemons/com.aquarium.helper.plist"
    static let configDestination = AquariumConfig.defaultPath

    static func isInstalled() -> Bool {
        guard bundledFilesExist(),
              FileManager.default.fileExists(atPath: helperDestination),
              FileManager.default.fileExists(atPath: daemonPlistDestination),
              bundledHelperMatchesInstalled(),
              bundledPlistMatchesInstalled() else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/\(label)"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func bundledFilesExist() -> Bool {
        Bundle.main.url(forResource: "com.aquarium.helper", withExtension: nil) != nil
            && Bundle.main.url(forResource: "com.aquarium.helper", withExtension: "plist") != nil
            && Bundle.main.url(forResource: "default-config", withExtension: "json") != nil
    }

    private static func bundledHelperMatchesInstalled() -> Bool {
        guard let helper = Bundle.main.url(forResource: "com.aquarium.helper", withExtension: nil) else {
            return false
        }
        return fileContentsMatch(helper.path, helperDestination)
    }

    private static func bundledPlistMatchesInstalled() -> Bool {
        guard let plist = Bundle.main.url(forResource: "com.aquarium.helper", withExtension: "plist") else {
            return false
        }
        return fileContentsMatch(plist.path, daemonPlistDestination)
    }

    private static func fileContentsMatch(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = try? Data(contentsOf: URL(fileURLWithPath: lhs)),
              let right = try? Data(contentsOf: URL(fileURLWithPath: rhs)) else {
            return false
        }
        return left == right
    }

    static func installFromBundle() throws {
        guard let helper = Bundle.main.url(forResource: "com.aquarium.helper", withExtension: nil),
              let plist = Bundle.main.url(forResource: "com.aquarium.helper", withExtension: "plist"),
              let config = Bundle.main.url(forResource: "default-config", withExtension: "json") else {
            throw InstallerError.missingBundledFiles
        }

        let script = [
            "set -e",
            "install -d -m 755 /Library/PrivilegedHelperTools",
            "install -m 755 \(shellQuote(helper.path)) \(shellQuote(helperDestination))",
            "install -d -m 775 -o root -g staff \(shellQuote((configDestination as NSString).deletingLastPathComponent))",
            "[ -f \(shellQuote(configDestination)) ] || install -m 664 -o root -g staff \(shellQuote(config.path)) \(shellQuote(configDestination))",
            "install -m 644 \(shellQuote(plist.path)) \(shellQuote(daemonPlistDestination))",
            "launchctl bootout system \(shellQuote(daemonPlistDestination)) 2>/dev/null || true",
            "launchctl bootstrap system \(shellQuote(daemonPlistDestination))",
            "launchctl enable system/\(label)"
        ].joined(separator: "; ")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \(appleScriptString(script)) with administrator privileges"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw InstallerError.installFailed(message.isEmpty ? "Authorization was cancelled or installation failed." : message)
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

enum InstallerError: LocalizedError {
    case missingBundledFiles
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledFiles:
            return "Aquarium is missing its bundled helper files."
        case .installFailed(let message):
            return message
        }
    }
}
