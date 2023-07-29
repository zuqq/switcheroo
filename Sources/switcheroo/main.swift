import ArgumentParser
import Carbon
import CoreGraphics
import Foundation
import IOKit
import IOKit.hid
import os
import _switcheroo

enum SwitcherooError: CustomStringConvertible, Error {
    case failedToOpenConfigurationFile(String)
    case failedToReadConfigurationFile(String)
    case failedToRetrieveDevices
    case failedToRetrieveInputSources
    case failedToRetrieveActiveInputSource
    case unknownInputSource(ConfigurationEntry, String)
    case invalidNaturalScrollSetting(String)

    public var description: String {
        switch self {
        case .failedToOpenConfigurationFile(let path):
            return "Failed to open configuration file: \(path)"
        case .failedToReadConfigurationFile(let path):
            return "Failed to read configuration file: \(path)"
        case .failedToRetrieveDevices:
            return "Failed to retrieve device list from the operating system."
        case .failedToRetrieveInputSources:
            return "Failed to retrieve input source list from the operating system."
        case .failedToRetrieveActiveInputSource:
            return "Failed to retrieve active input source."
        case .unknownInputSource(let entry, let inputSource):
            return "Input source \(inputSource) in this configuration file entry is unknown: \(entry)"
        case .invalidNaturalScrollSetting(let desired):
            return "Invalid setting for natural scroll (only `false` and `true` are valid): \(desired)"
        }
    }
}

// This is static so that it can be used in callbacks passed to unmanaged code.
let logger = Logger(subsystem: "switcheroo", category: "main")

let naturalScrollKey = "com.apple.swipescrolldirection" as CFString

let naturalScrollNotification = NSNotification.Name("SwipeScrollDirectionDidChangeNotification")

func getNaturalScroll() -> Bool {
    // I wasn't able to find a getter corresponding to the `CGSSetSwipeScrollDirection` setter,
    // so let's just read the value from `System Preferences.app` and hope that it has a correct
    // view of the world.
    return CFPreferencesGetAppBooleanValue(naturalScrollKey, kCFPreferencesAnyApplication, nil)
}

func setNaturalScroll(_ naturalScroll: Bool) {
    let connection = _CGSDefaultConnection()
    CGSSetSwipeScrollDirection(connection, naturalScroll);
    CFPreferencesSetAppValue(naturalScrollKey, naturalScroll as CFBoolean, kCFPreferencesAnyApplication);
    CFPreferencesAppSynchronize(kCFPreferencesAnyApplication);
    DistributedNotificationCenter.default().postNotificationName(naturalScrollNotification, object: nil)
}

func createDeviceManager() -> IOHIDManager {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    let filter = [
        kIOProviderClassKey: kIOHIDDeviceKey,
        kIOHIDTransportKey: kIOHIDTransportUSBValue,
        kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop,
        kIOHIDPrimaryUsageKey: kHIDUsage_GD_Keyboard
    ] as [String: Any] as CFDictionary
    IOHIDManagerSetDeviceMatching(manager, filter)
    return manager
}

func getDeviceKey(_ device: IOHIDDevice) -> String? {
    if let key = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String {
        return key
    }
    return nil
}

func getInputSourceKey(_ source: TISInputSource) -> String? {
    if let pointerToKey = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
        return Unmanaged<CFString>.fromOpaque(pointerToKey).takeUnretainedValue() as String
    }
    return nil
}

func getInputSources() throws -> [String: TISInputSource] {
    let filter = [
        kTISPropertyInputSourceIsEnableCapable: true,
        kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource!
    ] as [CFString?: Any] as CFDictionary
    guard let inputSources = TISCreateInputSourceList(filter, false).takeRetainedValue() as? [TISInputSource] else {
        throw SwitcherooError.failedToRetrieveInputSources
    }
    var inputSourcesByKey: [String: TISInputSource] = [:]
    for inputSource in inputSources {
        if let key = getInputSourceKey(inputSource) {
            inputSourcesByKey[key] = inputSource
        }
    }
    return inputSourcesByKey
}

func getActiveInputSource() -> TISInputSource {
    return TISCopyCurrentKeyboardInputSource().takeRetainedValue()
}

func setInputSource(_ source: TISInputSource) {
    TISSelectInputSource(source)
}

public struct DeviceSelector: Decodable, Equatable, Hashable {
    let value: String

    public init(value: String) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        value = try decoder.singleValueContainer().decode(String.self)
    }

    public func matches(_ device: String) -> Bool {
        return device.contains(value)
    }
}

public struct Rules: Decodable, Equatable {
    let inputSource: String?
    let naturalScroll: Bool?

    public init(inputSource: String?, naturalScroll: Bool?) {
        self.inputSource = inputSource
        self.naturalScroll = naturalScroll
    }
}

public struct ConfigurationEntry: Decodable, Equatable {
    let selector: DeviceSelector
    let rules: Rules

