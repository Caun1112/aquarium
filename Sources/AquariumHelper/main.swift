import Foundation
import Darwin
import CoreGraphics
import IOKit.ps

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
        rotateLogIfNeeded()
        log("aquarium-helper started with config \(configPath)")
        while true {
            autoreleasepool {
                applyOnce()
            }
            Thread.sleep(forTimeInterval: 1)
        }
    }

    private func applyOnce() {
        var config: AquariumConfig
        do {
            config = try AquariumConfigStore.load(path: configPath)
        } catch {
            log("配置加载失败: \(error.localizedDescription)，使用默认配置")
            config = AquariumConfig()
            // 尝试保存默认配置
            do {
                try AquariumConfigStore.save(config, path: configPath)
                log("已恢复默认配置")
            } catch {
                log("无法保存默认配置: \(error.localizedDescription)")
            }
        }
        config.normalizeForSave(previous: nil)

        let batteryPercent = batteryPercent()

        if shouldAutoDisable(config, batteryPercent: batteryPercent) {
            config.enabled = false
            try? AquariumConfigStore.save(config, path: configPath)
            sessionStarted = false
            log("auto-disabled below \(config.autoDisableBatteryPercent)% battery")
        }

        let appAllowed = appGateAllows(config)
        let batteryAllowed = batteryGateAllows(config, batteryPercent: batteryPercent)
        if !config.enabled || !appAllowed || !batteryAllowed {
            sessionStarted = false
        } else if !sessionStarted {
            sessionStarted = true
        }

        let active = config.enabled && appAllowed && sessionStarted
        logPolicyIfChanged(config: config, batteryPercent: batteryPercent, appAllowed: appAllowed, batteryAllowed: batteryAllowed, active: active)
        let shouldDisableSystemSleep = active && config.preventLidSleep
        applyClamshellSleepDisabled(shouldDisableSystemSleep)
        applyBrightnessPolicy(active: active, config: config)
    }

    private func logPolicyIfChanged(config: AquariumConfig, batteryPercent: Int?, appAllowed: Bool, batteryAllowed: Bool, active: Bool) {
        let summary = [
            "enabled=\(config.enabled)",
            "preventLidSleep=\(config.preventLidSleep)",
            "appFilterEnabled=\(config.appFilterEnabled)",
            "appAllowed=\(appAllowed)",
            "batteryAllowed=\(batteryAllowed)",
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

        if lastLidClosed != lidClosed {
            log("合盖状态变化: \(lidClosed ? "已合盖" : "已打开")")
        }

        defer { lastLidClosed = lidClosed }

        guard active, config.turnOffBrightnessWhenLidClosed else {
            restoreBrightness()
            return
        }

        if lidClosed {
            dimBrightnessToBlack()
        } else if lastLidClosed == true {
            restoreBrightness()
        }
    }

    private func appGateAllows(_ config: AquariumConfig) -> Bool {
        guard config.appFilterEnabled else { return true }
        let apps = config.allowedApps.filter(\.enabled)
        let cliProcesses = config.allowedCLIProcesses.filter(\.enabled)
        guard !apps.isEmpty || !cliProcesses.isEmpty else {
            log("filter enabled but no enabled apps or processes are selected")
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

    private func batteryGateAllows(_ config: AquariumConfig, batteryPercent: Int?) -> Bool {
        guard config.batteryGateEnabled else { return true }
        guard let percent = batteryPercent else {
            return true
        }
        return percent >= config.minimumBatteryPercent
    }

    private func shouldAutoDisable(_ config: AquariumConfig, batteryPercent: Int?) -> Bool {
        guard config.enabled, config.autoDisableBatteryEnabled else { return false }
        guard let percent = batteryPercent else {
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
    let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as Array

    for source in sources {
        guard let description = IOPSGetPowerSourceDescription(info, source).takeUnretainedValue() as? [String: Any],
              description[kIOPSTypeKey as String] as? String == kIOPSInternalBatteryType,
              let current = description[kIOPSCurrentCapacityKey as String] as? Int,
              let maximum = description[kIOPSMaxCapacityKey as String] as? Int,
              maximum > 0 else {
            continue
        }
        return Int((Double(current) / Double(maximum) * 100).rounded())
    }

    log("battery read failed from IOKit power sources")
    return nil
}

private func dimBrightnessToBlack() {
    let displays = onlineDisplayIDs()
    guard !displays.isEmpty else {
        log("brightness dim skipped; no online displays")
        return
    }

    if !AquariumRuntimeState.loadBrightnessByDisplay().isEmpty {
        setBrightness(0, for: displays)
        return
    }

    var savedBrightness: [UInt32: Float] = [:]
    for display in displays {
        guard let brightness = brightness(for: display) else { continue }
        savedBrightness[display] = brightness
    }

    guard !savedBrightness.isEmpty else {
        log("brightness dim skipped; brightness read failed for displays \(displays)")
        return
    }

    AquariumRuntimeState.saveBrightnessByDisplay(savedBrightness)
    setBrightness(0, for: displays)
    let summary = savedBrightness
        .map { "\($0.key)=\($0.value)" }
        .sorted()
        .joined(separator: ",")
    log("brightness dimmed displays \(summary)")
}

private func restoreBrightness() {
    let savedBrightness = AquariumRuntimeState.loadBrightnessByDisplay()
    guard !savedBrightness.isEmpty else { return }

    for (display, brightness) in savedBrightness {
        let status = DisplayServicesSetBrightness(display, brightness)
        if status != 0 {
            log("brightness restore failed display=\(display) status=\(status)")
        }
    }

    AquariumRuntimeState.clearBrightness()
    log("brightness restored for \(savedBrightness.count) display(s)")
}

private func onlineDisplayIDs() -> [UInt32] {
    var discovered = [CGDirectDisplayID]()
    func append(_ display: CGDirectDisplayID) {
        guard display != 0, !discovered.contains(display) else { return }
        discovered.append(display)
    }

    append(CGMainDisplayID())

    var count: UInt32 = 0
    var status = CGGetOnlineDisplayList(0, nil, &count)
    if status != .success {
        log("display list count failed -> \(status.rawValue)")
    } else if count > 0 {
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        status = CGGetOnlineDisplayList(count, &displays, &count)
        if status == .success {
            for index in 0..<Int(count) {
                append(displays[index])
            }
        } else {
            log("online display list failed -> \(status.rawValue)")
        }
    }

    count = 0
    status = CGGetActiveDisplayList(0, nil, &count)
    if status != .success {
        log("active display list count failed -> \(status.rawValue)")
    } else if count > 0 {
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        status = CGGetActiveDisplayList(count, &displays, &count)
        if status == .success {
            for index in 0..<Int(count) {
                append(displays[index])
            }
        } else {
            log("active display list failed -> \(status.rawValue)")
        }
    }

    let dimmableDisplays = discovered.filter { display in
        CGDisplayIsBuiltin(display) != 0 || CGDisplayIsActive(display) != 0 || display == CGMainDisplayID()
    }
    logDisplaySnapshot(dimmableDisplays)
    return dimmableDisplays.map { UInt32($0) }
}

private func logDisplaySnapshot(_ displays: [CGDirectDisplayID]) {
    let summary = displays
        .map { display in
            [
                "id=\(display)",
                "main=\(display == CGMainDisplayID())",
                "builtin=\(CGDisplayIsBuiltin(display) != 0)",
                "active=\(CGDisplayIsActive(display) != 0)",
                "online=\(CGDisplayIsOnline(display) != 0)",
                "asleep=\(CGDisplayIsAsleep(display) != 0)"
            ].joined(separator: ":")
        }
        .joined(separator: ",")
    log("display snapshot [\(summary)]")
}

private func brightness(for display: UInt32) -> Float? {
    var brightness: Float = 1
    let status = DisplayServicesGetBrightness(display, &brightness)
    guard status == 0 else {
        log("brightness read failed display=\(display) status=\(status)")
        return nil
    }
    return brightness
}

private func setBrightness(_ value: Float, for displays: [UInt32]) {
    for display in displays {
        let status = DisplayServicesSetBrightness(display, value)
        if status != 0 {
            log("brightness set failed display=\(display) value=\(value) status=\(status)")
        }
    }
}

enum AquariumRuntimeState {
    static let path = "/Library/Application Support/Aquarium/brightness-before-lid-close"

    static func saveBrightnessByDisplay(_ values: [UInt32: Float]) {
        let encoded = Dictionary(uniqueKeysWithValues: values.map { (String($0.key), $0.value) })
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    static func loadBrightnessByDisplay() -> [UInt32: Float] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [:] }
        if let encoded = try? JSONDecoder().decode([String: Float].self, from: data) {
            return Dictionary(uniqueKeysWithValues: encoded.compactMap { key, value in
                guard let display = UInt32(key) else { return nil }
                return (display, value)
            })
        }

        if let raw = String(data: data, encoding: .utf8),
           let brightness = Float(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return [1: brightness]
        }

        return [:]
    }

    static func clearBrightness() {
        try? FileManager.default.removeItem(atPath: path)
    }
}

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write(Data("[\(stamp)] \(message)\n".utf8))
}

func rotateLogIfNeeded() {
    let logPath = "/Library/Logs/AquariumHelper.log"
    let maxSize: Int64 = 10 * 1024 * 1024 // 10MB
    let maxBackups = 3

    guard let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
          let fileSize = attrs[.size] as? Int64,
          fileSize > maxSize else {
        return
    }

    // 轮转旧日志
    for i in stride(from: maxBackups - 1, through: 1, by: -1) {
        let oldPath = "\(logPath).\(i)"
        let newPath = "\(logPath).\(i + 1)"
        try? FileManager.default.removeItem(atPath: newPath)
        try? FileManager.default.moveItem(atPath: oldPath, toPath: newPath)
    }

    // 移动当前日志
    try? FileManager.default.moveItem(atPath: logPath, toPath: "\(logPath).1")
    log("日志已轮转（大小: \(fileSize / 1024 / 1024)MB）")
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
case "diagnose":
    print("batteryPercent=\(batteryPercent().map(String.init) ?? "unknown")")
    print("lidClosed=\(isLidClosed())")
    let displays = onlineDisplayIDs()
    print("onlineDisplays=\(displays)")
    for display in displays {
        let currentBrightness = brightness(for: display).map { String($0) } ?? "unreadable"
        print("display \(display) brightness=\(currentBrightness)")
    }
    exit(0)
default:
    print("usage: aquarium-helper daemon|status|diagnose [--config path]")
    exit(64)
}
