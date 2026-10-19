import AppKit
import Carbon.HIToolbox

/// A click-to-record field that captures a single keyboard shortcut.
@MainActor
final class HotKeyRecorderControl: NSView {
    var combo: HotKeyCombo {
        didSet { needsDisplay = true }
    }
    /// Called with a newly recorded, valid combo. Return `false` to reject it
    /// (e.g. a duplicate) and keep the previous value.
    var shouldAccept: ((HotKeyCombo) -> Bool)?
    var onChange: ((HotKeyCombo) -> Void)?

    private var recording = false {
        didSet { needsDisplay = true }
    }

    init(combo: HotKeyCombo) {
        self.combo = combo
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 26) }

    override func resignFirstResponder() -> Bool {
        recording = false
        return true
    }

    override func mouseDown(with event: NSEvent) {
        if recording {
            recording = false
            window?.makeFirstResponder(nil)
        } else {
            window?.makeFirstResponder(self)
            recording = true
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        return handle(event)
    }

    override func keyDown(with event: NSEvent) {
        if recording, handle(event) { return }
        super.keyDown(with: event)
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        guard recording else { return false }

        let cleanFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Escape with no modifiers cancels recording.
        if event.keyCode == UInt32(kVK_Escape), cleanFlags.isEmpty {
            window?.makeFirstResponder(nil)
            return true
        }

        let candidate = HotKeyCombo(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: HotKeyModifierConversion.carbon(from: event.modifierFlags)
        )
        guard candidate.isValid else {
            // Needs at least ⌘/⌃/⌥. Stay in recording mode.
            NSSound.beep()
            return true
        }
        if shouldAccept?(candidate) == false {
            NSSound.beep()
            window?.makeFirstResponder(nil)
            return true
        }
        combo = candidate
        onChange?(candidate)
        window?.makeFirstResponder(nil)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let frame = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)

        (recording
            ? NSColor.controlAccentColor.withAlphaComponent(0.12)
            : NSColor.controlBackgroundColor).setFill()
        path.fill()

        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = recording ? 2 : 1
        path.stroke()

        let text = recording ? NSLocalizedString("Type shortcut…", comment: "") : combo.displayString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    /// Called after any shortcut changes so the app can re-register hot keys.
    var onHotKeysChanged: (() -> Void)?
    /// Called when the window closes so the app can restore its activation policy.
    var onClose: (() -> Void)?

    private var recorders: [HotKeyAction: HotKeyRecorderControl] = [:]
    private let saveFolderValueLabel = NSTextField(labelWithString: "")
    private let defaultColorWell = SettingsColorWell()
    private let fileNameField = NSTextField(string: "")
    private let fileNamePreviewLabel = NSTextField(labelWithString: "")

    init() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("Settings", comment: "")
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let window, let contentView = window.contentView else { return }

        let heading = NSTextField(labelWithString: NSLocalizedString("Capture Shortcuts", comment: ""))
        heading.font = .systemFont(ofSize: 15, weight: .semibold)

        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.columnSpacing = 12
        grid.rowSpacing = 12
        grid.column(at: 0).xPlacement = .trailing

        for action in HotKeyAction.allCases {
            let label = NSTextField(labelWithString: action.title)
            label.font = .systemFont(ofSize: 13)

            let recorder = HotKeyRecorderControl(combo: HotKeySettings.shared.combo(for: action))
            recorder.translatesAutoresizingMaskIntoConstraints = false
            recorder.widthAnchor.constraint(equalToConstant: 150).isActive = true
            recorder.heightAnchor.constraint(equalToConstant: 26).isActive = true
            recorder.shouldAccept = { [weak self] candidate in
                self?.isComboAvailable(candidate, for: action) ?? true
            }
            recorder.onChange = { [weak self] combo in
                self?.updateCombo(combo, for: action)
            }
            recorders[action] = recorder

            grid.addRow(with: [label, recorder])
        }

        let hint = NSTextField(labelWithString: NSLocalizedString("Click a field and press the new key combination (include ⌘, ⌃, or ⌥).", comment: ""))
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2

        let resetButton = NSButton(title: NSLocalizedString("Reset to Defaults", comment: ""), target: self, action: #selector(resetDefaults))
        resetButton.bezelStyle = .rounded

        // Save location section.
        let saveHeading = NSTextField(labelWithString: NSLocalizedString("Save Folder (⌘S saves here instantly)", comment: ""))
        saveHeading.font = .systemFont(ofSize: 15, weight: .semibold)

        saveFolderValueLabel.font = .systemFont(ofSize: 12)
        saveFolderValueLabel.textColor = .secondaryLabelColor
        saveFolderValueLabel.lineBreakMode = .byTruncatingMiddle
        saveFolderValueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateSaveFolderLabel()

        let changeFolderButton = NSButton(title: NSLocalizedString("Change…", comment: ""), target: self, action: #selector(chooseSaveFolder))
        changeFolderButton.bezelStyle = .rounded
        let resetFolderButton = NSButton(title: NSLocalizedString("Reset to Downloads", comment: ""), target: self, action: #selector(resetSaveFolder))
        resetFolderButton.bezelStyle = .rounded
        let saveButtons = NSStackView(views: [changeFolderButton, resetFolderButton])
        saveButtons.spacing = 8
        let formatLabel = NSTextField(labelWithString: NSLocalizedString("Default Format", comment: ""))
        formatLabel.font = .systemFont(ofSize: 13)
        let formatSegmented = NSSegmentedControl(
            labels: ImageFormat.allCases.map(\.label),
            trackingMode: .selectOne,
            target: self,
            action: #selector(imageFormatChanged(_:))
        )
        formatSegmented.selectedSegment = ImageFormat.preferred.rawValue
        let formatRow = NSStackView(views: [formatLabel, formatSegmented])
        formatRow.spacing = 10
        let formatHint = NSTextField(labelWithString: NSLocalizedString("Used by ⌘S and drag export. Save As (⇧⌘S) lets you pick each time.", comment: ""))
        formatHint.font = .systemFont(ofSize: 11)
        formatHint.textColor = .secondaryLabelColor
        let fileNameLabel = NSTextField(labelWithString: NSLocalizedString("File Name", comment: ""))
        fileNameLabel.font = .systemFont(ofSize: 13)
        fileNameField.stringValue = ExportFileName.pattern
        fileNameField.font = .systemFont(ofSize: 13)
        fileNameField.isEditable = true
        fileNameField.isBezeled = true
        fileNameField.bezelStyle = .roundedBezel
        fileNameField.lineBreakMode = .byTruncatingTail
        fileNameField.delegate = self
        fileNameField.target = self
        fileNameField.action = #selector(fileNamePatternEdited(_:))
        fileNameField.cell?.sendsActionOnEndEditing = true
        let fileNameHint = NSTextField(wrappingLabelWithString: NSLocalizedString("Use {date}, {time}, or {datetime}. Dragging to the desktop and ⌘S use this name.", comment: ""))
        fileNameHint.font = .systemFont(ofSize: 11)
        fileNameHint.textColor = .secondaryLabelColor
        fileNamePreviewLabel.font = .systemFont(ofSize: 11)
        fileNamePreviewLabel.textColor = .secondaryLabelColor
        fileNamePreviewLabel.lineBreakMode = .byTruncatingMiddle
        updateFileNamePreview()
        let saveSection = NSStackView(views: [
            saveHeading, saveFolderValueLabel, saveButtons, formatRow, formatHint,
            fileNameLabel, fileNameField, fileNameHint, fileNamePreviewLabel
        ])
        saveSection.orientation = .vertical
        saveSection.alignment = .leading
        saveSection.spacing = 8
        saveSection.setCustomSpacing(14, after: saveButtons)
        saveSection.setCustomSpacing(14, after: formatHint)

        let colorHeading = NSTextField(labelWithString: NSLocalizedString("Default Color", comment: ""))
        colorHeading.font = .systemFont(ofSize: 15, weight: .semibold)
        defaultColorWell.color = AnnotationColorSettings.color
        defaultColorWell.target = self
        defaultColorWell.action = #selector(defaultColorChanged(_:))
        defaultColorWell.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            defaultColorWell.widthAnchor.constraint(equalToConstant: 48),
            defaultColorWell.heightAnchor.constraint(equalToConstant: 28)
        ])
        let colorHint = NSTextField(wrappingLabelWithString: NSLocalizedString("New arrows and labels start in this color. The last color you pick in the editor is remembered.", comment: ""))
        colorHint.font = .systemFont(ofSize: 11)
        colorHint.textColor = .secondaryLabelColor
        let colorSection = NSStackView(views: [colorHeading, defaultColorWell, colorHint])
        colorSection.orientation = .vertical
        colorSection.alignment = .leading
        colorSection.spacing = 8

        // Reference list of the fixed editor shortcuts.
        let refHeading = NSTextField(labelWithString: NSLocalizedString("Editor Shortcuts", comment: ""))
        refHeading.font = .systemFont(ofSize: 15, weight: .semibold)
        let refGrid = NSGridView(numberOfColumns: 2, rows: 0)
        refGrid.columnSpacing = 16
        refGrid.rowSpacing = 6
        refGrid.column(at: 0).xPlacement = .trailing
        let references: [(String, String)] = [
            (NSLocalizedString("Save / Save As", comment: ""), "⌘S / ⇧⌘S"),
            (NSLocalizedString("Copy", comment: ""), "⌘C"),
            (NSLocalizedString("Undo / Redo", comment: ""), "⌘Z / ⇧⌘Z"),
            (NSLocalizedString("Zoom In / Out / Fit", comment: ""), "⌘+ / ⌘- / ⌘0"),
            (NSLocalizedString("Open Settings", comment: ""), "⌘,"),
            (NSLocalizedString("Move Selection", comment: ""), NSLocalizedString("↑↓←→ (⇧ moves 10)", comment: ""))
        ]
        for (name, keys) in references {
            let n = NSTextField(labelWithString: name)
            n.font = .systemFont(ofSize: 12)
            n.textColor = .secondaryLabelColor
            let k = NSTextField(labelWithString: keys)
            k.font = .systemFont(ofSize: 12)
            k.lineBreakMode = .byWordWrapping
            k.maximumNumberOfLines = 2
            refGrid.addRow(with: [n, k])
        }

        // Timer duration section.
        let timerHeading = NSTextField(labelWithString: NSLocalizedString("Timer Length", comment: ""))
        timerHeading.font = .systemFont(ofSize: 15, weight: .semibold)
        let timerSegmented = NSSegmentedControl(
            labels: [NSLocalizedString("3 sec", comment: ""), NSLocalizedString("5 sec", comment: "")],
            trackingMode: .selectOne,
            target: self,
            action: #selector(timerSecondsChanged(_:))
        )
        timerSegmented.selectedSegment = CaptureTimerSettings.seconds == 3 ? 0 : 1
        let timerSection = NSStackView(views: [timerHeading, timerSegmented])
        timerSection.orientation = .vertical
        timerSection.alignment = .leading
        timerSection.spacing = 8

        // Interface language section.
        let languageHeading = NSTextField(labelWithString: NSLocalizedString("Language", comment: ""))
        languageHeading.font = .systemFont(ofSize: 15, weight: .semibold)
        let languageSegmented = NSSegmentedControl(
            labels: AppLanguage.allCases.map(\.label),
            trackingMode: .selectOne,
            target: self,
            action: #selector(languageChanged(_:))
        )
        languageSegmented.selectedSegment = AppLanguage.current.rawValue
        let languageHint = NSTextField(labelWithString: NSLocalizedString("Takes effect after Arrowshot restarts.", comment: ""))
        languageHint.font = .systemFont(ofSize: 11)
        languageHint.textColor = .secondaryLabelColor
        let languageSection = NSStackView(views: [languageHeading, languageSegmented, languageHint])
        languageSection.orientation = .vertical
        languageSection.alignment = .leading
        languageSection.spacing = 8

        let divider1 = NSBox(); divider1.boxType = .separator
        let divider2 = NSBox(); divider2.boxType = .separator
        let divider3 = NSBox(); divider3.boxType = .separator
        let divider4 = NSBox(); divider4.boxType = .separator
        let divider5 = NSBox(); divider5.boxType = .separator

        let stack = NSStackView(views: [
            heading, grid, hint, resetButton,
            divider5, colorSection,
            divider1, saveSection,
            divider3, timerSection,
            divider4, languageSection,
            divider2, refHeading, refGrid
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(8, after: grid)
        stack.setCustomSpacing(18, after: resetButton)
        stack.setCustomSpacing(18, after: colorSection)
        stack.setCustomSpacing(18, after: saveSection)
        stack.setCustomSpacing(18, after: timerSection)
        stack.setCustomSpacing(18, after: languageSection)
        stack.setCustomSpacing(8, after: refHeading)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document
        document.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
            divider1.widthAnchor.constraint(equalTo: stack.widthAnchor),
            divider2.widthAnchor.constraint(equalTo: stack.widthAnchor),
            divider3.widthAnchor.constraint(equalTo: stack.widthAnchor),
            divider4.widthAnchor.constraint(equalTo: stack.widthAnchor),
            divider5.widthAnchor.constraint(equalTo: stack.widthAnchor),
            saveFolderValueLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            fileNameField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            fileNameHint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            fileNamePreviewLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            colorHint.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(savedAnnotationColorChanged),
            name: AnnotationColorSettings.didChange,
            object: nil
        )
    }

    @objc private func defaultColorChanged(_ sender: NSColorWell) {
        AnnotationColorSettings.set(sender.color)
    }

    @objc private func savedAnnotationColorChanged() {
        let color = AnnotationColorSettings.color
        guard AnnotationColorSettings.hexString(for: defaultColorWell.color) != AnnotationColorSettings.hexString(for: color) else {
            return
        }
        defaultColorWell.color = color
    }

    @objc private func fileNamePatternEdited(_ sender: NSTextField) {
        ExportFileName.setPattern(sender.stringValue)
        updateFileNamePreview()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === fileNameField else { return }
        fileNamePatternEdited(field)
    }

    private func updateFileNamePreview() {
        let name = ExportFileName.fileName(format: ImageFormat.preferred, pattern: fileNameField.stringValue)
        fileNamePreviewLabel.stringValue = String(
            format: NSLocalizedString("Preview: %@", comment: "Resolved export file name"),
            name
        )
    }

    @objc private func languageChanged(_ sender: NSSegmentedControl) {
        guard let language = AppLanguage(rawValue: sender.selectedSegment),
              language != AppLanguage.current else { return }
        AppLanguage.set(language)

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Restart Arrowshot now to change the language?", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Restart Now", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Later", comment: ""))
        guard let window else { return }
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                AppLanguage.relaunch()
            }
        }
    }

    @objc private func imageFormatChanged(_ sender: NSSegmentedControl) {
        ImageFormat.setPreferred(ImageFormat(rawValue: sender.selectedSegment) ?? .png)
    }

    @objc private func timerSecondsChanged(_ sender: NSSegmentedControl) {
        CaptureTimerSettings.setSeconds(sender.selectedSegment == 0 ? 3 : 5)
        onHotKeysChanged?()
    }

    private func updateSaveFolderLabel() {
        let folder = SaveLocation.folderURL
        let suffix = SaveLocation.isCustom ? "" : NSLocalizedString(" (Default)", comment: "")
        saveFolderValueLabel.stringValue = "📁 \(folder.path)\(suffix)"
    }

    @objc private func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = SaveLocation.folderURL
        panel.prompt = NSLocalizedString("Choose", comment: "")
        if let window {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                SaveLocation.setFolder(url)
                self?.updateSaveFolderLabel()
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            SaveLocation.setFolder(url)
            updateSaveFolderLabel()
        }
    }

    @objc private func resetSaveFolder() {
        SaveLocation.resetToDefault()
        updateSaveFolderLabel()
    }

    private func isComboAvailable(_ combo: HotKeyCombo, for action: HotKeyAction) -> Bool {
        for other in HotKeyAction.allCases where other != action {
            if HotKeySettings.shared.combo(for: other) == combo {
                presentDuplicateAlert()
                return false
            }
        }
        return true
    }

    private func presentDuplicateAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("This Shortcut Is Already in Use", comment: "")
        alert.informativeText = NSLocalizedString("Choose a different key combination.", comment: "")
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    private func updateCombo(_ combo: HotKeyCombo, for action: HotKeyAction) {
        HotKeySettings.shared.setCombo(combo, for: action)
        onHotKeysChanged?()
    }

    @objc private func resetDefaults() {
        HotKeySettings.shared.resetToDefaults()
        for action in HotKeyAction.allCases {
            recorders[action]?.combo = action.defaultCombo
        }
        onHotKeysChanged?()
    }

    func present() {
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
        onClose?()
    }
}

/// Keeps the shared color panel from offering transparency. Annotation colors are opaque.
private final class SettingsColorWell: NSColorWell {
    override func activate(_ exclusive: Bool) {
        NSColorPanel.shared.showsAlpha = false
        super.activate(exclusive)
    }
}

/// Top-down document so the settings form scrolls from its heading.
private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}