    public init(selector: DeviceSelector, rules: Rules) {
        self.selector = selector
        self.rules = rules
    }
}

public struct Configuration: Decodable, Equatable {
    public let entries: [ConfigurationEntry]

    public init(entries: [ConfigurationEntry]) {
        self.entries = entries
    }

    public func validate(_ inputSources: Set<String>) throws {
        for entry in entries {
            if let inputSource = entry.rules.inputSource {
                if !inputSources.contains(inputSource) {
                    throw SwitcherooError.unknownInputSource(entry, inputSource)
                }
            }
        }
    }
}

struct InputSourceOverride {
    let selector: DeviceSelector
    let inputSource: String
}

struct NaturalScrollOverride {
    let selector: DeviceSelector
    let naturalScroll: Bool
}

public struct Overrides {
    let inputSourceOverrides: [InputSourceOverride]
    let naturalScrollOverrides: [NaturalScrollOverride]
    // Maps each device selector to the set of IDs of all connected devices that it matches.
    var devices: [DeviceSelector: Set<String>] = [:]

    public init(_ configuration: Configuration) {
        var inputSourceOverrides: [InputSourceOverride] = []
        var naturalScrollOverrides: [NaturalScrollOverride] = []
        for entry in configuration.entries {
            if let inputSource = entry.rules.inputSource {
                inputSourceOverrides.append(InputSourceOverride(selector: entry.selector, inputSource: inputSource))
            }
            if let naturalScroll = entry.rules.naturalScroll {
                naturalScrollOverrides.append(NaturalScrollOverride(selector: entry.selector, naturalScroll: naturalScroll))
            }
            devices[entry.selector] = Set<String>()
        }
        self.inputSourceOverrides = inputSourceOverrides
        self.naturalScrollOverrides = naturalScrollOverrides
    }

    public mutating func addDevice(_ device: String) {
        var it = devices.startIndex
        while it < devices.endIndex {
            var (selector, matches) = devices[it]
            if selector.matches(device) {
                matches.insert(device)
                devices.updateValue(matches, forKey: selector)
            }
            devices.formIndex(after: &it)
        }
    }

    public mutating func removeDevice(_ device: String) {
        var it = devices.startIndex
        while it < devices.endIndex {
            var (selector, matches) = devices[it]
            matches.remove(device)
            devices.updateValue(matches, forKey: selector)
            devices.formIndex(after: &it)
        }
    }

    public func getInputSource() -> String? {
        for current in inputSourceOverrides.reversed() {
            if let matches = devices[current.selector] {
                if !matches.isEmpty {
                    return current.inputSource
                }
            }
        }
        return nil
    }

    public func getNaturalScroll() -> Bool? {
        for current in naturalScrollOverrides.reversed() {
            if let matches = devices[current.selector] {
                if !matches.isEmpty {
                    return current.naturalScroll
                }
            }
        }
        return nil
    }
}

class Switcheroo {
    private let queue = DispatchQueue(label: "switcheroo")
    private let inputSources: [String: TISInputSource]
    private let inputSourceDefault: TISInputSource
    private let naturalScrollDefault: Bool
    private var overrides: Overrides

    init(_ configuration: Configuration) throws {
        inputSources = try getInputSources()
        inputSourceDefault = getActiveInputSource()
        naturalScrollDefault = getNaturalScroll()
        overrides = Overrides(configuration)
        try configuration.validate(Set(inputSources.keys))
    }

    private func update() {
        if let key = overrides.getInputSource() {
            logger.info("Setting input source to override: \(key, privacy: .public)")
            // We have convinced ourselves in the constructor that this input
            // source exists, so we just unwrap the result of the lookup here.
            setInputSource(inputSources[key]!)
        } else {
            let description = String(describing: inputSourceDefault)
            logger.info("Setting input source to default: \(description, privacy: .public)")
            setInputSource(inputSourceDefault)
        }
        if let naturalScroll = overrides.getNaturalScroll() {
            logger.info("Setting natural scroll to override: \(naturalScroll)")
            setNaturalScroll(naturalScroll)
        } else {
            logger.info("Setting natural scroll to default: \(self.naturalScrollDefault)")
            setNaturalScroll(naturalScrollDefault)
        }
    }

    private func addDevice(_ deviceKey: String) {
        logger.debug("Processing matching device: \(deviceKey, privacy: .public)")
        overrides.addDevice(deviceKey)
        update()
        logger.debug("Processed matching device: \(deviceKey, privacy: .public)")
    }

    func queueAddDevice(_ deviceKey: String) {
        logger.debug("Queueing matching device: \(deviceKey, privacy: .public)")
        queue.async {
            self.addDevice(deviceKey)
        }
    }

    private func removeDevice(_ deviceKey: String) {
        logger.debug("Processing removed device: \(deviceKey, privacy: .public)")
        overrides.removeDevice(deviceKey)
        update()
        logger.debug("Processed removed device: \(deviceKey, privacy: .public)")
    }

