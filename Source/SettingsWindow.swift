import AppKit
import UniformTypeIdentifiers

private final class SettingsDocument: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

private enum SettingsShape {
    static let cornerRadius: CGFloat = 12
}

private final class SettingsPopUpButton: NSPopUpButton {
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 8
        return size
    }
}

private func settingsPopUpButton() -> NSPopUpButton {
    let button = SettingsPopUpButton(frame: .zero, pullsDown: false)
    button.controlSize = .regular
    button.isBordered = false
    button.font = .systemFont(ofSize: NSFont.systemFontSize)
    return button
}

private final class SettingsCard: NSView {
    init(content: NSView) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = SettingsShape.cornerRadius
        layer?.borderWidth = 0
        layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (NSColor.windowBackgroundColor.blended(withFraction: 0.04, of: .labelColor) ?? .windowBackgroundColor).cgColor
            layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
        }
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var getConfiguration: () -> RulesConfiguration
    var getPermissionState: () -> PermissionDisplayState
    var getLoginState: () -> (enabled: Bool?, approvalNeeded: Bool)
    var onDefault: ((MenuBarMode) -> Void)?
    var onEnabled: ((Bool) -> Void)?
    var onLaunchAtLogin: ((Bool) -> Void)?
    var onShowIcon: ((Bool) -> Void)?
    var onPermission: (() -> Void)?
    var onSaveRule: ((AppRule) -> Void)?
    var onRemoveRule: ((String) -> Void)?
    var onClose: (() -> Void)?
    private let defaultPopup = settingsPopUpButton()
    private let add = NSButton(title: "Add app…", target: nil, action: nil)
    private let permissionArea = NSStackView()
    private var permissionDivider: NSView?
    private let enabled = NSSwitch()
    private let launchAtLogin = NSSwitch()
    private let showIcon = NSSwitch()
    private let loginNote = NSTextField(wrappingLabelWithString: "")
    private let iconNote = NSTextField(wrappingLabelWithString: "Open Menu Bar Toggle from Finder to return to Settings when the menu bar icon is hidden.")
    private let ruleCount = NSTextField(labelWithString: "")
    private let rules = NSStackView()
    private let permission = NSTextField(labelWithString: "")
    private let permissionDetail = NSTextField(wrappingLabelWithString: "")
    private let permissionIcon = NSImageView()
    private let accessButton = NSButton(title: "Open System Settings ↗", target: nil, action: nil)
    private let undoRemove = NSButton(title: "Undo Remove", target: nil, action: nil)
    private var removed: AppRule?
    private var currentMessage: String?

    init(configuration: @escaping () -> RulesConfiguration,
         permissionState: @escaping () -> PermissionDisplayState,
         loginState: @escaping () -> (enabled: Bool?, approvalNeeded: Bool)) {
        getConfiguration = configuration
        getPermissionState = permissionState
        getLoginState = loginState
        let availableHeight = NSScreen.main?.visibleFrame.height ?? 1000
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: min(600, availableHeight - 90)),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = .windowBackgroundColor
        window.minSize = NSSize(width: 540, height: 460)
        window.level = .normal
        window.collectionBehavior = [.primary, .managed, .fullScreenNone, .fullScreenDisallowsTiling]
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.center()
        super.init(window: window)
        window.delegate = self
        build()
        reload()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.onClose?() }
    }

    private func text(_ value: String, small: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: small ? 11 : 13)
        if small { label.textColor = .secondaryLabelColor }
        return label
    }
    private func vertical(_ views: [NSView], spacing: CGFloat = 0) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }
    private func stretch(_ view: NSView, in stack: NSStackView) {
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func row(_ left: NSView, _ right: NSView, height: CGFloat = 38) -> NSStackView {
        left.setContentHuggingPriority(.defaultLow, for: .horizontal)
        left.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        right.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [left, right])
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 16
        row.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: height).isActive = true
        return row
    }
    private func separator() -> NSView {
        let container = NSView()
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 1),
            line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            line.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            line.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }
    private func group(_ contents: [NSView]) -> NSView {
        let stack = vertical([])
        for (index, content) in contents.enumerated() {
            if index > 0 { let line = separator(); stack.addArrangedSubview(line); stretch(line, in: stack) }
            stack.addArrangedSubview(content)
            stretch(content, in: stack)
        }
        return SettingsCard(content: stack)
    }
    private func section(_ title: String, contents: [NSView], trailing: NSView? = nil) -> NSStackView {
        let heading = text(title)
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        let header: NSView
        if let trailing {
            heading.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let line = NSStackView(views: [heading, trailing])
            line.distribution = .fill
            line.alignment = .centerY
            header = line
        } else { header = heading }
        let stack = vertical([header] + contents, spacing: 10)
        for view in stack.arrangedSubviews { stretch(view, in: stack) }
        return stack
    }
    private func build() {
        guard let content = window?.contentView else { return }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let document = SettingsDocument()
        window?.initialFirstResponder = document
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        content.addSubview(scroll)
        let body = vertical([], spacing: 16)
        body.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(body)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            body.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            body.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            body.topAnchor.constraint(equalTo: document.topAnchor, constant: 36),
            body.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24)
        ])
        let title = text("Settings")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        body.addArrangedSubview(title)
        stretch(title, in: body)
        launchAtLogin.controlSize = .mini
        showIcon.controlSize = .mini
        launchAtLogin.target = self
        launchAtLogin.action = #selector(changeLogin)
        launchAtLogin.setAccessibilityLabel("Launch at Login")
        showIcon.target = self
        showIcon.action = #selector(changeIcon)
        showIcon.setAccessibilityLabel("Show App Icon in Menu Bar")
        for note in [loginNote, iconNote] { note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor }
        let general = section("General", contents: [group([
            row(text("Launch at login"), launchAtLogin),
            row(text("Show app icon in menu bar"), showIcon)
        ]), loginNote, iconNote])
        body.addArrangedSubview(general)
        stretch(general, in: body)

        for mode in MenuBarMode.allCases { defaultPopup.addItem(withTitle: mode.title) }
        defaultPopup.target = self
        defaultPopup.action = #selector(changeDefault)
        defaultPopup.setAccessibilityLabel("Automatically hide and show the menu bar")
        let defaultTitle = text("Automatically hide and show the menu bar")
        defaultTitle.font = .systemFont(ofSize: 13)
        let labels = vertical([defaultTitle, text("Used for every app without its own rule.", small: true)], spacing: 4)
        for view in labels.arrangedSubviews { stretch(view, in: labels) }
        let defaultRow = row(labels, defaultPopup, height: 52)
        defaultRow.spacing = 8
        let defaults = section("Default Behaviour", contents: [SettingsCard(content: defaultRow)])
        body.addArrangedSubview(defaults)
        stretch(defaults, in: body)

        rules.orientation = .vertical
        rules.alignment = .leading
        rules.spacing = 0
        add.target = self
        add.action = #selector(addApp)
        add.bezelStyle = .rounded
        add.controlSize = .regular
        add.font = .systemFont(ofSize: 13)
        add.heightAnchor.constraint(equalToConstant: 28).isActive = true
        add.widthAnchor.constraint(greaterThanOrEqualToConstant: 84).isActive = true
        undoRemove.target = self
        undoRemove.action = #selector(undoRemoval)
        undoRemove.isHidden = true
        let description = vertical([text("App Rules", small: true),
            text("Overrides the default while one of these apps is in front and full screen.", small: true)], spacing: 5)
        (description.arrangedSubviews[0] as? NSTextField)?.font = .systemFont(ofSize: 11, weight: .semibold)
        let header = NSStackView(views: [description, add])
        header.distribution = .fill
        header.alignment = .centerY
        header.spacing = 16
        description.setContentHuggingPriority(.defaultLow, for: .horizontal)
        description.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        add.setContentHuggingPriority(.required, for: .horizontal)
        permission.font = .systemFont(ofSize: 12, weight: .semibold)
        permissionDetail.font = .systemFont(ofSize: 11)
        permissionDetail.textColor = .secondaryLabelColor
        accessButton.controlSize = .regular
        accessButton.font = .systemFont(ofSize: 13)
        accessButton.target = self
        accessButton.action = #selector(allowAccess)
        accessButton.bezelStyle = .rounded
        permissionArea.orientation = .vertical
        permissionArea.alignment = .leading
        permissionArea.spacing = 7
        permissionArea.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        let appSection = vertical([header, SettingsCard(content: verticalRuleCard()), undoRemove], spacing: 12)
        for view in appSection.arrangedSubviews { stretch(view, in: appSection) }
        body.addArrangedSubview(appSection)
        stretch(appSection, in: body)

    }

    private func verticalRuleCard() -> NSStackView {
        let divider = separator()
        permissionDivider = divider
        let card = vertical([permissionArea, divider, rules])
        for view in card.arrangedSubviews { stretch(view, in: card) }
        return card
    }

    func reload(message: String? = nil) {
        currentMessage = message
        let config = getConfiguration()
        defaultPopup.selectItem(at: config.defaultMode?.rawValue ?? -1)
        enabled.state = config.enabled ? .on : .off
        showIcon.state = config.showMenuBarIcon ? .on : .off
        iconNote.isHidden = config.showMenuBarIcon
        let login = getLoginState()
        launchAtLogin.state = login.enabled == true ? .on : .off
        launchAtLogin.isEnabled = login.enabled != nil
        loginNote.stringValue = "Approve Launch at Login in System Settings → General → Login Items."
        loginNote.isHidden = !login.approvalNeeded
        for view in rules.arrangedSubviews { rules.removeArrangedSubview(view); view.removeFromSuperview() }
        let saved = config.rules.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        ruleCount.stringValue = "\(saved.count) \(saved.count == 1 ? "rule" : "rules")"
        if saved.isEmpty {
            let label = text("No app rules yet")
            label.alignment = .center
            let detail = text("Use Add app… to choose an app and set its own menu bar behaviour in full screen.", small: true)
            detail.alignment = .center
            let empty = vertical([label, detail], spacing: 5)
            empty.edgeInsets = NSEdgeInsets(top: 28, left: 32, bottom: 28, right: 32)
            label.widthAnchor.constraint(equalTo: empty.widthAnchor, constant: -64).isActive = true
            detail.widthAnchor.constraint(equalTo: empty.widthAnchor, constant: -64).isActive = true
            rules.addArrangedSubview(empty)
            stretch(empty, in: rules)
        }
        for (index, rule) in saved.enumerated() {
            if index > 0 { let line = separator(); rules.addArrangedSubview(line); stretch(line, in: rules) }
            let icon = NSImageView()
            icon.image = FileManager.default.fileExists(atPath: rule.path) ? NSWorkspace.shared.icon(forFile: rule.path)
                : NSImage(systemSymbolName: "app", accessibilityDescription: nil)
            icon.imageScaling = .scaleProportionallyDown
            icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 24).isActive = true
            let name = NSTextField(labelWithString: rule.name)
            name.font = .systemFont(ofSize: 13)
            name.lineBreakMode = .byTruncatingTail
            name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            name.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let popup = settingsPopUpButton()
            for mode in MenuBarMode.allCases { popup.addItem(withTitle: mode.title) }
            popup.selectItem(at: rule.mode.rawValue)
            popup.identifier = NSUserInterfaceItemIdentifier(rule.bundleID)
            popup.target = self
            popup.action = #selector(changeRule(_:))
            popup.setAccessibilityLabel("Automatically hide and show the menu bar for \(rule.name) in full screen")
            popup.setContentHuggingPriority(.required, for: .horizontal)
            let remove = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove")!, target: self, action: #selector(removeRule(_:)))
            remove.isBordered = false
            remove.contentTintColor = .secondaryLabelColor
            remove.identifier = NSUserInterfaceItemIdentifier(rule.bundleID)
            remove.setAccessibilityLabel("Remove custom setting for \(rule.name)")
            remove.toolTip = "Remove \(rule.name) rule"
            let appRow = NSStackView(views: [icon, name, popup, remove])
            appRow.distribution = .fill
            appRow.spacing = 12
            appRow.alignment = .centerY
            appRow.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            appRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            rules.addArrangedSubview(appRow)
            stretch(appRow, in: rules)
        }
        undoRemove.isHidden = removed == nil
        refreshPermission()
    }

    func refreshPermission() {
        let state = getPermissionState()
        let status: String
        switch state {
        case .checking: status = "Checking access…"
        case .granted: status = "✓  Access granted"
        case .notGranted: status = "!  Access needed"
        case .unavailable: status = "Unable to check access"
        }
        permission.stringValue = status
        permission.textColor = state == .granted ? .systemGreen : state == .notGranted ? .systemOrange : .secondaryLabelColor
        for view in permissionArea.arrangedSubviews { permissionArea.removeArrangedSubview(view); view.removeFromSuperview() }
        let granted = state == .granted
        permissionArea.isHidden = granted
        permissionDivider?.isHidden = granted
        permissionArea.wantsLayer = true
        permissionArea.layer?.backgroundColor = state == .notGranted ? NSColor.systemOrange.withAlphaComponent(0.10).cgColor : NSColor.clear.cgColor
        permissionDetail.stringValue = currentMessage ?? (granted
            ? ""
            : "Allow access so app rules can work. Your default behaviour still works without it. Restart the app after changing access.")
        accessButton.title = state == .unavailable ? "Check Again" : "Open System Settings"
        accessButton.isEnabled = state != .checking
        accessButton.setContentHuggingPriority(.required, for: .horizontal)
        if granted {
            let line = NSStackView(views: [permission, permissionDetail])
            line.spacing = 8
            line.alignment = .centerY
            permissionDetail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            permissionArea.addArrangedSubview(line)
        } else {
            permissionArea.addArrangedSubview(permission)
            let line = NSStackView(views: [permissionDetail, accessButton])
            line.spacing = 16
            permissionDetail.setContentHuggingPriority(.defaultLow, for: .horizontal)
            permissionDetail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            permissionArea.addArrangedSubview(line)
        }
        for view in permissionArea.arrangedSubviews { view.widthAnchor.constraint(equalTo: permissionArea.widthAnchor, constant: -20).isActive = true }
        add.isEnabled = granted
        // Keep existing rules editable/removable, including while permission is off.
    }

    @objc private func changeDefault() {
        guard let mode = MenuBarMode(rawValue: defaultPopup.indexOfSelectedItem) else { return }
        onDefault?(mode)
    }
    @objc private func changeEnabled() { onEnabled?(enabled.state == .on) }
    @objc private func changeLogin() { onLaunchAtLogin?(launchAtLogin.state == .on) }
    @objc private func changeIcon() { onShowIcon?(showIcon.state == .on) }
    @objc private func allowAccess() { onPermission?() }
    @objc private func changeRule(_ sender: NSPopUpButton) {
        guard let id = sender.identifier?.rawValue, var rule = getConfiguration().rules[id],
              let mode = MenuBarMode(rawValue: sender.indexOfSelectedItem) else { return }
        rule.mode = mode
        onSaveRule?(rule)
    }
    @objc private func removeRule(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        removed = getConfiguration().rules[id]
        onRemoveRule?(id)
    }
    @objc private func undoRemoval() {
        guard let rule = removed else { return }
        removed = nil
        onSaveRule?(rule)
    }
    @objc private func addApp() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose an App"
        panel.prompt = "Add App"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url, let bundle = Bundle(url: url),
                  let id = bundle.bundleIdentifier, id != Bundle.main.bundleIdentifier, id != SettingsBridge.owner else { return }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            guard let mode = self.getConfiguration().rules[id]?.mode ?? self.getConfiguration().defaultMode else {
                self.reload(message: "Choose a default menu bar setting before adding an app.")
                return
            }
            self.onSaveRule?(AppRule(bundleID: id, name: name, path: url.path, mode: mode))
        }
    }
}
