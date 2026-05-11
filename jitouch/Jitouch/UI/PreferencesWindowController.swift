import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AppLocalization {
    static var currentLanguage: AppLanguage = .system

    static func localizedString(_ key: String) -> String {
        guard
            let identifier = currentLanguage.localizationIdentifier,
            let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return NSLocalizedString(key, comment: "")
        }

        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

func L(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

extension AppThemeMode {
    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}

protocol PreferencesWindowControllerDelegate: AnyObject {
    func preferencesWindowControllerDidChangeSettings(_ controller: PreferencesWindowController)
}

final class PreferencesWindowController: NSWindowController {
    weak var delegate: PreferencesWindowControllerDelegate?

    private let settingsStore: SettingsStore
    private lazy var model = PreferencesViewModel(settingsStore: settingsStore) { [weak self] in
        guard let self else { return }
        self.delegate?.preferencesWindowControllerDidChangeSettings(self)
    }

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = NSToolbar()
        window.toolbar?.isVisible = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: PreferencesRootView(model: model))
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        model.reload()
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    func reload() {
        model.reload()
    }
}

@MainActor
final class PreferencesViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case trackpad
        case magicMouse
        case general

        var id: String { rawValue }
        var title: String {
            switch self {
            case .trackpad: L("Trackpad")
            case .magicMouse: L("Magic Mouse")
            case .general: L("General")
            }
        }
    }

    enum AddMode: String, CaseIterable, Identifiable {
        case action
        case shortcut

        var id: String { rawValue }
        var title: String {
            switch self {
            case .action: L("Action")
            case .shortcut: L("Keyboard Shortcut")
            }
        }
    }

    struct CommandRow: Identifiable, Equatable {
        var command: GestureCommand
        var id: String { command.gesture }
    }

    struct ApplicationOption: Identifiable {
        var application: String
        var title: String
        var icon: NSImage?

        var id: String { application }
    }

    private let settingsStore: SettingsStore
    private let onChange: () -> Void

    @Published var selectedTab: Tab = .trackpad
    @Published var selectedApplication = "All Applications"
    @Published var selectedGesture: String?
    @Published var isShowingAddSheet = false
    @Published var isShowingRestoreAlert = false
    @Published var generalSettings = JitouchSettings()
    @Published var iCloudSyncState = ICloudSyncState.disabled

    @Published var addApplication = "All Applications"
    @Published var addGesture = ""
    @Published var addMode: AddMode = .action
    @Published var addCommand = "-"
    @Published var addShortcutText = ""
    @Published var addShortcutFlags: UInt64 = 0
    @Published var addShortcutKeyCode: UInt16 = 0
    @Published var addEnabled = true
    @Published private var temporaryApplicationPaths: [String: String] = [:]
    @Published private var installedApplicationPaths: [String: String] = [:]

    let commands = [
        "-",
        "Move / Resize",
        "Next Tab",
        "Previous Tab",
        "Close / Close Tab",
        "Quit",
        "Hide",
        "Minimize",
        "Zoom",
        "Maximize",
        "Maximize Left",
        "Maximize Right",
        "Un-Maximize",
        "Copy",
        "Paste",
        "New",
        "New Tab",
        "Open",
        "Save",
        "Refresh",
        "Full Screen",
        "Open Recently Closed Tab",
        "Middle Click",
        "Left Click",
        "Right Click",
        "Launch Finder",
        "Launch Browser",
        "Show Desktop",
        "Mission Control",
        "Application Windows",
        "Launchpad",
        "Scroll to Top",
        "Scroll to Bottom",
        "Play / Pause",
        "Next",
        "Previous",
        "Volume Up",
        "Volume Down",
        "Brightness Up",
        "Brightness Down"
    ]

    init(settingsStore: SettingsStore, onChange: @escaping () -> Void) {
        self.settingsStore = settingsStore
        self.onChange = onChange
        settingsStore.onICloudSyncStateChanged = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.iCloudSyncState = self.settingsStore.iCloudSyncState
            }
        }
        refreshInstalledApplications()
        reload()
    }

    var selectedDevice: GestureDevice {
        switch selectedTab {
        case .trackpad:
            return .trackpad
        case .magicMouse:
            return .magicMouse
        case .general:
            return .trackpad
        }
    }

    var deviceOptions: [GestureDevice] {
        [.trackpad, .magicMouse]
    }

    var applicationProfiles: [AppGestureCommands] {
        settingsStore.applicationProfiles(for: selectedDevice)
    }

    var applicationOptions: [String] {
        applicationProfiles.map { displayName(for: $0.application) }
    }

    var installedApplicationOptions: [String] {
        Set(installedApplicationPaths.keys)
            .union(applicationProfiles.map(\.application))
            .filter { $0 != "All Applications" }
            .sorted { lhs, rhs in
                lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
    }

    var addApplicationOptions: [ApplicationOption] {
        var options: [ApplicationOption] = [
            ApplicationOption(
                application: "All Applications",
                title: L("All Applications"),
                icon: allApplicationsIcon()
            )
        ]

        for application in installedApplicationOptions {
            options.append(
                ApplicationOption(
                    application: application,
                    title: application,
                    icon: icon(for: application)
                )
            )
        }

        options.append(
            ApplicationOption(
                application: L("Other..."),
                title: L("Other..."),
                icon: nil
            )
        )
        return options
    }

    var commandRows: [CommandRow] {
        settingsStore.commands(for: selectedDevice, application: selectedApplication)
            .map { CommandRow(command: $0) }
    }

    var selectedCommand: GestureCommand? {
        guard let selectedGesture else { return nil }
        return commandRows.first { $0.command.gesture == selectedGesture }?.command
    }

    var canAdd: Bool {
        !settingsStore.availableGestures(for: selectedDevice, application: selectedApplication).isEmpty
    }

    var canDelete: Bool {
        selectedCommand != nil
    }

    func reload() {
        refreshInstalledApplications()
        applyInterfaceSettings()
        generalSettings = settingsStore.settings
        iCloudSyncState = settingsStore.iCloudSyncState
        if applicationProfiles.contains(where: { $0.application == selectedApplication }) == false {
            selectedApplication = "All Applications"
        }
    }

    func selectDevice(_ device: GestureDevice) {
        selectedTab = device == .trackpad ? .trackpad : .magicMouse
        resetGestureSelection()
    }

    func resetGestureSelection() {
        selectedApplication = "All Applications"
        selectedGesture = nil
    }

    func beginAdd() {
        addApplication = selectedApplication
        addMode = .action
        addCommand = "-"
        addEnabled = true
        addShortcutText = ""
        addShortcutFlags = 0
        addShortcutKeyCode = 0
        refreshAddGesture()
        isShowingAddSheet = true
    }

    func refreshAddGesture() {
        let available = settingsStore.availableGestures(for: selectedDevice, application: addApplication)
        addGesture = available.first ?? ""
    }

    func handleAddApplicationSelection(_ value: String) {
        if value == L("Other...") {
            chooseApplicationForAddSheet()
        } else {
            addApplication = value
            refreshAddGesture()
        }
    }

    func commitAdd() {
        guard addGesture.isEmpty == false else { return }
        let isAction = addMode == .action
        let command = GestureCommand(
            gesture: addGesture,
            command: isAction ? addCommand : addShortcutText,
            isAction: isAction,
            modifierFlags: isAction ? 0 : addShortcutFlags,
            keyCode: isAction ? 0 : addShortcutKeyCode,
            isEnabled: addEnabled,
            openFilePath: nil,
            openURL: nil
        )

        settingsStore.updateCommand(command, device: selectedDevice, application: addApplication, path: path(for: addApplication))
        selectedApplication = addApplication
        selectedGesture = addGesture
        finishSettingsChange()
        isShowingAddSheet = false
    }

    func deleteSelectedCommand() {
        guard let selectedCommand else { return }
        settingsStore.removeCommand(gesture: selectedCommand.gesture, device: selectedDevice, application: selectedApplication)
        selectedGesture = nil
        finishSettingsChange()
    }

    func restoreDefaults() {
        settingsStore.restoreDefaultCommands(for: selectedDevice)
        selectedApplication = "All Applications"
        selectedGesture = nil
        finishSettingsChange()
    }

    func update(_ command: GestureCommand) {
        settingsStore.updateCommand(command, device: selectedDevice, application: selectedApplication, path: path(for: selectedApplication))
        finishSettingsChange()
    }

    func updateGeneral(_ update: (inout JitouchSettings) -> Void) {
        settingsStore.updateGeneralSettings(update)
        applyInterfaceSettings()
        generalSettings = settingsStore.settings
        iCloudSyncState = settingsStore.iCloudSyncState
        finishSettingsChange()
    }

    func syncICloudNow() {
        settingsStore.synchronizeICloudNow()
        iCloudSyncState = settingsStore.iCloudSyncState
    }

    private func applyInterfaceSettings() {
        AppLocalization.currentLanguage = settingsStore.settings.appLanguage
        NSApp.appearance = settingsStore.settings.themeMode.nsAppearance
    }

    func availableAddGestures() -> [String] {
        settingsStore.availableGestures(for: selectedDevice, application: addApplication)
    }

    func displayName(for application: String) -> String {
        application == "All Applications" ? L("All Applications") : application
    }

    func normalizedApplicationName(_ displayName: String) -> String {
        displayName == L("All Applications") ? "All Applications" : displayName
    }

    private func path(for application: String) -> String {
        if let temporaryPath = temporaryApplicationPaths[application] {
            return temporaryPath
        }
        if let installedPath = installedApplicationPaths[application] {
            return installedPath
        }
        return applicationProfiles.first { $0.application == application }?.path ?? ""
    }

    private func chooseApplicationForAddSheet() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            addApplication = "All Applications"
            refreshAddGesture()
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        temporaryApplicationPaths[name] = url.path
        installedApplicationPaths[name] = url.path
        addApplication = name
        refreshAddGesture()
    }

    private func refreshInstalledApplications() {
        installedApplicationPaths = Self.scanInstalledApplications()
    }

    private func icon(for application: String) -> NSImage {
        let path = path(for: application)
        if path.isEmpty == false {
            return Self.normalizedApplicationIcon(NSWorkspace.shared.icon(forFile: path))
        }
        return Self.normalizedApplicationIcon(NSWorkspace.shared.icon(for: UTType.application))
    }

    private func allApplicationsIcon() -> NSImage {
        let icon = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
            ?? NSWorkspace.shared.icon(for: UTType.application)
        return Self.normalizedApplicationIcon(icon)
    }

    private static func normalizedApplicationIcon(_ icon: NSImage) -> NSImage {
        let image = icon.copy() as? NSImage ?? icon
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    private static func scanInstalledApplications() -> [String: String] {
        let fileManager = FileManager.default
        let searchDirectories = [
            "/Applications",
            "/System/Applications",
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ]

        var results: [String: String] = [:]
        for directory in searchDirectories {
            guard let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: directory),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                let name = url.deletingPathExtension().lastPathComponent
                if results[name] == nil {
                    results[name] = url.path
                }
            }
        }

        return results
    }

    private func finishSettingsChange() {
        objectWillChange.send()
        settingsStore.postRuntimeSettingsChanged()
        onChange()
    }
}

