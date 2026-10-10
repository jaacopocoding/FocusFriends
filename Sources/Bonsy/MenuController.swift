import AppKit
import ServiceManagement

/// Menu dell'app: icona nella barra dei menu e tasto destro sul personaggio.
final class MenuController: NSObject, NSMenuDelegate {
    private let window: PetWindow
    private let speaker: Speaker
    private let pomodoro: Pomodoro
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let toggleItem = NSMenuItem()
    private let speakItem = NSMenuItem()
    private let loginItem = NSMenuItem()
    private var petItems: [NSMenuItem] = []
    private var movementItems: [NSMenuItem] = []
    private let stopTimerItem = NSMenuItem()
    private var breakItems: [NSMenuItem] = []

    init(window: PetWindow, speaker: Speaker, pomodoro: Pomodoro) {
        self.window = window
        self.speaker = speaker
        self.pomodoro = pomodoro
        super.init()

        toggleItem.title = "Nascondi Bonsy"
        toggleItem.action = #selector(toggleVisibility)
        toggleItem.target = self
        menu.addItem(toggleItem)

        speakItem.title = "Fai parlare Bonsy"
        speakItem.action = #selector(makeSpeak)
        speakItem.target = self
        menu.addItem(speakItem)

        menu.addItem(makePomofocusItem())
        menu.addItem(makePetItem())
        menu.addItem(makeMovementItem())

        menu.addItem(.separator())

        loginItem.title = "Avvia al login"
        loginItem.action = #selector(toggleLaunchAtLogin)
        loginItem.target = self
        menu.addItem(loginItem)

        let quotes = NSMenuItem(title: "Modifica le frasi…", action: #selector(openQuotesFile), keyEquivalent: "")
        quotes.target = self
        menu.addItem(quotes)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Esci da Bonsy", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Stato delle voci gestito a mano (es. "Ferma timer" attiva solo se il timer gira).
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()
        statusItem.button?.toolTip = "Bonsy"

        // Tasto destro sul personaggio: stesso menu.
        window.contentView?.menu = menu
    }

    private func makePetItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Personaggio", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Personaggio")
        sub.autoenablesItems = false
        for pet in Pet.all {
            let item = NSMenuItem(title: pet.name, action: #selector(choosePet(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pet.id
            sub.addItem(item)
            petItems.append(item)
        }
        parent.submenu = sub
        return parent
    }

