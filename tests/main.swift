import Foundation

// Prove del registro e delle statistiche (Sources/FocusFriends/SessionLog.swift).
// Si lanciano con: ./tests/run.sh

var failures = 0
var checks = 0
func check(_ condition: Bool, _ message: String, line: Int = #line) {
    checks += 1
    if !condition {
        failures += 1
        print("  ✗ riga \(line): \(message)")
    }
}
func section(_ name: String) { print("• \(name)") }

var cal = StudyPeriod.calendar()
cal.timeZone = TimeZone(identifier: "Europe/Rome")!
func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}
func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ff-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// ---------------------------------------------------------------- materie
section("Materie")
check(Subject.clean("  Anatomia  ") == "Anatomia", "toglie gli spazi ai bordi")
check(Subject.clean("Fisica   generale") == "Fisica generale", "riduce gli spazi interni")
check(Subject.clean("   ") == nil, "solo spazi = nessuna materia")
check(Subject.clean(nil) == nil, "nil resta nil")
check(Subject.clean(String(repeating: "a", count: 80))?.count == Subject.maxLength, "accorcia a \(Subject.maxLength)")

// ---------------------------------------------------------------- registro
section("Registro")
let dir = tempDirectory()
let rome = TimeZone(identifier: "Europe/Rome")!
let log = SessionLog(directory: dir, timeZone: rome)
check(log.add(start: date(2026, 10, 12, 9), seconds: 59, plannedMinutes: 30, completed: false, subject: "X") == nil,
      "sotto il minuto non conta")
check(log.sessions.isEmpty, "niente salvato")
let a = log.add(start: date(2026, 10, 12, 15), seconds: 3000, plannedMinutes: 50, completed: true, subject: "Anatomia")
let b = log.add(start: date(2026, 10, 12, 9), seconds: 1800, plannedMinutes: 30, completed: true, subject: "Fisiologia")
let c = log.add(start: date(2026, 10, 13, 10), seconds: 600, plannedMinutes: 25, completed: false, subject: nil)
let d = log.add(start: date(2026, 10, 14, 10), seconds: 1500, plannedMinutes: 25, completed: true, subject: " anatomia ")
check(log.sessions.count == 4, "quattro sessioni")
check(log.sessions.map { $0.start } == log.sessions.map { $0.start }.sorted(), "in ordine di tempo")
check(log.recentSubjects() == ["Anatomia", "Fisiologia"], "recenti: più recente per prima, senza doppioni e con la scrittura già usata (\(log.recentSubjects()))")
check(log.recentSubjects(limit: 1).count == 1, "il limite vale")

let reopened = SessionLog(directory: dir, timeZone: rome)
check(reopened.sessions == log.sessions, "riletto dal file uguale")
if let a { reopened.setSubject(id: a.id, subject: "  Biochimica ") }
check(reopened.sessions.first(where: { $0.id == a?.id })?.subject == "Biochimica", "materia cambiata")
if let c { reopened.remove(id: c.id) }
check(reopened.sessions.count == 3, "una sessione tolta")
_ = (b, d)

// file rovinato
let badDir = tempDirectory()
try? "questo non è json".write(to: badDir.appendingPathComponent("sessioni.json"), atomically: true, encoding: .utf8)
let bad = SessionLog(directory: badDir)
check(bad.sessions.isEmpty, "file rovinato: si riparte da vuoto")
let aside = (try? FileManager.default.contentsOfDirectory(atPath: badDir.path)) ?? []
check(aside.contains { $0.hasPrefix("sessioni.corrotto-") }, "il file rovinato è messo da parte")
check(!aside.contains("sessioni.json"), "e non resta al suo posto")

// ---------------------------------------------------------------- focus in corso
section("Focus in corso (app chiusa di colpo)")
let progressDir = tempDirectory()
let pl = SessionLog(directory: progressDir)
check(pl.recoverInterrupted() == nil, "niente da recuperare")
let start = Date().addingTimeInterval(-20 * 60)      // iniziato venti minuti fa
pl.beginInProgress(start: start, plannedMinutes: 50, subject: "Chimica")
let again = SessionLog(directory: progressDir)
let recovered = again.recoverInterrupted()
check(recovered != nil, "recuperata")
check(recovered?.completed == false, "segnata come interrotta")
check(recovered?.subject == "Chimica", "con la sua materia")
check((recovered?.seconds ?? 0) <= 50 * 60, "mai più del previsto")
check(abs((recovered?.seconds ?? 0) - 20 * 60) <= 2, "circa venti minuti (\(recovered?.seconds ?? -1) s)")
check(again.recoverInterrupted() == nil, "una volta sola")
pl.beginInProgress(start: Date().addingTimeInterval(-600), plannedMinutes: 25, subject: nil)
pl.finishInProgress()
check(SessionLog(directory: progressDir).recoverInterrupted() == nil, "chi finisce bene non lascia tracce")

// ---------------------------------------------------------------- periodi
section("Periodi")
let wed = date(2026, 10, 14, 11, 30)           // mercoledì
let week = StudyPeriod.containing(wed, kind: .week, calendar: cal)
check(week.start == date(2026, 10, 12), "la settimana parte da lunedì 12")
check(week.end == date(2026, 10, 19), "e finisce lunedì 19")
let month = StudyPeriod.containing(wed, kind: .month, calendar: cal)
check(month.start == date(2026, 10, 1) && month.end == date(2026, 11, 1), "mese di ottobre")
let day = StudyPeriod.containing(wed, kind: .day, calendar: cal)
check(day.start == date(2026, 10, 14) && day.end == date(2026, 10, 15), "il giorno")
check(week.shifted(by: -1, calendar: cal).start == date(2026, 10, 5), "settimana precedente")
check(month.shifted(by: 1, calendar: cal).start == date(2026, 11, 1), "mese dopo")
check(day.contains(wed) && !day.contains(date(2026, 10, 15)), "contains: fine esclusa")
// cambio dell'ora legale (25 ottobre 2026, 25 ore): il giorno resta intero
let dst = StudyPeriod.containing(date(2026, 10, 25, 12), kind: .day, calendar: cal)
check(dst.end == date(2026, 10, 26), "il giorno del cambio d'ora finisce a mezzanotte")

