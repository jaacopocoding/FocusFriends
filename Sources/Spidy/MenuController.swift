import AppKit
import ServiceManagement

/// Menu di Spidy: icona nella barra dei menu e tasto destro sul personaggio.
final class MenuController: NSObject, NSMenuDelegate {
    private let window: SpidyWindow
    private let speaker: Speaker
    private let pomodoro: Pomodoro
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let toggleItem = NSMenuItem()
    private let loginItem = NSMenuItem()
    private let stopTimerItem = NSMenuItem()
    private var breakItems: [NSMenuItem] = []

    init(window: SpidyWindow, speaker: Speaker, pomodoro: Pomodoro) {
        self.window = window
        self.speaker = speaker
        self.pomodoro = pomodoro
        super.init()

        toggleItem.title = "Nascondi Spidy"
        toggleItem.action = #selector(toggleVisibility)
        toggleItem.target = self
        menu.addItem(toggleItem)

        let speak = NSMenuItem(title: "Fai parlare Spidy", action: #selector(makeSpeak), keyEquivalent: "")
        speak.target = self
        menu.addItem(speak)

        menu.addItem(makePomofocusItem())

        menu.addItem(.separator())

        loginItem.title = "Avvia al login"
        loginItem.action = #selector(toggleLaunchAtLogin)
        loginItem.target = self
        menu.addItem(loginItem)

        let quotes = NSMenuItem(title: "Modifica le frasi…", action: #selector(openQuotesFile), keyEquivalent: "")
        quotes.target = self
        menu.addItem(quotes)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Esci da Spidy", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.delegate = self
        statusItem.menu = menu
        if let icon = Self.menuBarIcon() {
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = "🕷"
        }
        statusItem.button?.toolTip = "Spidy"

        // Tasto destro sul personaggio: stesso menu.
        window.contentView?.menu = menu
    }

    private func makePomofocusItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Pomofocus", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Pomofocus")

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
        toggleItem.title = window.isVisible ? "Nascondi Spidy" : "Mostra Spidy"
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
        showSpidyIfHidden()
        pomodoro.startFocus(minutes: sender.tag)
    }

    @objc private func startBreak(_ sender: NSMenuItem) {
        showSpidyIfHidden()
        pomodoro.startBreak(minutes: sender.tag)
    }

    @objc private func stopTimer() {
        pomodoro.stop()
    }

    private func showSpidyIfHidden() {
        if !window.isVisible {
            window.orderFrontRegardless()
            speaker.start()
        }
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
                "Apri Impostazioni di Sistema → Generali → Elementi login e consenti a Spidy di avviarsi."
            )
        }
    }

    @objc private func openQuotesFile() {
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Spidy")
        let file = dir.appendingPathComponent("frasi.txt")
        if !fm.fileExists(atPath: file.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if let bundled = Bundle.main.url(forResource: "frasi", withExtension: "txt") {
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

    /// La testa di Spidy, ritagliata dall'immagine del personaggio.
    private static func menuBarIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "spidy", withExtension: "png"),
              let source = NSImage(contentsOf: url) else { return nil }
        let size = NSSize(width: 20, height: 22)
        let head = NSRect(x: 70, y: source.size.height - 255, width: 215, height: 250)
        let icon = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect, from: head, operation: .sourceOver, fraction: 1)
            return true
        }
        return icon
    }
}
