import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: PetWindow?
    private var speaker: Speaker?
    private var pomodoro: Pomodoro?
    private var walker: Walker?
    private var menu: MenuController?
    private let introCard = IntroCard()
    private let reflectionCard = ReflectionCard()

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
        // A fine focus: "com'è andata?" (se non l'hai spenta dal menu) e, se il focus era partito da una voce di «Da fare» ancora da fare,
        // «Hai finito «…»?» (anche con «com'è andata» spento). Sparisce da sola quando il timer riparte o si ferma.
        pomodoro.onFocusRecorded = { [weak self, weak window, weak speaker] session, todoID in
            self?.menu?.evaluateCompanionRewards(announce: true)
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
