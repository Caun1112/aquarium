import Foundation

@_silgen_name("DisplayServicesGetBrightness")
func DisplayServicesGetBrightness(_ display: UInt32, _ brightness: UnsafeMutablePointer<Float>) -> Int32

@_silgen_name("DisplayServicesSetBrightness")
func DisplayServicesSetBrightness(_ display: UInt32, _ brightness: Float) -> Int32

struct CommandResult {
    let status: Int32
    let output: String
}

@discardableResult
func run(_ executable: String, _ arguments: [String]) -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    } catch {
        return CommandResult(status: 127, output: String(describing: error))
    }
}

final class AquariumPolicyDaemon {
    private let configPath: String
    private var appliedDisablesleep: Bool?
    private var lastLidClosed: Bool?
    private var brightnessBeforeLidClose: Float?
    private var sessionStarted = false

    init(configPath: String) {
        self.configPath = configPath
    }

    func runForever() -> Never {
        log("aquarium-helper started with config \(configPath)")
        while true {
            autoreleasepool {
                applyOnce()
            }
            Thread.sleep(forTimeInterval: 1)
        }
    }

    private func applyOnce() {
        var config = (try? AquariumConfigStore.load(path: configPath)) ?? AquariumConfig()
        config.normalizeForSave(previous: nil)

        if shouldAutoDisable(config) {
            config.enabled = false
            try? AquariumConfigStore.save(config, path: configPath)
            sessionStarted = false
            log("auto-disabled below \(config.autoDisableBatteryPercent)% battery")
        }

        let appAllowed = appGateAllows(config)
        if !config.enabled || !appAllowed {
            sessionStarted = false
        } else if !sessionStarted && startBatteryGateAllows(config) {
            sessionStarted = true
        }

        let active = config.enabled && appAllowed && sessionStarted
        let shouldDisableSystemSleep = active && config.preventLidSleep
        applyClamshellSleepDisabled(shouldDisableSystemSleep)
        applyBrightnessPolicy(active: active, config: config)
    }

    private func applyClamshellSleepDisabled(_ disabled: Bool) {
        guard appliedDisablesleep != disabled else { return }
        let result = run("/usr/bin/pmset", ["-a", "disablesleep", disabled ? "1" : "0"])
        appliedDisablesleep = result.status == 0 ? disabled : appliedDisablesleep
        log("pmset disablesleep \(disabled ? "1" : "0") -> \(result.status)")
    }

    private func applyBrightnessPolicy(active: Bool, config: AquariumConfig) {
        let lidClosed = isLidClosed()
        defer { lastLidClosed = lidClosed }

        guard active, config.turnOffBrightnessWhenLidClosed else {
            if brightnessBeforeLidClose != nil {
                restoreBrightness()
            }
            return
        }

        if lidClosed && lastLidClosed != true {
            dimBrightnessToBlack()
        } else if !lidClosed && lastLidClosed == true {
            restoreBrightness()
        }
    }

    private func appGateAllows(_ config: AquariumConfig) -> Bool {
        guard config.appFilterEnabled else { return true }
        let apps = config.allowedApps.filter(\.enabled)
        let cliProcesses = config.allowedCLIProcesses.filter(\.enabled)
        guard !apps.isEmpty || !cliProcesses.isEmpty else { return false }

        let running = Set(runningExecutableNames())
        return apps.contains { running.contains($0.executableName) }
            || cliProcesses.contains { running.contains($0.name) }
    }

    private func startBatteryGateAllows(_ config: AquariumConfig) -> Bool {
        guard config.batteryGateEnabled else { return true }
        guard let percent = batteryPercent() else { return false }
        return percent >= config.minimumBatteryPercent
    }

    private func shouldAutoDisable(_ config: AquariumConfig) -> Bool {
        guard config.enabled, config.autoDisableBatteryEnabled else { return false }
        guard let percent = batteryPercent() else { return false }
        return percent < config.autoDisableBatteryPercent
    }
}

private func isLidClosed() -> Bool {
    let output = run("/usr/sbin/ioreg", ["-r", "-k", "AppleClamshellState", "-d", "1"]).output
    return output.contains("\"AppleClamshellState\" = Yes")
}

private func runningExecutableNames() -> [String] {
    let result = run("/bin/ps", ["-axo", "comm="])
    return result.output
        .split(separator: "\n")
        .map { URL(fileURLWithPath: String($0)).lastPathComponent }
        .filter { !$0.isEmpty }
}

private func batteryPercent() -> Int? {
    let output = run("/usr/bin/pmset", ["-g", "batt"]).output
    guard let percentRange = output.range(of: #"(\d+)%"#, options: .regularExpression) else { return nil }
    return Int(output[percentRange].dropLast())
}

private func dimBrightnessToBlack() {
    var brightness: Float = 1
    let getResult = DisplayServicesGetBrightness(1, &brightness)
    guard getResult == 0 else {
        log("brightness read failed -> \(getResult)")
        return
    }

    AquariumRuntimeState.saveBrightness(brightness)
    _ = DisplayServicesSetBrightness(1, 0)
    log("brightness dimmed from \(brightness)")
}

private func restoreBrightness() {
    guard let brightness = AquariumRuntimeState.loadBrightness() else { return }
    _ = DisplayServicesSetBrightness(1, brightness)
    AquariumRuntimeState.clearBrightness()
    log("brightness restored to \(brightness)")
}

enum AquariumRuntimeState {
    static let path = "/Library/Application Support/Aquarium/brightness-before-lid-close"

    static func saveBrightness(_ value: Float) {
        try? String(value).write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func loadBrightness() -> Float? {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return Float(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func clearBrightness() {
        try? FileManager.default.removeItem(atPath: path)
    }
}

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write(Data("[\(stamp)] \(message)\n".utf8))
}

let args = CommandLine.arguments
let configPath: String = {
    guard let index = args.firstIndex(of: "--config"), args.indices.contains(index + 1) else {
        return AquariumConfig.defaultPath
    }
    return args[index + 1]
}()

switch args.dropFirst().first {
case "daemon":
    AquariumPolicyDaemon(configPath: configPath).runForever()
case "status":
    if let config = try? AquariumConfigStore.load(path: configPath) {
        print(config)
        exit(0)
    }
    print("No Aquarium config at \(configPath)")
    exit(1)
default:
    print("usage: aquarium-helper daemon|status [--config path]")
    exit(64)
}
