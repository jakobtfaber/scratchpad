import Cocoa

// MARK: - Configuration Constants
let storageURL = ProcessInfo.processInfo.environment["DESKTOP_NOTEPAD_STORAGE_PATH"].map(URL.init(fileURLWithPath:))
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".desktop_notes.txt")
let userDefaultsFrameKey = "com.jakobfaber.DesktopScratchpad.windowFrame"
let defaultPadSize = NSSize(width: 480, height: 560)

// MARK: - Custom Views

/// Drag header view that provides a dedicated grip area to reposition the pad smoothly
class HeaderView: NSView {
    private let titleLabel = NSTextField(labelWithString: "SCRATCHPAD")
    private let subtitleLabel = NSTextField(labelWithString: "~/.desktop_notes.txt")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true
        autoresizingMask = [.width]

        titleLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .bold)
        titleLabel.textColor = NSColor.secondaryLabelColor
        titleLabel.sizeToFit()
        titleLabel.frame.origin = NSPoint(x: 14, y: (bounds.height - titleLabel.frame.height) / 2)
        titleLabel.autoresizingMask = [.maxXMargin, .minYMargin, .maxYMargin]
        addSubview(titleLabel)

        subtitleLabel.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
        subtitleLabel.textColor = NSColor.tertiaryLabelColor
        subtitleLabel.sizeToFit()
        subtitleLabel.frame.origin = NSPoint(x: titleLabel.frame.maxX + 10, y: (bounds.height - subtitleLabel.frame.height) / 2)
        subtitleLabel.autoresizingMask = [.maxXMargin, .minYMargin, .maxYMargin]
        addSubview(subtitleLabel)
    }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.performDrag(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        titleLabel.frame.origin = NSPoint(x: 14, y: (bounds.height - titleLabel.frame.height) / 2)
        subtitleLabel.isHidden = bounds.width < titleLabel.frame.maxX + subtitleLabel.frame.width + 24
        subtitleLabel.frame.origin = NSPoint(x: titleLabel.frame.maxX + 10, y: (bounds.height - subtitleLabel.frame.height) / 2)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }
}

/// Custom NSTextView that responds to the very first click without requiring prior window activation
class ScratchpadTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers == [.command] || modifiers == [.command, .shift] else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a" where modifiers == [.command]: selectAll(nil)
        case "c" where modifiers == [.command]: copy(nil)
        case "v" where modifiers == [.command]: paste(nil)
        case "x" where modifiers == [.command]: cut(nil)
        case "z" where modifiers == [.command]: undoManager?.undo()
        case "z" where modifiers == [.command, .shift]: undoManager?.redo()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func shouldDelayWindowOrdering(for event: NSEvent) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        NSApplication.shared.preventWindowOrdering()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        super.mouseDown(with: event)
    }
}

// MARK: - Desktop Pinned Panel

class DesktopNotepadPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        // Stay below every standard application window, including during Space transitions.
        self.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)

        // .canJoinAllSpaces: visible across all virtual desktop spaces
        // .stationary: stays anchored to the desktop during Mission Control / Exposé
        // .ignoresCycle: excluded from Cmd + ` window cycling
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.isMovableByWindowBackground = true
        self.minSize = NSSize(width: 280, height: 200)
    }
}

// MARK: - External File Monitor

class FileWatcher {
    private var source: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.desktop-scratchpad.filewatcher")
    private let onFileChange: () -> Void

    init(url: URL, onFileChange: @escaping () -> Void) {
        self.onFileChange = onFileChange
        startWatching()
    }

    func startWatching() {
        stopWatching()

        let src = DispatchSource.makeTimerSource(queue: queue)
        src.schedule(deadline: .now() + 0.25, repeating: 0.25, leeway: .milliseconds(50))

        src.setEventHandler { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.onFileChange()
            }
        }

        self.source = src
        src.resume()
    }

    func stopWatching() {
        if let src = source {
            src.cancel()
            source = nil
        }
    }

    deinit {
        stopWatching()
    }
}

