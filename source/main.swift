import Foundation
import AppKit
import IOKit

// Only USB attachment metadata is observed. No key events are read.
let label = "local.display-switch"
let fm = FileManager.default
let support = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Display Switch")
let logs = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Display Switch")
let agent = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
let installedBinary = support.appendingPathComponent("display-switch")
let installedConfiguration = support.appendingPathComponent("config.json")
let domain = "gui/\(getuid())"

func log(_ text: String) { print("\(ISO8601DateFormatter().string(from: Date())) \(text)") }
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
struct Configuration: Codable {
    let usbVendorID: Int
    let usbProductID: Int
    let monitorNameContains: String
    let inputCode: Int
    let inputName: String?
    let settleDelaySeconds: Double?
    let wakeSuppressionSeconds: Double?

    var displayInputName: String { inputName ?? "DDC input \(inputCode)" }
    var settleDelay: Double { settleDelaySeconds ?? 0.8 }
    var wakeSuppression: Double { wakeSuppressionSeconds ?? 8 }

    func validate() throws {
        guard (1...65535).contains(usbVendorID), (0...65535).contains(usbProductID) else {
            throw ConfigurationError("USB vendor and product IDs must be decimal numbers in the 16-bit range (vendor ID must be nonzero).")
        }
        guard !monitorNameContains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigurationError("monitorNameContains must identify a monitor; it cannot be empty.")
        }
        guard (1...255).contains(inputCode) else {
            throw ConfigurationError("inputCode must be a decimal DDC input value from 1 to 255.")
        }
        if let name = inputName, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ConfigurationError("inputName must be nonempty when provided.")
        }
        guard settleDelay.isFinite, (0...30).contains(settleDelay),
              wakeSuppression.isFinite, (0...120).contains(wakeSuppression) else {
            throw ConfigurationError("settleDelaySeconds must be between 0 and 30, and wakeSuppressionSeconds between 0 and 120.")
        }
    }
}
struct ConfigurationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
func loadConfiguration(_ path: String) throws -> Configuration {
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    let size = try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber
    guard let size = size, size.intValue <= 65536 else {
        throw ConfigurationError("Configuration must be a JSON file no larger than 64 KiB.")
    }
    let data = try Data(contentsOf: url)
    let allowed: Set<String> = ["usbVendorID", "usbProductID", "monitorNameContains", "inputCode", "inputName", "settleDelaySeconds", "wakeSuppressionSeconds"]
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ConfigurationError("Configuration must be a JSON object.")
    }
    let unknown = Set(object.keys).subtracting(allowed)
    guard unknown.isEmpty else {
        throw ConfigurationError("Unknown configuration fields: \(unknown.sorted().joined(separator: ", ")).")
    }
    let configuration = try JSONDecoder().decode(Configuration.self, from: data)
    try configuration.validate()
    return configuration
}

struct Request: Encodable {
    let uuid: String
    let commands: [String]
    let parameters: [String: String?]
}
struct Response: Decodable {
    let uuid: String?
    let result: Bool?
    let payload: String?
}
final class BetterDisplay: NSObject {
    let center = DistributedNotificationCenter.default()
    var callbacks: [String: (Response?) -> Void] = [:]
    override init() {
        super.init()
        center.addObserver(self, selector: #selector(receive(_:)),
            name: .init("pro.betterdisplay.BetterDisplay.response"), object: nil)
    }
    @objc func receive(_ notification: Notification) {
        guard let text = notification.object as? String,
              let response = try? JSONDecoder().decode(Response.self, from: Data(text.utf8)),
              let id = response.uuid,
              let callback = callbacks.removeValue(forKey: id) else { return }
        callback(response)
    }
    func send(_ operation: String, _ parameters: [String: String?], completion: @escaping (Response?) -> Void) {
        let id = UUID().uuidString
        callbacks[id] = completion
        let request = Request(uuid: id, commands: [operation], parameters: parameters)
        guard let data = try? JSONEncoder().encode(request) else {
            callbacks.removeValue(forKey: id)?(nil)
            return
        }
        center.postNotificationName(.init("pro.betterdisplay.BetterDisplay.request"),
            object: String(decoding: data, as: UTF8.self), userInfo: nil, deliverImmediately: true)
        Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            self?.callbacks.removeValue(forKey: id)?(nil)
        }
    }
    func query(_ configuration: Configuration) -> Response? {
        var done = false
        var response: Response?
        send("get", ["originalNameLike": configuration.monitorNameContains, "identifiers": nil]) {
            response = $0
            done = true
        }
        withExtendedLifetime(self) {
            while !done { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        }
        return response
    }
}

