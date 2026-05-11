import AppKit
import SwiftUI
import UniformTypeIdentifiers

private func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
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
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("Jitouch Gesture Settings")
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
}

@MainActor
final class PreferencesViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case gestures
        case general

        var id: String { rawValue }
        var title: String {
            switch self {
            case .gestures: L("Gestures")
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

    private let settingsStore: SettingsStore
    private let onChange: () -> Void

    @Published var selectedTab: Tab = .gestures
    @Published var selectedDevice: GestureDevice = .trackpad
    @Published var selectedApplication = "All Applications"
    @Published var selectedGesture: String?
    @Published var isShowingAddSheet = false
    @Published var isShowingRestoreAlert = false
    @Published var generalSettings = JitouchSettings()

    @Published var addApplication = "All Applications"
    @Published var addGesture = ""
    @Published var addMode: AddMode = .action
    @Published var addCommand = "-"
    @Published var addShortcutText = ""
    @Published var addShortcutFlags: UInt64 = 0
    @Published var addShortcutKeyCode: UInt16 = 0
    @Published var addEnabled = true
    @Published private var temporaryApplicationPaths: [String: String] = [:]

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
        reload()
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
        generalSettings = settingsStore.settings
        if applicationProfiles.contains(where: { $0.application == selectedApplication }) == false {
            selectedApplication = "All Applications"
        }
    }

    func selectDevice(_ device: GestureDevice) {
        selectedDevice = device
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

    func addApplicationOptions() -> [String] {
        applicationOptions + [L("Other...")]
    }

    func handleAddApplicationSelection(_ value: String) {
        if value == L("Other...") {
            chooseApplicationForAddSheet()
        } else {
            addApplication = normalizedApplicationName(value)
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
        generalSettings = settingsStore.settings
        finishSettingsChange()
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
        addApplication = name
        refreshAddGesture()
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
            List(selection: $model.selectedTab) {
                ForEach(PreferencesViewModel.Tab.allCases) { tab in
                    Label(tab.title, systemImage: sidebarIcon(for: tab))
                        .tag(tab)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            switch model.selectedTab {
            case .gestures:
                GestureSettingsView(model: model)
                    .liquidGlassCard()
                    .padding(24)
            case .general:
                GeneralSettingsView(model: model)
                    .liquidGlassCard()
                    .padding(24)
            }
        }
        .navigationTitle(L("Jitouch Gesture Settings"))
        .frame(minWidth: 920, minHeight: 580)
        .background {
            LinearGradient(colors: [Color(nsColor: .windowBackgroundColor), Color.accentColor.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        }
    }

    private func sidebarIcon(for tab: PreferencesViewModel.Tab) -> String {
        switch tab {
        case .gestures:
            return "hand.tap"
        case .general:
            return "gearshape"
        }
    }
}

struct GestureSettingsView: View {
    @ObservedObject var model: PreferencesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Picker("", selection: Binding(
                    get: { model.selectedDevice },
                    set: { model.selectDevice($0) }
                )) {
                    ForEach(model.deviceOptions, id: \.self) { device in
                        Text(deviceTitle(device)).tag(device)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 230)

                Picker("", selection: Binding(
                    get: { model.displayName(for: model.selectedApplication) },
                    set: { model.selectedApplication = model.normalizedApplicationName($0) }
                )) {
                    ForEach(model.applicationOptions, id: \.self) { app in
                        Text(app).tag(app)
                    }
                }
                .frame(width: 240)
            }

            commandHeader

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.commandRows) { row in
                        CommandRowView(
                            model: model,
                            row: row,
                            isSelected: row.id == model.selectedGesture
                        )
                        .onTapGesture { model.selectedGesture = row.id }
                    }
                }
                .padding(8)
            }
            .frame(minHeight: 310)
            .liquidGlassSurface()

            HStack(spacing: 10) {
                Button(L("Add...")) { model.beginAdd() }
                    .disabled(!model.canAdd)
                    .liquidGlassButton(prominent: true)
                Button(L("Delete")) { model.deleteSelectedCommand() }
                    .disabled(!model.canDelete)
                    .liquidGlassButton()
                Button(L("Restore Defaults")) { model.isShowingRestoreAlert = true }
                    .liquidGlassButton()
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

    private var commandHeader: some View {
        HStack {
            Text(L("On")).frame(width: 44, alignment: .leading)
            Text(L("Gesture")).frame(maxWidth: .infinity, alignment: .leading)
            Text(L("Command")).frame(width: 260, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
    }
}

struct CommandRowView: View {
    @ObservedObject var model: PreferencesViewModel
    var row: PreferencesViewModel.CommandRow
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { row.command.isEnabled },
                set: { value in
                    var command = row.command
                    command.isEnabled = value
                    model.update(command)
                }
            ))
            .labelsHidden()
            .frame(width: 44)

            Text(row.command.gesture)
                .lineLimit(1)
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
                .frame(width: 260)
            } else {
                Text(row.command.command)
                    .foregroundStyle(.secondary)
                    .frame(width: 260, alignment: .leading)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.035))
        }
    }
}

