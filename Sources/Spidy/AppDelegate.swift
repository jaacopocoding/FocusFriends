import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: SpidyWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Nessuna icona nel Dock, nessuna finestra "normale".
        NSApp.setActivationPolicy(.accessory)

        let window = SpidyWindow()
        window.placeOnGround()
        window.orderFrontRegardless()
        self.window = window
    }
}
