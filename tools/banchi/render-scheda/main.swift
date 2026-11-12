// Disegna fuori schermo la scheda del menu vera dell'app (MenuCardView) in un PNG, con dati inventati, per le immagini del README.
// Si lancia da tools/banchi/render-scheda.sh: render <file.png> [riposo|focus|giro] [compagno]
// «giro»: la scheda a riposo con il velo del giro guidato sul giardino, e accanto (giro-fumetto.png) il fumetto di quel passo; in giro.txt la parte illuminata.
import AppKit

@main
struct Render {
    static func main() {
        _ = NSApplication.shared
        let args = CommandLine.arguments
        let out = args[1]
        let focusing = args.count > 2 && args[2] == "focus"
        let petID = args.count > 3 ? args[3] : "gattino"
        let pets = Pet.all
        let pet = pets.first { $0.id == petID } ?? pets[0]
        let ids = pets.map(\.id)
        let focuses = 32
        let earned = CompanionRewards.earned(first: petID, all: ids, focuses: focuses)
        let avatars = AvatarRoster.entries(first: petID, all: ids, isUnlocked: { earned.contains($0) })
        let state = MenuCardState(
            pet: pet, allPets: pets, userName: "Jacopo", isPetVisible: true, phase: focusing ? .focus : nil, subject: focusing ? "Anatomia" : nil,
            remaining: focusing ? "24:10" : "", breakMinutes: 5, todaySeconds: 5100, todayFocusCount: 3, streak: 4, focusTimers: [30, 50], restTimers: [5],
            customFocus: [], customRest: [], chattiness: .sometimes, petWalks: true, movementOn: true, askOn: true, ambient: .none, ambientVolume: 0.5, music: .off,
            musicLabel: "", musicVolume: 0.5, focusProgress: focusing ? 0.5 : 0, phaseRange: focusing ? "16:20 – 17:10" : "", focusMinutes: 50, isPaused: false,
            isLongBreak: false, cycleDone: 1, avatars: avatars, focusesDone: focuses, notes: [], background: .none, backgroundVolume: 0.5, lastFocusMinutes: nil,
            lastFocusSubject: nil, lastSessionID: nil, lastRating: nil, albumFound: 34, albumTotal: GardenCatalog.items.count, albumNew: 2, giftMinutesLeft: 35, giftProgress: 0.42)
        let live = MenuCardLiveState(phase: focusing ? .focus : nil, isPaused: false, remaining: focusing ? "24:10" : "", focusProgress: focusing ? 0.5 : 0)
        let actions = MenuCardActions(
            startFocus: { _ in }, startBreak: { _ in }, stopTimer: {}, selectPet: { _ in }, showStats: {}, showGarden: {}, showAlbum: {},
            cycleChattiness: {}, toggleMovement: {}, toggleAsk: {}, cycleAmbient: {}, cycleMusic: {}, setMusicVolume: { _ in }, setAmbientVolume: { _ in },
            toggleVisibility: {}, speak: {}, addTimer: { _, _ in .added }, removeTimer: { _, _ in }, moreSettings: {}, quit: {}, addMinutes: {}, togglePause: {},
            addNote: { _ in }, discardFocus: {}, setBackground: { _ in }, setBackgroundVolume: { _ in }, rateLast: { _ in },
            todoAdd: { _, _, _ in }, todoUpdate: { _, _, _, _ in }, todoToggle: { _ in }, todoRemove: { _ in }, todoStartFocus: { _, _ in })
        let view = MenuCardView(state: { state }, live: { live }, actions: actions, perform: { _, action in action() })
        view.layoutSubtreeIfNeeded()
        let size = view.frame.size
        view.frame = NSRect(origin: .zero, size: size)
        let touring = args.count > 2 && args[2] == "giro"
        if touring, let index = GuidedTour.steps.firstIndex(where: { $0.section == .garden }) {
            view.layoutSubtreeIfNeeded()
            view.setSpotlight(.garden, active: true)
            let step = GuidedTour.steps[index]
            let tip = TourTipView(text: step.text, count: "\(index + 1) di \(GuidedTour.steps.count)", next: "Avanti")
            tip.tailOnRight = true
            tip.tailY = 30
            tip.layoutSubtreeIfNeeded()
            tip.frame = NSRect(origin: .zero, size: tip.fittingSize)
            tip.layoutSubtreeIfNeeded()
            let folder = (out as NSString).deletingLastPathComponent
            let tipRep = tip.bitmapImageRepForCachingDisplay(in: tip.bounds)!
            tip.cacheDisplay(in: tip.bounds, to: tipRep)
            try! tipRep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: folder + "/giro-fumetto.png"))
            let spot = view.sections[.garden] ?? .zero
            try! "\(spot.minX) \(spot.minY) \(spot.width) \(spot.height)\n".write(toFile: folder + "/giro.txt", atomically: true, encoding: .utf8)
            print("giro: fumetto", tip.frame.size, "giardino", spot)
        }
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
        print("scheda", size, rep.pixelsWide, "×", rep.pixelsHigh)
    }
}