// ---------------------------------------------------------------- riepiloghi
section("Riepiloghi")
let sessions = [
    StudySession(start: date(2026, 10, 12, 9), seconds: 1800, plannedMinutes: 30, completed: true, subject: "Fisiologia"),
    StudySession(start: date(2026, 10, 12, 15), seconds: 3000, plannedMinutes: 50, completed: true, subject: "Anatomia"),
    StudySession(start: date(2026, 10, 12, 23, 40), seconds: 3000, plannedMinutes: 50, completed: true, subject: "Anatomia"),  // passa la mezzanotte
    StudySession(start: date(2026, 10, 13, 10), seconds: 600, plannedMinutes: 25, completed: false, subject: nil),
    StudySession(start: date(2026, 10, 14, 10), seconds: 1500, plannedMinutes: 25, completed: true, subject: "Anatomia"),
    StudySession(start: date(2026, 9, 30, 10), seconds: 900, plannedMinutes: 15, completed: true, subject: "Fisica"),
]
func summaryFor(_ kind: PeriodKind, _ ref: Date) -> StudySummary {
    StudyStats.summary(sessions: sessions, period: StudyPeriod.containing(ref, kind: kind, calendar: cal), calendar: cal)
}

let mon = summaryFor(.day, date(2026, 10, 12))
check(mon.focusCount == 3, "lunedì: 3 focus (\(mon.focusCount))")
check(mon.totalSeconds == 7800, "lunedì: 7800 s, la sessione di mezzanotte conta al giorno d'inizio (\(mon.totalSeconds))")
check(mon.completedCount == 3 && mon.interruptedCount == 0, "tutte complete")
check(mon.buckets.count == 24, "il giorno ha 24 barre (\(mon.buckets.count))")
check(mon.buckets[9].seconds == 1800 && mon.buckets[15].seconds == 3000 && mon.buckets[23].seconds == 3000, "ore giuste")
check(mon.bySubject.first?.subject == "Anatomia" && mon.bySubject.first?.seconds == 6000, "Anatomia in testa")

let wk = summaryFor(.week, date(2026, 10, 14))
check(wk.focusCount == 5, "settimana: 5 focus (\(wk.focusCount))")
check(wk.totalSeconds == 1800 + 3000 + 3000 + 600 + 1500, "settimana: totale")
check(wk.buckets.count == 7, "sette giorni")
check(wk.buckets.map { $0.seconds } == [7800, 600, 1500, 0, 0, 0, 0], "per giorno: \(wk.buckets.map { $0.seconds })")
check(wk.completedCount == 4 && wk.interruptedCount == 1, "4 complete, 1 interrotta")
check(wk.bySubject.map { $0.subject } == ["Anatomia", "Fisiologia", "Senza materia"], "materie: \(wk.bySubject.map { $0.subject })")
check(wk.sessions.first?.start == date(2026, 10, 14, 10), "la più recente per prima")

let mo = summaryFor(.month, date(2026, 10, 14))
check(mo.focusCount == 5 && mo.buckets.count == 31, "ottobre: 5 focus e 31 giorni")
let sep = summaryFor(.month, date(2026, 9, 15))
check(sep.focusCount == 1 && sep.bySubject.first?.subject == "Fisica", "settembre")
let empty = summaryFor(.week, date(2026, 8, 3))
check(empty.focusCount == 0 && empty.totalSeconds == 0 && empty.bySubject.isEmpty, "periodo vuoto")

// ---------------------------------------------------------------- serie di giorni
section("Giorni di fila")
func s(_ day: Int) -> StudySession {
    StudySession(start: date(2026, 10, day, 10), seconds: 600, plannedMinutes: 10, completed: true, subject: nil)
}
check(StudyStats.streak(sessions: [s(12), s(13), s(14)], now: date(2026, 10, 14, 20), calendar: cal) == 3, "tre di fila")
check(StudyStats.streak(sessions: [s(11), s(13), s(14)], now: date(2026, 10, 14, 20), calendar: cal) == 2, "un buco spezza la serie")
check(StudyStats.streak(sessions: [s(12), s(13)], now: date(2026, 10, 14, 8), calendar: cal) == 2, "oggi ancora vuoto: conta da ieri")
check(StudyStats.streak(sessions: [s(10)], now: date(2026, 10, 14, 8), calendar: cal) == 0, "serie finita")
check(StudyStats.streak(sessions: [], now: date(2026, 10, 14), calendar: cal) == 0, "senza sessioni")
check(StudyStats.streak(sessions: [s(14), s(14)], now: date(2026, 10, 14, 12), calendar: cal) == 1, "due nello stesso giorno = 1")

// ---------------------------------------------------------------- testi
section("Testi")
check(StudyStats.duration(seconds: 0) == "0 min", "0 min")
check(StudyStats.duration(seconds: 2700) == "45 min", "45 min")
check(StudyStats.duration(seconds: 3600) == "1 h", "1 h")
check(StudyStats.duration(seconds: 12_000) == "3 h 20", "3 h 20")
check(StudyStats.duration(seconds: 3900) == "1 h 05", "1 h 05")
check(StudyStats.dayLine(mon, isToday: true, dayName: "Lunedì") == "Oggi hai fatto 3 focus: 2 h 10 di studio.", "riga di oggi: \(StudyStats.dayLine(mon, isToday: true, dayName: "Lunedì"))")
check(StudyStats.dayLine(empty, isToday: true, dayName: "") == "Oggi non hai ancora fatto nessun focus.", "oggi vuoto")
check(StudyStats.dayLine(empty, isToday: false, dayName: "Lunedì") == "Lunedì non hai fatto nessun focus.", "giorno passato vuoto")
check(StudyStats.dayLine(summaryFor(.day, date(2026, 10, 13)), isToday: false, dayName: "Martedì") == "Martedì hai fatto 1 focus: 10 min di studio.", "singolare")
check(!StudyStats.encouragement(totalSeconds: 0).isEmpty && !StudyStats.encouragement(totalSeconds: 20_000).isEmpty, "incoraggiamenti")