struct PreferencesRootView: View {
    @ObservedObject var model: PreferencesViewModel

    var body: some View {
        NavigationSplitView {
            List(selection: selectedTab) {
                ForEach(PreferencesViewModel.Tab.allCases) { tab in
                    Label(tab.title, systemImage: sidebarIcon(for: tab))
                        .tag(tab)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            switch model.selectedTab {
            case .trackpad:
                GestureSettingsView(model: model)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            case .magicMouse:
                GestureSettingsView(model: model)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            case .general:
                GeneralSettingsView(model: model)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
        }
        .frame(minWidth: 920, minHeight: 580)
        .ignoresSafeArea(.container, edges: .top)
        .background {
            LinearGradient(colors: [Color(nsColor: .windowBackgroundColor), Color.accentColor.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        }
    }

    private func sidebarIcon(for tab: PreferencesViewModel.Tab) -> String {
        switch tab {
        case .trackpad:
            return "hand.tap"
        case .magicMouse:
            return "magicmouse"
        case .general:
            return "gearshape"
        }
    }

    private var selectedTab: Binding<PreferencesViewModel.Tab> {
        Binding(
            get: { model.selectedTab },
            set: { tab in
                model.selectedTab = tab
                switch tab {
                case .trackpad, .magicMouse:
                    model.resetGestureSelection()
                case .general:
                    break
                }
            }
        )
    }
}

struct GestureSettingsView: View {
    @ObservedObject var model: PreferencesViewModel

    var body: some View {
        applicationTabs
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(L("Restore Defaults")) { model.isShowingRestoreAlert = true }
                    Button(L("Delete")) { model.deleteSelectedCommand() }
                        .disabled(!model.canDelete)
                    Button(L("Add")) { model.beginAdd() }
                        .disabled(!model.canAdd)
                        .buttonStyle(.borderedProminent)
                }
            }
            .sheet(isPresented: $model.isShowingAddSheet) {
                AddGestureSheet(model: model)
            }
            .alert(L("Restore default settings?"), isPresented: $model.isShowingRestoreAlert) {
                Button(L("Cancel"), role: .cancel) {}
                Button(L("OK"), role: .destructive) { model.restoreDefaults() }
            } message: {
                Text(String(format: L("Your current %@ gesture settings will be deleted."), deviceTitle(model.selectedDevice)))
            }
    }

    private var applicationTabs: some View {
        TabView(selection: selectedApplication) {
            ForEach(model.applicationOptions, id: \.self) { app in
                commandForm
                    .tabItem {
                        Text(app)
                    }
                    .tag(model.normalizedApplicationName(app))
            }
        }
        .tabViewStyle(.automatic)
        .background(Color.clear)
    }

    private var selectedApplication: Binding<String> {
        Binding(
            get: { model.selectedApplication },
            set: { application in
                model.selectedApplication = application
                model.selectedGesture = nil
            }
        )
    }

    private var commandForm: some View {
        Form {
            Section {
                commandHeader
                    .listRowSeparator(.hidden)
                ForEach(model.commandRows) { row in
                    CommandRowView(model: model, row: row)
                    .contentShape(Rectangle())
                    .onTapGesture { model.selectedGesture = row.id }
                    .listRowBackground(row.id == model.selectedGesture ? Color.accentColor.opacity(0.16) : Color.clear)
                }
            } header: {
                Text(deviceTitle(model.selectedDevice))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private var commandHeader: some View {
        HStack {
            Text(L("Gesture")).frame(maxWidth: .infinity, alignment: .leading)
            Text(L("Command")).frame(width: 260, alignment: .trailing)
            Text(L("On")).frame(width: 44, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

struct CommandRowView: View {
    @ObservedObject var model: PreferencesViewModel
    var row: PreferencesViewModel.CommandRow
    @State private var isShowingGesturePreview = false

    var body: some View {
        HStack(spacing: 12) {
            gestureTitle
                .frame(maxWidth: .infinity, alignment: .leading)

            if row.command.isAction {
                Picker("", selection: Binding(
                    get: { row.command.command },
                    set: { value in
                        var command = row.command
                        command.command = value
                        command.isAction = true
                        model.update(command)
                    }
                )) {
                    ForEach(model.commands, id: \.self) { command in
                        Text(command).tag(command)
                    }
                }
                .frame(width: 260, alignment: .trailing)
            } else {
                Text(row.command.command)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 260, alignment: .trailing)
            }

            Toggle("", isOn: Binding(
                get: { row.command.isEnabled },
                set: { value in
                    var command = row.command
                    command.isEnabled = value
                    model.update(command)
                }
            ))
            .labelsHidden()
            .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private var gestureTitle: some View {
        Text(row.command.gesture)
            .lineLimit(1)
            .onHover { isHovering in
                isShowingGesturePreview = isHovering
            }
            .popover(isPresented: $isShowingGesturePreview, arrowEdge: .trailing) {
                GestureAnimationPreview(gesture: row.command.gesture, device: model.selectedDevice)
            }
    }
}

struct GestureAnimationPreview: View {
    let gesture: String
    let device: GestureDevice
    private let size = CGSize(width: 184, height: 132)
    private var sequence: GesturePreviewSequence {
        GesturePreviewSequence(gesture: gesture, device: device)
    }

    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.animation) { timeline in
                let time = animationTime(at: timeline.date, duration: sequence.duration)
                ZStack {
                    deviceSurface
                    ForEach(Array(sequence.segments.enumerated()), id: \.offset) { index, segment in
                        if let state = segment.state(at: time) {
                            fingerDot(state, id: index)
                        }
                    }
                }
                .frame(width: size.width, height: size.height)
            }
            .frame(width: size.width, height: size.height)

            Text(gesture)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: size.width)
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var deviceSurface: some View {
        Group {
            if device == .magicMouse {
                Capsule()
                    .fill(Color.primary.opacity(0.06))
                    .overlay(Capsule().stroke(Color.primary.opacity(0.18), lineWidth: 1))
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(Color.primary.opacity(0.16))
                            .frame(width: 2, height: 30)
                            .padding(.top, 12)
                    }
                    .frame(width: 104, height: 132)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.18), lineWidth: 1))
                    .frame(width: 154, height: 106)
            }
        }
    }

    private func fingerDot(_ state: GesturePreviewState, id: Int) -> some View {
        let point = point(from: state.point)

        return Circle()
            .fill(state.pressed ? Color.red.opacity(0.72) : Color.accentColor.opacity(0.76))
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1))
            .frame(width: 16, height: 16)
            .scaleEffect(state.pressed ? 1.35 : 1)
            .position(point)
            .shadow(color: Color.black.opacity(0.16), radius: 3, x: 0, y: 1)
    }

    private func point(from normalized: CGPoint) -> CGPoint {
        CGPoint(x: normalized.x * size.width, y: (1 - normalized.y) * size.height)
    }

    private func animationTime(at date: Date, duration: Double) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: max(duration, 0.1))
    }
}

private struct GesturePreviewState {
    let point: CGPoint
    let pressed: Bool
}

private struct GesturePreviewSegment {
    let start: CGPoint
    let end: CGPoint
    let t0: Double
    let t1: Double
    let holdBeforeStart: Double?
    let holdAfterEnd: Double?
    let pressed: Bool

