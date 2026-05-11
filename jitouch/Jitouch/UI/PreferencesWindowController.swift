import AppKit
import UniformTypeIdentifiers

private func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

final class ShortcutRecorderField: NSTextField {
    var capturedModifierFlags: UInt64 = 0
    var capturedKeyCode: UInt16 = 0

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        capturedModifierFlags = UInt64(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
        capturedKeyCode = UInt16(event.keyCode)
        stringValue = Self.displayString(for: event)
    }

    func reset() {
        capturedModifierFlags = 0
        capturedKeyCode = 0
        stringValue = ""
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

protocol PreferencesWindowControllerDelegate: AnyObject {
    func preferencesWindowControllerDidChangeSettings(_ controller: PreferencesWindowController)
}

final class PreferencesWindowController: NSWindowController {
    weak var delegate: PreferencesWindowControllerDelegate?

    private let settingsStore: SettingsStore
    private let tabView = NSTabView()
    private let deviceControl = NSSegmentedControl(labels: [L("Trackpad"), L("Magic Mouse")], trackingMode: .selectOne, target: nil, action: nil)
    private let applicationControl = NSPopUpButton()
    private let gesturesTable = NSTableView()
    private let addButton = NSButton(title: L("Add..."), target: nil, action: nil)
    private let deleteButton = NSButton(title: L("Delete"), target: nil, action: nil)
    private let restoreDefaultsButton = NSButton(title: L("Restore Defaults"), target: nil, action: nil)
    private let addGesturePanel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 520, height: 330),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    private let addPanelTitle = NSTextField(labelWithString: L("Add Gesture"))
    private let addApplicationPopup = NSPopUpButton()
    private let addGesturePopup = NSPopUpButton()
    private let addModeControl = NSSegmentedControl(labels: [L("Action"), L("Keyboard Shortcut")], trackingMode: .selectOne, target: nil, action: nil)
    private let addCommandPopup = NSPopUpButton()
    private let shortcutField = ShortcutRecorderField()
    private let addEnabledSwitch = NSSwitch()
    private var addApplicationPaths: [String: String] = [:]
    private var selectedApplicationPath = ""
    private let commands = [
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
    private let enabledSwitch = NSSwitch()
    private let showIconSwitch = NSSwitch()
    private let trackpadSwitch = NSSwitch()
    private let trackpadHandedControl = NSSegmentedControl(labels: [L("Right"), L("Left")], trackingMode: .selectOne, target: nil, action: nil)
    private let magicMouseSwitch = NSSwitch()
    private let magicMouseHandedControl = NSSegmentedControl(labels: [L("Right"), L("Left")], trackingMode: .selectOne, target: nil, action: nil)
    private let clickSpeedSlider = NSSlider(value: 0.25, minValue: 0.05, maxValue: 0.5, target: nil, action: nil)
    private let sensitivitySlider = NSSlider(value: 4.6666, minValue: 1.0, maxValue: 8.0, target: nil, action: nil)

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("Jitouch Gesture Settings")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        super.init(window: window)
        window.contentView = makeContentView()
        configureAddGesturePanel()
        reloadControls()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        reloadControls()
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeContentView() -> NSView {
        let content = NSView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tabView)

        let gesturesItem = NSTabViewItem(identifier: "Gestures")
        gesturesItem.label = L("Gestures")
        gesturesItem.view = makeGesturesView()
        tabView.addTabViewItem(gesturesItem)

        let generalItem = NSTabViewItem(identifier: "General")
        generalItem.label = L("General")
        generalItem.view = makeGeneralView()
        tabView.addTabViewItem(generalItem)
        tabView.selectTabViewItem(gesturesItem)

        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            tabView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            tabView.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            tabView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])

