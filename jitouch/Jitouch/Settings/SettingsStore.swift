import Foundation

struct ICloudSyncState: Equatable {
    enum Status: Equatable {
        case disabled
        case waiting
        case syncing
        case synced
        case failed
    }

    var status: Status = .disabled
    var lastSyncDate: Date?
    var message: String?

    static let disabled = ICloudSyncState(status: .disabled)
}

enum GestureSettingsTransferError: LocalizedError {
    case invalidFile

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "Invalid gesture settings file."
        }
    }
}

final class SettingsStore {
    private enum Key {
        static let enabled = "enAll"
        static let clickSpeed = "ClickSpeed"
        static let sensitivity = "Sensitivity"
        static let showIcon = "ShowIcon"
        static let logLevel = "LogLevel"
        static let appLanguage = "AppLanguage"
        static let iCloudSyncEnabled = "ICloudSyncEnabled"
        static let nightMode = "NightMode"
        static let themeMode = "ThemeMode"
        static let trackpadEnabled = "enTPAll"
        static let handed = "Handed"
        static let magicMouseEnabled = "enMMAll"
        static let magicMouseHanded = "MMHanded"
        static let trackpadCommands = "TrackpadCommands"
        static let magicMouseCommands = "MagicMouseCommands"
        static let iCloudSettings = "JitouchSettings"
        static let iCloudLastSyncDate = "ICloudLastSyncDate"
    }

    private static let iCloudSyncedKeys: Set<String> = [
        Key.enabled,
        Key.clickSpeed,
        Key.sensitivity,
        Key.showIcon,
        Key.logLevel,
        Key.appLanguage,
        Key.nightMode,
        Key.themeMode,
        Key.trackpadEnabled,
        Key.handed,
        Key.magicMouseEnabled,
        Key.magicMouseHanded,
        Key.trackpadCommands,
        Key.magicMouseCommands,
        Key.iCloudLastSyncDate
    ]

    var onExternalSettingsChanged: (() -> Void)?
    var onICloudSyncStateChanged: (() -> Void)?

    private let iCloudStore = NSUbiquitousKeyValueStore.default
    private var iCloudObserver: NSObjectProtocol?
    private var isApplyingICloudSettings = false

    deinit {
        if let iCloudObserver {
            NotificationCenter.default.removeObserver(iCloudObserver)
        }
    }

