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
    private var chattinessItems: [NSMenuItem] = []
    private let stopTimerItem = NSMenuItem()
    private var breakItems: [NSMenuItem] = []
    private let headerView = MenuHeaderView()
    private let pomofocusItem = NSMenuItem()
    private let chattinessParent = NSMenuItem()
    private let movementParent = NSMenuItem()
    private var petParent: NSMenuItem?
    private let statsItem = NSMenuItem()
    private let subjectPrompt = SubjectPrompt()
    private let askItem = NSMenuItem()
    private let dashboard = DashboardController()
    private let garden = GardenController()
    private let gardenItem = NSMenuItem()
    private let nameItem = NSMenuItem()
    private var card: MenuCard!

    init(window: PetWindow, speaker: Speaker, pomodoro: Pomodoro) {
        self.window = window
        self.speaker = speaker
        self.pomodoro = pomodoro
        super.init()

        // In cima: la scheda con il personaggio e cosa sta facendo (si aggiorna quando cambia personaggio).
        headerView.title = window.pet.name
        headerView.icon = Self.menuIcon(for: window.pet, height: 80)
        let header = NSMenuItem()
        header.view = headerView
        menu.addItem(header)
        menu.addItem(.separator())

        // Azioni
        toggleItem.title = "Nascondi \(window.pet.name)"
        toggleItem.action = #selector(toggleVisibility)
        toggleItem.target = self
        toggleItem.image = Self.symbol("eye.slash")
        menu.addItem(toggleItem)

        speakItem.title = "Fai parlare \(window.pet.name)"
        speakItem.action = #selector(makeSpeak)
        speakItem.target = self
        speakItem.image = Self.symbol("bubble.left")
        menu.addItem(speakItem)

        menu.addItem(.separator())

        // Timer e impostazioni di comportamento
        let pomofocusMenu = NSMenu(title: "Pomofocus")
        pomofocusMenu.autoenablesItems = false
        pomofocusItem.submenu = pomofocusMenu
        populatePomofocusMenu()
        pomofocusItem.title = "Pomofocus"
        pomofocusItem.image = Self.symbol("timer")
        menu.addItem(pomofocusItem)

        statsItem.title = "Statistiche e riepilogo…"
        statsItem.action = #selector(showStats)
        statsItem.target = self
        statsItem.image = Self.symbol("chart.bar.xaxis")
        menu.addItem(statsItem)

        gardenItem.title = "Il mio giardino…"
        gardenItem.action = #selector(showGarden)
        gardenItem.target = self
        gardenItem.image = Self.symbol("leaf")
        menu.addItem(gardenItem)

        let chat = makeChattinessItem()
        chattinessParent.submenu = chat.submenu
        chattinessParent.title = "Frequenza delle frasi"
        chattinessParent.image = Self.symbol("text.bubble")
        menu.addItem(chattinessParent)

        menu.addItem(makePetItem())

        let move = makeMovementItem()
        movementParent.submenu = move.submenu
        movementParent.title = "Movimento"
        movementParent.image = Self.symbol("figure.walk")
        menu.addItem(movementParent)

        menu.addItem(.separator())

        // L'app
        nameItem.title = "Il tuo nome…"
        nameItem.action = #selector(editName)
        nameItem.target = self
        nameItem.image = Self.symbol("person.crop.circle")
        menu.addItem(nameItem)

        askItem.title = "Chiedi com'è andata"
        askItem.action = #selector(toggleAskHowItWent)
        askItem.target = self
        askItem.image = Self.symbol("face.smiling")
        menu.addItem(askItem)

        loginItem.title = "Avvia al login"
        loginItem.action = #selector(toggleLaunchAtLogin)
        loginItem.target = self
        loginItem.image = Self.symbol("power")
        menu.addItem(loginItem)

        let quotes = NSMenuItem(title: "Modifica le frasi…", action: #selector(openQuotesFile), keyEquivalent: "")
        quotes.target = self
        quotes.image = Self.symbol("pencil")
        menu.addItem(quotes)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Esci da FocusFriends", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.image = Self.symbol("xmark.circle")
        menu.addItem(quit)

        // Stato delle voci gestito a mano (es. "Ferma timer" attiva solo se il timer gira).
        menu.autoenablesItems = false
        menu.delegate = self
        updateStatusIcon()
        statusItem.button?.toolTip = "FocusFriends"

        // Clic sull'icona o tasto destro sul personaggio: la scheda. Tasto destro o ⌥-clic sull'icona: il menu di prima.
        card = MenuCard(state: { [unowned self] in self.cardState() }, actions: cardActions())
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        window.onContextClick = { [weak self] in self?.showCardNearPet() }
    }

    private func makePetItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Personaggio", action: nil, keyEquivalent: "")
        parent.image = Self.symbol("pawprint")
        petParent = parent
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

    private func makeChattinessItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Frequenza delle frasi", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Frequenza delle frasi")
        sub.autoenablesItems = false
        for level in Chattiness.allCases {
            let item = NSMenuItem(title: level.title, action: #selector(setChattiness(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = level.rawValue
            item.image = Self.symbol(level.symbolName)
            sub.addItem(item)
            chattinessItems.append(item)
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
            item.image = Self.symbol(moving ? "figure.walk" : "pause.circle")
            sub.addItem(item)
            movementItems.append(item)
        }
        parent.submenu = sub
        return parent
    }

    private let customTimers = CustomTimers()

    /// (Ri)costruisce il sottomenu Pomofocus: i timer di serie e quelli personalizzati, in ordine di durata.
    private func populatePomofocusMenu() {
        guard let sub = pomofocusItem.submenu else { return }
        sub.removeAllItems()
        breakItems = []

        for minutes in customTimers.all(.focus) {
            let item = NSMenuItem(title: "Focus \(minutes) min", action: #selector(startFocus(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            item.image = Self.symbol("hourglass")
            sub.addItem(item)
        }
        sub.addItem(.separator())

        // La durata scelta vale anche per la pausa che parte da sola dopo il focus (spunta).
        for minutes in customTimers.all(.rest) {
            let item = NSMenuItem(title: "Pausa \(minutes) min", action: #selector(startBreak(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            item.image = Self.symbol("cup.and.saucer")
            sub.addItem(item)
            breakItems.append(item)
        }
        sub.addItem(.separator())

        // Personalizza: aggiunge un focus o una pausa; "Rimuovi" compare solo se ce ne sono.
        let add = NSMenuItem(title: "Personalizza…", action: #selector(addCustomTimer), keyEquivalent: "")
        add.target = self
        add.image = Self.symbol("slider.horizontal.3")
        sub.addItem(add)

        let custom: [(CustomTimers.Kind, Int)] = [.focus, .rest].flatMap { kind in
            customTimers.custom(kind).map { (kind, $0) }
        }
        if !custom.isEmpty {
            let remove = NSMenuItem(title: "Rimuovi un timer personalizzato", action: nil, keyEquivalent: "")
            remove.image = Self.symbol("minus.circle")
            let removeMenu = NSMenu(title: "Rimuovi")
            removeMenu.autoenablesItems = false
            for (kind, minutes) in custom {
                let item = NSMenuItem(title: "\(kind.title) \(minutes) min", action: #selector(removeCustomTimer(_:)), keyEquivalent: "")
                item.target = self
                item.tag = minutes
                item.representedObject = kind.rawValue
                removeMenu.addItem(item)
            }
            remove.submenu = removeMenu
            sub.addItem(remove)
        }
        sub.addItem(.separator())

        stopTimerItem.title = "Ferma timer"
        stopTimerItem.action = #selector(stopTimer)
        stopTimerItem.target = self
        stopTimerItem.image = Self.symbol("stop.circle")
        sub.addItem(stopTimerItem)
    }

    // MARK: - Aggiornamento voci

    func menuNeedsUpdate(_ menu: NSMenu) {
        let name = window.pet.name
        toggleItem.title = window.isVisible ? "Nascondi \(name)" : "Mostra \(name)"
        toggleItem.image = Self.symbol(window.isVisible ? "eye.slash" : "eye")
        speakItem.title = "Fai parlare \(name)"
        // La scheda in cima segue il personaggio scelto.
        headerView.title = name
        headerView.icon = Self.menuIcon(for: window.pet, height: 80)
        headerView.iconFocus = window.pet.iconFocus

        // Lo stato attuale si legge senza aprire i sottomenu, e la scheda dice cosa sta facendo.
        switch pomodoro.phase {
        case .focus?:
            if let subject = pomodoro.subject {
                headerView.status = "Focus · \(subject) · \(pomodoro.remainingText)"
            } else {
                headerView.status = "Focus · \(pomodoro.remainingText)"
            }
        case .rest?: headerView.status = "Pausa · \(pomodoro.remainingText)"
        case nil: headerView.status = window.isVisible ? "Qui con te" : "Nascosto"
        }
        statsItem.title = Profile.shared.statsTitle + "…"
        gardenItem.title = Profile.shared.gardenTitle + "…"
        petParent?.title = "Personaggio · \(name)"
        pomofocusItem.title = pomodoro.isRunning ? "Pomofocus · \(pomodoro.remainingText)" : "Pomofocus"
        chattinessParent.title = "Frequenza delle frasi · \(Chattiness.current.title)"
        movementParent.title = window.pet.walks
            ? "Movimento · \(Walker.isMovementEnabled ? "In movimento" : "Fermo")"
            : "Movimento"
        for item in chattinessItems {
            item.state = (item.representedObject as? String) == Chattiness.current.rawValue ? .on : .off
        }

        // Il movimento ha senso solo per i personaggi che camminano.
        for item in movementItems {
            item.isEnabled = window.pet.walks
            item.state = (item.tag == 1) == Walker.isMovementEnabled ? .on : .off
        }
        for item in petItems {
            item.state = (item.representedObject as? String) == window.pet.id ? .on : .off
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        askItem.state = ReflectionCard.isEnabled ? .on : .off

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

    /// Prima chiede la materia ("Cosa studi adesso?"), poi parte il focus.
    @objc private func startFocus(_ sender: NSMenuItem) {
        beginFocus(minutes: sender.tag)
    }

    private func beginFocus(minutes: Int) {
        subjectPrompt.ask(minutes: minutes, recent: SessionLog.shared.recentSubjects(),
                          lastNote: SessionLog.shared.lastNote(), near: window) { [weak self] choice in
            guard let self else { return }
            switch choice {
            case .cancel:
                break
            case .start(let subject):
                self.showPetIfHidden()
                self.pomodoro.startFocus(minutes: minutes, subject: subject)
            }
        }
    }

    // MARK: - La scheda

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let classic = event?.type == .rightMouseUp || event?.modifierFlags.contains(.option) == true
        if classic {
            card.close()
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if let frame = sender.window?.frame {
            card.toggle(anchor: .below(frame))
        }
    }

    private func showCardNearPet() {
        card.toggle(anchor: .beside(window.frame))
    }

    /// Fotografia del momento per la scheda.
    private func cardState() -> MenuCardState {
        let now = Date()
        let calendar = StudyPeriod.calendar()
        let today = StudyStats.summary(sessions: SessionLog.shared.sessions,
                                       period: StudyPeriod.containing(now, kind: .day, calendar: calendar), calendar: calendar)
        return MenuCardState(
            pet: window.pet, allPets: Pet.all, userName: Profile.shared.name, isPetVisible: window.isVisible,
            phase: pomodoro.phase, subject: pomodoro.subject, remaining: pomodoro.remainingText,
            breakMinutes: pomodoro.breakMinutes, todaySeconds: today.totalSeconds, todayFocusCount: today.focusCount,
            streak: StudyStats.streak(sessions: SessionLog.shared.sessions, now: now, calendar: calendar),
            chattiness: Chattiness.current, petWalks: window.pet.walks, movementOn: Walker.isMovementEnabled,
            askOn: ReflectionCard.isEnabled
        )
    }

    private func cardActions() -> MenuCardActions {
        MenuCardActions(
            startFocus: { [weak self] in self?.beginFocus(minutes: $0) },
            startBreak: { [weak self] in self?.showPetIfHidden(); self?.pomodoro.startBreak(minutes: $0) },
            stopTimer: { [weak self] in self?.pomodoro.stop() },
            selectPet: { [weak self] in self?.selectPet($0) },
            showStats: { [weak self] in self?.showStats() },
            showGarden: { [weak self] in self?.showGarden() },
            cycleChattiness: { [weak self] in self?.cycleChattiness() },
            toggleMovement: { Walker.isMovementEnabled.toggle() },
            toggleAsk: { ReflectionCard.isEnabled.toggle() },
            toggleVisibility: { [weak self] in self?.toggleVisibility() },
            speak: { [weak self] in self?.makeSpeak() },
            otherTimers: { [weak self] in
                guard let self, let submenu = self.pomofocusItem.submenu else { return }
                self.menuNeedsUpdate(self.menu)
                submenu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            },
            moreSettings: { [weak self] in
                guard let self else { return }
                self.menuNeedsUpdate(self.menu)
                self.menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            },
            quit: { NSApp.terminate(nil) }
        )
    }

    private func cycleChattiness() {
        let all = Chattiness.allCases
        let index = all.firstIndex(of: Chattiness.current) ?? 0
        let level = all[(index + 1) % all.count]
        Chattiness.current = level
        pomodoro.refreshChatter()
        speaker.reschedule()
        if level == .never { speaker.dismissNow() }
    }

    @objc private func showStats() {
        dashboard.show(kind: .day)
    }

    @objc private func showGarden() {
        garden.show()
    }

    @objc private func startBreak(_ sender: NSMenuItem) {
        showPetIfHidden()
        pomodoro.startBreak(minutes: sender.tag)
    }

    /// Finestra per aggiungere un timer: tipo (focus o pausa) e minuti.
    @objc private func addCustomTimer() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Nuovo timer personalizzato"
        alert.informativeText = "Scegli se è un focus o una pausa e per quanti minuti."
        alert.addButton(withTitle: "Aggiungi")
        alert.addButton(withTitle: "Annulla")

        let kind = NSPopUpButton(frame: NSRect(x: 0, y: 30, width: 120, height: 26), pullsDown: false)
        kind.addItems(withTitles: [CustomTimers.Kind.focus.title, CustomTimers.Kind.rest.title])
        let minutes = NSTextField(frame: NSRect(x: 130, y: 31, width: 60, height: 24))
        minutes.placeholderString = "25"
        let unit = NSTextField(labelWithString: "minuti")
        unit.frame = NSRect(x: 198, y: 33, width: 60, height: 20)
        let hint = NSTextField(labelWithString: "Focus da 1 a 180 minuti, pausa da 1 a 60.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 0, y: 3, width: 290, height: 16)
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 290, height: 62))
        [kind, minutes, unit, hint].forEach(accessory.addSubview)
        alert.accessoryView = accessory
        alert.window.initialFirstResponder = minutes

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let chosen: CustomTimers.Kind = kind.indexOfSelectedItem == 0 ? .focus : .rest
        let range = CustomTimers.allowed[chosen]!
        let text = minutes.stringValue.trimmingCharacters(in: .whitespaces)
        guard let value = Int(text) else {
            showAlert("Numero non valido", "Scrivi un numero intero di minuti, da \(range.lowerBound) a \(range.upperBound).")
            return
        }
        switch customTimers.add(value, kind: chosen) {
        case .added:
            populatePomofocusMenu()
        case .outOfRange(let r):
            showAlert("Durata non valida", "Per \(chosen == .focus ? "un focus" : "una pausa") servono da \(r.lowerBound) a \(r.upperBound) minuti.")
        case .alreadyExists:
            showAlert("C'è già", "\(chosen.title) \(value) min c'è già nel menu.")
        case .tooMany(let max):
            showAlert("Troppi timer", "Puoi aggiungere al massimo \(max) timer personalizzati per tipo. Rimuovine uno e riprova.")
        }
    }

    @objc private func removeCustomTimer(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = CustomTimers.Kind(rawValue: raw) else { return }
        customTimers.remove(sender.tag, kind: kind)
        populatePomofocusMenu()
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

    @objc private func setChattiness(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let level = Chattiness(rawValue: raw) else { return }
        Chattiness.current = level
        pomodoro.refreshChatter()
        speaker.reschedule()
        if level == .never { speaker.dismissNow() }   // "adesso silenzio": anche il fumetto che c'è sparisce
    }

    @objc private func setMovement(_ sender: NSMenuItem) {
        Walker.isMovementEnabled = sender.tag == 1
    }

    @objc private func choosePet(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let pet = Pet.all.first(where: { $0.id == id }) else { return }
        selectPet(pet)
    }

    /// Cambia personaggio (dal menu, o dalla scheda di introduzione).
    func selectPet(_ pet: Pet) {
        guard pet != window.pet else { return }
        pet.remember()
        window.apply(pet)
        updateStatusIcon()
        showPetIfHidden()
        speaker.say(pet.greeting)
    }

    /// "Il tuo nome…": cambia il nome con cui si personalizzano i titoli.
    @objc private func editName() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Il tuo nome"
        alert.informativeText = "Compare nei titoli, per esempio «Il giardino di …». Lascia vuoto per toglierlo."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = Profile.shared.name ?? ""
        field.placeholderString = "Il tuo nome"
        alert.accessoryView = field
        alert.addButton(withTitle: "Salva")
        alert.addButton(withTitle: "Annulla")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            Profile.shared.setName(field.stringValue)
        }
    }

    @objc private func toggleAskHowItWent() {
        ReflectionCard.isEnabled.toggle()
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
                "Apri Impostazioni di Sistema → Generali → Elementi login e consenti a FocusFriends di avviarsi."
            )
        }
    }

    @objc private func openQuotesFile() {
        let fm = FileManager.default
        let pet = window.pet
        let file = Quotes.userFile(for: pet)
        if !fm.fileExists(atPath: file.path) {
            try? fm.createDirectory(at: Quotes.userDirectory, withIntermediateDirectories: true)
            // Parto dal file di una vecchia cartella (se l'utente l'aveva già modificato), altrimenti da quello dell'app.
            let legacy = Quotes.legacyDirectories
                .map { $0.appendingPathComponent(pet.quotesUserFile) }
                .first { fm.fileExists(atPath: $0.path) }
            let bundled = Bundle.main.url(forResource: pet.quotesResource, withExtension: "txt")
            if let legacy {
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

    // MARK: - Icone

    /// Un'icona di sistema (SF Symbols) per le voci del menu; se non esiste su questo Mac, nessuna icona.
    private static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    private func updateStatusIcon() {
        if let icon = Self.menuIcon(for: window.pet, height: 22) {
            statusItem.button?.title = ""
            statusItem.button?.image = icon
        } else {
            statusItem.button?.image = nil
            statusItem.button?.title = window.pet.name
        }
    }

    /// Il personaggio (o solo la sua testa) ritagliato dall'immagine, alto quanto richiesto.
    static func menuIcon(for pet: Pet, height: CGFloat) -> NSImage? {
        guard let url = Bundle.main.url(forResource: pet.iconResource, withExtension: "png"),
              let source = NSImage(contentsOf: url) else { return nil }

        let crop = pet.iconCrop ?? NSRect(x: 0, y: 0, width: 1, height: 1)
        let from = NSRect(
            x: crop.minX * source.size.width, y: crop.minY * source.size.height,
            width: crop.width * source.size.width, height: crop.height * source.size.height
        )
        let size = NSSize(width: ceil(height * from.width / from.height), height: height)
        return NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect, from: from, operation: .sourceOver, fraction: 1)
            return true
        }
    }
}
