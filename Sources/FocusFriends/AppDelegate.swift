import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: PetWindow?
    private var speaker: Speaker?
    private var pomodoro: Pomodoro?
    private var walker: Walker?
    private var menu: MenuController?
    private let introCard = IntroCard()
    private let reflectionCard = ReflectionCard()
    /// Quando il computer è andato in sleep (per salutare al risveglio) e gli ascoltatori di sleep e risveglio.
    private var sleptAt: Date?
    private var powerObservers: [NSObjectProtocol] = []
    /// Quale riepilogo della settimana è già stato detto (così non si ripete a ogni avvio).
    private static let recapKey = "lastWeeklyRecap"

    /// Quello che serve a far parlare il compagno adesso: l'ora, il nome, lo studio e le cose da fare.
    private func remarksContext() -> Remarks.Context {
        let now = Date()
        let today = ToDoDay.string(for: now, calendar: ToDoDay.calendar())
        return Remarks.Context(now: now, name: Profile.shared.name, sessions: SessionLog.shared.sessions,
                               openTodoCount: ToDoList.shared.openCount, due: ToDoReminder.message(for: ToDoList.shared.items, today: today))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Migration.run()

        // Nessuna icona nel Dock, nessuna finestra "normale".
        NSApp.setActivationPolicy(.accessory)

        let window = PetWindow(pet: Pet.saved)
        window.placeOnGround()
        window.orderFrontRegardless()
        self.window = window

        let speaker = Speaker(petWindow: window)
        speaker.start()
        self.speaker = speaker
        // I problemi con i dati (un file che non si legge, una scrittura che fallisce) li dice il personaggio.
        SessionLog.shared.onProblem = { [weak speaker] in speaker?.say($0) }
        Profile.shared.onProblem = { [weak speaker] in speaker?.say($0) }
        Garden.shared.onProblem = { [weak speaker] in speaker?.say($0) }
        ToDoList.shared.onProblem = { [weak speaker] in speaker?.say($0) }
        AmbientPlayer.shared.onStartFailure = { [weak speaker] in
            speaker?.say("Non riesco ad avviare l'audio: il suono ambiente non si sente.")
        }

        let walker = Walker(petWindow: window, speaker: speaker)
        walker.start()
        self.walker = walker

        // Se l'app si era chiusa di colpo durante un focus, lo salvo come interrotto.
        SessionLog.shared.recoverInterrupted()

        let pomodoro = Pomodoro(petWindow: window, speaker: speaker)
        self.pomodoro = pomodoro
        pomodoro.onFocusCompleted = { [weak walker] in walker?.eatNow() }
        // Le scadenze di oggi e domani: ogni tanto il compagno le ricorda, al posto di una frase a caso (mai durante un focus).
        speaker.reminder = { [weak pomodoro] in
            guard pomodoro?.phase != .focus else { return nil }
            return ToDoReminder.message(for: ToDoList.shared.items, today: ToDoDay.string(for: Date(), calendar: ToDoDay.calendar()))
        }
        // Il saluto dell'avvio, e il riepilogo della settimana (il lunedì, fino al mercoledì): si dicono alla prima frase spontanea, quindi mai con «Frasi: Mai».
        if Profile.shared.introSeen {
            let context = remarksContext()
            let greeting = Remarks.launchGreeting(context, variant: Int.random(in: 0..<12))
            speaker.enqueue(Speaker.Occasion(text: greeting.text, coversReminder: greeting.coversReminder))
            if let recap = Remarks.weeklyRecap(context), UserDefaults.standard.string(forKey: Self.recapKey) != recap.key {
                speaker.enqueue(Speaker.Occasion(text: recap.text, onSaid: { UserDefaults.standard.set(recap.key, forKey: Self.recapKey) }))
            }
        }
        // Ogni tanto, al posto di una frase a caso, una delle frasi «quando rendi meglio» (mai due volte di fila la stessa, mai durante un focus).
        var lastInsight: String?
        speaker.insight = { [weak self, weak pomodoro] in
            guard let self, pomodoro?.phase != .focus,
                  let text = Remarks.insight(self.remarksContext(), variant: Int.random(in: 0..<10)), text != lastInsight else { return nil }
            lastInsight = text
            return text
        }
        // Al risveglio dallo sleep (dopo almeno un'ora): «Rieccoti!», con quello che c'è da sapere.
        let center = NSWorkspace.shared.notificationCenter
        powerObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleptAt = Date()
        })
        powerObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self, weak pomodoro, weak speaker] _ in
            guard let self, let slept = self.sleptAt else { return }
            self.sleptAt = nil
            guard Profile.shared.introSeen, Chattiness.current != .never, pomodoro?.phase != .focus,
                  let remark = Remarks.wakeGreeting(self.remarksContext(), away: Date().timeIntervalSince(slept), variant: Int.random(in: 0..<9)) else { return }
            if remark.coversReminder { speaker?.markReminderSaid() }
            speaker?.sayWhenQuiet(remark.text, after: 5, while: { pomodoro?.phase != .focus })
        })
        // A fine focus: "com'è andata?" (se non l'hai spenta dal menu) e, se il focus era partito da una voce di «Da fare» ancora da fare,
        // «Hai finito «…»?» (anche con «com'è andata» spento). Sparisce da sola quando il timer riparte o si ferma.
        pomodoro.onFocusRecorded = { [weak self, weak window, weak speaker, weak pomodoro] session, todoID in
            self?.menu?.evaluateCompanionRewards(announce: true)
            // Un traguardo (giorni di fila, focus, ore, «un mese insieme»): detto dopo la frase di fine focus.
            let all = SessionLog.shared.sessions
            if let text = Remarks.milestone(before: all.filter { $0.id != session.id }, after: all, now: Date()) {
                speaker?.sayWhenQuiet(text, after: 9, while: { pomodoro?.phase == .rest })
            }
            guard let self, let window else { return }
            let todo = todoID.flatMap { id in ToDoList.shared.items.first { $0.id == id && !$0.isDone } }
            self.reflectionCard.ask(session: session, near: window, todo: todo, askHowItWent: ReflectionCard.isEnabled, onTodoAnswer: { finished in
                guard finished, let todo, ToDoList.shared.markDone(id: todo.id) else { return }
                speaker?.say(ToDoReminder.doneMessage(for: todo, variant: Int.random(in: 0..<3)))
            }, completion: { rating in
                if let rating { speaker?.say(ReflectionCard.reply(for: rating)) }
            })
        }
        pomodoro.onTimerReset = { [weak self] in self?.reflectionCard.dismiss() }
        // Il suono ambiente (se acceso) accompagna il focus.
        pomodoro.onFocusActiveChanged = { active in
            AmbientPlayer.shared.setFocusActive(active)
            MusicPlayer.shared.setFocusActive(active)
        }
        let menu = MenuController(window: window, speaker: speaker, pomodoro: pomodoro)
        self.menu = menu
        // Chi usava già l'app li tiene tutti; per gli altri si guadagnano (silenziosamente: al massimo sono già meritati).
        Profile.shared.keepAllCompanions(Pet.all.map(\.id))
        menu.evaluateCompanionRewards(announce: false)

        // La prima volta (anche per chi la usava già): come ti chiami e chi ti fa compagnia.
        if !Profile.shared.introSeen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self, weak window, weak speaker, weak menu] in
                guard let self, let window, let speaker, let menu else { return }
                speaker.stop()      // mentre c'è la scheda, niente frase a sorpresa
                self.introCard.ask(currentPet: window.pet, near: window) { name, pet in
                    Profile.shared.setName(name)
                    Profile.shared.markIntroSeen()
                    Profile.shared.chooseFirstCompanion(pet.id)
                    if pet != window.pet {
                        menu.selectPet(pet)
                    } else {
                        speaker.say(pet.greeting)
                    }
                    speaker.reschedule()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Un focus ancora in corso non va perso.
        pomodoro?.recordInterruptedFocusOnQuit()
    }
}