final class Watcher {
    let configuration: Configuration
    let dryRun: Bool
    let betterDisplay = BetterDisplay()
    var initial = true
    var present = Set<UInt64>()
    var generation = 0
    var pending: Timer?
    var sleeping = false
    var suppressUntil = Date.distantPast
    var sleepObservers: [NSObjectProtocol] = []
    var port: IONotificationPortRef?
    var added: io_iterator_t = 0
    var removed: io_iterator_t = 0

    init(configuration: Configuration, dryRun: Bool) {
        self.configuration = configuration
        self.dryRun = dryRun
    }
    func matching() -> CFDictionary {
        ["IOProviderClass": "IOUSBHostDevice", "idVendor": configuration.usbVendorID, "idProduct": configuration.usbProductID] as CFDictionary
    }
    func cancel() {
        generation += 1
        pending?.invalidate()
        pending = nil
    }
    func consume(_ iterator: io_iterator_t, arrival: Bool) {
        while true {
            let device = IOIteratorNext(iterator)
            if device == 0 { break }
            var id: UInt64 = 0
            let result = IORegistryEntryGetRegistryEntryID(device, &id)
            IOObjectRelease(device)
            guard result == KERN_SUCCESS else { continue }
            if arrival {
                let wasAbsent = present.isEmpty
                let inserted = present.insert(id).inserted
                if !initial && inserted && wasAbsent { arrived() }
            } else {
                present.remove(id)
                if present.isEmpty { cancel() }
                if !initial { log("USB device disconnected: ignored.") }
            }
        }
    }
    func arrived() {
        cancel()
        guard !sleeping, Date() >= suppressUntil else {
            log("USB device arrival during sleep/wake settling: ignored.")
            return
        }
        let current = generation
        log("USB device arrived; waiting briefly for the USB connection to settle.")
        pending = Timer.scheduledTimer(withTimeInterval: configuration.settleDelay, repeats: false) { [weak self] _ in
            guard let self = self, self.generation == current, !self.present.isEmpty,
                  !self.sleeping, Date() >= self.suppressUntil else { return }
            if self.dryRun {
                log("TEST ONLY: would select \(self.configuration.displayInputName). No display command sent.")
                return
            }
            self.selectInput(generation: current, attempt: 1)
        }
    }
    func selectInput(generation current: Int, attempt: Int) {
        guard generation == current, !present.isEmpty, !sleeping else { return }
        betterDisplay.send("set", ["originalNameLike": configuration.monitorNameContains, "feature": "ddc",
            "vcp": "inputSelect", "value": String(configuration.inputCode)]) { [weak self] response in
            guard let self = self, self.generation == current else { return }
            if response?.result == true {
                log("BetterDisplay accepted selection of \(self.configuration.displayInputName).")
            } else if attempt < 2 && !self.present.isEmpty && !self.sleeping {
                log("Input request failed or timed out; one retry in two seconds.")
                self.pending = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                    self?.selectInput(generation: current, attempt: 2)
                }
            } else {
                log("Input selection failed. Check BetterDisplay is running, notification integration is enabled, and the monitor accepts commands from this input.")
            }
        }
    }
    func run(duration: Double? = nil) {
        guard let port = IONotificationPortCreate(kIOMainPortDefault),
              let source = IONotificationPortGetRunLoopSource(port) else { fail("USB notifications are unavailable.") }
        self.port = port
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source.takeUnretainedValue(), .defaultMode)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let addResult = IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, matching(),
            { context, iterator in Unmanaged<Watcher>.fromOpaque(context!).takeUnretainedValue().consume(iterator, arrival: true) },
            context, &added)
        guard addResult == KERN_SUCCESS else { fail("USB arrival registration failed: \(addResult)") }
        consume(added, arrival: true)
        let removeResult = IOServiceAddMatchingNotification(port, kIOTerminatedNotification, matching(),
            { context, iterator in Unmanaged<Watcher>.fromOpaque(context!).takeUnretainedValue().consume(iterator, arrival: false) },
            context, &removed)
        guard removeResult == KERN_SUCCESS else { fail("USB removal registration failed: \(removeResult)") }
        consume(removed, arrival: false)
        let notifications = NSWorkspace.shared.notificationCenter
        sleepObservers.append(notifications.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = true
            self?.cancel()
        })
        sleepObservers.append(notifications.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = false
            if let self = self { self.suppressUntil = Date().addingTimeInterval(self.configuration.wakeSuppression) }
            self?.cancel()
        })
        initial = false
        log("\(dryRun ? "TEST" : "LIVE") watcher ready for \(configuration.displayInputName). USB device \(present.isEmpty ? "absent" : "present"); initial state ignored.")
        if let duration = duration { CFRunLoopRunInMode(.defaultMode, duration, false) }
        else { CFRunLoopRun() }
        pending?.invalidate()
        for observer in sleepObservers { notifications.removeObserver(observer) }
        IOObjectRelease(added)
        IOObjectRelease(removed)
        IONotificationPortDestroy(port)
    }
}