// MARK: - Application Delegate & Coordinator

class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSWindowDelegate {
    var panel: DesktopNotepadPanel!
    var textView: ScratchpadTextView!
    var saveTimer: Timer?
    var statusItem: NSStatusItem?
    var fileWatcher: FileWatcher?
    var lastSavedContent: String = ""
    var workspaceObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupPanel()
        setupMenuBar()
        setupBackgroundEnforcement()
        ensureFileExists()
        loadFileContent()
        setupFileWatcher()
    }

    private func setupPanel() {
        let initialFrame = loadSavedFrame()
        panel = DesktopNotepadPanel(contentRect: initialFrame)
        panel.delegate = self

        // Frosted translucent card background
        let visualEffect = NSVisualEffectView(frame: panel.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .underWindowBackground
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 16
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 1.0
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        // Header view for dragging and title
        let headerHeight: CGFloat = 28
        let header = HeaderView(frame: NSRect(
            x: 0,
            y: visualEffect.bounds.height - headerHeight,
            width: visualEffect.bounds.width,
            height: headerHeight
        ))
        header.autoresizingMask = [.width, .minYMargin]
        visualEffect.addSubview(header)

        // Scroll view container
        let scrollFrame = NSRect(
            x: 4,
            y: 4,
            width: visualEffect.bounds.width - 8,
            height: visualEffect.bounds.height - headerHeight - 6
        )
        let scrollView = NSScrollView(frame: scrollFrame)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        // Text view with clean monospaced typography
        let contentSize = scrollView.contentSize
        textView = ScratchpadTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.minSize = NSSize(width: 0.0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        textView.font = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.delegate = self
        textView.textContainerInset = NSSize(width: 12, height: 8)

        scrollView.documentView = textView
        visualEffect.addSubview(scrollView)
        panel.contentView?.addSubview(visualEffect)

        // Order back to sit under regular windows
        panel.orderFrontRegardless()
        panel.orderBack(nil)
    }

    /// Automatically ensure the panel drops to the back whenever another app activates
    private func setupBackgroundEnforcement() {
        let activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self.sendToBack()
        }
        workspaceObservers = [activationObserver]
    }

    func windowDidResignKey(_ notification: Notification) {
        panel.orderBack(nil)
    }

    private func setupMenuBar() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Desktop Scratchpad")
        }

        let menu = NSMenu()
        let headerItem = NSMenuItem(title: "Desktop Scratchpad", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Show / Focus Scratchpad", action: #selector(showAndFocus), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Send to Desktop (Back)", action: #selector(sendToBack), keyEquivalent: "b"))
        menu.addItem(NSMenuItem.separator())

        let screenMenu = NSMenu()
        screenMenu.addItem(NSMenuItem(title: "Move to Active Screen (Mouse)", action: #selector(moveToMouseScreen), keyEquivalent: "m"))
        screenMenu.addItem(NSMenuItem(title: "Move to External Screen", action: #selector(moveToExternalScreen), keyEquivalent: ""))
        screenMenu.addItem(NSMenuItem(title: "Move to Laptop Screen", action: #selector(moveToLaptopScreen), keyEquivalent: ""))
        screenMenu.addItem(NSMenuItem(title: "Center on Screen", action: #selector(centerOnCurrentScreen), keyEquivalent: "c"))

        let displayItem = NSMenuItem(title: "Display Placement", action: nil, keyEquivalent: "")
        displayItem.submenu = screenMenu
        menu.addItem(displayItem)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Open ~/.desktop_notes.txt in External Editor", action: #selector(openInEditor), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reveal File in Finder", action: #selector(revealFile), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Clear Scratchpad", action: #selector(clearPad), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Desktop Scratchpad", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    // MARK: - Frame Persistence & Display Positioning

    private func loadSavedFrame() -> NSRect {
        if let saved = UserDefaults.standard.string(forKey: userDefaultsFrameKey) {
            let rect = NSRectFromString(saved)
            if rect.width >= 200 && rect.height >= 150 {
                if let screen = NSScreen.screens.max(by: {
                    $0.frame.intersection(rect).area < $1.frame.intersection(rect).area
                }), screen.frame.intersection(rect).area > 0 {
                    return fittedFrame(rect, on: screen)
                }
            }
        }
        return defaultFrameForActiveScreen()
    }

    private func defaultFrameForActiveScreen() -> NSRect {
        // Prioritize screen containing mouse, or largest (external) screen
        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) })
            ?? NSScreen.screens.max(by: { $0.frame.width < $1.frame.width })
            ?? NSScreen.main
            ?? NSScreen.screens.first!

        let visible = targetScreen.visibleFrame
        return NSRect(
            x: visible.minX + 60,
            y: visible.minY + 60,
            width: defaultPadSize.width,
            height: defaultPadSize.height
        )
    }

    private func fittedFrame(_ frame: NSRect, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let size = NSSize(
            width: min(max(frame.width, panel?.minSize.width ?? 280), visible.width),
            height: min(max(frame.height, panel?.minSize.height ?? 200), visible.height)
        )
        return NSRect(
            x: min(max(frame.minX, visible.minX), visible.maxX - size.width),
            y: min(max(frame.minY, visible.minY), visible.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }

    private func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }

    private func persistCurrentFrame() {
        guard let panel = panel else { return }
        let frameStr = NSStringFromRect(panel.frame)
        UserDefaults.standard.set(frameStr, forKey: userDefaultsFrameKey)
    }

    func windowDidMove(_ notification: Notification) {
        persistCurrentFrame()
    }

    func windowDidResize(_ notification: Notification) {
        persistCurrentFrame()
    }

    // MARK: - Display Placement Actions

    @objc private func showAndFocus() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
    }

    @objc private func sendToBack() {
        panel.orderBack(nil)
    }

    @objc private func moveToMouseScreen() {
        let mouseLoc = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }) {
            movePanelToScreen(screen)
        }
    }

    @objc private func moveToExternalScreen() {
        if let external = NSScreen.screens.first(where: { !isBuiltIn($0) }) {
            movePanelToScreen(external)
        }
    }

    @objc private func moveToLaptopScreen() {
        if let laptop = NSScreen.screens.first(where: { isBuiltIn($0) }) {
            movePanelToScreen(laptop)
        }
    }

    @objc private func centerOnCurrentScreen() {
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.midY - panel.frame.height / 2
        ))
        persistCurrentFrame()
        panel.orderBack(nil)
    }

    private func movePanelToScreen(_ screen: NSScreen) {
        let visible = screen.visibleFrame
        let proposed = NSRect(
            x: visible.minX + 60,
            y: visible.minY + 60,
            width: panel.frame.width,
            height: panel.frame.height
        )
        let newRect = fittedFrame(proposed, on: screen)
        panel.setFrame(newRect, display: true, animate: true)
        persistCurrentFrame()
        panel.orderBack(nil)
    }

    // MARK: - File I/O & Bidirectional Sync

    private func ensureFileExists() {
        if !FileManager.default.fileExists(atPath: storageURL.path) {
            try? "".write(to: storageURL, atomically: true, encoding: .utf8)
        }
    }

    private func loadFileContent() {
        if let content = try? String(contentsOf: storageURL, encoding: .utf8) {
            lastSavedContent = content
            textView.string = content
        }
    }

    private func setupFileWatcher() {
        fileWatcher = FileWatcher(url: storageURL) { [weak self] in
            self?.handleExternalFileChange()
        }
    }

    private func handleExternalFileChange() {
        guard let diskContent = try? String(contentsOf: storageURL, encoding: .utf8) else { return }
        if diskContent != lastSavedContent && diskContent != textView.string {
            saveTimer?.invalidate()
            saveTimer = nil
            lastSavedContent = diskContent
            let selectedRange = textView.selectedRange()
            textView.string = diskContent
            let length = (diskContent as NSString).length
            let location = min(selectedRange.location, length)
            textView.setSelectedRange(NSRange(location: location, length: min(selectedRange.length, length - location)))
        } else if diskContent != lastSavedContent {
            lastSavedContent = diskContent
        }
    }

    func textDidChange(_ notification: Notification) {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: false) { [weak self] _ in
            self?.persistContent()
        }
    }

    private func persistContent() {
        guard let text = textView?.string else { return }
        if text == lastSavedContent { return }

        do {
            try text.write(to: storageURL, atomically: true, encoding: .utf8)
            lastSavedContent = text
        } catch {
            NSLog("DesktopNotepad could not save %@: %@", storageURL.path, error.localizedDescription)
        }
    }

    // MARK: - Menu Actions

    @objc private func openInEditor() {
        NSWorkspace.shared.open(storageURL)
    }

    @objc private func revealFile() {
        NSWorkspace.shared.activateFileViewerSelecting([storageURL])
    }

    @objc private func clearPad() {
        let alert = NSAlert()
        alert.messageText = "Clear Scratchpad?"
        alert.informativeText = "This will empty the scratchpad and clear ~/.desktop_notes.txt."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            textView.string = ""
            persistContent()
        }
    }

    @objc private func quitApp() {
        saveTimer?.invalidate()
        persistContent()
        fileWatcher?.stopWatching()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveTimer?.invalidate()
        persistContent()
        fileWatcher?.stopWatching()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

private final class ShortcutProbeTextView: ScratchpadTextView {
    let testUndoManager = UndoManager()
    var receivedAction = ""

    override var undoManager: UndoManager? { testUndoManager }
    override func selectAll(_ sender: Any?) { receivedAction = "selectAll" }
    override func copy(_ sender: Any?) { receivedAction = "copy" }
    override func paste(_ sender: Any?) { receivedAction = "paste" }
    override func cut(_ sender: Any?) { receivedAction = "cut" }
}

private func runShortcutChecks() -> Bool {
    let view = ShortcutProbeTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))

    func event(_ key: String, shift: Bool = false) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: shift ? [.command, .shift] : [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: key,
            charactersIgnoringModifiers: key.lowercased(),
            isARepeat: false,
            keyCode: 0
        )!
    }

    func check(_ condition: @autoclosure () -> Bool, _ message: String) -> Bool {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            return false
        }
        return true
    }

    view.receivedAction = ""
    guard check(view.performKeyEquivalent(with: event("a")), "Command-A was not handled"),
          check(view.receivedAction == "selectAll", "Command-A did not invoke selectAll") else { return false }

    view.receivedAction = ""
    guard check(view.performKeyEquivalent(with: event("c")), "Command-C was not handled"),
          check(view.receivedAction == "copy", "Command-C did not invoke copy") else { return false }

    view.receivedAction = ""
    guard check(view.performKeyEquivalent(with: event("x")), "Command-X was not handled"),
          check(view.receivedAction == "cut", "Command-X did not invoke cut") else { return false }

    view.receivedAction = ""
    guard check(view.performKeyEquivalent(with: event("v")), "Command-V was not handled"),
          check(view.receivedAction == "paste", "Command-V did not invoke paste") else { return false }

    view.testUndoManager.registerUndo(withTarget: view) { target in
        target.receivedAction = "undo"
        target.testUndoManager.registerUndo(withTarget: target) { $0.receivedAction = "redo" }
    }
    view.receivedAction = ""
    guard check(view.performKeyEquivalent(with: event("z")), "Command-Z was not handled"),
          check(view.receivedAction == "undo", "Command-Z did not invoke undo") else { return false }

    view.receivedAction = ""
    guard check(view.performKeyEquivalent(with: event("Z", shift: true)), "Command-Shift-Z was not handled"),
          check(view.receivedAction == "redo", "Command-Shift-Z did not invoke redo") else { return false }
    return true
}

// MARK: - Entry Point
let app = NSApplication.shared
if CommandLine.arguments.contains("--test-key-equivalents") {
    exit(runShortcutChecks() ? 0 : 1)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