    func state(at time: Double) -> GesturePreviewState? {
        if let holdBeforeStart, time >= holdBeforeStart, time <= t0 {
            return GesturePreviewState(point: start, pressed: pressed)
        }
        if let holdAfterEnd, time >= t1, time <= holdAfterEnd {
            return GesturePreviewState(point: end, pressed: pressed)
        }
        guard time >= t0, time <= t1 else { return nil }
        let span = max(t1 - t0, 0.001)
        let rawProgress = (time - t0) / span
        let progress = (1 - sin(.pi / 2 + rawProgress * .pi)) / 2
        let point = CGPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        )
        return GesturePreviewState(point: point, pressed: pressed)
    }
}

private struct GesturePreviewSequence {
    let segments: [GesturePreviewSegment]
    let duration: Double

    init(gesture: String, device: GestureDevice) {
        let builder = GesturePreviewSequenceBuilder()
        if device == .magicMouse {
            builder.createMagicMouse(gesture)
        } else {
            builder.createTrackpad(gesture)
        }
        segments = builder.segments
        duration = builder.duration
    }
}

private final class GesturePreviewSequenceBuilder {
    private(set) var segments: [GesturePreviewSegment] = []
    private(set) var duration: Double = 1.6

    private func reset(_ duration: Double) {
        segments.removeAll()
        self.duration = duration * 2
    }