@discardableResult func launchctl(_ arguments: [String], quiet: Bool = false) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    if quiet {
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
    }
    do { try process.run(); process.waitUntilExit(); return process.terminationStatus }
    catch { fail("Unable to run launchctl: \(error.localizedDescription)") }
}

func enable(configuration: Configuration, dryRun: Bool) throws {
    if !dryRun {
        let client = BetterDisplay()
        guard let response = withExtendedLifetime(client, { client.query(configuration) }), response.result == true,
              let payload = response.payload, payload.localizedCaseInsensitiveContains(configuration.monitorNameContains) else {
            fail("Could not find the configured monitor through BetterDisplay. Open BetterDisplay and enable notification integration under Settings > Application > Integration, then retry. Any existing installation was left unchanged.")
        }
    }
    let isLoaded = launchctl(["print", "\(domain)/\(label)"], quiet: true) == 0
    if isLoaded && launchctl(["bootout", "\(domain)/\(label)"]) != 0 {
        fail("Could not stop the existing helper. Its installed files were left unchanged; the new mode was not enabled.")
    }
    for directory in [support, logs, agent.deletingLastPathComponent()] {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let source = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    if source != installedBinary.standardizedFileURL {
        let temporary = support.appendingPathComponent("display-switch.new")
        if fm.fileExists(atPath: temporary.path) { try fm.removeItem(at: temporary) }
        try fm.copyItem(at: source, to: temporary)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
        if fm.fileExists(atPath: installedBinary.path) { try fm.removeItem(at: installedBinary) }
        try fm.moveItem(at: temporary, to: installedBinary)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(configuration).write(to: installedConfiguration, options: .atomic)
    var args = [installedBinary.path, "watch", installedConfiguration.path]
    if dryRun { args.append("--dry-run") }
    let plist: [String: Any] = ["Label": label, "ProgramArguments": args,
        "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 15,
        "ProcessType": "Background", "LimitLoadToSessionType": "Aqua",
        "StandardOutPath": logs.appendingPathComponent("events.log").path,
        "StandardErrorPath": logs.appendingPathComponent("events.log").path]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agent, options: .atomic)
    launchctl(["enable", "\(domain)/\(label)"], quiet: true)
    guard launchctl(["bootstrap", domain, agent.path]) == 0 else {
        try? fm.removeItem(at: agent)
        fail("Could not start the helper. Run Enable from Raycast in your normal logged-in Mac session.")
    }
    // bootstrap alone can leave the job loaded but unspawned until the next login; kickstart forces it to start now.
    guard launchctl(["kickstart", "\(domain)/\(label)"], quiet: true) == 0 else {
        fail("The helper was installed, but could not be started now. Run Enable from Raycast in your normal logged-in Mac session.")
    }
    print("\(dryRun ? "Test mode" : "Monitor follow") enabled for \(configuration.displayInputName). Existing connections were ignored. Switch the USB connection away and back to test.")
}

setbuf(stdout, nil)
let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { fail("Commands: validate config.json, check [config.json] [--show-identifiers], enable [config.json], test [config.json], pause, status, watch config.json [--dry-run] [--once]") }
do {
    switch command {
    case "validate":
        guard args.count == 2 else { fail("Usage: validate config.json") }
        let configuration = try loadConfiguration(args[1])
        print("Configuration valid: \(configuration.displayInputName).")
    case "check":
        let options = Array(args.dropFirst())
        let paths = options.filter { !$0.hasPrefix("--") }
        guard paths.count <= 1, options.filter({ $0.hasPrefix("--") }).allSatisfy({ $0 == "--show-identifiers" }) else {
            fail("Usage: check [config.json] [--show-identifiers]")
        }
        let configuration = try loadConfiguration(paths.first ?? installedConfiguration.path)
        let client = BetterDisplay()
        guard let response = withExtendedLifetime(client, { client.query(configuration) }) else {
            fail("No BetterDisplay response. Run this check from Raycast with BetterDisplay open and notification integration enabled.")
        }
        guard response.result == true, let payload = response.payload,
              payload.localizedCaseInsensitiveContains(configuration.monitorNameContains) else {
            fail("BetterDisplay did not find the configured monitor.")
        }
        print("BetterDisplay connection confirmed for \(configuration.monitorNameContains).")
        if options.contains("--show-identifiers") { print(payload) }
    case "enable", "test":
        guard args.count <= 2 else { fail("Usage: \(command) [config.json]") }
        let configuration = try loadConfiguration(args.count == 2 ? args[1] : installedConfiguration.path)
        try enable(configuration: configuration, dryRun: command == "test")
    case "pause":
        guard args.count == 1 else { fail("Usage: pause") }
        let isLoaded = launchctl(["print", "\(domain)/\(label)"], quiet: true) == 0
        if isLoaded && launchctl(["bootout", "\(domain)/\(label)"]) != 0 {
            fail("Could not stop the helper. The login configuration was left in place; pause has not been confirmed.")
        }
        if fm.fileExists(atPath: agent.path) { try fm.removeItem(at: agent) }
        print("Monitor follow paused, including at the next login. Run Enable to resume.")
    case "status":
        guard args.count == 1 else { fail("Usage: status") }
        let running = launchctl(["print", "\(domain)/\(label)"], quiet: true) == 0
        print(running ? "Helper loaded." : "Helper not loaded.")
        if let data = try? Data(contentsOf: agent),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let program = plist["ProgramArguments"] as? [String], program.count >= 3 {
            if let configuration = try? loadConfiguration(program[2]) {
                print("Input: \(configuration.displayInputName). Mode: \(program.contains("--dry-run") ? "test only" : "live").")
            } else {
                print("Configuration unavailable or from an older installation. Run the installer to update it.")
            }
        }
        let logFile = logs.appendingPathComponent("events.log")
        if let text = try? String(contentsOf: logFile, encoding: .utf8) {
            print(text.split(separator: "\n").suffix(12).joined(separator: "\n"))
        }
    case "watch":
        guard args.count >= 2 else { fail("Specify a configuration file.") }
        guard args.dropFirst(2).allSatisfy({ ["--dry-run", "--once"].contains($0) }) else { fail("Unknown watcher option.") }
        let configuration = try loadConfiguration(args[1])
        Watcher(configuration: configuration, dryRun: args.contains("--dry-run")).run(duration: args.contains("--once") ? 1 : nil)
    default: fail("Unknown command: \(command)")
    }
} catch { fail(error.localizedDescription) }
