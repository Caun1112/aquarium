import Foundation
import Darwin

@_silgen_name("proc_listpids")
func procListPIDs(_ type: UInt32, _ typeinfo: UInt32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_pidpath")
func procPIDPath(_ pid: Int32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: UInt32) -> Int32

private let procPIDPathInfoMaxSize = 4096

@_silgen_name("DisplayServicesGetBrightness")
func DisplayServicesGetBrightness(_ display: UInt32, _ brightness: UnsafeMutablePointer<Float>) -> Int32

@_silgen_name("DisplayServicesSetBrightness")
func DisplayServicesSetBrightness(_ display: UInt32, _ brightness: Float) -> Int32

struct CommandResult {
    let status: Int32
    let output: String
}

final class CommandOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func store(_ newData: Data) {
        lock.lock()
        data = newData
        lock.unlock()
    }

    func load() -> Data {
        lock.lock()
        let current = data
        lock.unlock()
        return current
    }
}

@discardableResult
func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 3) -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        let finished = DispatchSemaphore(value: 0)
        let outputRead = DispatchSemaphore(value: 0)
        let output = CommandOutput()

        DispatchQueue.global(qos: .utility).async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            output.store(data)
            outputRead.signal()
        }

        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            finished.signal()
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                process.interrupt()
            }
            _ = outputRead.wait(timeout: .now() + 1)
            return CommandResult(status: 124, output: "Timed out running \(executable)")
        }

        _ = outputRead.wait(timeout: .now() + 1)
        let data = output.load()
        return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    } catch {
        return CommandResult(status: 127, output: String(describing: error))
    }
}

final class AquariumPolicyDaemon {
    private let configPath: String
    private var appliedDisablesleep: Bool?
    private var lastDisablesleepApply: Date?
    private var lastLidClosed: Bool?
    private var lastPolicySummary: String?
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

        let batteryPercent = batteryPercent()

        if shouldAutoDisable(config, batteryPercent: batteryPercent) {
            config.enabled = false
            try? AquariumConfigStore.save(config, path: configPath)
            sessionStarted = false
            log("auto-disabled below \(config.autoDisableBatteryPercent)% battery")
        }

        let appAllowed = appGateAllows(config)
        if !config.enabled || !appAllowed {
            sessionStarted = false
        } else if !sessionStarted && startBatteryGateAllows(config, batteryPercent: batteryPercent) {
            sessionStarted = true
        }

        let active = config.enabled && appAllowed && sessionStarted
        logPolicyIfChanged(config: config, batteryPercent: batteryPercent, appAllowed: appAllowed, active: active)
        let shouldDisableSystemSleep = active && config.preventLidSleep
        applyClamshellSleepDisabled(shouldDisableSystemSleep)
        applyBrightnessPolicy(active: active, config: config)
    }

    private func logPolicyIfChanged(config: AquariumConfig, batteryPercent: Int?, appAllowed: Bool, active: Bool) {
        let summary = [
            "enabled=\(config.enabled)",
            "preventLidSleep=\(config.preventLidSleep)",
            "appFilterEnabled=\(config.appFilterEnabled)",
            "appAllowed=\(appAllowed)",
            "battery=\(batteryPercent.map(String.init) ?? "unknown")",
            "startGate=\(config.batteryGateEnabled ? "\(config.minimumBatteryPercent)%" : "off")",
            "autoDisable=\(config.autoDisableBatteryEnabled ? "\(config.autoDisableBatteryPercent)%" : "off")",
            "sessionStarted=\(sessionStarted)",
            "active=\(active)"
        ].joined(separator: " ")

        guard summary != lastPolicySummary else { return }
        lastPolicySummary = summary
        log("policy \(summary)")
    }

    private func applyClamshellSleepDisabled(_ disabled: Bool) {
        if appliedDisablesleep == disabled,
           let lastDisablesleepApply,
           Date().timeIntervalSince(lastDisablesleepApply) < 30 {
            return
        }

        let result = run("/usr/bin/pmset", ["-a", "disablesleep", disabled ? "1" : "0"])
        if result.status == 0 {
            appliedDisablesleep = disabled
            lastDisablesleepApply = Date()
        }
        log("pmset disablesleep \(disabled ? "1" : "0") -> \(result.status)")
    }

    private func applyBrightnessPolicy(active: Bool, config: AquariumConfig) {
        let lidClosed = isLidClosed()
        defer { lastLidClosed = lidClosed }

        guard active, config.turnOffBrightnessWhenLidClosed else {
            restoreBrightness()
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
        let apps = config.allowedApps
        let cliProcesses = config.allowedCLIProcesses
        guard !apps.isEmpty || !cliProcesses.isEmpty else {
            log("filter enabled but no apps or processes are selected")
            return false
        }

        let runningProcesses = runningProcessSnapshot()

        let appMatches = apps.contains { app in
            runningProcesses.contains { $0.matches(app: app) }
        }
        let processMatches = cliProcesses.contains { selectedProcess in
            runningProcesses.contains { $0.matches(processName: selectedProcess.name) }
        }

        return appMatches || processMatches
    }

    private func startBatteryGateAllows(_ config: AquariumConfig, batteryPercent: Int?) -> Bool {
        guard config.batteryGateEnabled else { return true }
        guard let percent = batteryPercent else {
            log("battery unavailable; allowing start gate")
            return true
        }
        return percent >= config.minimumBatteryPercent
    }

    private func shouldAutoDisable(_ config: AquariumConfig, batteryPercent: Int?) -> Bool {
        guard config.enabled, config.autoDisableBatteryEnabled else { return false }
        guard let percent = batteryPercent else {
            log("battery unavailable; skipping auto-disable")
            return false
        }
        return percent < config.autoDisableBatteryPercent
    }
}