// ---------------------------------------------------------------- giardino e personaggio
section("Giardino e personaggio")
func daySession(_ hour: Int, _ minutes: Int, _ subject: String? = nil, pet: String? = nil, completed: Bool = true) -> StudySession {
    StudySession(start: date(2026, 10, 14, hour), seconds: minutes * 60, plannedMinutes: minutes, completed: completed,
                 subject: subject, pet: pet)
}
func plantsFor(_ sessions: [StudySession]) -> [GardenRules.DayPlant] { GardenRules.plants(of: sessions, calendar: cal) }

check(plantsFor([]).isEmpty, "nessuno studio: nessuna piantina")
check(plantsFor([daySession(9, 0)]).isEmpty, "zero minuti: niente")
let gFifty = plantsFor([daySession(9, 50)])
check(gFifty.count == 1 && gFifty[0].isAdult && gFifty[0].stage == 5, "50 minuti: una pianta adulta")
check(plantsFor([daySession(9, 49)]).first?.stage == 4, "49 minuti: ancora in crescita, stadio 4 (la 5 solo a 50 pieni)")
check(plantsFor([daySession(9, 5)]).first?.stage == 1, "5 minuti: il seme")
check(plantsFor([daySession(9, 10)]).first?.stage == 2, "10 minuti: stadio 2")
check(plantsFor([daySession(9, 20)]).first?.stage == 3, "20 minuti: stadio 3")
check(plantsFor([daySession(9, 30)]).first?.stage == 4, "30 minuti: stadio 4")
let gAlmost = StudySession(start: date(2026, 10, 14, 9), seconds: 59, plannedMinutes: 25, completed: false, subject: nil)
check(plantsFor([gAlmost]).isEmpty, "meno di un minuto: non nasce niente")
let gTwoHours = plantsFor([daySession(9, 50), daySession(11, 50), daySession(15, 20)])
check(gTwoHours.count == 3 && gTwoHours.filter { $0.isAdult }.count == 2 && gTwoHours.last?.stage == 3, "120 minuti: due adulte e una al 3")
let gSplit = plantsFor([daySession(9, 30), daySession(11, 30)])
check(gSplit.count == 2 && gSplit[0].isAdult && gSplit[1].stage == 2, "i minuti di focus diversi si sommano: 30+30 = una adulta e 10 minuti (stadio 2)")
let gLong = plantsFor([daySession(9, 75)])
check(gLong.count == 2 && gLong[0].isAdult && gLong[1].stage == 3, "un focus lungo passa da una pianta all'altra: 75 = adulta + 25")
let gCut = plantsFor([daySession(9, 40, completed: false), daySession(11, 10, completed: false)])
check(gCut.count == 1 && gCut[0].isAdult, "anche i focus interrotti contano i loro minuti")
// materia e personaggio prevalenti
let gMixed = plantsFor([daySession(9, 30, "Anatomia", pet: "ciccio"), daySession(11, 40, "Fisiologia", pet: "porcellino")])
check(gMixed.count == 2 && gMixed[0].subject == "Anatomia" && gMixed[0].pet == "ciccio", "la prima pianta è dell'Anatomia (30 su 50)")
check(gMixed[0].subjects.count == 2 && gMixed[0].subjects[1].subject == "Fisiologia" && gMixed[0].subjects[1].seconds == 1200, "con 20 minuti di Fisiologia")
check(gMixed[1].subject == "Fisiologia" && gMixed[1].stage == 3 && gMixed[1].pet == "porcellino", "il resto è Fisiologia (20 minuti)")
let gSorted = plantsFor([daySession(15, 50, "B"), daySession(9, 50, "A")])
check(gSorted[0].subject == "A", "in ordine di inizio, non di inserimento")
// frasi di fine focus
check(GardenRules.finishLine(before: 2400, after: 3300).contains("pianta adulta"), "supera i 50 minuti: nasce una adulta")
check(GardenRules.finishLine(before: 0, after: 1500).contains("ancora 25 minuti"), "a 25 minuti ne mancano 25")
check(GardenRules.finishLine(before: 3000, after: 3300).contains("ancora 45 minuti"), "dopo un'adulta si ricomincia: 5 su 50")
check(!GardenRules.finishLine(before: 1000, after: 2000).contains("pianta adulta"), "senza traguardo non dice che è nata")
check(StudyStats.seconds(onDayOf: daySession(9, 30), in: [daySession(9, 30), daySession(15, 20)], calendar: cal) == 3000, "secondi del giorno")

let petDir = tempDirectory()
let petLog = SessionLog(directory: petDir)
let withPet = petLog.add(start: date(2026, 10, 14, 9), seconds: 1800, plannedMinutes: 30, completed: true, subject: "Anatomia", pet: "ciccio")
check(withPet?.pet == "ciccio", "il personaggio si salva")
check(SessionLog(directory: petDir).sessions.first?.pet == "ciccio", "e si rilegge")

// un file scritto prima che esistesse il campo si legge ancora
let oldDir = tempDirectory()
let oldJSON = """
[{"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000001", "plannedMinutes": 25,
  "seconds": 1500, "start": "2026-10-12T08:00:00Z", "subject": "Anatomia"}]
"""
try? oldJSON.write(to: oldDir.appendingPathComponent("sessioni.json"), atomically: true, encoding: .utf8)
let oldLog = SessionLog(directory: oldDir)
check(oldLog.sessions.count == 1 && oldLog.sessions[0].pet == nil, "file vecchio: letto, senza personaggio")
check(oldLog.sessions.first?.subject == "Anatomia", "e con la sua materia")

