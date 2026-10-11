import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: PetWindow?
    private var speaker: Speaker?
    private var pomodoro: Pomodoro?
    private var walker: Walker?
    private var menu: MenuController?

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

        let pomodoro = Pomodoro(petWindow: window, speaker: speaker)
        self.pomodoro = pomodoro
        menu = MenuController(window: window, speaker: speaker, pomodoro: pomodoro)
    }
}
