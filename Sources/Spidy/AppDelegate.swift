import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: SpidyWindow?
    private var speaker: Speaker?
    private var menu: MenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Nessuna icona nel Dock, nessuna finestra "normale".
        NSApp.setActivationPolicy(.accessory)

        let window = SpidyWindow()
        window.placeOnGround()
        window.orderFrontRegardless()
        self.window = window

        let speaker = Speaker(spidy: window)
        speaker.start()
        self.speaker = speaker
        menu = MenuController(window: window, speaker: speaker)
    }
}