// il personaggio sopravvive al recupero dopo una chiusura improvvisa
let petProg = tempDirectory()
let pp = SessionLog(directory: petProg)
pp.beginInProgress(start: Date().addingTimeInterval(-300), plannedMinutes: 25, subject: nil, pet: "porcellino")
check(SessionLog(directory: petProg).recoverInterrupted()?.pet == "porcellino", "recupero con il personaggio")

// ---------------------------------------------------------------- formato e migrazione
section("Formato versionato e migrazione")
let fmtDir = tempDirectory()
let fmtLog = SessionLog(directory: fmtDir, timeZone: rome)
fmtLog.add(start: date(2026, 10, 14, 9, 30), seconds: 1800, plannedMinutes: 30, completed: true, subject: "Anatomia", pet: "pianty")
let raw = (try? Data(contentsOf: fmtDir.appendingPathComponent("sessioni.json"))) ?? Data()
let object = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
check(object?["version"] as? Int == SessionLog.formatVersion, "il file ha la versione")
check((object?["sessions"] as? [[String: Any]])?.count == 1, "e la lista delle sessioni")
check((object?["sessions"] as? [[String: Any]])?.first?["localStart"] as? String == "2026-10-14T09:30", "con l'ora locale")

// vecchio formato: la sola lista, con materie scritte in modi diversi e senza ora locale
let v0Dir = tempDirectory()
let v0 = """
[{"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000001", "plannedMinutes": 25, "seconds": 1500,
  "start": "2026-10-12T08:00:00Z", "subject": "anatomia"},
 {"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000002", "plannedMinutes": 25, "seconds": 1500,
  "start": "2026-10-13T08:00:00Z", "subject": "Anatomia"},
 {"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000003", "plannedMinutes": 25, "seconds": 1500,
  "start": "2026-10-14T08:00:00Z", "subject": "FISIOLOGIA"}]
"""
try? v0.write(to: v0Dir.appendingPathComponent("sessioni.json"), atomically: true, encoding: .utf8)
let migrated = SessionLog(directory: v0Dir, timeZone: rome)
check(migrated.sessions.count == 3, "migrazione: nessuna sessione persa")
check(migrated.sessions.allSatisfy { $0.localStart != nil }, "migrazione: ora locale aggiunta")
check(migrated.sessions[0].subject == "Anatomia" && migrated.sessions[1].subject == "Anatomia", "migrazione: materie unite con la scrittura più recente (\(migrated.sessions.map { $0.subject ?? "-" }))")
let v0After = (try? JSONSerialization.jsonObject(with: Data(contentsOf: v0Dir.appendingPathComponent("sessioni.json")))) as? [String: Any]
check(v0After?["version"] as? Int == SessionLog.formatVersion, "migrazione: il file è stato riscritto nel formato nuovo")
check(FileManager.default.fileExists(atPath: v0Dir.appendingPathComponent("backup/sessioni-formato0.json").path), "migrazione: copia intatta del vecchio file")

// file di una versione più nuova: si legge, non si riscrive
let newerDir = tempDirectory()
let newer = """
{"version": 99, "sessions": [{"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000009", "plannedMinutes": 25,
 "seconds": 1500, "start": "2026-10-12T08:00:00Z", "subject": "Futuro", "campoNuovo": 1}]}
"""
try? newer.write(to: newerDir.appendingPathComponent("sessioni.json"), atomically: true, encoding: .utf8)
let newerLog = SessionLog(directory: newerDir, timeZone: rome)
check(newerLog.sessions.count == 1 && newerLog.isReadOnly, "versione più nuova: letta, in sola lettura")
check(newerLog.add(start: date(2026, 10, 14, 9), seconds: 600, plannedMinutes: 10, completed: true, subject: nil) == nil, "e non si scrive")
check((try? String(contentsOf: newerDir.appendingPathComponent("sessioni.json"))) == newer, "il file è rimasto identico (nessuna perdita)")

// ---------------------------------------------------------------- materie unite
section("Materie unite")
let subjDir = tempDirectory()
let sl = SessionLog(directory: subjDir, timeZone: rome)
let s1 = sl.add(start: date(2026, 10, 12, 9), seconds: 1800, plannedMinutes: 30, completed: true, subject: "Anatomia")
let s2 = sl.add(start: date(2026, 10, 13, 9), seconds: 1800, plannedMinutes: 30, completed: true, subject: "anatomia")
let s3 = sl.add(start: date(2026, 10, 14, 9), seconds: 1800, plannedMinutes: 30, completed: true, subject: "ANATOMIA ")
check(s1?.subject == "Anatomia" && s2?.subject == "Anatomia" && s3?.subject == "Anatomia", "una nuova scrittura prende quella già usata")
let s4 = sl.add(start: date(2026, 10, 14, 11), seconds: 1800, plannedMinutes: 30, completed: true, subject: "Fisica")
let s5 = sl.add(start: date(2026, 10, 14, 13), seconds: 1800, plannedMinutes: 30, completed: true, subject: "fisíca")
check(s5?.subject == "Fisica", "senza distinguere gli accenti (\(s5?.subject ?? "-"))")
check(Subject.key("Èsame") == Subject.key("esame"), "la chiave ignora accenti e maiuscole")
check(sl.renameSubject(from: "fisica", to: "Fisica generale") == 2, "rinomina in tutte le sessioni")
check(sl.sessions.filter { $0.subject == "Fisica generale" }.count == 2, "e le sessioni sono cambiate")
let s6 = sl.add(start: date(2026, 10, 15, 9), seconds: 1800, plannedMinutes: 30, completed: true, subject: "Chimica")
check(sl.renameSubject(from: "Chimica", to: "anatomia") == 1 && s6 != nil, "unire due materie")
check(sl.sessions.last?.subject == "Anatomia", "l'unione usa la scrittura della materia che c'è già (\(sl.sessions.last?.subject ?? "-"))")
check(sl.renameSubject(from: "Anatomia", to: nil) == 4 && sl.sessions.allSatisfy { $0.subject != "Anatomia" }, "rinominare in vuoto toglie la materia")