    func queueRemoveDevice(_ deviceKey: String) {
        logger.debug("Queueing removed device: \(deviceKey, privacy: .public)")
        queue.async {
            self.removeDevice(deviceKey)
        }
    }

    private func shutdown() {
        logger.debug("Processing shutdown.")
        setInputSource(inputSourceDefault)
        setNaturalScroll(naturalScrollDefault)
        logger.debug("Processed shutdown.")
        exit(143)
    }

    func queueShutdown() {
        logger.debug("Queueing shutdown.")
        queue.async {
            self.shutdown()
        }
    }
}

struct ListDevices: ParsableCommand {
    func run() throws {
        let manager = createDeviceManager()
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            throw SwitcherooError.failedToRetrieveDevices
        }
        for device in devices {
            if let key = getDeviceKey(device) {
                print(key)
            }
        }
    }
}

struct ListInputSources: ParsableCommand {
    func run() throws {
        for inputSource in try getInputSources() {
            print(inputSource.key)
        }
    }
}

struct GetInputSource: ParsableCommand {
    func run() throws {
        if let key = getInputSourceKey(getActiveInputSource()) {
            print(key)
        } else {
            throw SwitcherooError.failedToRetrieveActiveInputSource
        }
    }
}

struct SetInputSource: ParsableCommand {
    @Argument(help: "The desired input source.")
    var desired: String

    func run() throws {
        let inputSources = try getInputSources()
        if let inputSource = inputSources[desired] {
            setInputSource(inputSource)
        }
    }
}

struct GetNaturalScroll: ParsableCommand {
    func run() {
        print(getNaturalScroll())
    }
}

struct SetNaturalScroll: ParsableCommand {
    @Argument(help: "The desired setting for natural scroll (`false` or `true`).")
    var desired: String

    func run() throws {
        if let naturalScroll = Bool(desired) {
            setNaturalScroll(naturalScroll)
        } else {
            throw SwitcherooError.invalidNaturalScrollSetting(desired)
        }
    }
}

func onDeviceMatching(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    let switcheroo = Unmanaged<Switcheroo>.fromOpaque(context!).takeUnretainedValue()
    if let deviceKey = getDeviceKey(device) {
        switcheroo.queueAddDevice(deviceKey)
    } else {
        // Manually convert `device` to a `String` because `IOHIDDevice` is not `CustomStringConvertible`.
        let description = String(describing: device)
        logger.error("Failed to retrieve device key from device: \(description, privacy: .public)")
    }
}

func onDeviceRemoved(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    let switcheroo = Unmanaged<Switcheroo>.fromOpaque(context!).takeUnretainedValue()
    if let deviceKey = getDeviceKey(device) {
        switcheroo.queueRemoveDevice(deviceKey)
    } else {
        // Manually convert `device` to a `String` because `IOHIDDevice` is not `CustomStringConvertible`.
        let description = String(describing: device)
        logger.error("Failed to retrieve device key from device: \(description, privacy: .public)")
    }
}

public func defaultConfigurationFile() -> String {
    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".switcheroo.json").path
}

public func readConfigurationFile(_ file: String) throws -> Data {
    guard let handle = FileHandle(forReadingAtPath: file) else {
        throw SwitcherooError.failedToOpenConfigurationFile(file)
    }
    guard let data = try handle.readToEnd() else {
        throw SwitcherooError.failedToReadConfigurationFile(file)
    }
    return data
}

public func decodeConfigurationFile(_ data: Data) throws -> Configuration {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Configuration.self, from: data)
}

struct SwitcherooCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        subcommands: [
            ListDevices.self,
            ListInputSources.self,
            GetInputSource.self,
            SetInputSource.self,
            GetNaturalScroll.self,
            SetNaturalScroll.self
        ]
    )

    func run() throws {
        let configurationFile = defaultConfigurationFile()
        print("Using configuration file: \(configurationFile)")
        let configuration = try decodeConfigurationFile(readConfigurationFile(configurationFile))
        print("Successfully decoded configuration file.")
        let switcheroo = try Switcheroo(configuration)

        var shutdownSources: [DispatchSourceSignal] = []
        for signalNumber in [SIGINT, SIGTERM] {
            let shutdownSource = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            shutdownSources.append(shutdownSource)
            shutdownSource.setEventHandler {
                switcheroo.queueShutdown()
            }
            shutdownSource.resume()
            signal(signalNumber, SIG_IGN)
        }

        let switcherooPointer = Unmanaged.passUnretained(switcheroo).toOpaque()
        let manager = createDeviceManager()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, onDeviceMatching, switcherooPointer)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, onDeviceRemoved, switcherooPointer)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        print("Entering main loop.")
        RunLoop.current.run()
    }
}

SwitcherooCommand.main()
