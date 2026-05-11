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
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = NSToolbar()
        window.toolbar?.isVisible = false
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
        generalSettings = settingsStore.settings
        if applicationProfiles.contains(where: { $0.application == selectedApplication }) == false {
            selectedApplication = "All Applications"
        }
    }

    func selectDevice(_ device: GestureDevice) {
        selectedTab = device == .trackpad ? .trackpad : .magicMouse
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
            List(selection: $model.selectedTab) {
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
}

struct GestureSettingsView: View {
    @ObservedObject var model: PreferencesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            applicationSegmentedPicker

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

    private var applicationSegmentedPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(model.applicationOptions, id: \.self) { app in
                    Button {
                        model.selectedApplication = model.normalizedApplicationName(app)
                    } label: {
                        Text(app)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isSelectedApplication(app) ? Color.accentColor : Color.clear)
                            }
                            .foregroundStyle(isSelectedApplication(app) ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isSelectedApplication(_ app: String) -> Bool {
        model.normalizedApplicationName(app) == model.selectedApplication
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
                menuControl(title: model.addGesture) {
                    ForEach(model.availableAddGestures(), id: \.self) { gesture in
                        Button {
                            model.addGesture = gesture
                        } label: {
                            menuItemLabel(title: gesture, isSelected: gesture == model.addGesture)
                        }
                    }
                }
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
                    .liquidGlassButton()
                Button(L("Add")) {
                    model.commitAdd()
                    dismiss()
                }
                .disabled(model.addGesture.isEmpty || (model.addMode == .shortcut && model.addShortcutText.isEmpty))
                .liquidGlassButton(prominent: true)
            }
            .frame(width: formWidth, alignment: .trailing)
        }
        .padding(28)
        .frame(width: formWidth + 56)
        .liquidGlassCard()
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

struct GeneralSettingsView: View {
    @ObservedObject var model: PreferencesViewModel
    private let labelWidth: CGFloat = 220
    private let controlWidth: CGFloat = 260
    private let columnSpacing: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section(L("General")) {
                switchRow(L("Enable Jitouch"), isOn: binding(\.isEnabled))
                switchRow(L("Show menu bar icon"), isOn: binding(\.showsMenuBarIcon))
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
                switchRow(L("Enable trackpad gestures"), isOn: binding(\.trackpadEnabled))
                generalRow(L("Handedness")) {
                    Picker("", selection: Binding(
                        get: { model.generalSettings.trackpadLeftHanded },
                        set: { value in model.updateGeneral { $0.trackpadLeftHanded = value } }
                    )) {
                        Text(L("Right")).tag(false)
                        Text(L("Left")).tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: controlWidth)
                }
            }

            section(L("Magic Mouse")) {
                switchRow(L("Enable Magic Mouse gestures"), isOn: binding(\.magicMouseEnabled))
                generalRow(L("Handedness")) {
                    Picker("", selection: Binding(
                        get: { model.generalSettings.magicMouseLeftHanded },
                        set: { value in model.updateGeneral { $0.magicMouseLeftHanded = value } }
                    )) {
                        Text(L("Right")).tag(false)
                        Text(L("Left")).tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: controlWidth)
                }
            }
        }
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

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
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
        field.isEditable = true
        field.isSelectable = true
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
        if shouldBecomeFirstResponder, nsView.window?.firstResponder !== nsView.currentEditor() {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

final class ShortcutRecorderField: NSTextField {
    var onChange: ((String, UInt64, UInt16) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        currentEditor()?.selectedRange = NSRange(location: stringValue.count, length: 0)
        return didBecomeFirstResponder
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

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