        return content
    }

    private func makeGeneralView() -> NSView {
        let content = NSView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        stack.addArrangedSubview(sectionTitle(L("General")))
        stack.addArrangedSubview(row(L("Enable Jitouch"), enabledSwitch))
        stack.addArrangedSubview(row(L("Show menu bar icon"), showIconSwitch))
        stack.addArrangedSubview(sliderRow(L("Click speed"), clickSpeedSlider))
        stack.addArrangedSubview(sliderRow(L("Sensitivity"), sensitivitySlider))

        stack.addArrangedSubview(sectionTitle(L("Trackpad")))
        stack.addArrangedSubview(row(L("Enable trackpad gestures"), trackpadSwitch))
        stack.addArrangedSubview(row(L("Handedness"), trackpadHandedControl))

        stack.addArrangedSubview(sectionTitle(L("Magic Mouse")))
        stack.addArrangedSubview(row(L("Enable Magic Mouse gestures"), magicMouseSwitch))
        stack.addArrangedSubview(row(L("Handedness"), magicMouseHandedControl))

        for control in [enabledSwitch, showIconSwitch, trackpadSwitch, magicMouseSwitch] {
            control.target = self
            control.action = #selector(controlChanged)
        }
        for control in [trackpadHandedControl, magicMouseHandedControl] {
            control.target = self
            control.action = #selector(controlChanged)
        }
        for slider in [clickSpeedSlider, sensitivitySlider] {
            slider.target = self
            slider.action = #selector(controlChanged)
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
        ])

        return content
    }

    private func makeGesturesView() -> NSView {
        let content = NSView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        deviceControl.selectedSegment = 0
        deviceControl.target = self
        deviceControl.action = #selector(deviceChanged)
        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 12
        topRow.addArrangedSubview(deviceControl)

        applicationControl.target = self
        applicationControl.action = #selector(applicationChanged)
        applicationControl.widthAnchor.constraint(equalToConstant: 220).isActive = true
        topRow.addArrangedSubview(applicationControl)
        stack.addArrangedSubview(topRow)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.widthAnchor.constraint(equalToConstant: 640).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: 340).isActive = true

        gesturesTable.headerView = NSTableHeaderView()
        gesturesTable.delegate = self
        gesturesTable.dataSource = self
        gesturesTable.usesAlternatingRowBackgroundColors = true
        gesturesTable.rowHeight = 28
        gesturesTable.allowsEmptySelection = true
        gesturesTable.doubleAction = #selector(editSelectedCommand)
        gesturesTable.target = self

        let enabledColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("enabled"))
        enabledColumn.title = L("On")
        enabledColumn.width = 54
        gesturesTable.addTableColumn(enabledColumn)

        let gestureColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("gesture"))
        gestureColumn.title = L("Gesture")
        gestureColumn.width = 300
        gesturesTable.addTableColumn(gestureColumn)

        let commandColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        commandColumn.title = L("Command")
        commandColumn.width = 270
        gesturesTable.addTableColumn(commandColumn)

        scrollView.documentView = gesturesTable
        stack.addArrangedSubview(scrollView)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        addButton.target = self
        addButton.action = #selector(addCommand)
        deleteButton.target = self
        deleteButton.action = #selector(deleteCommand)
        restoreDefaultsButton.target = self
        restoreDefaultsButton.action = #selector(restoreDefaults)

        buttonRow.addArrangedSubview(addButton)
        buttonRow.addArrangedSubview(deleteButton)
        buttonRow.addArrangedSubview(restoreDefaultsButton)
        stack.addArrangedSubview(buttonRow)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18)
        ])

        return content
    }

    private func reloadControls() {
        let settings = settingsStore.settings
        enabledSwitch.state = settings.isEnabled ? .on : .off
        showIconSwitch.state = settings.showsMenuBarIcon ? .on : .off
        clickSpeedSlider.doubleValue = settings.clickSpeed
        sensitivitySlider.doubleValue = settings.sensitivity
        trackpadSwitch.state = settings.trackpadEnabled ? .on : .off
        trackpadHandedControl.selectedSegment = settings.trackpadLeftHanded ? 1 : 0
        magicMouseSwitch.state = settings.magicMouseEnabled ? .on : .off
        magicMouseHandedControl.selectedSegment = settings.magicMouseLeftHanded ? 1 : 0
        gesturesTable.reloadData()
        updateGestureButtons()
        reloadApplicationMenus()
    }

    @objc private func controlChanged() {
        settingsStore.updateGeneralSettings { settings in
            settings.isEnabled = enabledSwitch.state == .on
            settings.showsMenuBarIcon = showIconSwitch.state == .on
            settings.clickSpeed = clickSpeedSlider.doubleValue
            settings.sensitivity = sensitivitySlider.doubleValue
            settings.trackpadEnabled = trackpadSwitch.state == .on
            settings.trackpadLeftHanded = trackpadHandedControl.selectedSegment == 1
            settings.magicMouseEnabled = magicMouseSwitch.state == .on
            settings.magicMouseLeftHanded = magicMouseHandedControl.selectedSegment == 1
        }
        settingsStore.postRuntimeSettingsChanged()
        delegate?.preferencesWindowControllerDidChangeSettings(self)
    }

    @objc private func deviceChanged() {
        selectedApplicationPath = ""
        reloadApplicationMenus()
        gesturesTable.reloadData()
        updateGestureButtons()
    }

    @objc private func applicationChanged() {
        selectedApplicationPath = selectedApplicationProfile?.path ?? ""
        gesturesTable.reloadData()
        updateGestureButtons()
    }

    private var selectedDevice: GestureDevice {
        deviceControl.selectedSegment == 0 ? .trackpad : .magicMouse
    }

    private var displayedCommands: [GestureCommand] {
        settingsStore.commands(for: selectedDevice, application: selectedApplicationName)
    }

    private var selectedApplicationName: String {
        applicationControl.titleOfSelectedItem == L("All Applications") ? "All Applications" : (applicationControl.titleOfSelectedItem ?? "All Applications")
    }

    private var selectedApplicationProfile: AppGestureCommands? {
        settingsStore.applicationProfiles(for: selectedDevice).first { $0.application == selectedApplicationName }
    }

    private var selectedCommand: GestureCommand? {
        let row = gesturesTable.selectedRow
        guard row >= 0, row < displayedCommands.count else {
            return nil
        }
        return displayedCommands[row]
    }

    private func updateGestureButtons() {
        deleteButton.isEnabled = selectedCommand != nil
        addButton.isEnabled = !settingsStore.availableGestures(for: selectedDevice, application: selectedApplicationName).isEmpty
    }

    private func reloadApplicationMenus() {
        let profiles = settingsStore.applicationProfiles(for: selectedDevice)
        applicationControl.removeAllItems()
        addApplicationPopup.removeAllItems()
        addApplicationPaths = ["All Applications": ""]

        for profile in profiles {
            let title = profile.application == "All Applications" ? L("All Applications") : profile.application
            applicationControl.addItem(withTitle: title)
            addApplicationPopup.addItem(withTitle: title)
            addApplicationPaths[title] = profile.path
        }
        addApplicationPopup.menu?.addItem(.separator())
        addApplicationPopup.addItem(withTitle: L("Other..."))

        if profiles.contains(where: { $0.application == selectedApplicationName }) {
            applicationControl.selectItem(withTitle: selectedApplicationName == "All Applications" ? L("All Applications") : selectedApplicationName)
        } else {
            applicationControl.selectItem(at: 0)
        }
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .boldSystemFont(ofSize: 13)
        return field
    }

    private func row(_ label: String, _ control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let labelField = NSTextField(labelWithString: label)
        labelField.widthAnchor.constraint(equalToConstant: 190).isActive = true
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true

        row.addArrangedSubview(labelField)
        row.addArrangedSubview(control)
        return row
    }

    private func sliderRow(_ label: String, _ slider: NSSlider) -> NSView {
        slider.widthAnchor.constraint(equalToConstant: 170).isActive = true
        return row(label, slider)
    }

    private func configureAddGesturePanel() {
        addGesturePanel.title = L("Add Gesture")
        addGesturePanel.isReleasedWhenClosed = false
        addGesturePanel.isRestorable = false

        let content = NSView()
        addGesturePanel.contentView = content

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        addPanelTitle.font = .boldSystemFont(ofSize: 17)
        stack.addArrangedSubview(addPanelTitle)

        addApplicationPopup.target = self
        addApplicationPopup.action = #selector(addApplicationChanged)
        addApplicationPopup.widthAnchor.constraint(equalToConstant: 280).isActive = true
        addGesturePopup.widthAnchor.constraint(equalToConstant: 240).isActive = true
        addModeControl.selectedSegment = 0
        addModeControl.target = self
        addModeControl.action = #selector(addModeChanged)
        addModeControl.widthAnchor.constraint(equalToConstant: 280).isActive = true
        addCommandPopup.widthAnchor.constraint(equalToConstant: 240).isActive = true
        shortcutField.placeholderString = L("Press shortcut")
        shortcutField.widthAnchor.constraint(equalToConstant: 240).isActive = true
        addEnabledSwitch.state = .on

        stack.addArrangedSubview(row(L("Application"), addApplicationPopup))
        stack.addArrangedSubview(row(L("Gesture"), addGesturePopup))
        stack.addArrangedSubview(row(L("Type"), addModeControl))
        stack.addArrangedSubview(row(L("Command"), addCommandPopup))
        stack.addArrangedSubview(row(L("Keyboard Shortcut"), shortcutField))
        stack.addArrangedSubview(row(L("Enabled"), addEnabledSwitch))

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let cancelButton = NSButton(title: L("Cancel"), target: self, action: #selector(cancelAddGesture))
        let commitButton = NSButton(title: L("Add"), target: self, action: #selector(commitAddGesture))
        commitButton.keyEquivalent = "\r"
        buttonRow.addArrangedSubview(cancelButton)
        buttonRow.addArrangedSubview(commitButton)
        stack.addArrangedSubview(buttonRow)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -22)
        ])
    }

    private func populateAddGesturePanel() {
        reloadApplicationMenus()
        addApplicationPopup.selectItem(withTitle: selectedApplicationName == "All Applications" ? L("All Applications") : selectedApplicationName)
        addGesturePopup.removeAllItems()
        addGesturePopup.addItems(withTitles: settingsStore.availableGestures(for: selectedDevice, application: addApplicationName))
        addCommandPopup.removeAllItems()
        addCommandPopup.addItems(withTitles: commands)
        addCommandPopup.selectItem(withTitle: "-")
        addModeControl.selectedSegment = 0
        shortcutField.reset()
        addEnabledSwitch.state = .on
        updateAddModeVisibility()
    }

    @objc private func addCommand() {
        populateAddGesturePanel()
        guard addGesturePopup.numberOfItems > 0, let window else {
            return
        }
        window.beginSheet(addGesturePanel)
    }

    @objc private func cancelAddGesture() {
        endAddGestureSheet()
    }

    @objc private func addApplicationChanged() {
        if addApplicationPopup.titleOfSelectedItem == L("Other...") {
            chooseApplicationForAddPanel()
        }
        addGesturePopup.removeAllItems()
        addGesturePopup.addItems(withTitles: settingsStore.availableGestures(for: selectedDevice, application: addApplicationName))
        updateGestureButtons()
    }

    @objc private func addModeChanged() {
        updateAddModeVisibility()
    }

    @objc private func commitAddGesture() {
        guard let gesture = addGesturePopup.titleOfSelectedItem else {
            return
        }
        let isAction = addModeControl.selectedSegment == 0
        let command = GestureCommand(
            gesture: gesture,
            command: isAction ? (addCommandPopup.titleOfSelectedItem ?? "-") : shortcutField.stringValue,
            isAction: isAction,
            modifierFlags: isAction ? 0 : shortcutField.capturedModifierFlags,
            keyCode: isAction ? 0 : shortcutField.capturedKeyCode,
            isEnabled: addEnabledSwitch.state == .on,
            openFilePath: nil,
            openURL: nil
        )
        settingsStore.updateCommand(command, device: selectedDevice, application: addApplicationName, path: addApplicationPath)
        endAddGestureSheet()
        reloadApplicationMenus()
        applicationControl.selectItem(withTitle: addApplicationName == "All Applications" ? L("All Applications") : addApplicationName)
        selectedApplicationPath = addApplicationPath
        gesturesTable.reloadData()
        selectCommand(gesture: gesture)
        updateGestureButtons()
        notifyGestureSettingsChanged()
    }

    @objc private func deleteCommand() {
        guard let command = selectedCommand else {
            return
        }
        settingsStore.removeCommand(gesture: command.gesture, device: selectedDevice, application: selectedApplicationName)
        gesturesTable.reloadData()
        updateGestureButtons()
        notifyGestureSettingsChanged()
    }

    @objc private func restoreDefaults() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Restore default settings?")
        alert.informativeText = String(format: L("Your current %@ gesture settings will be deleted."), selectedDeviceName)
        alert.addButton(withTitle: L("OK"))
        alert.addButton(withTitle: L("Cancel"))
        alert.beginSheetModal(for: window ?? addGesturePanel) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else {
                return
            }
            self.settingsStore.restoreDefaultCommands(for: self.selectedDevice)
            self.gesturesTable.reloadData()
            self.updateGestureButtons()
            self.notifyGestureSettingsChanged()
        }
    }

    @objc private func editSelectedCommand() {
        guard let command = selectedCommand else {
            return
        }
        let alert = NSAlert()
        alert.messageText = command.gesture
        alert.informativeText = L("Choose the command for this gesture.")
        alert.addButton(withTitle: L("Save"))
        alert.addButton(withTitle: L("Cancel"))

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        popup.addItems(withTitles: commands)
        if commands.contains(command.command) {
            popup.selectItem(withTitle: command.command)
        } else {
            popup.addItem(withTitle: command.command)
            popup.selectItem(withTitle: command.command)
        }
        alert.accessoryView = popup
        alert.beginSheetModal(for: window ?? addGesturePanel) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else {
                return
            }
            var updated = command
            updated.command = popup.titleOfSelectedItem ?? "-"
            updated.isAction = true
            self.settingsStore.updateCommand(updated, device: self.selectedDevice, application: self.selectedApplicationName, path: self.selectedApplicationPath)
            self.gesturesTable.reloadData()
            self.selectCommand(gesture: updated.gesture)
            self.notifyGestureSettingsChanged()
        }
    }

    private var selectedDeviceName: String {
        selectedDevice == .trackpad ? L("trackpad") : L("Magic Mouse")
    }

    private var addApplicationName: String {
        let title = addApplicationPopup.titleOfSelectedItem ?? L("All Applications")
        return title == L("All Applications") ? "All Applications" : title
    }

    private var addApplicationPath: String {
        addApplicationPaths[addApplicationPopup.titleOfSelectedItem ?? L("All Applications")] ?? ""
    }

    private func updateAddModeVisibility() {
        let usesAction = addModeControl.selectedSegment == 0
        addCommandPopup.isEnabled = usesAction
        shortcutField.isEnabled = !usesAction
        if !usesAction {
            addGesturePanel.makeFirstResponder(shortcutField)
        }
    }

    private func chooseApplicationForAddPanel() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            addApplicationPopup.selectItem(withTitle: L("All Applications"))
            return
        }

        let applicationName = url.deletingPathExtension().lastPathComponent
        if addApplicationPopup.itemTitles.contains(applicationName) == false {
            addApplicationPopup.insertItem(withTitle: applicationName, at: max(addApplicationPopup.numberOfItems - 1, 0))
        }
        addApplicationPaths[applicationName] = url.path
        addApplicationPopup.selectItem(withTitle: applicationName)
    }

    private func selectCommand(gesture: String) {
        guard let row = displayedCommands.firstIndex(where: { $0.gesture == gesture }) else {
            return
        }
        gesturesTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        gesturesTable.scrollRowToVisible(row)
    }

    private func notifyGestureSettingsChanged() {
        settingsStore.postRuntimeSettingsChanged()
        delegate?.preferencesWindowControllerDidChangeSettings(self)
    }

    private func endAddGestureSheet() {
        if let sheetParent = addGesturePanel.sheetParent {
            sheetParent.endSheet(addGesturePanel)
        } else {
            window?.endSheet(addGesturePanel)
        }
    }
}