// le statistiche non separano le scritture diverse
let mixed = [
    StudySession(start: date(2026, 10, 12, 9), seconds: 600, plannedMinutes: 10, completed: true, subject: "anatomia"),
    StudySession(start: date(2026, 10, 12, 10), seconds: 600, plannedMinutes: 10, completed: true, subject: "Anatomia"),
    StudySession(start: date(2026, 10, 12, 11), seconds: 600, plannedMinutes: 10, completed: true, subject: "ANATOMIA"),
]
let mixedSummary = StudyStats.summary(sessions: mixed, period: StudyPeriod.containing(date(2026, 10, 12), kind: .day, calendar: cal), calendar: cal)
check(mixedSummary.bySubject.count == 1 && mixedSummary.bySubject[0].seconds == 1800, "statistiche: una sola materia (\(mixedSummary.bySubject.map { $0.subject }))")
check(mixedSummary.bySubject[0].subject == "ANATOMIA", "e si mostra la scrittura più recente")

// ---------------------------------------------------------------- copie di sicurezza e cancellazione
section("Copie di sicurezza e cancellazione")
let bkDir = tempDirectory()
var fakeNow = date(2026, 10, 1, 12)
let bk = SessionLog(directory: bkDir, now: { fakeNow }, timeZone: rome)
for day in 1...10 {
    fakeNow = date(2026, 10, day, 12)
    bk.add(start: fakeNow, seconds: 600, plannedMinutes: 10, completed: true, subject: "G\(day)")
}
let backups = ((try? FileManager.default.contentsOfDirectory(atPath: bkDir.appendingPathComponent("backup").path)) ?? []).sorted()
check(backups.count == SessionLog.backupsToKeep, "tiene solo le ultime \(SessionLog.backupsToKeep) copie (\(backups.count))")
check(backups.first == "sessioni-2026-10-04.json" && backups.last == "sessioni-2026-10-10.json", "le più recenti (\(backups.first ?? "-") … \(backups.last ?? "-"))")
let lastBackup = (try? Data(contentsOf: bkDir.appendingPathComponent("backup/sessioni-2026-10-10.json"))) ?? Data()
let lastBackupObject = (try? JSONSerialization.jsonObject(with: lastBackup)) as? [String: Any]
check((lastBackupObject?["sessions"] as? [Any])?.count == 9, "la copia del giorno è lo stato di prima delle modifiche del giorno (\((lastBackupObject?["sessions"] as? [Any])?.count ?? -1) sessioni)")
fakeNow = date(2026, 10, 10, 18)
bk.add(start: fakeNow, seconds: 600, plannedMinutes: 10, completed: true, subject: "G10b")
let againBackups = ((try? FileManager.default.contentsOfDirectory(atPath: bkDir.appendingPathComponent("backup").path)) ?? []).count
check(againBackups == SessionLog.backupsToKeep, "una sola copia al giorno")

var notified = 0
bk.addObserver { notified += 1 }
bk.beginInProgress(start: Date(), plannedMinutes: 10, subject: nil)
bk.deleteAll()
check(bk.sessions.isEmpty && notified == 1, "cancella tutto: vuoto e gli osservatori avvisati")
let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: bkDir.path)) ?? []
check(leftovers.isEmpty, "cancella tutto: nessun file rimasto (\(leftovers))")
check(SessionLog(directory: bkDir, timeZone: rome).sessions.isEmpty, "e alla riapertura è ancora vuoto")

// ---------------------------------------------------------------- fuso orario
section("Fuso orario")
var tokyo = StudyPeriod.calendar()
tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
let lateRome = StudySession(
    start: date(2026, 10, 14, 23, 30), localStart: "2026-10-14T23:30", seconds: 1800, plannedMinutes: 30, completed: true, subject: nil
)
let inTokyo = StudyStats.summary(sessions: [lateRome], period: StudyPeriod.containing(date(2026, 10, 14, 12), kind: .day, calendar: tokyo), calendar: tokyo)
check(inTokyo.focusCount == 1, "una sessione serale a Roma resta nel suo giorno anche letta con un altro fuso")
let nextDayTokyo = StudyStats.summary(sessions: [lateRome], period: StudyPeriod.containing(date(2026, 10, 15, 12), kind: .day, calendar: tokyo), calendar: tokyo)
check(nextDayTokyo.focusCount == 0, "e non compare nel giorno dopo")
check(inTokyo.buckets.count == 24 && inTokyo.buckets[23].seconds == 1800, "all'ora 23, quella dell'orologio")
let noLocal = StudySession(start: date(2026, 10, 14, 9), seconds: 600, plannedMinutes: 10, completed: true, subject: nil)
check(noLocal.startTime(in: cal) == date(2026, 10, 14, 9), "senza ora locale vale l'istante assoluto")
let badLocal = StudySession(start: date(2026, 10, 14, 9), localStart: "boh", seconds: 600, plannedMinutes: 10, completed: true, subject: nil)
check(badLocal.startTime(in: cal) == date(2026, 10, 14, 9), "ora locale illeggibile: si ricade sull'istante")
check(StudyStats.streak(sessions: [lateRome], now: date(2026, 10, 15, 8), calendar: tokyo) == 1, "i giorni di fila usano l'ora locale")

