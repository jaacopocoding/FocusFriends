import AppKit

// Rifà windows/data/pets.json: tutti i dati dei compagni (Sources/FocusFriends/Pet.swift) in forma di JSON, per la
// versione per Windows. L'app per Mac è la fonte: se cambia un personaggio si rilancia tools/genera-pets.sh e si
// guarda cosa cambia nel file.
//
// Non tocca nessun dato dell'utente: legge solo le costanti dei personaggi.

let args = CommandLine.arguments
guard args.count == 3 else { print("uso: genera-pets <cartella assets> <file di uscita>"); exit(2) }
let assets = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
var missing: [String] = []

/// Il nome di una risorsa dell'app per Mac («ciccio_frame3») → il file in assets/ («ciccio/frame3.png»), come fa build.sh.
func path(_ resource: String) -> String {
    let relative: String
    if resource.hasPrefix("garden_") || resource.hasPrefix("growth_") {
        relative = "garden/\(resource).png"
    } else {
        let parts = resource.split(separator: "_", maxSplits: 1).map(String.init)
        relative = "\(parts[0])/\(parts[1]).png"
    }
    if !FileManager.default.fileExists(atPath: assets.appendingPathComponent(relative).path) { missing.append(relative) }
    return relative
}

func r(_ x: CGFloat) -> Double { (Double(x) * 100000).rounded() / 100000 }
func size(_ s: NSSize) -> [String: Any] { ["width": r(s.width), "height": r(s.height)] }

var pets: [[String: Any]] = []
for pet in Pet.all {
    var entry: [String: Any] = [
        "id": pet.id, "name": pet.name,
        "images": pet.imageResources.map(path),
        "size": size(pet.size),
        "quotesFile": pet.quotesUserFile, "fallbackQuote": pet.fallbackQuote, "greeting": pet.greeting,
        "shadowWidthFraction": r(pet.shadowWidthFraction), "groundFraction": r(pet.groundFraction),
        "iconFocus": r(pet.iconFocus),
        "walks": pet.walks, "walkFrames": pet.walkFrames, "stepInterval": pet.stepInterval,
        "facesRight": pet.facesRight, "eatFrames": pet.eatFrames,
        "sleepFrames": pet.sleepFrames, "popcornFrames": pet.popcornFrames, "popcornInterval": pet.popcornInterval,
        "focusGrowthImages": pet.focusGrowthResources.map(path), "focusGrowthFeetFraction": r(pet.focusGrowthFeetFraction),
        "eatsWhenFocusCompletes": pet.eatsWhenFocusCompletes,
        // Valori che l'app per Mac ricava dagli altri: servono come prova che la versione per Windows li ricava uguali.
        "stageCount": pet.stageCount, "finalStage": pet.finalStage, "restStage": pet.restStage,
        "restImageIndex": pet.restImageIndex, "growsWithTimer": pet.growsWithTimer, "iconImage": path(pet.iconResource),
    ]
    entry["iconCrop"] = pet.iconCrop.map { ["x": r($0.origin.x), "y": r($0.origin.y), "width": r($0.size.width), "height": r($0.size.height)] } ?? NSNull()
    entry["talkFrame"] = pet.talkFrame ?? NSNull()
    entry["sleepIntroFrame"] = pet.sleepIntroFrame ?? NSNull()
    entry["framesPerStage"] = pet.framesPerStage ?? NSNull()
    entry["picked"] = pet.pickedResource.map { image in
        ["image": path(image), "size": size(pet.pickedSize), "grab": ["x": r(pet.pickedGrab.x), "y": r(pet.pickedGrab.y)]] as [String: Any]
    } ?? NSNull()
    // Le tappe di crescita durante il focus, per ogni avanzamento da 0 a 1 a passi di un decimo.
    entry["focusGrowthStages"] = (0...10).map { pet.focusGrowthStage(forProgress: Double($0) / 10) }
    entry["stages"] = (0...10).map { pet.stage(forProgress: Double($0) / 10) }
    pets.append(entry)
}

guard missing.isEmpty else { print("Mancano questi file in assets/: \(missing.sorted())"); exit(1) }
let document: [String: Any] = ["comment": "Generato da tools/genera-pets.sh a partire da Sources/FocusFriends/Pet.swift: non si modifica a mano.", "pets": pets]
let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try (data + Data("\n".utf8)).write(to: output)
print("Scritti \(pets.count) personaggi in \(output.path)")