    private let appID = "com.zhuanz.JitouchModern" as CFString
    private(set) var rawSettings: [String: Any] = [:]
    var settings = JitouchSettings()
    private(set) var iCloudSyncState = ICloudSyncState.disabled {
        didSet {
            guard oldValue != iCloudSyncState else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onICloudSyncStateChanged?()
            }
        }
    }

    func load() {
        let preferencesDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences")
        guard
            let data = try? Data(contentsOf: preferencesDirectory.appendingPathComponent("com.zhuanz.JitouchModern.plist")),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [.mutableContainersAndLeaves], format: nil),
            let dictionary = plist as? [String: Any]
        else {
            rawSettings = DefaultsFactory.makeDefaultSettings()
            persistRawSettings()
            apply(rawSettings)
            configureICloudSyncAfterLoad()
            return
        }

        rawSettings = dictionary
        apply(dictionary)
        persistRawSettings()
        configureICloudSyncAfterLoad()
    }

    func load(from userInfo: [AnyHashable: Any]?) {
        guard let dictionary = userInfo as? [String: Any] else {
            load()
            return
        }
        rawSettings = dictionary
        apply(dictionary)
        configureICloudSyncAfterLoad()
    }

    func saveRuntimeToggle() {
        setBool(settings.isEnabled, forKey: Key.enabled)
        synchronize()
    }

    func updateGeneralSettings(_ update: (inout JitouchSettings) -> Void) {
        let wasICloudSyncEnabled = settings.iCloudSyncEnabled
        update(&settings)
        setBool(settings.isEnabled, forKey: Key.enabled)
        setBool(settings.showsMenuBarIcon, forKey: Key.showIcon)
        setDouble(settings.clickSpeed, forKey: Key.clickSpeed)
        setDouble(settings.sensitivity, forKey: Key.sensitivity)
        setBool(settings.trackpadEnabled, forKey: Key.trackpadEnabled)
        setBool(settings.trackpadLeftHanded, forKey: Key.handed)
        setBool(settings.magicMouseEnabled, forKey: Key.magicMouseEnabled)
        setBool(settings.magicMouseLeftHanded, forKey: Key.magicMouseHanded)
        setString(settings.appLanguage.rawValue, forKey: Key.appLanguage)
        setString(settings.themeMode.rawValue, forKey: Key.themeMode)
        setBool(settings.iCloudSyncEnabled, forKey: Key.iCloudSyncEnabled)

        if wasICloudSyncEnabled != settings.iCloudSyncEnabled {
            synchronize(pushToICloud: false)
            if settings.iCloudSyncEnabled {
                startICloudSync(mergeFromICloud: true)
            } else {
                stopICloudSync()
            }
        } else {
            synchronize()
        }
    }

    func synchronizeICloudNow() {
        guard settings.iCloudSyncEnabled else {
            iCloudSyncState = .disabled
            return
        }
        startICloudSync(mergeFromICloud: true)
    }

    func postRuntimeSettingsChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            .jitouchRuntimeDidChange,
            object: NotificationObject.runtime,
            userInfo: [Key.enabled: NSNumber(value: settings.isEnabled)],
            deliverImmediately: true
        )
    }

    func command(for gesture: String, device: GestureDevice, application: String?) -> GestureCommand? {
        let maps: [String: AppGestureCommands]
        switch device {
        case .trackpad:
            maps = settings.trackpadCommands
        case .magicMouse:
            maps = settings.magicMouseCommands
        }

        let applicationMap = application.flatMap { maps[$0] }
        if let command = applicationMap?.gestures[gesture], command.isEnabled {
            return command
        }

        if let fallback = applicationMap?.gestures["All Unassigned Gestures"], fallback.isEnabled {
            return fallback
        }

        let allApplications = maps["All Applications"]
        if let command = allApplications?.gestures[gesture], command.isEnabled {
            return command
        }

        return nil
    }

    func applicationProfiles(for device: GestureDevice) -> [AppGestureCommands] {
        let map: [String: AppGestureCommands]
        switch device {
        case .trackpad:
            map = settings.trackpadCommands
        case .magicMouse:
            map = settings.magicMouseCommands
        }

        return map.values.sorted {
            if $0.application == "All Applications" {
                return true
            }
            if $1.application == "All Applications" {
                return false
            }
            return $0.application.localizedStandardCompare($1.application) == .orderedAscending
        }
    }

    func commands(for device: GestureDevice, application: String) -> [GestureCommand] {
        let appCommands = applicationProfiles(for: device).first { $0.application == application }
        let commands = appCommands.map { Array($0.gestures.values) } ?? []
        let catalog = gestureCatalog(for: device)
        let catalogSet = Set(catalog)
        return commands
            .filter { catalogSet.contains($0.gesture) }
            .sorted {
                let lhs = catalog.firstIndex(of: $0.gesture) ?? Int.max
                let rhs = catalog.firstIndex(of: $1.gesture) ?? Int.max
                if lhs == rhs {
                    return $0.gesture.localizedStandardCompare($1.gesture) == .orderedAscending
                }
                return lhs < rhs
            }
    }

    func allApplicationCommands(for device: GestureDevice) -> [GestureCommand] {
        commands(for: device, application: "All Applications")
    }

    func gestureCatalog(for device: GestureDevice) -> [String] {
        switch device {
        case .trackpad:
            return DefaultsFactory.trackpadGestures
        case .magicMouse:
            return DefaultsFactory.magicMouseGestures
        }
    }

    func availableGestures(for device: GestureDevice, application: String) -> [String] {
        let assigned = Set(commands(for: device, application: application).map(\.gesture))
        return gestureCatalog(for: device).filter { !assigned.contains($0) }
    }

    func availableGestures(for device: GestureDevice) -> [String] {
        availableGestures(for: device, application: "All Applications")
    }

    func updateCommand(_ command: GestureCommand, device: GestureDevice, application: String = "All Applications", path: String = "") {
        switch device {
        case .trackpad:
            var app = settings.trackpadCommands[application] ?? AppGestureCommands(dictionary: ["Application": application, "Path": path, "Gestures": []])
            app.path = path.isEmpty ? app.path : path
            app.gestures[command.gesture] = command
            settings.trackpadCommands[application] = app
            saveCommandMap(settings.trackpadCommands, key: Key.trackpadCommands)

        case .magicMouse:
            var app = settings.magicMouseCommands[application] ?? AppGestureCommands(dictionary: ["Application": application, "Path": path, "Gestures": []])
            app.path = path.isEmpty ? app.path : path
            app.gestures[command.gesture] = command
            settings.magicMouseCommands[application] = app
            saveCommandMap(settings.magicMouseCommands, key: Key.magicMouseCommands)
        }
    }

    func removeCommand(gesture: String, device: GestureDevice, application: String = "All Applications") {
        switch device {
        case .trackpad:
            settings.trackpadCommands[application]?.gestures.removeValue(forKey: gesture)
            saveCommandMap(settings.trackpadCommands, key: Key.trackpadCommands)
        case .magicMouse:
            settings.magicMouseCommands[application]?.gestures.removeValue(forKey: gesture)
            saveCommandMap(settings.magicMouseCommands, key: Key.magicMouseCommands)
        }
    }

    func removeApplicationCommands(device: GestureDevice, application: String) {
        guard application != "All Applications" else { return }

        switch device {
        case .trackpad:
            settings.trackpadCommands.removeValue(forKey: application)
            saveCommandMap(settings.trackpadCommands, key: Key.trackpadCommands)
        case .magicMouse:
            settings.magicMouseCommands.removeValue(forKey: application)
            saveCommandMap(settings.magicMouseCommands, key: Key.magicMouseCommands)
        }
    }

    func exportGestureSettings(to url: URL) throws {
        let dictionary: [String: Any] = [
            "Format": "JitouchGestureSettings",
            "Version": 1,
            Key.trackpadCommands: Self.commandList(from: settings.trackpadCommands),
            Key.magicMouseCommands: Self.commandList(from: settings.magicMouseCommands)
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }

    func importGestureSettings(from url: URL) throws {
        let data = try Data(contentsOf: url)
        guard
            let plist = try PropertyListSerialization.propertyList(from: data, options: [.mutableContainersAndLeaves], format: nil) as? [String: Any],
            plist[Key.trackpadCommands] != nil || plist[Key.magicMouseCommands] != nil
        else {
            throw GestureSettingsTransferError.invalidFile
        }

        if let trackpadCommands = plist[Key.trackpadCommands] {
            settings.trackpadCommands = Self.commandMap(from: trackpadCommands)
            rawSettings[Key.trackpadCommands] = Self.commandList(from: settings.trackpadCommands)
            CFPreferencesSetAppValue(Key.trackpadCommands as CFString, rawSettings[Key.trackpadCommands] as CFPropertyList, appID)
        }

        if let magicMouseCommands = plist[Key.magicMouseCommands] {
            settings.magicMouseCommands = Self.commandMap(from: magicMouseCommands)
            rawSettings[Key.magicMouseCommands] = Self.commandList(from: settings.magicMouseCommands)
            CFPreferencesSetAppValue(Key.magicMouseCommands as CFString, rawSettings[Key.magicMouseCommands] as CFPropertyList, appID)
        }

        synchronize()
    }

    func restoreDefaultCommands(for device: GestureDevice) {
        let defaults = DefaultsFactory.makeDefaultSettings()
        switch device {
        case .trackpad:
            rawSettings[Key.trackpadCommands] = defaults[Key.trackpadCommands]
            settings.trackpadCommands = Self.commandMap(from: defaults[Key.trackpadCommands])
            CFPreferencesSetAppValue(Key.trackpadCommands as CFString, rawSettings[Key.trackpadCommands] as CFPropertyList, appID)
        case .magicMouse:
            rawSettings[Key.magicMouseCommands] = defaults[Key.magicMouseCommands]
            settings.magicMouseCommands = Self.commandMap(from: defaults[Key.magicMouseCommands])
            CFPreferencesSetAppValue(Key.magicMouseCommands as CFString, rawSettings[Key.magicMouseCommands] as CFPropertyList, appID)
        }
        synchronize()
    }

    private func apply(_ dictionary: [String: Any]) {
        settings.isEnabled = Self.bool(dictionary[Key.enabled], default: true)
        settings.showsMenuBarIcon = Self.bool(dictionary[Key.showIcon], default: true)
        settings.clickSpeed = Self.double(dictionary[Key.clickSpeed], default: 0.25)
        settings.sensitivity = Self.double(dictionary[Key.sensitivity], default: 4.6666)
        settings.logLevel = Int(Self.double(dictionary[Key.logLevel], default: 0))
        settings.appLanguage = AppLanguage(rawValue: dictionary[Key.appLanguage] as? String ?? "") ?? .system
        settings.themeMode = Self.themeMode(from: dictionary)
        settings.iCloudSyncEnabled = Self.bool(dictionary[Key.iCloudSyncEnabled], default: false)
        settings.trackpadEnabled = Self.bool(dictionary[Key.trackpadEnabled], default: true)
        settings.trackpadLeftHanded = Self.bool(dictionary[Key.handed], default: false)
        settings.magicMouseEnabled = Self.bool(dictionary[Key.magicMouseEnabled], default: true)
        settings.magicMouseLeftHanded = Self.bool(dictionary[Key.magicMouseHanded], default: false)
        settings.trackpadCommands = Self.commandMap(from: dictionary[Key.trackpadCommands])
        settings.magicMouseCommands = Self.commandMap(from: dictionary[Key.magicMouseCommands])
        updateICloudSyncStateFromSettings()
    }

    private func persistRawSettings(pushToICloud: Bool = false) {
        for (key, value) in rawSettings {
            CFPreferencesSetAppValue(key as CFString, value as CFPropertyList, appID)
        }
        CFPreferencesAppSynchronize(appID)
        if pushToICloud {
            pushSettingsToICloudIfNeeded()
        }
    }

    private func setBool(_ value: Bool, forKey key: String) {
        rawSettings[key] = value ? 1 : 0
        CFPreferencesSetAppValue(key as CFString, NSNumber(value: value), appID)
    }

    private func setDouble(_ value: Double, forKey key: String) {
        rawSettings[key] = value
        CFPreferencesSetAppValue(key as CFString, NSNumber(value: value), appID)
    }

    private func setString(_ value: String, forKey key: String) {
        rawSettings[key] = value
        CFPreferencesSetAppValue(key as CFString, value as CFString, appID)
    }

    private func synchronize(pushToICloud: Bool = true) {
        CFPreferencesAppSynchronize(appID)
        if pushToICloud {
            pushSettingsToICloudIfNeeded()
        }
    }

    private func saveCommandMap(_ map: [String: AppGestureCommands], key: String) {
        rawSettings[key] = Self.commandList(from: map)
        CFPreferencesSetAppValue(key as CFString, rawSettings[key] as CFPropertyList, appID)
        synchronize()
    }

    private static func commandList(from map: [String: AppGestureCommands]) -> [[String: Any]] {
        map.values
            .sorted { $0.application.localizedStandardCompare($1.application) == .orderedAscending }
            .map { $0.dictionary() }
    }

    private func configureICloudSyncAfterLoad() {
        if settings.iCloudSyncEnabled {
            startICloudSync(mergeFromICloud: true)
        } else {
            stopICloudSync()
        }
    }

    private func startICloudSync(mergeFromICloud: Bool) {
        observeICloudChanges()
        guard FileManager.default.ubiquityIdentityToken != nil else {
            iCloudSyncState = ICloudSyncState(
                status: .waiting,
                lastSyncDate: iCloudSyncState.lastSyncDate,
                message: "iCloud is unavailable."
            )
            return
        }

        iCloudSyncState = ICloudSyncState(
            status: .syncing,
            lastSyncDate: iCloudSyncState.lastSyncDate,
            message: nil
        )
        let didSynchronize = iCloudStore.synchronize()
        if mergeFromICloud, let iCloudSettings = iCloudStore.dictionary(forKey: Key.iCloudSettings) {
            reconcileICloudSettings(iCloudSettings)
        } else if didSynchronize {
            pushSettingsToICloudIfNeeded()
        } else {
            iCloudSyncState = ICloudSyncState(
                status: .failed,
                lastSyncDate: iCloudSyncState.lastSyncDate,
                message: "iCloud sync failed."
            )
        }
    }

    private func stopICloudSync() {
        if let iCloudObserver {
            NotificationCenter.default.removeObserver(iCloudObserver)
            self.iCloudObserver = nil
        }
        iCloudSyncState = .disabled
    }

    private func observeICloudChanges() {
        guard iCloudObserver == nil else { return }
        iCloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: iCloudStore,
            queue: .main
        ) { [weak self] notification in
            self?.handleICloudChange(notification)
        }
    }

    private func handleICloudChange(_ notification: Notification) {
        guard settings.iCloudSyncEnabled else { return }
        let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        if changedKeys == nil || changedKeys?.contains(Key.iCloudSettings) == true,
           let iCloudSettings = iCloudStore.dictionary(forKey: Key.iCloudSettings) {
            iCloudSyncState = ICloudSyncState(
                status: .syncing,
                lastSyncDate: iCloudSyncState.lastSyncDate,
                message: nil
            )
            reconcileICloudSettings(iCloudSettings)
        }
    }

    private func reconcileICloudSettings(_ iCloudSettings: [String: Any]) {
        let localTimestamp = Self.double(rawSettings[Key.iCloudLastSyncDate], default: 0)
        let iCloudTimestamp = Self.double(iCloudSettings[Key.iCloudLastSyncDate], default: 0)

        if iCloudTimestamp > localTimestamp {
            applyICloudSettings(iCloudSettings)
        } else if localTimestamp > iCloudTimestamp {
            pushSettingsToICloudIfNeeded()
        } else {
            iCloudSyncState = ICloudSyncState(
                status: .synced,
                lastSyncDate: localTimestamp > 0 ? Date(timeIntervalSince1970: localTimestamp) : nil,
                message: nil
            )
        }
    }

    private func applyICloudSettings(_ iCloudSettings: [String: Any]) {
        guard isApplyingICloudSettings == false else { return }
        isApplyingICloudSettings = true
        defer { isApplyingICloudSettings = false }

        var mergedSettings = rawSettings
        for key in Self.iCloudSyncedKeys {
            if let value = iCloudSettings[key] {
                mergedSettings[key] = value
            }
        }
        rawSettings = mergedSettings
        apply(mergedSettings)
        persistRawSettings(pushToICloud: false)
        markICloudSynced(at: Self.double(iCloudSettings[Key.iCloudLastSyncDate], default: Date().timeIntervalSince1970))
        onExternalSettingsChanged?()
    }

    private func pushSettingsToICloudIfNeeded() {
        guard settings.iCloudSyncEnabled, isApplyingICloudSettings == false else { return }
        guard FileManager.default.ubiquityIdentityToken != nil else {
            iCloudSyncState = ICloudSyncState(
                status: .waiting,
                lastSyncDate: iCloudSyncState.lastSyncDate,
                message: "iCloud is unavailable."
            )
            return
        }

        iCloudSyncState = ICloudSyncState(
            status: .syncing,
            lastSyncDate: iCloudSyncState.lastSyncDate,
            message: nil
        )
        let syncDate = Date()
        rawSettings[Key.iCloudLastSyncDate] = syncDate.timeIntervalSince1970

        var iCloudSettings: [String: Any] = [:]
        for key in Self.iCloudSyncedKeys {
            if let value = rawSettings[key] {
                iCloudSettings[key] = value
            }
        }
        iCloudStore.set(iCloudSettings, forKey: Key.iCloudSettings)
        if iCloudStore.synchronize() {
            markICloudSynced(at: syncDate.timeIntervalSince1970)
        } else {
            iCloudSyncState = ICloudSyncState(
                status: .failed,
                lastSyncDate: iCloudSyncState.lastSyncDate,
                message: "iCloud sync failed."
            )
        }
    }

    private func updateICloudSyncStateFromSettings() {
        let timestamp = Self.double(rawSettings[Key.iCloudLastSyncDate], default: 0)
        let lastSyncDate = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        guard settings.iCloudSyncEnabled else {
            iCloudSyncState = .disabled
            return
        }
        iCloudSyncState = ICloudSyncState(
            status: lastSyncDate == nil ? .waiting : .synced,
            lastSyncDate: lastSyncDate,
            message: nil
        )
    }

    private func markICloudSynced(at timestamp: TimeInterval) {
        let date = Date(timeIntervalSince1970: timestamp)
        setDouble(timestamp, forKey: Key.iCloudLastSyncDate)
        CFPreferencesAppSynchronize(appID)
        iCloudSyncState = ICloudSyncState(
            status: .synced,
            lastSyncDate: date,
            message: nil
        )
    }

    private static func commandMap(from value: Any?) -> [String: AppGestureCommands] {
        guard let apps = value as? [[String: Any]] else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: apps.map {
            let app = AppGestureCommands(dictionary: $0)
            let normalizedName: String
            switch app.application {
            case "Chrome":
                normalizedName = "Google Chrome"
            case "Word":
                normalizedName = "Microsoft Word"
            default:
                normalizedName = app.application
            }
            return (normalizedName, app)
        })
    }

    private static func bool(_ value: Any?, default defaultValue: Bool) -> Bool {
        guard let value else {
            return defaultValue
        }
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.intValue != 0
        }
        return defaultValue
    }

    private static func double(_ value: Any?, default defaultValue: Double) -> Double {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return defaultValue
    }

    private static func themeMode(from dictionary: [String: Any]) -> AppThemeMode {
        if let rawValue = dictionary[Key.themeMode] as? String,
           let themeMode = AppThemeMode(rawValue: rawValue) {
            return themeMode
        }

        return bool(dictionary[Key.nightMode], default: false) ? .dark : .system
    }
}