    private func segment(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ t0: Double, _ t1: Double, pressed: Bool = false) {
        segments.append(
            GesturePreviewSegment(
                start: CGPoint(x: x1, y: y1),
                end: CGPoint(x: x2, y: y2),
                t0: t0 * 2,
                t1: t1 * 2,
                holdBeforeStart: nil,
                holdAfterEnd: nil,
                pressed: pressed
            )
        )
    }

    private func segmentHold(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ t0: Double, _ t1: Double, _ holdStart: Double, _ holdEnd: Double, pressed: Bool = false) {
        segments.append(
            GesturePreviewSegment(
                start: CGPoint(x: x1, y: y1),
                end: CGPoint(x: x2, y: y2),
                t0: t0 * 2,
                t1: t1 * 2,
                holdBeforeStart: holdStart * 2,
                holdAfterEnd: holdEnd * 2,
                pressed: pressed
            )
        )
    }

    func createTrackpad(_ gesture: String) {
        switch gesture {
        case "Three-Finger Tap":
            threeFingerTap()
        case "Three-Finger Click":
            threeFingerClick()
        case "Three-Finger Pinch-In":
            reset(1); segment(0.50, 0.51, 0.50, 0.50, 0, 0.37); segmentHold(0.31, 0.48, 0.36, 0.48, 0.04, 0.29, 0, 0.37); segmentHold(0.69, 0.48, 0.64, 0.48, 0.04, 0.29, 0, 0.37)
        case "Three-Finger Pinch-Out":
            reset(1); segment(0.50, 0.50, 0.50, 0.51, 0, 0.37); segmentHold(0.36, 0.48, 0.31, 0.48, 0.04, 0.29, 0, 0.37); segmentHold(0.64, 0.48, 0.69, 0.48, 0.04, 0.29, 0, 0.37)
        case "Four-Finger Tap":
            fourFingerTap()
        case "Four-Finger Click":
            fourFingerClick()
        case "One-Fix Left-Tap":
            reset(0.6); segment(0.36, 0.49, 0.36, 0.49, 0.3, 0.45); segment(0.50, 0.50, 0.50, 0.50, 0, 1)
        case "One-Fix Right-Tap":
            reset(0.6); segment(0.50, 0.50, 0.50, 0.50, 0, 1); segment(0.64, 0.49, 0.64, 0.49, 0.3, 0.45)
        case "Pinky-To-Index":
            pinkyToIndex()
        case "Index-To-Pinky":
            indexToPinky()
        case "One-Fix One-Slide":
            moveResize()
        case "One-Fix Two-Slide-Up":
            oneFixTwoSlide(up: true, pressed: false)
        case "One-Fix Two-Slide-Down":
            oneFixTwoSlide(up: false, pressed: false)
        case "One-Fix-Press Two-Slide-Up":
            oneFixTwoSlide(up: true, pressed: true)
        case "One-Fix-Press Two-Slide-Down":
            oneFixTwoSlide(up: false, pressed: true)
        case "Two-Fix Index-Double-Tap":
            twoFixOneDoubleTap(0)
        case "Two-Fix Middle-Double-Tap":
            twoFixOneDoubleTap(1)
        case "Two-Fix Ring-Double-Tap":
            twoFixOneDoubleTap(2)
        case "Two-Fix One-Slide-Up":
            twoFixOneSlide(dx: 0, dy: 0.08)
        case "Two-Fix One-Slide-Down":
            twoFixOneSlide(dx: 0, dy: -0.08)
        case "Two-Fix One-Slide-Left":
            twoFixOneSlide(dx: -0.05, dy: 0)
        case "Two-Fix One-Slide-Right":
            twoFixOneSlide(dx: 0.05, dy: 0)
        case "Three-Swipe-Up":
            threeSwipe(dx: 0, dy: 0.14)
        case "Three-Swipe-Down":
            threeSwipe(dx: 0, dy: -0.14)
        case "Three-Swipe-Left":
            threeSwipe(dx: -0.14, dy: 0)
        case "Three-Swipe-Right":
            threeSwipe(dx: 0.14, dy: 0)
        case "Four-Swipe-Up":
            fourSwipe(dx: 0, dy: 0.14)
        case "Four-Swipe-Down":
            fourSwipe(dx: 0, dy: -0.14)
        case "Four-Swipe-Left":
            fourSwipe(dx: -0.14, dy: 0)
        case "Four-Swipe-Right":
            fourSwipe(dx: 0.14, dy: 0)
        case "Left-Side Scroll":
            sideScroll(left: true)
        case "Right-Side Scroll":
            sideScroll(left: false)
        default:
            fallbackTrackpad(gesture)
        }
    }