// ---------------------------------------------------------------- profilo
section("Profilo e titoli")
check(Profile.clean("  Marco  ") == "Marco", "il nome: spazi ai bordi tolti")
check(Profile.clean("Anna   Maria") == "Anna Maria", "spazi interni ridotti")
check(Profile.clean("marco") == "marco", "le maiuscole restano come scritte")
check(Profile.clean("   ") == nil && Profile.clean(nil) == nil && Profile.clean("") == nil, "vuoto = nessun nome")
check(Profile.clean("Ma\u{0}rco\u{7}") == "Marco", "caratteri di controllo tolti")
check(Profile.clean(String(repeating: "x", count: 60))?.count == Profile.maxNameLength, "al massimo \(Profile.maxNameLength) caratteri")
check(Profile.clean("Zoë 🌱") == "Zoë 🌱", "accenti ed emoji restano")

let profDir = tempDirectory()
let prof = Profile(directory: profDir)
check(prof.name == nil && !prof.introSeen, "profilo nuovo: senza nome e senza introduzione")
check(prof.gardenTitle == "Il mio giardino" && prof.statsTitle == "Statistiche e riepilogo", "senza nome: titoli di sempre")
var profChanges = 0
prof.addObserver { profChanges += 1 }
prof.setName(" Marco ")
check(prof.gardenTitle == "Il giardino di Marco" && prof.statsTitle == "Le statistiche di Marco", "con il nome: titoli personali (\(prof.gardenTitle))")
prof.markIntroSeen()
check(profChanges == 2, "gli osservatori vengono avvisati")
let profAgain = Profile(directory: profDir)
check(profAgain.name == "Marco" && profAgain.introSeen, "si salva e si rilegge")
let profObj = (try? JSONSerialization.jsonObject(with: Data(contentsOf: profDir.appendingPathComponent("profilo.json")))) as? [String: Any]
check(profObj?["version"] as? Int == Profile.formatVersion, "il file ha la versione")
profAgain.setName("")
check(profAgain.name == nil && profAgain.gardenTitle == "Il mio giardino", "nome svuotato: si torna ai titoli di sempre")
profAgain.reset()
check(!FileManager.default.fileExists(atPath: profDir.appendingPathComponent("profilo.json").path), "reset: il file sparisce")
check(!Profile(directory: profDir).introSeen, "reset: alla riapertura si ricomincia")
let badProfDir = tempDirectory()
try? "non e' json".write(to: badProfDir.appendingPathComponent("profilo.json"), atomically: true, encoding: .utf8)
let badProf = Profile(directory: badProfDir)
check(badProf.name == nil && !badProf.introSeen, "file rovinato: si riparte senza errori")
// il nome non finisce nelle sessioni
let nameLog = SessionLog(directory: profDir, timeZone: rome)
let namedSession = nameLog.add(start: date(2026, 10, 14, 9), seconds: 600, plannedMinutes: 10, completed: true, subject: "X")
let sessionsText = (try? String(contentsOf: profDir.appendingPathComponent("sessioni.json"))) ?? ""
check(namedSession != nil && !sessionsText.contains("Marco"), "il nome non è scritto nelle sessioni")

// ---------------------------------------------------------------- com'è andata
section("Com'è andata e cosa hai fatto")
check(SessionNote.clean("  cap. 4,   nervi\tcranici ") == "cap. 4, nervi cranici", "la nota si pulisce")
check(SessionNote.clean("   ") == nil && SessionNote.clean(nil) == nil, "nota vuota = nessuna nota")
check(SessionNote.clean(String(repeating: "x", count: 200))?.count == SessionNote.maxLength, "nota accorciata")
let refDir = tempDirectory()
let refLog = SessionLog(directory: refDir, timeZone: rome)
let refSession = refLog.add(start: date(2026, 10, 14, 9), seconds: 1500, plannedMinutes: 25, completed: true, subject: "Anatomia")
check(refSession?.rating == nil && refSession?.note == nil, "una sessione nuova non ha voto né nota")
check(refLog.lastNote() == nil, "nessuna nota: niente suggerimento")
if let refSession { refLog.setReflection(id: refSession.id, rating: .poor, note: "  nervi   cranici ") }
let refSaved = SessionLog(directory: refDir, timeZone: rome).sessions.first
check(refSaved?.rating == .poor && refSaved?.note == "nervi cranici", "voto e nota si salvano e si rileggono")
check(refLog.lastNote()?.note == "nervi cranici" && refLog.lastNote()?.subject == "Anatomia", "l'ultima nota con la sua materia")
if let refSession { refLog.setReflection(id: refSession.id, rating: nil, note: "") }
check(refLog.sessions.first?.rating == nil && refLog.sessions.first?.note == nil, "si può togliere")
let refRaw = (try? JSONSerialization.jsonObject(with: Data(contentsOf: refDir.appendingPathComponent("sessioni.json")))) as? [String: Any]
check((refRaw?["sessions"] as? [[String: Any]])?.first?["rating"] == nil, "senza voto il campo non c'è nel file")

// file di formato 1 (senza voto né nota): si legge, si passa al 2, copia intatta
let v1Dir = tempDirectory()
let v1 = """
{"version": 1, "sessions": [{"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000010", "plannedMinutes": 25,
 "seconds": 1500, "start": "2026-10-12T08:00:00Z", "subject": "Anatomia", "localStart": "2026-10-12T10:00"}]}
"""
try? v1.write(to: v1Dir.appendingPathComponent("sessioni.json"), atomically: true, encoding: .utf8)
let v1Log = SessionLog(directory: v1Dir, timeZone: rome)
check(v1Log.sessions.count == 1 && v1Log.sessions[0].rating == nil && !v1Log.isReadOnly, "formato 1 letto")
let v1After = (try? JSONSerialization.jsonObject(with: Data(contentsOf: v1Dir.appendingPathComponent("sessioni.json")))) as? [String: Any]
check(v1After?["version"] as? Int == 2, "riscritto nel formato 2")
check((try? String(contentsOf: v1Dir.appendingPathComponent("backup/sessioni-formato1.json"))) == v1, "copia intatta del formato 1")

