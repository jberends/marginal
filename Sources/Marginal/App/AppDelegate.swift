import AppKit

// All of this is UI work (menus, windows, NSApp) -- pin the whole delegate to the
// main actor so Swift 6 strict concurrency knows every member runs there.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {

    private var preferencesWindowController: NSWindowController?

    /// When the current ⌘Q/⌘W keypress started, so a *held* shortcut can be told apart from a
    /// tapped one. Cleared on key-up and whenever the shortcut is not the one being held.
    private var discardShortcutHeldSince: Date?
    private var discardShortcutMonitor: Any?

    /// How long ⌘Q/⌘W must be held before it means "leave without saving". Long enough that a
    /// normal quit never trips it, short enough to feel like an answer to a stuck dialog.
    private static let discardHoldDuration: TimeInterval = 0.6

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.buildMainMenu(target: self)
        // Ten recent documents, the macOS default, stated explicitly so it does not drift with
        // whatever the system-wide preference happens to be.
        UserDefaults.standard.register(defaults: ["NSRecentDocumentsLimit": 10])
        installDiscardShortcutMonitor()
    }

    // MARK: - Leave without saving

    /// Two ways out of an unsaved document, both of which *discard* the unsaved changes:
    /// hold ⌘Q/⌘W, or press it a second time while the "do you want to save?" sheet is up.
    /// The second is the important one -- that sheet appears in response to ⌘Q/⌘W, so pressing
    /// the same keys again is the natural reflex, and until now it did nothing at all.
    private func installDiscardShortcutMonitor() {
        discardShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            guard event.modifierFlags.contains(.command),
                  let key = event.charactersIgnoringModifiers?.lowercased(),
                  key == "q" || key == "w" else {
                self.discardShortcutHeldSince = nil
                return event
            }

            if event.type == .keyUp {
                self.discardShortcutHeldSince = nil
                return event
            }

            let quitting = (key == "q")

            // Pressed again while the save sheet is showing: answer it with "don't save".
            if self.isShowingSaveSheet {
                self.discardChanges(quittingApp: quitting)
                return nil
            }

            if event.isARepeat {
                if let since = self.discardShortcutHeldSince,
                   Date().timeIntervalSince(since) >= Self.discardHoldDuration {
                    self.discardShortcutHeldSince = nil
                    self.discardChanges(quittingApp: quitting)
                    return nil
                }
            } else {
                self.discardShortcutHeldSince = Date()
            }
            return event
        }
    }

    private var isShowingSaveSheet: Bool {
        NSApp.windows.contains { $0.attachedSheet != nil }
    }

    /// Throws away unsaved changes and closes -- the whole app for ⌘Q, just the front document
    /// for ⌘W. Clearing each document's change count first is what stops AppKit putting the save
    /// sheet straight back up as it closes.
    private func discardChanges(quittingApp: Bool) {
        let documents = NSDocumentController.shared.documents
        let frontDocument = (NSApp.keyWindow ?? NSApp.mainWindow)?.windowController?.document as? NSDocument
        let targets: [NSDocument] = quittingApp ? documents : [frontDocument].compactMap { $0 }

        // Clear the change count first: dismissing the sheet lets the close it belonged to carry
        // on, and if the document still looks dirty at that moment AppKit simply asks again.
        for document in targets {
            document.updateChangeCount(.changeCleared)
        }

        for window in NSApp.windows {
            if let sheet = window.attachedSheet {
                window.endSheet(sheet, returnCode: .abort)
            }
        }

        if quittingApp {
            NSApp.terminate(nil)
        } else {
            // Close the front document itself rather than its window: with tabs, one document owns
            // one tab, and closing the document takes that tab away without disturbing its
            // siblings in the same window.
            for document in targets {
                document.close()
            }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func showAboutPanel(_ sender: Any?) {
        let credits = NSAttributedString(
            string: "Apache License 2.0\n© 2026 Jochem Berends",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    /// App menu -> Check for Updates: compares the running version against the newest
    /// GitHub release. Network access happens only here, on the user's explicit request.
    @objc private func checkForUpdates(_ sender: Any?) {
        UpdateChecker.check { result in
            DispatchQueue.main.async {
                let alert = NSAlert()
                switch result {
                case .upToDate(let current):
                    alert.messageText = "Marginal is up to date."
                    alert.informativeText = "Version \(current) is the latest release."
                    alert.addButton(withTitle: "OK")
                case .updateAvailable(let current, let release):
                    alert.messageText = "Marginal \(release.version) is available."
                    alert.informativeText = "You have \(current). Marginal can download the update, quit, install it, and relaunch."
                    alert.addButton(withTitle: "Download & Install")
                    alert.addButton(withTitle: "View Release")
                    alert.addButton(withTitle: "Later")
                case .failed(let reason):
                    alert.messageText = "Could not check for updates."
                    alert.informativeText = reason
                    alert.addButton(withTitle: "OK")
                }
                let response = alert.runModal()
                if case .updateAvailable(_, let release) = result {
                    switch response {
                    case .alertFirstButtonReturn:
                        UpdateInstaller.downloadAndInstall(release) { error in
                            let failure = NSAlert()
                            failure.messageText = "Could not install the update."
                            failure.informativeText = error.localizedDescription
                            failure.runModal()
                        }
                    case .alertSecondButtonReturn:
                        NSWorkspace.shared.open(UpdateChecker.releasesPage)
                    default:
                        break
                    }
                }
            }
        }
    }

    // iTerm2-style direct tab access: ⌘1…⌘9 jump straight to that tab in the key window's
    // tab group (menu item tag carries the zero-based tab index).
    @objc func selectTabAtIndex(_ sender: NSMenuItem) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let tabs = window.tabbedWindows ?? [window]
        guard tabs.indices.contains(sender.tag) else { return }
        tabs[sender.tag].makeKeyAndOrderFront(nil)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(selectTabAtIndex(_:)) {
            let tabs = (NSApp.keyWindow ?? NSApp.mainWindow)?.tabbedWindows
            return menuItem.tag < (tabs?.count ?? 1)
        }
        return true
    }

    @objc private func showPreferences(_ sender: Any?) {
        if preferencesWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Preferences"
            window.isReleasedWhenClosed = false
            window.center()

            let label = NSTextField(labelWithString: "Preferences are coming in a future update.")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.alignment = .center
            window.contentView?.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor)
            ])

            preferencesWindowController = NSWindowController(window: window)
        }
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private static func buildMainMenu(target: AppDelegate) -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Marginal", action: #selector(AppDelegate.showAboutPanel(_:)), keyEquivalent: "")
        appMenu.items.last?.target = target
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: "")
        appMenu.items.last?.target = target
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Preferences…", action: #selector(AppDelegate.showPreferences(_:)), keyEquivalent: ",")
        appMenu.items.last?.target = target
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Marginal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(NSWindow.newWindowForTab(_:)), keyEquivalent: "t")
        fileMenu.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")

        // AppKit fills this in itself -- and keeps it across launches -- as long as the submenu
        // carries the identifier it looks for. Building the list by hand would mean duplicating
        // the tracking NSDocumentController already does every time a document is opened or saved.
        let openRecentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let openRecentMenu = NSMenu(title: "Open Recent")
        openRecentMenu.identifier = NSUserInterfaceItemIdentifier("NSRecentDocumentsMenu")
        openRecentItem.submenu = openRecentMenu
        fileMenu.addItem(openRecentItem)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(withTitle: "Save…", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "Save As…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        fileMenu.addItem(withTitle: "Revert to Saved", action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Export as PDF…", action: #selector(DocumentViewController.exportAsPDF(_:)), keyEquivalent: "E")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        // Copy is routed through DocumentViewController rather than NSText.copy(_:) so it puts
        // only the raw markdown source on the pasteboard -- see the doc comment on
        // DocumentViewController.copySelectionAsMarkdown(_:) for why the default rich-text copy
        // isn't safe to use here.
        editMenu.addItem(withTitle: "Copy", action: #selector(DocumentViewController.copySelectionAsMarkdown(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Copy as HTML", action: #selector(DocumentViewController.copySelectionAsHTML(_:)), keyEquivalent: "C")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Show Previous Tab", action: #selector(NSWindow.selectPreviousTab(_:)), keyEquivalent: "")
        windowMenu.addItem(withTitle: "Show Next Tab", action: #selector(NSWindow.selectNextTab(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        // iTerm2-style ⌘1…⌘9 direct tab access (tag carries the zero-based tab index).
        for tabNumber in 1...9 {
            let item = NSMenuItem(title: "Select Tab \(tabNumber)", action: #selector(AppDelegate.selectTabAtIndex(_:)), keyEquivalent: "\(tabNumber)")
            item.tag = tabNumber - 1
            item.target = target
            windowMenu.addItem(item)
        }
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Move Tab to New Window", action: #selector(NSWindow.moveTabToNewWindow(_:)), keyEquivalent: "")
        windowMenu.addItem(withTitle: "Merge All Windows", action: #selector(NSWindow.mergeAllWindows(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }
}