private func isLidClosed() -> Bool {
    let output = run("/usr/sbin/ioreg", ["-r", "-k", "AppleClamshellState", "-d", "1"]).output
    return output.contains("\"AppleClamshellState\" = Yes")
}

private struct RunningProcess {
    let pid: Int
    let executablePath: String
    let command: String

    var executableName: String {
        URL(fileURLWithPath: executablePath).lastPathComponent
    }

    var commandExecutablePath: String? {
        guard let first = command.split(whereSeparator: \.isWhitespace).first else { return nil }
        return String(first)
    }

    var usableCommandExecutablePath: String? {
        guard let commandExecutablePath else { return nil }
        if commandExecutablePath.hasPrefix("/") {
            return FileManager.default.fileExists(atPath: commandExecutablePath) ? commandExecutablePath : nil
        }
        guard !commandExecutablePath.contains("/") else { return nil }
        return commandExecutablePath
    }

    var commandExecutableName: String? {
        guard let path = usableCommandExecutablePath else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    func matches(app: AllowedApp) -> Bool {
        let appPath = standardizedPath(app.path)
        let executableNames = Set([
            app.executableName,
            URL(fileURLWithPath: app.path).deletingPathExtension().lastPathComponent
        ].map(normalizedProcessName).filter { !$0.isEmpty })

        if executableNames.contains(normalizedProcessName(executableName)) {
            return true
        }

        if let commandExecutableName,
           executableNames.contains(normalizedProcessName(commandExecutableName)) {
            return true
        }

        return pathIsInsideApp(executablePath, appPath: appPath)
            || commandContainsAppPath(command, appPath: appPath)
    }

    func matches(processName rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }

        if name.contains("/") {
            let selectedPath = standardizedPath(name)
            return standardizedPath(executablePath) == selectedPath
                || standardizedPath(usableCommandExecutablePath ?? "") == selectedPath
        }

        let selectedName = normalizedProcessName(name)
        return normalizedProcessName(executableName) == selectedName
            || normalizedProcessName(commandExecutableName ?? "") == selectedName
    }
}

private func runningProcessSnapshot() -> [RunningProcess] {
    let commands = runningCommandsByPID()

    return runningExecutablePathsByPID().map { pid, executablePath in
        RunningProcess(
            pid: pid,
            executablePath: executablePath,
            command: commands[pid] ?? executablePath
        )
    }
}

private func runningCommandsByPID() -> [Int: String] {
    let result = run("/bin/ps", ["-axo", "pid=,command="])
    return Dictionary(uniqueKeysWithValues: result.output
        .split(separator: "\n")
        .compactMap { line -> (Int, String)? in
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count == 2, let pid = Int(parts[0]) else {
                return nil
            }
            return (pid, parts[1])
        })
}

private func runningExecutablePathsByPID() -> [(Int, String)] {
    let probeSize = procListPIDs(UInt32(PROC_ALL_PIDS), 0, nil, 0)
    guard probeSize > 0 else { return [] }

    var pids = [pid_t](repeating: 0, count: Int(probeSize) / MemoryLayout<pid_t>.size)
    let bytes = pids.withUnsafeMutableBytes { buffer in
        procListPIDs(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
    }
    guard bytes > 0 else { return [] }

    return pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size).compactMap { pid -> (Int, String)? in
        guard pid > 0 else { return nil }
        var pathBuffer = [CChar](repeating: 0, count: procPIDPathInfoMaxSize)
        let pathLength = pathBuffer.withUnsafeMutableBytes { buffer in
            procPIDPath(pid, buffer.baseAddress, UInt32(buffer.count))
        }
        guard pathLength > 0 else { return nil }
        let path = String(decoding: pathBuffer.prefix(Int(pathLength)).map(UInt8.init(bitPattern:)), as: UTF8.self)
        guard !path.isEmpty else { return nil }
        return (Int(pid), path)
    }
}

private func normalizedProcessName(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func standardizedPath(_ value: String) -> String {
    URL(fileURLWithPath: value).standardizedFileURL.path
}

private func pathIsInsideApp(_ candidatePath: String, appPath: String) -> Bool {
    let path = standardizedPath(candidatePath)
    return path == appPath || path.hasPrefix(appPath + "/")
}

private func commandContainsAppPath(_ command: String, appPath: String) -> Bool {
    command
        .split(whereSeparator: \.isWhitespace)
        .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
        .contains { pathIsInsideApp($0, appPath: appPath) }
}

private func batteryPercent() -> Int? {
    let output = run("/usr/bin/pmset", ["-g", "batt"]).output
    guard let percentRange = output.range(of: #"(\d+)%"#, options: .regularExpression) else { return nil }
    return Int(output[percentRange].dropLast())
}

private func dimBrightnessToBlack() {
    guard AquariumRuntimeState.loadBrightness() == nil else {
        _ = DisplayServicesSetBrightness(1, 0)
        log("brightness already saved; dimmed without overwriting saved value")
        return
    }

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