private enum DefaultsFactory {
    static let trackpadGestures = RecognizedGesture.supportedGestures(for: .trackpad) + ["All Unassigned Gestures"]

    static let magicMouseGestures = RecognizedGesture.supportedGestures(for: .magicMouse) + ["All Unassigned Gestures"]

    static func makeDefaultSettings() -> [String: Any] {
        [
            "enAll": 1,
            "ClickSpeed": 0.25,
            "Sensitivity": 4.6666,
            "ShowIcon": 1,
            "Revision": 20240427,
            "LogLevel": 0,
            "AppLanguage": AppLanguage.system.rawValue,
            "ThemeMode": AppThemeMode.system.rawValue,
            "enTPAll": 1,
            "Handed": 0,
            "enMMAll": 1,
            "MMHanded": 0,
            "TrackpadCommands": [
                app("All Applications", gestures: [
                    gesture("One-Fix Left-Tap", "Previous Tab"),
                    gesture("One-Fix Right-Tap", "Next Tab"),
                    gesture("One-Fix One-Slide", "Move / Resize"),
                    gesture("One-Fix Two-Slide-Down", "Close / Close Tab"),
                    gesture("One-Fix-Press Two-Slide-Down", "Quit"),
                    gesture("Two-Fix Index-Double-Tap", "Refresh"),
                    gesture("Three-Finger Tap", "Middle Click"),
                    gesture("Pinky-To-Index", "Zoom"),
                    gesture("Index-To-Pinky", "Minimize")
                ])
            ],
            "MagicMouseCommands": [
                app("All Applications", gestures: [
                    gesture("Middle-Fix Index-Near-Tap", "Next Tab"),
                    gesture("Middle-Fix Index-Far-Tap", "Previous Tab"),
                    gesture("Middle-Fix Index-Slide-Out", "Close / Close Tab"),
                    gesture("Middle-Fix Index-Slide-In", "Refresh"),
                    gesture("Three-Swipe-Up", "Show Desktop"),
                    gesture("Three-Swipe-Down", "Mission Control"),
                    gesture("V-Shape", "Move / Resize"),
                    gesture("Middle Click", "Middle Click")
                ])
            ]
        ]
    }

    private static func app(_ name: String, gestures: [[String: Any]]) -> [String: Any] {
        ["Application": name, "Path": "", "Gestures": gestures]
    }

    private static func gesture(_ gesture: String, _ command: String) -> [String: Any] {
        [
            "Gesture": gesture,
            "Command": command,
            "IsAction": true,
            "ModifierFlags": 0,
            "KeyCode": 0,
            "Enable": 1
        ]
    }
}
