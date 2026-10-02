import AppKit
import PlumeKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings = PlumeSettings.shared
    private let session = SessionController()
    private let hotkeys = HotkeyManager()
    private lazy var app = AppModel(session: session)
    private var island: IslandController!
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var remote: NSObjectProtocol?
    /// Sans cela, macOS met en sommeil les apps sans fenêtre (App Nap) et ralentit la
    /// détection des raccourcis.
    private let activity = ProcessInfo.processInfo.beginActivity(
        options: .userInitiatedAllowingIdleSystemSleep, reason: "Raccourcis globaux de dictée")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Fonts.register()
        Sounds.live = true
        buildMainMenu()
        installKeys()

        island = IslandController(session: session)
        island.onOpen = { [weak self] transcript in
            self?.session.dismiss()
            self?.showWindow(opening: transcript)
        }

        session.onPhaseChanged = { [weak self] phase in
            guard let self else { return }
            if TestHooks.showsIsland { self.island.phaseChanged(phase) }
            self.updateEscape()
            self.hotkeys.holdEnabled = !self.session.isBusy
            self.updateStatusIcon()
        }
        session.onModeChanged = { [weak self] _ in self?.updateEscape() }
        session.onLibraryChanged = { [weak self] in self?.app.refresh() }

        hotkeys.onPress = { [weak self] action in
            TestHooks.log("raccourci : appui \(action)")
            if action == .open {
                self?.showWindow()
            } else {
                self?.session.handlePress(action)
            }
        }
        hotkeys.onRelease = { [weak self] in
            TestHooks.log("raccourci : relâchement \($0) après \(String(format: "%.2f", $1)) s")
            self?.session.handleRelease($0, held: $1)
        }
        hotkeys.onCancel = { [weak self] in
            TestHooks.log("raccourci : annulation \($0)")
            self?.session.handleCancel($0)
        }
        hotkeys.onEscape = { [weak self] in self?.session.cancel() }
        if !TestHooks.headless { hotkeys.reload() }

        app.settings.onShortcutsChanged = { [weak self] in
            if !TestHooks.headless { self?.hotkeys.reload() }
        }
        app.settings.onRecordingShortcut = { [weak self] recording in self?.hotkeys.isPaused = recording }
        app.settings.onModelChanged = { [weak self] in self?.session.loadModel() }
        app.settings.onAppearanceChanged = { [weak self] in self?.applyAppearance() }

        settings.store.prepare()
        // Mise en veille en plein enregistrement : on termine avec ce qui a été capté.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.session.stop() }
        }
        remote = Remote.listen(session: session) { [weak self] in self?.showWindow() }
        Remote.onSnapshot = { [weak self] in
            self?.island.debugSnapshot(to: FileManager.default.temporaryDirectory.appendingPathComponent("plume-ile.png"))
        }
        Remote.onDrawer = { [weak self] open in self?.island.debugPin(open) }
        if !TestHooks.headless { setupStatusItem() }
        Updates.shared.start()
        session.loadModel()

        // Premier lancement, ou autorisation manquante : la fenêtre s'ouvre sur l'accueil.
        if TestHooks.fakeMic == nil, !settings.onboarded || app.settings.permissionsMissing {
            settings.onboarded = true
            showWindow()
        }
    }

    /// Échap n'est intercepté que pendant une dictée (pas pendant une réunion d'une heure).
    private func updateEscape() {
        guard !TestHooks.headless else { return }
        hotkeys.setEscapeEnabled(session.phase == .recording && session.mode == .dictation)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.shutdown()
    }

    // MARK: - Barre de menus

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Plume — clic : ouvrir · clic droit : menu"
        }
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        // La plume de l'icône de l'app, en forme pleine.
        let image = Glyph.plume.image(size: 18)
        image.accessibilityDescription = "Plume"
        button.image = image
        button.contentTintColor = session.phase == .recording ? .systemRed : nil
    }

    /// Clic : la fenêtre de Plume. Clic droit (ou ⌃clic) : un court menu.
    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        let secondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        guard secondary else {
            showWindow()
            return
        }
        let menu = NSMenu()
        let recording = session.phase == .recording
        menu.addItem(
            item(recording ? "Terminer l'enregistrement" : "Dicter", #selector(toggleDictation),
                hint: HotkeyManager.describe(settings.dictationShortcut)))
        if recording {
            menu.addItem(item("Annuler", #selector(cancelRecording)))
        } else {
            menu.addItem(item("Enregistrer une réunion", #selector(toggleMeeting)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Ouvrir Plume", #selector(openWindow)))
        if Updates.shared.isAvailable {
            menu.addItem(item("Rechercher une mise à jour…", #selector(checkForUpdates)))
        }
        menu.addItem(item("Quitter Plume", #selector(quit), key: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector, key: String = "", hint: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let hint, hint != "Aucun" {
            let text = NSMutableAttributedString(string: title)
            text.append(
                NSAttributedString(
                    string: "   \(hint)",
                    attributes: [.foregroundColor: NSColor.tertiaryLabelColor, .font: NSFont.menuFont(ofSize: 13)]))
            item.attributedTitle = text
        }
        return item
    }

    @objc private func toggleDictation() {
        if session.phase == .recording { session.stop() } else { session.start(.dictation) }
    }
    @objc private func toggleMeeting() { session.toggle(.meeting) }
    @objc private func cancelRecording() { session.cancel() }
    @objc private func openWindow() { showWindow() }
    @objc private func checkForUpdates() { Updates.shared.check() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Fenêtre

    private func showWindow(opening transcript: Transcript? = nil) {
        if window == nil {
            let host = NSHostingController(rootView: AppShell(app: app, session: session))
            let window = NSWindow(contentViewController: host)
            window.title = "Plume"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.setContentSize(NSSize(width: 1040, height: 740))
            window.minSize = NSSize(width: 880, height: 560)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("PlumeFenetre")
            self.window = window
            applyAppearance()
        }
        app.refresh()
        app.settings.refreshPermissions()
        if window?.isVisible != true { Sounds.play(.windowOpen) }
        if let transcript { app.open(transcript) }
        // Tant que la fenêtre est ouverte, Plume se comporte comme une app ordinaire
        // (Dock, ⌘Tab) ; fermée, elle redevient une simple icône de barre de menus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Touches de la fenêtre, comme sur le portfolio : 1 à 4 pour les pages, T pour le thème,
    /// S pour les sons. Sans effet pendant qu'on écrit dans un champ ou qu'on saisit un raccourci.
    private func installKeys() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window, !self.hotkeys.isPaused,
                event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                !(window.firstResponder is NSText), let key = event.charactersIgnoringModifiers?.lowercased()
            else { return event }
            switch key {
            case "1", "2", "3", "4", "&", "é", "\"", "'":
                // Rangée du haut d'un clavier français : & é " ' sans majuscule.
                let index = ["1": 0, "2": 1, "3": 2, "4": 3, "&": 0, "é": 1, "\"": 2, "'": 3][key] ?? 0
                withAnimation(UI.spring) { self.app.page = Page.allCases[index] }
            case "t":
                Sounds.play(.tab)
                let dark = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                self.app.settings.appearance = dark ? "clair" : "sombre"
            case "s":
                self.app.settings.sounds.toggle()
                if self.app.settings.sounds { Sounds.play(.confirm) }
            default:
                return event
            }
            return nil
        }
    }

    private func applyAppearance() {
        switch settings.appearance {
        case "clair": window?.appearance = NSAppearance(named: .aqua)
        case "systeme": window?.appearance = nil
        default: window?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func windowWillClose(_ notification: Notification) {
        app.library.player.stop()
        NSApp.setActivationPolicy(.accessory)
    }

    /// Menu principal : nécessaire pour que ⌘C, ⌘V, ⌘W et ⌘Q fonctionnent dans la fenêtre.
    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "Plume")
        appItem.submenu?.addItem(
            NSMenuItem(title: "Masquer Plume", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appItem.submenu?.addItem(.separator())
        appItem.submenu?.addItem(
            NSMenuItem(title: "Quitter Plume", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        main.addItem(appItem)

        let edit = NSMenuItem()
        edit.submenu = NSMenu(title: "Édition")
        edit.submenu?.addItem(NSMenuItem(title: "Annuler", action: Selector(("undo:")), keyEquivalent: "z"))
        edit.submenu?.addItem(NSMenuItem(title: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.submenu?.addItem(NSMenuItem(title: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.submenu?.addItem(NSMenuItem(title: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.submenu?.addItem(
            NSMenuItem(title: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        main.addItem(edit)

        let windowItem = NSMenuItem()
        windowItem.submenu = NSMenu(title: "Fenêtre")
        windowItem.submenu?.addItem(
            NSMenuItem(title: "Fermer", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu?.addItem(
            NSMenuItem(title: "Réduire", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}
