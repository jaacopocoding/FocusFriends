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

        let walker = Walker(petWindow: window, speaker: speaker)
        walker.start()
        self.walker = walker

        // Se l'app si era chiusa di colpo durante un focus, lo salvo come interrotto.
        SessionLog.shared.recoverInterrupted()

        let pomodoro = Pomodoro(petWindow: window, speaker: speaker)
        self.pomodoro = pomodoro
        pomodoro.onFocusCompleted = { [weak walker] in walker?.eatNow() }
        // A fine focus: "com'è andata?" (se non l'hai spenta dal menu). Sparisce da sola quando il timer riparte o si ferma.
        pomodoro.onFocusRecorded = { [weak self, weak window, weak speaker] session in
            guard ReflectionCard.isEnabled, let self, let window else { return }
            self.reflectionCard.ask(session: session, near: window) { rating in
                if let rating { speaker?.say(ReflectionCard.reply(for: rating)) }
            }
        }
        pomodoro.onTimerReset = { [weak self] in self?.reflectionCard.dismiss() }
        // Il suono ambiente (se acceso) accompagna il focus.
        pomodoro.onFocusActiveChanged = { active in AmbientPlayer.shared.setFocusActive(active) }
        let menu = MenuController(window: window, speaker: speaker, pomodoro: pomodoro)
        self.menu = menu

        // La prima volta (anche per chi la usava già): come ti chiami e chi ti fa compagnia.
        if !Profile.shared.introSeen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self, weak window, weak speaker, weak menu] in
                guard let self, let window, let speaker, let menu else { return }
                speaker.stop()      // mentre c'è la scheda, niente frase a sorpresa
                self.introCard.ask(currentPet: window.pet, near: window) { name, pet in
                    Profile.shared.setName(name)
                    Profile.shared.markIntroSeen()
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