    func createMagicMouse(_ gesture: String) {
        switch gesture {
        case "Middle-Fix Index-Slide-Out":
            mouseFixedSlide(fixedX: 0.75, startX: 0.45, endX: 0.25)
        case "Middle-Fix Index-Slide-In":
            mouseFixedSlide(fixedX: 0.75, startX: 0.25, endX: 0.45)
        case "Index-Fix Middle-Slide-In":
            mouseFixedSlide(fixedX: 0.25, startX: 0.75, endX: 0.60)
        case "Index-Fix Middle-Slide-Out":
            mouseFixedSlide(fixedX: 0.25, startX: 0.60, endX: 0.75)
        case "Three-Swipe-Left":
            mouseThreeSwipe(dx: -0.15, dy: 0)
        case "Three-Swipe-Right":
            mouseThreeSwipe(dx: 0.15, dy: 0)
        case "Three-Swipe-Up":
            mouseThreeSwipe(dx: 0, dy: 0.08)
        case "Three-Swipe-Down":
            mouseThreeSwipe(dx: 0, dy: -0.08)
        case "Three-Finger Click":
            reset(0.7); segment(0.25, 0.75, 0.25, 0.75, 0.25, 0.4, pressed: true); segment(0.50, 0.75, 0.50, 0.75, 0.25, 0.4, pressed: true); segment(0.75, 0.75, 0.75, 0.75, 0.25, 0.4, pressed: true)
        case "Middle-Fix Index-Near-Tap":
            reset(0.6); segment(0.50, 0.75, 0.50, 0.75, 0.3, 0.45); segment(0.75, 0.75, 0.75, 0.75, 0, 1)
        case "Middle-Fix Index-Far-Tap":
            reset(0.6); segment(0.25, 0.75, 0.25, 0.75, 0.3, 0.45); segment(0.75, 0.75, 0.75, 0.75, 0, 1)
        case "Index-Fix Middle-Near-Tap":
            reset(0.6); segment(0.50, 0.75, 0.50, 0.75, 0.3, 0.45); segment(0.25, 0.75, 0.25, 0.75, 0, 1)
        case "Index-Fix Middle-Far-Tap":
            reset(0.6); segment(0.75, 0.75, 0.75, 0.75, 0.3, 0.45); segment(0.25, 0.75, 0.25, 0.75, 0, 1)
        case "One-Fix Left-Tap":
            reset(0.6); segment(0.30, 0.75, 0.30, 0.75, 0.3, 0.45); segment(0.70, 0.75, 0.70, 0.75, 0, 1)
        case "One-Fix Right-Tap":
            reset(0.6); segment(0.30, 0.75, 0.30, 0.75, 0, 1); segment(0.70, 0.75, 0.70, 0.75, 0.3, 0.45)
        case "V-Shape":
            reset(1); segment(0.11, 0.84, 0.11, 0.84, 0, 4); segment(0.87, 0.84, 0.87, 0.84, 0, 4)
        case "Thumb":
            reset(0.7); segment(0.15, 0.55, 0.15, 0.55, 0, 1)
        case "Middle Click":
            reset(0.7); segment(0.75, 0.75, 0.75, 0.75, 0.25, 0.4, pressed: true); segment(0.50, 0.75, 0.50, 0.75, 0.25, 0.4, pressed: true)
        case "Two-Fix One-Slide-Up":
            mouseTwoFixOneSlide(dx: 0, dy: 0.06)
        case "Two-Fix One-Slide-Down":
            mouseTwoFixOneSlide(dx: 0, dy: -0.06)
        case "Two-Fix One-Slide-Left":
            mouseTwoFixOneSlide(dx: -0.08, dy: 0)
        case "Two-Fix One-Slide-Right":
            mouseTwoFixOneSlide(dx: 0.08, dy: 0)
        default:
            createTrackpad(gesture)
        }
    }

    private func threeFingerTap() {
        reset(3.8)
        segment(0.36, 0.50, 0.36, 0.50, 0.25, 0.4); segment(0.50, 0.53, 0.50, 0.53, 0.25, 0.4); segment(0.64, 0.51, 0.64, 0.51, 0.25, 0.4)
        segment(0.36, 0.50, 0.36, 0.50, 1, 1.9); segment(0.50, 0.53, 0.50, 0.53, 1.5, 1.65); segment(0.64, 0.51, 0.64, 0.51, 1.5, 1.65)
        segment(0.36, 0.50, 0.36, 0.50, 3, 3.15); segment(0.50, 0.53, 0.50, 0.53, 2.5, 3.5); segment(0.64, 0.51, 0.64, 0.51, 3, 3.15)
    }

    private func threeFingerClick() {
        reset(0.7)
        segment(0.36, 0.50, 0.36, 0.50, 0, 1); segment(0.50, 0.53, 0.50, 0.53, 0, 1); segment(0.64, 0.51, 0.64, 0.51, 0, 1)
        segment(0.36, 0.50, 0.36, 0.50, 0.25, 0.4, pressed: true); segment(0.50, 0.53, 0.50, 0.53, 0.25, 0.4, pressed: true); segment(0.64, 0.51, 0.64, 0.51, 0.25, 0.4, pressed: true)
    }

    private func fourFingerTap() {
        reset(2.5)
        let points: [CGPoint] = [CGPoint(x: 0.29, y: 0.50), CGPoint(x: 0.43, y: 0.53), CGPoint(x: 0.57, y: 0.51), CGPoint(x: 0.71, y: 0.48)]
        for point in points { segment(point.x, point.y, point.x, point.y, 0.25, 0.4) }
        for (index, point) in points.enumerated() { segment(point.x, point.y, point.x, point.y, index == 0 ? 1 : 1.5, index == 0 ? 1.9 : 1.65) }
    }

    private func fourFingerClick() {
        reset(0.7)
        let points: [CGPoint] = [CGPoint(x: 0.29, y: 0.50), CGPoint(x: 0.43, y: 0.53), CGPoint(x: 0.57, y: 0.51), CGPoint(x: 0.71, y: 0.48)]
        for point in points { segment(point.x, point.y, point.x, point.y, 0, 1) }
        for point in points { segment(point.x, point.y, point.x, point.y, 0.25, 0.4, pressed: true) }
    }

    private func indexToPinky() {
        reset(1); segment(0.29, 0.45, 0.29, 0.45, 0, 0.4); segment(0.43, 0.51, 0.43, 0.51, 0.1, 0.4); segment(0.57, 0.485, 0.57, 0.485, 0.2, 0.4); segment(0.71, 0.43, 0.71, 0.43, 0.3, 0.4)
    }

    private func pinkyToIndex() {
        reset(1); segment(0.29, 0.45, 0.29, 0.45, 0.3, 0.4); segment(0.43, 0.51, 0.43, 0.51, 0.2, 0.4); segment(0.57, 0.485, 0.57, 0.485, 0.1, 0.4); segment(0.71, 0.43, 0.71, 0.43, 0, 0.4)
    }

    private func moveResize() {
        reset(3); segment(0.43, 0.50, 0.43, 0.50, 0, 3); segmentHold(0.57, 0.57, 0.57, 0.43, 0.4, 0.8, 0.33, 1); segment(0.57, 0.50, 0.57, 0.50, 1.5, 1.65); segmentHold(0.57, 0.43, 0.57, 0.57, 2.15, 2.55, 2.08, 2.75)
    }

    private func oneFixTwoSlide(up: Bool, pressed: Bool) {
        reset(1.1)
        segment(0.36, 0.50, 0.36, 0.50, 0, 1.1, pressed: pressed)
        let y1: CGFloat = up ? 0.41 : 0.62
        let y2: CGFloat = up ? 0.62 : 0.41
        segmentHold(0.50, y1, 0.50, y2, 0.4, 0.8, 0.33, 1)
        segmentHold(0.64, up ? 0.38 : 0.60, 0.64, up ? 0.60 : 0.38, 0.4, 0.8, 0.33, 1)
    }