// un voto sconosciuto (da una versione futura) non rende illeggibile il file
let oddDir = tempDirectory()
let odd = """
{"version": 2, "sessions": [{"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000011", "plannedMinutes": 25,
 "seconds": 1500, "start": "2026-10-12T08:00:00Z", "rating": "ottimo", "note": "ok"}]}
"""
try? odd.write(to: oddDir.appendingPathComponent("sessioni.json"), atomically: true, encoding: .utf8)
let oddLog = SessionLog(directory: oddDir, timeZone: rome)
check(oddLog.sessions.count == 1 && oddLog.sessions[0].rating == nil && oddLog.sessions[0].note == "ok", "voto sconosciuto: sessione letta, voto ignorato")

// statistiche del periodo
let ratedSessions: [StudySession] = [
    StudySession(start: date(2026, 10, 12, 9), localStart: "2026-10-12T09:00", seconds: 1500, plannedMinutes: 25, completed: true, subject: "A", rating: .good),
    StudySession(start: date(2026, 10, 12, 11), localStart: "2026-10-12T11:00", seconds: 1500, plannedMinutes: 25, completed: true, subject: "A", rating: .poor),
    StudySession(start: date(2026, 10, 12, 15), localStart: "2026-10-12T15:00", seconds: 1500, plannedMinutes: 25, completed: true, subject: "B"),
]
let ratedSummary = StudyStats.summary(sessions: ratedSessions, period: StudyPeriod.containing(date(2026, 10, 12), kind: .day, calendar: cal), calendar: cal)
check(ratedSummary.ratedCount == 2 && ratedSummary.ratingCounts[.good] == 1 && ratedSummary.ratingCounts[.poor] == 1, "conteggio dei voti nel periodo")

// "quando rendi meglio": poche sessioni = niente conclusioni
check(StudyStats.insights(sessions: ratedSessions, calendar: cal).isEmpty, "pochi voti: nessuna frase")
var many: [StudySession] = []
func rated(_ day: Int, _ hour: Int, _ subject: String, _ rating: FocusRating) -> StudySession {
    StudySession(start: date(2026, 10, day, hour), localStart: StudySession.localString(for: date(2026, 10, day, hour), calendar: cal),
                 seconds: 1500, plannedMinutes: 25, completed: true, subject: subject, rating: rating)
}
// mattina: 4 su 4 bene; sera: 0 su 4 bene → la fascia fa la differenza (materie e giorni mescolati)
for i in 0..<4 { many.append(rated(5 + i, 9, i % 2 == 0 ? "Anatomia" : "Chimica", .good)) }
for i in 0..<4 { many.append(rated(5 + i, 21, i % 2 == 0 ? "Anatomia" : "Chimica", .poor)) }
let found = StudyStats.insights(sessions: many, calendar: cal)
check(!found.isEmpty && found.count <= 2, "con abbastanza voti compare una frase (\(found))")
check(found.contains(where: { $0.contains("di mattina") && $0.contains("4 focus su 4") }), "la mattina è la fascia migliore, con i conteggi (\(found))")
// tutto uguale: niente da dire
var flat: [StudySession] = []
for i in 0..<10 { flat.append(rated(5 + i % 5, (i / 2) % 2 == 0 ? 9 : 16, "Anatomia", i % 2 == 0 ? .good : .poor)) }
check(StudyStats.insights(sessions: flat, calendar: cal).isEmpty, "nessuna differenza: nessuna frase")

// esportazione CSV
let csvSessions = [StudySession(start: date(2026, 10, 14, 9), localStart: "2026-10-14T09:00", seconds: 1500, plannedMinutes: 25,
                                completed: true, subject: "=SOMMA(A1)", pet: "pianty", rating: .good, note: "cap. 4, \"nervi\"")]
let csvText = SessionCSV.csv(for: csvSessions)
check(csvText.hasPrefix(SessionCSV.header + "\n"), "intestazione del CSV")
check(csvText.contains(",\"'=SOMMA(A1)\",pianty,good,\"cap. 4, \"\"nervi\"\"\""), "campi di testo protetti e virgolette raddoppiate (\(csvText))")

// ---------------------------------------------------------------- quadrante dei timer
section("Quadrante dei timer")
check(TimerDialMath.minutes(fraction: 0.5, previous: 50, maxMinutes: 120, step: 5) == 60, "mezzo giro = 60 minuti")
check(TimerDialMath.minutes(fraction: 0.33, previous: 30, maxMinutes: 120, step: 5) == 40, "si arrotonda ai 5 minuti (39,6 -> 40)")
check(TimerDialMath.minutes(fraction: 0.999, previous: 110, maxMinutes: 120, step: 5) == 120, "in fondo al giro: il massimo")
check(TimerDialMath.minutes(fraction: 0.001, previous: 5, maxMinutes: 120, step: 5) == 5, "all'inizio: mai sotto il minimo")
check(TimerDialMath.minutes(fraction: 0.02, previous: 115, maxMinutes: 120, step: 5) == 120, "passando per mezzogiorno non torna a zero")
check(TimerDialMath.minutes(fraction: 0.98, previous: 5, maxMinutes: 120, step: 5) == 5, "e non salta al massimo")
check(TimerDialMath.minutes(fraction: 0.5, previous: 150, maxMinutes: 120, step: 5) == 60, "un timer tuo oltre il giro si riporta dentro")
check(TimerDialMath.minutes(fraction: 0.5, previous: 5, maxMinutes: 30, step: 1) == 15, "pausa: mezzo giro = 15 minuti")
check(TimerDialMath.filledFraction(minutes: 60, maxMinutes: 120) == 0.5, "parte colorata")
check(TimerDialMath.filledFraction(minutes: 150, maxMinutes: 120) == 1, "al massimo un giro")

