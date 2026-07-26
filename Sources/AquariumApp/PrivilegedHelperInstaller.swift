import Foundation

enum HelperInstallState: Equatable {
    case unknown
    case installed
    case missing
    case installing
    case failed(String)
}

struct HelperDiagnostics: Equatable {
    var bundledFilesExist: Bool = false
    var helperExists: Bool = false
    var daemonPlistExists: Bool = false
    var helperMatchesBundle: Bool = false
    var daemonPlistMatchesBundle: Bool = false
    var launchdState: String = "未知"
    var launchdOutput: String = ""
    var clamshellSleepDisabled: Bool = false
    var preventsDisplaySleep: Bool = false
    var preventsSystemSleep: Bool = false
    var declaresUserActive: Bool = false
    var latestLogLine: String?

    var helperRunning: Bool {
        launchdState == "running"
    }

    var installedAndRunning: Bool {
        bundledFilesExist
            && helperExists
            && daemonPlistExists
            && helperMatchesBundle
            && daemonPlistMatchesBundle
            && helperRunning
    }

    var lockProtectionActive: Bool {
        clamshellSleepDisabled && preventsDisplaySleep && preventsSystemSleep && declaresUserActive
    }
}

enum PrivilegedHelperInstaller {
    static let label = "com.aquarium.helper"
    static let helperDestination = "/Library/PrivilegedHelperTools/com.aquarium.helper"
    static let daemonPlistDestination = "/Library/LaunchDaemons/com.aquarium.helper.plist"
    static let configDestination = AquariumConfig.defaultPath
    static let logPath = "/Library/Logs/AquariumHelper.log"

    static func isInstalled() -> Bool {
        diagnostics().installedAndRunning
    }

    static func diagnostics() -> HelperDiagnostics {
        let bundledFilesExist = bundledFilesExist()
        let helperExists = FileManager.default.fileExists(atPath: helperDestination)
        let daemonPlistExists = FileManager.default.fileExists(atPath: daemonPlistDestination)
        let helperMatchesBundle = bundledHelperMatchesInstalled()
        let daemonPlistMatchesBundle = bundledPlistMatchesInstalled()
        let launchdOutput = run("/bin/launchctl", ["print", "system/\(label)"])
        let powerSettingsOutput = run("/usr/bin/pmset", ["-g"])
        let assertionsOutput = run("/usr/bin/pmset", ["-g", "assertions"])
        let aquariumAssertionLines = assertionsOutput
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.contains("com.aquarium.helper") || $0.contains("Aquarium") }

        return HelperDiagnostics(
            bundledFilesExist: bundledFilesExist,
            helperExists: helperExists,
            daemonPlistExists: daemonPlistExists,
            helperMatchesBundle: helperMatchesBundle,
            daemonPlistMatchesBundle: daemonPlistMatchesBundle,
            launchdState: launchdState(from: launchdOutput),
            launchdOutput: launchdOutput,
            clamshellSleepDisabled: sleepDisabled(from: powerSettingsOutput),
            preventsDisplaySleep: aquariumAssertionLines.contains { $0.contains("PreventUserIdleDisplaySleep") },
            preventsSystemSleep: aquariumAssertionLines.contains { $0.contains("PreventUserIdleSystemSleep") },
            declaresUserActive: aquariumAssertionLines.contains { $0.contains("UserIsActive") },
            latestLogLine: latestLogLine()
        )
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

    private static func run(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let standardInput = FileHandle(forReadingAtPath: "/dev/null")
        process.standardInput = standardInput
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return String(describing: error)
        }
    }

    private static func launchdState(from output: String) -> String {
        output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("state = ") }?
            .replacingOccurrences(of: "state = ", with: "") ?? "未加载"
    }

    private static func sleepDisabled(from output: String) -> Bool {
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.count == 2,
               fields[0] == "SleepDisabled",
               fields[1] == "1" {
                return true
            }
        }
        return false
    }

    private static func latestLogLine() -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: logPath)),
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        return raw
            .split(separator: "\n")
            .last
            .map(String.init)
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
            "launchctl enable system/\(label)",
            "launchctl kickstart -k system/\(label)"
        ].joined(separator: "; ")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \(appleScriptString(script)) with administrator privileges"]
        let standardInput = FileHandle(forReadingAtPath: "/dev/null")
        process.standardInput = standardInput

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