    private func twoFixOneDoubleTap(_ type: Int) {
        reset(1)
        let fixed = [CGPoint(x: 0.36, y: 0.50), CGPoint(x: 0.50, y: 0.53), CGPoint(x: 0.64, y: 0.51)]
        for (index, point) in fixed.enumerated() where index != type { segment(point.x, point.y, point.x, point.y, 0, 1) }
        let tap = fixed[type]
        segment(tap.x, tap.y, tap.x, tap.y, 0.5, 0.6)
        segment(tap.x, tap.y, tap.x, tap.y, 0.7, 0.8)
    }

    private func twoFixOneSlide(dx: CGFloat, dy: CGFloat) {
        reset(1)
        segment(0.50, 0.50, 0.50, 0.50, 0, 4)
        segment(0.64, 0.49, 0.64, 0.49, 0, 4)
        segmentHold(0.36, 0.48, 0.36 + dx, 0.48 + dy, 0.5, 0.75, 0.46, 0.83)
    }

    private func threeSwipe(dx: CGFloat, dy: CGFloat) {
        reset(0.8)
        let points = [CGPoint(x: 0.36, y: 0.50), CGPoint(x: 0.50, y: 0.53), CGPoint(x: 0.64, y: 0.50)]
        for point in points { segmentHold(point.x - dx / 2, point.y - dy / 2, point.x + dx / 2, point.y + dy / 2, 0.3, 0.55, 0, 0.63) }
    }

    private func fourSwipe(dx: CGFloat, dy: CGFloat) {
        reset(0.8)
        let points = [CGPoint(x: 0.29, y: 0.50), CGPoint(x: 0.43, y: 0.53), CGPoint(x: 0.57, y: 0.53), CGPoint(x: 0.71, y: 0.50)]
        for point in points { segmentHold(point.x - dx / 2, point.y - dy / 2, point.x + dx / 2, point.y + dy / 2, 0.3, 0.55, 0, 0.63) }
    }

    private func sideScroll(left: Bool) {
        reset(2.1)
        let xs: [CGFloat] = left ? [0.05, 0.15] : [0.95, 0.85]
        for x in xs { segmentHold(x, 0.50, x, 0.60, 0.2, 0.8, 0.1, 0.8) }
        for x in xs { segmentHold(x, 0.60, x, 0.40, 0.8, 1.4, 0.8, 1.4) }
        for x in xs { segmentHold(x, 0.40, x, 0.50, 1.4, 2.0, 1.4, 2.1) }
    }

    private func fallbackTrackpad(_ gesture: String) {
        reset(1)
        if gesture.contains("Four") { fourSwipe(dx: 0.10, dy: 0) }
        else if gesture.contains("Three") { threeSwipe(dx: 0.10, dy: 0) }
        else { segment(0.50, 0.50, 0.50, 0.50, 0.25, 0.7) }
    }

    private func mouseFixedSlide(fixedX: CGFloat, startX: CGFloat, endX: CGFloat) {
        reset(1); segment(fixedX, 0.75, fixedX, 0.75, 0, 4); segmentHold(startX, 0.75, endX, 0.75, 0.5, 0.75, 0.46, 0.83)
    }

    private func mouseThreeSwipe(dx: CGFloat, dy: CGFloat) {
        reset(1)
        let points = [CGPoint(x: 0.25, y: 0.75), CGPoint(x: 0.50, y: 0.75), CGPoint(x: 0.75, y: 0.75)]
        for point in points { segmentHold(point.x - dx / 2, point.y - dy / 2, point.x + dx / 2, point.y + dy / 2, 0.5, 0.75, 0.46, 0.83) }
    }

    private func mouseTwoFixOneSlide(dx: CGFloat, dy: CGFloat) {
        reset(1)
        segment(0.50, 0.75, 0.50, 0.75, 0, 4)
        segment(0.75, 0.75, 0.75, 0.75, 0, 4)
        segmentHold(0.25, 0.75, 0.25 + dx, 0.75 + dy, 0.5, 0.75, 0.46, 0.85)
    }
}

struct AddGestureSheet: View {
    @ObservedObject var model: PreferencesViewModel
    @Environment(\.dismiss) private var dismiss
    private let labelWidth: CGFloat = 150
    private let columnSpacing: CGFloat = 16
    private let controlWidth: CGFloat = 320
    private var formWidth: CGFloat { labelWidth + columnSpacing + controlWidth }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Add Gesture"))
                .font(.title2.weight(.semibold))
                .frame(width: formWidth, alignment: .leading)

            settingsRow(L("Application"), labelWidth: labelWidth, controlWidth: controlWidth, spacing: columnSpacing) {
                menuControl(title: selectedApplicationTitle, icon: selectedApplicationIcon) {
                    if let allApplications = model.addApplicationOptions.first {
                        applicationMenuButton(allApplications)
                        Divider()
                    }
                    ForEach(model.addApplicationOptions.dropFirst()) { app in
                        applicationMenuButton(app)
                    }
                }
            }

            settingsRow(L("Gesture"), labelWidth: labelWidth, controlWidth: controlWidth, spacing: columnSpacing) {
                AddGesturePicker(
                    selection: $model.addGesture,
                    gestures: model.availableAddGestures(),
                    device: model.selectedDevice,
                    width: controlWidth
                )
            }

            settingsRow(L("Type"), labelWidth: labelWidth, controlWidth: controlWidth, spacing: columnSpacing) {
                addModeControl
            }

            if model.addMode == .action {
                settingsRow(L("Command"), labelWidth: labelWidth, controlWidth: controlWidth, spacing: columnSpacing) {
                    menuControl(title: model.addCommand) {
                        ForEach(model.commands, id: \.self) { command in
                            Button {
                                model.addCommand = command
                            } label: {
                                menuItemLabel(title: command, isSelected: command == model.addCommand)
                            }
                        }
                    }
                }
            }

            if model.addMode == .shortcut {
                settingsRow(L("Keyboard Shortcut"), labelWidth: labelWidth, controlWidth: controlWidth, spacing: columnSpacing) {
                    ShortcutRecorder(
                        text: $model.addShortcutText,
                        modifierFlags: $model.addShortcutFlags,
                        keyCode: $model.addShortcutKeyCode,
                        shouldBecomeFirstResponder: model.addMode == .shortcut
                    )
                    .frame(width: controlWidth, height: 30)
                }
            }