struct AddGestureSheet: View {
    @ObservedObject var model: PreferencesViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Add Gesture"))
                .font(.title2.weight(.semibold))

            settingsRow(L("Application")) {
                Picker("", selection: Binding(
                    get: { model.displayName(for: model.addApplication) },
                    set: { model.handleAddApplicationSelection($0) }
                )) {
                    ForEach(model.addApplicationOptions(), id: \.self) { app in
                        Text(app).tag(app)
                    }
                }
                .frame(width: 300)
            }

            settingsRow(L("Gesture")) {
                Picker("", selection: $model.addGesture) {
                    ForEach(model.availableAddGestures(), id: \.self) { gesture in
                        Text(gesture).tag(gesture)
                    }
                }
                .frame(width: 300)
            }

            settingsRow(L("Type")) {
                Picker("", selection: $model.addMode) {
                    ForEach(PreferencesViewModel.AddMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }

            settingsRow(L("Command")) {
                Picker("", selection: $model.addCommand) {
                    ForEach(model.commands, id: \.self) { command in
                        Text(command).tag(command)
                    }
                }
                .frame(width: 300)
                .disabled(model.addMode != .action)
            }

            settingsRow(L("Keyboard Shortcut")) {
                ShortcutRecorder(
                    text: $model.addShortcutText,
                    modifierFlags: $model.addShortcutFlags,
                    keyCode: $model.addShortcutKeyCode
                )
                .frame(width: 300, height: 28)
                .disabled(model.addMode != .shortcut)
            }

            Toggle(L("Enabled"), isOn: $model.addEnabled)

            HStack {
                Button(L("Cancel")) { dismiss() }
                    .liquidGlassButton()
                Button(L("Add")) {
                    model.commitAdd()
                    dismiss()
                }
                .disabled(model.addGesture.isEmpty || (model.addMode == .shortcut && model.addShortcutText.isEmpty))
                .liquidGlassButton(prominent: true)
            }
        }
        .padding(28)
        .frame(width: 560)
        .liquidGlassCard()
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var model: PreferencesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section(L("General")) {
                Toggle(L("Enable Jitouch"), isOn: binding(\.isEnabled))
                Toggle(L("Show menu bar icon"), isOn: binding(\.showsMenuBarIcon))
                slider(L("Click speed"), value: Binding(
                    get: { model.generalSettings.clickSpeed },
                    set: { newValue in model.updateGeneral { $0.clickSpeed = newValue } }
                ), range: 0.05...0.5)
                slider(L("Sensitivity"), value: Binding(
                    get: { model.generalSettings.sensitivity },
                    set: { newValue in model.updateGeneral { $0.sensitivity = newValue } }
                ), range: 1...8)
            }

            section(L("Trackpad")) {
                Toggle(L("Enable trackpad gestures"), isOn: binding(\.trackpadEnabled))
                Picker(L("Handedness"), selection: Binding(
                    get: { model.generalSettings.trackpadLeftHanded },
                    set: { value in model.updateGeneral { $0.trackpadLeftHanded = value } }
                )) {
                    Text(L("Right")).tag(false)
                    Text(L("Left")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            section(L("Magic Mouse")) {
                Toggle(L("Enable Magic Mouse gestures"), isOn: binding(\.magicMouseEnabled))
                Picker(L("Handedness"), selection: Binding(
                    get: { model.generalSettings.magicMouseLeftHanded },
                    set: { value in model.updateGeneral { $0.magicMouseLeftHanded = value } }
                )) {
                    Text(L("Right")).tag(false)
                    Text(L("Left")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding(_ keyPath: WritableKeyPath<JitouchSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.generalSettings[keyPath: keyPath] },
            set: { value in model.updateGeneral { $0[keyPath: keyPath] = value } }
        )
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label).frame(width: 190, alignment: .leading)
            Slider(value: value, in: range).frame(width: 240)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .padding(.bottom, 4)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var text: String
    @Binding var modifierFlags: UInt64
    @Binding var keyCode: UInt16

    func makeNSView(context: Context) -> ShortcutRecorderField {
        let field = ShortcutRecorderField()
        field.placeholderString = L("Press shortcut")
        field.isEditable = false
        field.isSelectable = false
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
    }
}

final class ShortcutRecorderField: NSTextField {
    var onChange: ((String, UInt64, UInt16) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
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
        let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
        parts.append(key.isEmpty ? "Key \(event.keyCode)" : key)
        return parts.joined()
    }
}

private func deviceTitle(_ device: GestureDevice) -> String {
    switch device {
    case .trackpad: return L("Trackpad")
    case .magicMouse: return L("Magic Mouse")
    case .characterRecognition: return L("Character Recognition")
    }
}

private func settingsRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
    HStack {
        Text(label)
            .font(.body.weight(.semibold))
            .frame(width: 150, alignment: .leading)
        content()
    }
}

private extension View {
    @ViewBuilder
    func liquidGlassCard() -> some View {
        if #available(macOS 26.0, *) {
            self
                .padding(22)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        } else {
            self
                .padding(22)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    func liquidGlassSurface() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            self.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    func liquidGlassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}