    private func makeMovementItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Movimento", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Movimento")
        sub.autoenablesItems = false
        for (title, moving) in [("In movimento", true), ("Fermo", false)] {
            let item = NSMenuItem(title: title, action: #selector(setMovement(_:)), keyEquivalent: "")
            item.target = self
            item.tag = moving ? 1 : 0
            sub.addItem(item)
            movementItems.append(item)
        }
        parent.submenu = sub
        return parent
    }

    private func makePomofocusItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Pomofocus", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Pomofocus")
        sub.autoenablesItems = false

        for minutes in [30, 50] {
            let item = NSMenuItem(title: "Focus \(minutes) min", action: #selector(startFocus(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            sub.addItem(item)
        }
        sub.addItem(.separator())

        // La durata scelta vale anche per la pausa che parte da sola dopo il focus (spunta).
        for minutes in [5, 10] {
            let item = NSMenuItem(title: "Pausa \(minutes) min", action: #selector(startBreak(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            sub.addItem(item)
            breakItems.append(item)
        }
        sub.addItem(.separator())

        stopTimerItem.title = "Ferma timer"
        stopTimerItem.action = #selector(stopTimer)
        stopTimerItem.target = self
        sub.addItem(stopTimerItem)

        parent.submenu = sub
        return parent
    }

    // MARK: - Aggiornamento voci

    func menuNeedsUpdate(_ menu: NSMenu) {
        let name = window.pet.name
        toggleItem.title = window.isVisible ? "Nascondi \(name)" : "Mostra \(name)"
        speakItem.title = "Fai parlare \(name)"
        // Il movimento ha senso solo per i personaggi che camminano.
        for item in movementItems {
            item.isEnabled = window.pet.walks
            item.state = (item.tag == 1) == Walker.isMovementEnabled ? .on : .off
        }
        for item in petItems {
            item.state = (item.representedObject as? String) == window.pet.id ? .on : .off
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off

        for item in breakItems {
            item.state = item.tag == pomodoro.breakMinutes ? .on : .off
        }
        stopTimerItem.isEnabled = pomodoro.isRunning
        stopTimerItem.title = pomodoro.isRunning ? "Ferma timer (\(pomodoro.remainingText))" : "Ferma timer"
    }

    // MARK: - Azioni

    @objc private func toggleVisibility() {
        if window.isVisible {
            speaker.stop()
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
            speaker.start()
        }
    }

    @objc private func startFocus(_ sender: NSMenuItem) {
        showPetIfHidden()
        pomodoro.startFocus(minutes: sender.tag)
    }

    @objc private func startBreak(_ sender: NSMenuItem) {
        showPetIfHidden()
        pomodoro.startBreak(minutes: sender.tag)
    }

    @objc private func stopTimer() {
        pomodoro.stop()
    }

    private func showPetIfHidden() {
        if !window.isVisible {
            window.orderFrontRegardless()
            speaker.start()
        }
    }

    @objc private func setMovement(_ sender: NSMenuItem) {
        Walker.isMovementEnabled = sender.tag == 1
    }

    @objc private func choosePet(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let pet = Pet.all.first(where: { $0.id == id }), pet != window.pet else { return }
        pet.remember()
        window.apply(pet)
        updateStatusIcon()
        showPetIfHidden()
        speaker.say(pet.greeting)
    }

    @objc private func makeSpeak() {
        if !window.isVisible { window.orderFrontRegardless() }
        speaker.sayRandom()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            showAlert("Non riesco a cambiare l'avvio al login", error.localizedDescription)
            return
        }
        if service.status == .requiresApproval {
            showAlert(
                "Serve la tua approvazione",
                "Apri Impostazioni di Sistema → Generali → Elementi login e consenti a Bonsy di avviarsi."
            )
        }
    }

    @objc private func openQuotesFile() {
        let fm = FileManager.default
        let pet = window.pet
        let file = Quotes.userFile(for: pet)
        if !fm.fileExists(atPath: file.path) {
            try? fm.createDirectory(at: Quotes.userDirectory, withIntermediateDirectories: true)
            // Parto dal file della vecchia cartella (se l'utente l'aveva già modificato), altrimenti da quello dell'app.
            let legacy = Quotes.legacyDirectory.appendingPathComponent(pet.quotesUserFile)
            let bundled = Bundle.main.url(forResource: pet.quotesResource, withExtension: "txt")
            if fm.fileExists(atPath: legacy.path) {
                try? fm.copyItem(at: legacy, to: file)
            } else if let bundled {
                try? fm.copyItem(at: bundled, to: file)
            }
        }
        NSWorkspace.shared.open(file)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    // MARK: - Icona

    private func updateStatusIcon() {
        if let icon = Self.menuBarIcon(for: window.pet) {
            statusItem.button?.title = ""
            statusItem.button?.image = icon
        } else {
            statusItem.button?.image = nil
            statusItem.button?.title = window.pet.name
        }
    }

    /// Il personaggio (o solo la sua testa) ritagliato dall'immagine, alto quanto la barra dei menu.
    private static func menuBarIcon(for pet: Pet) -> NSImage? {
        guard let url = Bundle.main.url(forResource: pet.iconResource, withExtension: "png"),
              let source = NSImage(contentsOf: url) else { return nil }

        let crop = pet.iconCrop ?? NSRect(x: 0, y: 0, width: 1, height: 1)
        let from = NSRect(
            x: crop.minX * source.size.width, y: crop.minY * source.size.height,
            width: crop.width * source.size.width, height: crop.height * source.size.height
        )
        let height: CGFloat = 22
        let size = NSSize(width: ceil(height * from.width / from.height), height: height)
        return NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect, from: from, operation: .sourceOver, fraction: 1)
            return true
        }
    }
}