// ---------------------------------------------------------------- stagioni
section("Stagioni")
check(Season.of(date(2026, 3, 1), calendar: cal) == .spring && Season.of(date(2026, 5, 31), calendar: cal) == .spring, "marzo-maggio: primavera")
check(Season.of(date(2026, 6, 1), calendar: cal) == .summer && Season.of(date(2026, 8, 31), calendar: cal) == .summer, "giugno-agosto: estate")
check(Season.of(date(2026, 9, 1), calendar: cal) == .autumn && Season.of(date(2026, 11, 30), calendar: cal) == .autumn, "settembre-novembre: autunno")
check(Season.of(date(2026, 12, 1), calendar: cal) == .winter && Season.of(date(2027, 2, 28), calendar: cal) == .winter, "dicembre-febbraio: inverno")
check(Season.allCases.count == 4 && Season.winter.title == "Inverno", "quattro stagioni, con il nome")

// ---------------------------------------------------------------- suoni ambiente
section("Suoni ambiente")
check(AmbientSound.none.next == .rain && AmbientSound.rain.next == .brown && AmbientSound.brown.next == .wind && AmbientSound.wind.next == .none,
      "il ciclo dei suoni torna a Nessuno")
check(AmbientSound.allCases.allSatisfy { !$0.title.isEmpty && !$0.symbolName.isEmpty }, "ogni suono ha nome e icona")
check(AmbientSettings.clamp(-1) == 0 && AmbientSettings.clamp(2) == 1 && AmbientSettings.clamp(0.4) == 0.4, "il volume resta tra 0 e 1")
check(AmbientSettings.clamp(.nan) == AmbientSettings.defaultVolume, "volume non valido: torna al valore di partenza")
check(AmbientSettings.defaultVolume <= 0.3, "parte a volume basso")
let ambientDefaults = UserDefaults(suiteName: "ff-ambient-test-\(UUID().uuidString)")!
check(AmbientSettings.load(ambientDefaults).sound == .none && AmbientSettings.load(ambientDefaults).volume == AmbientSettings.defaultVolume,
      "di partenza: nessun suono, volume basso")
AmbientSettings.save(sound: .rain, volume: 0.4, ambientDefaults)
check(AmbientSettings.load(ambientDefaults).sound == .rain && AmbientSettings.load(ambientDefaults).volume == 0.4, "si ricorda")
AmbientSettings.save(sound: .wind, volume: 9, ambientDefaults)
check(AmbientSettings.load(ambientDefaults).volume == 1, "un volume troppo alto viene riportato a 1")
check(AmbientSettings.nearestStep(to: 0.27) == 0.25 && AmbientSettings.nearestStep(to: 0.55) == 0.60, "il livello più vicino per la spunta")

// ---------------------------------------------------------------- musica
section("Musica")
check(MusicLibrary.isAudio(URL(fileURLWithPath: "/m/brano.MP3")) && MusicLibrary.isAudio(URL(fileURLWithPath: "/m/a.flac")), "mp3 e flac sono audio")
check(!MusicLibrary.isAudio(URL(fileURLWithPath: "/m/nota.txt")) && !MusicLibrary.isAudio(URL(fileURLWithPath: "/m/.nascosto.mp3")), "i testi e i file nascosti no")
let musicDir = tempDirectory()
for name in ["10 b.mp3", "2 a.m4a", "copertina.jpg", ".DS_Store", "Sub/3 c.wav"] {
    let url = musicDir.appendingPathComponent(name)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data([0]).write(to: url)
}
let musicFound = MusicLibrary.tracks(in: musicDir)
check(musicFound.map { $0.lastPathComponent } == ["2 a.m4a", "10 b.mp3", "3 c.wav"], "i brani trovati: prima quelli della cartella (ordine naturale, 2 prima di 10), poi le sottocartelle (\(musicFound.map { $0.lastPathComponent }))")
check(MusicLibrary.tracks(in: tempDirectory()).isEmpty, "cartella vuota: nessun brano")
struct FixedRandom: RandomNumberGenerator { var s: UInt64 = 7; mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s } }
var fixed = FixedRandom()
let three = [URL(fileURLWithPath: "/a.mp3"), URL(fileURLWithPath: "/b.mp3"), URL(fileURLWithPath: "/c.mp3")]
for last in three {
    let order = MusicLibrary.shuffled(three, avoidingFirst: last, using: &fixed)
    check(order.count == 3 && Set(order) == Set(three) && order[0] != last, "il primo brano non è quello appena suonato")
}
check(MusicLibrary.shuffled([three[0]], avoidingFirst: three[0], using: &fixed) == [three[0]], "con un solo brano suona quello")
check(MusicLibrary.title(of: URL(fileURLWithPath: "/m/music_01_dreamy_night-owl.m4a")) == "dreamy night owl", "titolo leggibile dal nome del file")
check(MusicLibrary.title(of: URL(fileURLWithPath: "/m/2. Rain Walk.mp3")) == "Rain Walk", "toglie il numero d'ordine")
let musicDefaults = UserDefaults(suiteName: "ff-music-test-\(UUID().uuidString)")!
check(MusicSettings.load(musicDefaults) == MusicSettings.Saved(source: .off, folder: nil, volume: MusicSettings.defaultVolume), "di partenza: spenta")
let savedMusic = MusicSettings.Saved(source: .folder, folder: URL(fileURLWithPath: "/Users/x/Lofi", isDirectory: true), volume: 0.4)
MusicSettings.save(savedMusic, musicDefaults)
check(MusicSettings.load(musicDefaults) == savedMusic, "si ricorda la cartella e il volume")
check(MusicSettings.label(source: .folder, folder: savedMusic.folder) == "Cartella: Lofi" && MusicSettings.label(source: .off, folder: nil) == "Spenta", "le etichette")

print("\n\(checks) controlli, \(failures) falliti")
exit(failures == 0 ? 0 : 1)