extension PreferencesWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        displayedCommands.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateGestureButtons()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let command = displayedCommands[row]
        guard let identifier = tableColumn?.identifier.rawValue else {
            return nil
        }

        switch identifier {
        case "enabled":
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(gestureEnabledChanged(_:)))
            checkbox.state = command.isEnabled ? .on : .off
            checkbox.tag = row
            return checkbox

        case "gesture":
            let field = NSTextField(labelWithString: command.gesture)
            field.lineBreakMode = .byTruncatingTail
            return field

        case "command":
            let popup = NSPopUpButton()
            popup.addItems(withTitles: commands)
            if commands.contains(command.command) {
                popup.selectItem(withTitle: command.command)
            } else {
                popup.addItem(withTitle: command.command)
                popup.selectItem(withTitle: command.command)
            }
            popup.target = self
            popup.action = #selector(commandPopupChanged(_:))
            popup.tag = row
            return popup

        default:
            return nil
        }
    }

    @objc private func gestureEnabledChanged(_ sender: NSButton) {
        var command = displayedCommands[sender.tag]
        command.isEnabled = sender.state == .on
        settingsStore.updateCommand(command, device: selectedDevice, application: selectedApplicationName, path: selectedApplicationPath)
        delegate?.preferencesWindowControllerDidChangeSettings(self)
    }

    @objc private func commandPopupChanged(_ sender: NSPopUpButton) {
        var command = displayedCommands[sender.tag]
        command.command = sender.titleOfSelectedItem ?? "-"
        command.isAction = true
        settingsStore.updateCommand(command, device: selectedDevice, application: selectedApplicationName, path: selectedApplicationPath)
        delegate?.preferencesWindowControllerDidChangeSettings(self)
    }
}