            settingsRow(L("Enabled"), labelWidth: labelWidth, controlWidth: controlWidth, spacing: columnSpacing) {
                Toggle("", isOn: $model.addEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            HStack {
                Button(L("Cancel")) { dismiss() }
                Button(L("Add")) {
                    model.commitAdd()
                    dismiss()
                }
                .disabled(model.addGesture.isEmpty || (model.addMode == .shortcut && model.addShortcutText.isEmpty))
                .buttonStyle(.borderedProminent)
            }
            .frame(width: formWidth, alignment: .trailing)
        }
        .padding(28)
        .frame(width: formWidth + 56)
    }

    private var selectedApplicationOption: PreferencesViewModel.ApplicationOption? {
        model.addApplicationOptions.first { $0.application == model.addApplication }
    }

    private var selectedApplicationTitle: String {
        selectedApplicationOption?.title ?? model.addApplication
    }

    private var selectedApplicationIcon: NSImage? {
        selectedApplicationOption?.icon
    }

    private var addModeControl: some View {
        HStack(spacing: 0) {
            ForEach(PreferencesViewModel.AddMode.allCases) { mode in
                Button {
                    model.addMode = mode
                } label: {
                    Text(mode.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(model.addMode == mode ? Color.accentColor : Color.clear)
                        }
                        .foregroundStyle(model.addMode == mode ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .frame(width: controlWidth)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func applicationMenuButton(_ app: PreferencesViewModel.ApplicationOption) -> some View {
        Button {
            model.handleAddApplicationSelection(app.application)
        } label: {
            if let icon = app.icon {
                Label {
                    Text(app.title)
                } icon: {
                    Image(nsImage: icon)
                }
            } else {
                Text(app.title)
            }
        }
    }

    private func menuItemLabel(title: String, isSelected: Bool) -> some View {
        Text(menuItemTitle(title, isSelected: isSelected))
    }

    private func menuItemTitle(_ title: String, isSelected: Bool) -> String {
        "\(menuItemCheckmark(isSelected: isSelected)) \(title)"
    }

    private func menuItemCheckmark(isSelected: Bool) -> String {
        isSelected ? "✓" : "  "
    }

    private func menuControl<Content: View>(
        title: String,
        icon: NSImage? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 8) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 14, height: 14)
                }
                Text(title.isEmpty ? "-" : title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(width: controlWidth, height: 30)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct AddGesturePicker: View {
    @Binding var selection: String
    let gestures: [String]
    let device: GestureDevice
    let width: CGFloat
    @State private var isShowingPopover = false
    @State private var hoveredGesture: String?

    var body: some View {
        Button {
            hoveredGesture = selection.isEmpty ? gestures.first : selection
            isShowingPopover = true
        } label: {
            HStack(spacing: 8) {
                Text(selection.isEmpty ? "-" : selection)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(width: width, height: 30)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingPopover, arrowEdge: .trailing) {
            HStack(spacing: 14) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(gestures, id: \.self) { gesture in
                            gestureRow(gesture)
                        }
                    }
                    .padding(6)
                }
                .frame(width: 250, height: 260)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                GestureAnimationPreview(gesture: previewGesture, device: device)
                    .frame(width: 220)
            }
            .padding(12)
            .onAppear {
                hoveredGesture = selection.isEmpty ? gestures.first : selection
            }
        }
    }

    private func gestureRow(_ gesture: String) -> some View {
        Button {
            selection = gesture
            hoveredGesture = gesture
            isShowingPopover = false
        } label: {
            HStack(spacing: 8) {
                Text(gesture == selection ? "✓" : " ")
                    .font(.body.weight(.semibold))
                    .frame(width: 14)
                Text(gesture)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(gesture == previewGesture ? Color.accentColor.opacity(0.16) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering {
                hoveredGesture = gesture
            }
        }
    }

    private var previewGesture: String {
        if let hoveredGesture, hoveredGesture.isEmpty == false {
            return hoveredGesture
        }
        if selection.isEmpty == false {
            return selection
        }
        return gestures.first ?? ""
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var model: PreferencesViewModel
    private let labelWidth: CGFloat = 220
    private let controlWidth: CGFloat = 260
    private let columnSpacing: CGFloat = 24

    var body: some View {
        Form {
            Section {
                switchRow(L("Enable Jitouch"), isOn: binding(\.isEnabled))
                switchRow(L("Show menu bar icon"), isOn: binding(\.showsMenuBarIcon))
                iCloudSyncRow()
                languageRow(Binding(
                    get: { model.generalSettings.appLanguage },
                    set: { value in model.updateGeneral { $0.appLanguage = value } }
                ))
                themeRow(Binding(
                    get: { model.generalSettings.themeMode },
                    set: { value in model.updateGeneral { $0.themeMode = value } }
                ))
                slider(L("Click speed"), value: Binding(
                    get: { model.generalSettings.clickSpeed },
                    set: { newValue in model.updateGeneral { $0.clickSpeed = newValue } }
                ), range: 0.05...0.5)
                slider(L("Sensitivity"), value: Binding(
                    get: { model.generalSettings.sensitivity },
                    set: { newValue in model.updateGeneral { $0.sensitivity = newValue } }
                ), range: 1...8)
            } header: {
                Text(L("General"))
            }

            Section {
                switchRow(L("Enable trackpad gestures"), isOn: binding(\.trackpadEnabled))
                handednessRow(Binding(
                    get: { model.generalSettings.trackpadLeftHanded },
                    set: { value in model.updateGeneral { $0.trackpadLeftHanded = value } }
                ))
            } header: {
                Text(L("Trackpad"))
            }

            Section {
                switchRow(L("Enable Magic Mouse gestures"), isOn: binding(\.magicMouseEnabled))
                handednessRow(Binding(
                    get: { model.generalSettings.magicMouseLeftHanded },
                    set: { value in model.updateGeneral { $0.magicMouseLeftHanded = value } }
                ))
            } header: {
                Text(L("Magic Mouse"))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func binding(_ keyPath: WritableKeyPath<JitouchSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.generalSettings[keyPath: keyPath] },
            set: { value in model.updateGeneral { $0[keyPath: keyPath] = value } }
        )
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        generalRow(label) {
            Slider(value: value, in: range)
                .frame(width: controlWidth)
        }
    }

    private func switchRow(_ label: String, isOn: Binding<Bool>) -> some View {
        generalRow(label) {
            HStack {
                Spacer()
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .frame(width: controlWidth)
        }
    }

    private func iCloudSyncRow() -> some View {
        generalRow(L("Sync with iCloud")) {
            HStack(spacing: 10) {
                Text(iCloudSyncStatusText)
                    .font(.caption)
                    .foregroundStyle(iCloudSyncStatusColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Button(L("Sync Now")) {
                    model.syncICloudNow()
                }
                .disabled(model.generalSettings.iCloudSyncEnabled == false || model.iCloudSyncState.status == .syncing)

                Toggle("", isOn: binding(\.iCloudSyncEnabled))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .frame(width: controlWidth, alignment: .trailing)
        }
    }

    private func handednessRow(_ selection: Binding<Bool>) -> some View {
        generalRow(L("Handedness")) {
            HStack {
                Spacer(minLength: 0)
                handednessControl(selection)
            }
            .frame(width: controlWidth, alignment: .trailing)
        }
    }

    private func languageRow(_ selection: Binding<AppLanguage>) -> some View {
        generalRow(L("Language")) {
            HStack {
                Spacer(minLength: 0)
                Picker("", selection: selection) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(languageTitle(language)).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .frame(width: controlWidth, alignment: .trailing)
        }
    }

    private func themeRow(_ selection: Binding<AppThemeMode>) -> some View {
        generalRow(L("Theme Mode")) {
            HStack {
                Spacer(minLength: 0)
                Picker("", selection: selection) {
                    ForEach(AppThemeMode.allCases) { themeMode in
                        Text(themeTitle(themeMode)).tag(themeMode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .frame(width: controlWidth, alignment: .trailing)
        }
    }

    private func handednessControl(_ selection: Binding<Bool>) -> some View {
        HStack(spacing: 0) {
            segmentedButton(title: L("Right"), isSelected: selection.wrappedValue == false) {
                selection.wrappedValue = false
            }
            segmentedButton(title: L("Left"), isSelected: selection.wrappedValue == true) {
                selection.wrappedValue = true
            }
        }
        .padding(2)
        .frame(width: controlWidth)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func segmentedButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                }
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func languageTitle(_ language: AppLanguage) -> String {
        switch language {
        case .system:
            return L("System")
        case .english:
            return L("English")
        case .simplifiedChinese:
            return L("Chinese")
        }
    }

    private func themeTitle(_ themeMode: AppThemeMode) -> String {
        switch themeMode {
        case .system:
            return L("System")
        case .light:
            return L("Light")
        case .dark:
            return L("Dark")
        }
    }

    private var iCloudSyncStatusText: String {
        switch model.iCloudSyncState.status {
        case .disabled:
            return L("iCloud sync is off.")
        case .waiting:
            return L("Waiting for iCloud.")
        case .syncing:
            return L("Syncing with iCloud...")
        case .synced:
            if let lastSyncDate = model.iCloudSyncState.lastSyncDate {
                let time = DateFormatter.localizedString(from: lastSyncDate, dateStyle: .none, timeStyle: .medium)
                return String(format: L("Last synced: %@"), time)
            }
            return L("Synced with iCloud.")
        case .failed:
            return model.iCloudSyncState.message.map(L) ?? L("iCloud sync failed.")
        }
    }

    private var iCloudSyncStatusColor: Color {
        switch model.iCloudSyncState.status {
        case .failed:
            return .red
        case .waiting:
            return .orange
        case .synced:
            return .secondary
        case .disabled, .syncing:
            return .secondary
        }
    }

    private func generalRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: columnSpacing) {
            Text(label)
                .frame(width: labelWidth, alignment: .leading)
            Spacer(minLength: columnSpacing)
            content()
                .frame(width: controlWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var text: String
    @Binding var modifierFlags: UInt64
    @Binding var keyCode: UInt16
    var shouldBecomeFirstResponder: Bool

    func makeNSView(context: Context) -> ShortcutRecorderField {
        let field = ShortcutRecorderField()
        field.placeholderString = L("Press shortcut")
        field.isEditable = false
        field.isSelectable = false
        field.focusRingType = .default
        field.onChange = { text, flags, keyCode in
            self.text = text
            self.modifierFlags = flags
            self.keyCode = keyCode
        }
        return field
    }

    func updateNSView(_ nsView: ShortcutRecorderField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if shouldBecomeFirstResponder, nsView.window?.firstResponder !== nsView {
            DispatchQueue.main.async {
                if nsView.window?.firstResponder !== nsView {
                    nsView.window?.makeFirstResponder(nsView)
                }
            }
        }
    }
}

final class ShortcutRecorderField: NSTextField {
    var onChange: ((String, UInt64, UInt16) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        return didBecomeFirstResponder
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        record(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        record(event)
        return true
    }

    private func record(_ event: NSEvent) {
        let flags = UInt64(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
        let keyCode = UInt16(event.keyCode)
        let text = Self.displayString(for: event)
        stringValue = text
        onChange?(text, flags, keyCode)
    }

    private static func displayString(for event: NSEvent) -> String {
        var parts: [String] = []
        if event.modifierFlags.contains(.control) { parts.append("^") }
        if event.modifierFlags.contains(.option) { parts.append("⌥") }
        if event.modifierFlags.contains(.shift) { parts.append("⇧") }
        if event.modifierFlags.contains(.command) { parts.append("⌘") }
        let key = displayKey(for: event)
        parts.append(key.isEmpty ? "Key \(event.keyCode)" : key)
        return parts.joined()
    }

    private static func displayKey(for event: NSEvent) -> String {
        if let specialKey = specialKeyTitle(for: event.keyCode) {
            return specialKey
        }

        let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard key.count == 1, key.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) else {
            return ""
        }
        return key
    }

    private static func specialKeyTitle(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "Esc"
        case 71: return "Clear"
        case 76: return "⌅"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 106: return "F16"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 114: return "Help"
        case 115: return "↖"
        case 116: return "⇞"
        case 117: return "⌦"
        case 118: return "F4"
        case 119: return "↘"
        case 120: return "F2"
        case 121: return "⇟"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return nil
        }
    }
}

private func deviceTitle(_ device: GestureDevice) -> String {
    switch device {
    case .trackpad: return L("Trackpad")
    case .magicMouse: return L("Magic Mouse")
    case .characterRecognition: return L("Character Recognition")
    }
}

private func settingsRow<Content: View>(
    _ label: String,
    labelWidth: CGFloat = 150,
    controlWidth: CGFloat? = nil,
    spacing: CGFloat = 8,
    @ViewBuilder content: () -> Content
) -> some View {
    HStack(spacing: spacing) {
        Text(label)
            .font(.body.weight(.semibold))
            .frame(width: labelWidth, alignment: .leading)
        content()
            .frame(width: controlWidth, alignment: .trailing)
    }
}
