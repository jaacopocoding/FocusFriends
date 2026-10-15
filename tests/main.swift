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
check(StudyStats.streak(sessions: [s(11), s(13), s(14)], now: date(2026, 10, 14, 20), calendar: cal) == 3, "un giorno saltato non spezza la serie: la ghiaccia")
check(StudyStats.streak(sessions: [s(10), s(13), s(14)], now: date(2026, 10, 14, 20), calendar: cal) == 2, "due giorni di fila senza studio la spezzano")
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

// ---------------------------------------------------------------- personaggio e secondi del giorno
section("Personaggio e secondi del giorno")
func daySession(_ hour: Int, _ minutes: Int, _ subject: String? = nil, pet: String? = nil, completed: Bool = true) -> StudySession {
    StudySession(start: date(2026, 10, 14, hour), seconds: minutes * 60, plannedMinutes: minutes, completed: completed,
                 subject: subject, pet: pet)
}
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
check(v1After?["version"] as? Int == SessionLog.formatVersion, "riscritto nel formato nuovo")
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
check(MusicLibrary.hasTracks(in: musicDir) && !MusicLibrary.hasTracks(in: tempDirectory()), "hasTracks: c'è almeno un brano, senza elencarli tutti")
let onlyCovers = tempDirectory()
try? Data([0]).write(to: onlyCovers.appendingPathComponent("copertina.jpg"))
check(!MusicLibrary.hasTracks(in: onlyCovers), "una cartella senza audio non conta")
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

// ---------------------------------------------------------------- note del focus
section("Note del focus")
check(FocusNotes.clean("  chiedere   al prof \t la trasformata ") == "chiedere al prof la trasformata", "la nota si pulisce")
check(FocusNotes.clean("   ") == nil && FocusNotes.clean(nil) == nil, "nota vuota = niente")
check(FocusNotes.clean(String(repeating: "x", count: 500))?.count == FocusNotes.maxLength, "nota accorciata")
check(FocusNotes.clean(list: ["  a ", "", "  ", "b"]) == ["a", "b"], "la lista toglie le note vuote")
check(FocusNotes.clean(list: []) == nil && FocusNotes.clean(list: ["   "]) == nil, "lista vuota = nil")
check((FocusNotes.clean(list: (0..<100).map { "n\($0)" }) ?? []).count == FocusNotes.maxCount, "al massimo \(FocusNotes.maxCount) note")
let notesDir = tempDirectory()
let notesLog = SessionLog(directory: notesDir, timeZone: rome)
let withNotes = notesLog.add(start: date(2026, 10, 14, 9), seconds: 1800, plannedMinutes: 30, completed: true, subject: "Segnali",
                             notes: ["rivedere la trasformata", "  ", "esercizio 4"])
check(withNotes?.notes == ["rivedere la trasformata", "esercizio 4"], "le note si salvano pulite")
check(SessionLog(directory: notesDir, timeZone: rome).sessions.first?.notes == ["rivedere la trasformata", "esercizio 4"], "e si rileggono")
if let withNotes { notesLog.setNotes(id: withNotes.id, notes: []) }
check(notesLog.sessions.first?.notes == nil, "si possono togliere")
// le note del focus in corso sopravvivono a una chiusura improvvisa
let crashDir = tempDirectory()
let crashLog = SessionLog(directory: crashDir, now: { date(2026, 10, 14, 9, 20) }, timeZone: rome)
crashLog.beginInProgress(start: date(2026, 10, 14, 9), plannedMinutes: 50, subject: "Segnali", pet: "ciccio")
crashLog.updateInProgressNotes(["chiedere al prof"])
let recoveredNotes = SessionLog(directory: crashDir, now: { date(2026, 10, 14, 9, 30) }, timeZone: rome).recoverInterrupted()
check(recoveredNotes?.notes == ["chiedere al prof"], "le note del focus interrotto si recuperano")
// il tempo fermo non conta nel recupero dopo una chiusura improvvisa
section("Recupero con il timer fermo")
// ferma da 09:10, l'app si chiude alle 09:25: 25 minuti trascorsi meno 15 fermo = 10 minuti
let stopDir = tempDirectory()
let stopLog = SessionLog(directory: stopDir, now: { date(2026, 10, 14, 9, 10) }, timeZone: rome)
stopLog.beginInProgress(start: date(2026, 10, 14, 9), plannedMinutes: 50, subject: "Segnali")
stopLog.updateInProgressPause(seconds: 0, since: date(2026, 10, 14, 9, 10))
stopLog.heartbeat(now: date(2026, 10, 14, 9, 25))
check(SessionLog(directory: stopDir, timeZone: rome).recoverInterrupted()?.seconds == 600, "fermo quando si chiude: 10 minuti di studio")
// ripartito dopo 10 minuti di pausa, chiusura alle 09:30: 30 meno 10 = 20 minuti
let resumedDir = tempDirectory()
let resumedLog = SessionLog(directory: resumedDir, now: { date(2026, 10, 14, 9, 20) }, timeZone: rome)
resumedLog.beginInProgress(start: date(2026, 10, 14, 9), plannedMinutes: 50, subject: "Segnali")
resumedLog.updateInProgressPause(seconds: 0, since: date(2026, 10, 14, 9, 10))
resumedLog.updateInProgressPause(seconds: 600, since: nil)
resumedLog.heartbeat(now: date(2026, 10, 14, 9, 30))
check(SessionLog(directory: resumedDir, timeZone: rome).recoverInterrupted()?.seconds == 1200, "ripartito: 20 minuti di studio")
// «+5 minuti» riscrive il file del focus: il tempo fermo resta
let plusDir = tempDirectory()
let plusLog = SessionLog(directory: plusDir, now: { date(2026, 10, 14, 9, 20) }, timeZone: rome)
plusLog.beginInProgress(start: date(2026, 10, 14, 9), plannedMinutes: 50, subject: "Segnali")
plusLog.updateInProgressPause(seconds: 600, since: nil)
plusLog.beginInProgress(start: date(2026, 10, 14, 9).addingTimeInterval(0.43), plannedMinutes: 55, subject: "Segnali")
plusLog.heartbeat(now: date(2026, 10, 14, 9, 30))
check(SessionLog(directory: plusDir, timeZone: rome).recoverInterrupted()?.seconds == 1200, "dopo +5 minuti il tempo fermo non si perde")
// un focus nuovo (altra partenza) non eredita il tempo fermo del precedente
plusLog.beginInProgress(start: date(2026, 10, 14, 10), plannedMinutes: 25, subject: "Altro")
plusLog.heartbeat(now: date(2026, 10, 14, 10, 20))
check(SessionLog(directory: plusDir, timeZone: rome).recoverInterrupted()?.seconds == 1200, "un focus nuovo parte da zero")
// un file «in corso» di prima (senza questi campi) si recupera come sempre
let oldProgDir = tempDirectory()
let oldProg = """
{"start": "2026-10-14T07:00:00Z", "plannedMinutes": 50, "subject": "Segnali", "lastSeen": "2026-10-14T07:20:00Z"}
"""
try? oldProg.write(to: oldProgDir.appendingPathComponent("in-corso.json"), atomically: true, encoding: .utf8)
check(SessionLog(directory: oldProgDir, timeZone: rome).recoverInterrupted()?.seconds == 1200, "un file in corso di prima si recupera")

// un file del formato 2 (senza note) si legge e si migra
let v2Dir = tempDirectory()
let v2 = """
{"version": 2, "sessions": [{"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000020", "plannedMinutes": 25,
 "seconds": 1500, "start": "2026-10-12T08:00:00Z", "subject": "Anatomia", "rating": "good", "note": "nervi"}]}
"""
try? v2.write(to: v2Dir.appendingPathComponent("sessioni.json"), atomically: true, encoding: .utf8)
let v2Log = SessionLog(directory: v2Dir, timeZone: rome)
check(v2Log.sessions.count == 1 && v2Log.sessions[0].notes == nil && v2Log.sessions[0].rating == .good, "il formato 2 si legge")
check((try? String(contentsOf: v2Dir.appendingPathComponent("backup/sessioni-formato2.json"))) == v2, "copia intatta del formato 2")
let csvNotes = SessionCSV.csv(for: [StudySession(start: date(2026, 10, 14, 9), seconds: 600, plannedMinutes: 10, completed: true,
                                                subject: "X", notes: ["uno", "due"])])
check(csvNotes.contains("\"uno | due\""), "le note nel CSV, separate da |")

// ---------------------------------------------------------------- compagni da sbloccare
section("Compagni da sbloccare")
let pets = ["pianty", "porcellino", "ciccio"]
check(CompanionRewards.focuses(totalSeconds: 0) == 0 && CompanionRewards.focuses(totalSeconds: 49 * 60) == 0, "meno di 50 minuti: nessun focus pieno")
check(CompanionRewards.focuses(totalSeconds: 50 * 60) == 1 && CompanionRewards.focuses(totalSeconds: 20 * 50 * 60 + 59) == 20, "50 minuti = un focus pieno")
check(CompanionRewards.focuses(totalSeconds: -5) == 0, "mai negativi")
check(CompanionRewards.order(first: "ciccio", all: pets) == ["ciccio", "pianty", "porcellino"], "prima il primo scelto, poi gli altri nell'ordine")
check(CompanionRewards.order(first: nil, all: pets) == pets && CompanionRewards.order(first: "sconosciuto", all: pets) == pets, "senza una scelta valida, l'ordine di sempre")
check(CompanionRewards.earned(first: "pianty", all: pets, focuses: 0) == ["pianty"], "all'inizio solo il primo")
check(CompanionRewards.earned(first: "pianty", all: pets, focuses: 19) == ["pianty"], "a 19 ancora no")
check(CompanionRewards.earned(first: "pianty", all: pets, focuses: 20) == ["pianty", "porcellino"], "a 20 il secondo")
check(CompanionRewards.earned(first: "pianty", all: pets, focuses: 49) == ["pianty", "porcellino"], "a 49 il terzo non c'è")
check(CompanionRewards.earned(first: "pianty", all: pets, focuses: 50) == Set(pets), "a 50 tutti")
check(CompanionRewards.earned(first: "ciccio", all: pets, focuses: 20) == ["ciccio", "pianty"], "con Ciccio per primo, il secondo è Pianty")
check(CompanionRewards.need(for: "ciccio", first: "pianty", all: pets) == 50 && CompanionRewards.need(for: "porcellino", first: "pianty", all: pets) == 20
      && CompanionRewards.need(for: "pianty", first: "pianty", all: pets) == 0, "quanto serve a ciascuno")
check(CompanionRewards.threshold(at: 3) == 100 && CompanionRewards.threshold(at: 4) == 150, "oltre il terzo: altri 50 a testa")
// il profilo ricorda cosa è sbloccato
let rwDir = tempDirectory()
let freshProfile = Profile(directory: rwDir)
check(freshProfile.isCompanionUnlocked("ciccio"), "senza scelta, niente è bloccato")
freshProfile.keepAllCompanions(pets)
check(freshProfile.unlocked == nil, "chi non ha visto la presentazione non li ha ancora tutti")
freshProfile.chooseFirstCompanion("porcellino")
check(freshProfile.isCompanionUnlocked("porcellino") && !freshProfile.isCompanionUnlocked("pianty") && freshProfile.firstCompanion == "porcellino", "il primo è libero, gli altri no")
freshProfile.unlock(["pianty"])
let reopenedProfile = Profile(directory: rwDir)
check(reopenedProfile.isCompanionUnlocked("pianty") && reopenedProfile.isCompanionUnlocked("porcellino") && !reopenedProfile.isCompanionUnlocked("ciccio"), "si ricorda alla riapertura")
check(reopenedProfile.firstCompanion == "porcellino", "e anche il primo scelto")
reopenedProfile.reset()
check(Profile(directory: rwDir).unlocked == nil && Profile(directory: rwDir).isCompanionUnlocked("ciccio"), "«Cancella tutto» ricomincia")
// chi usava già l'app li tiene tutti
let keepDir = tempDirectory()
let keepUser = Profile(directory: keepDir)
keepUser.setName("Anna"); keepUser.markIntroSeen()
keepUser.keepAllCompanions(pets)
check(pets.allSatisfy { Profile(directory: keepDir).isCompanionUnlocked($0) } && Profile(directory: keepDir).unlocked == Set(pets), "chi c'era già: tutti sbloccati")
keepUser.chooseFirstCompanion("ciccio")
check(Profile(directory: keepDir).unlocked == Set(pets), "e la scelta iniziale non toglie niente")
// modalità sviluppatore: tutto sbloccato senza toccare il profilo
let devDir = tempDirectory()
let devProfile = Profile(directory: devDir)
devProfile.chooseFirstCompanion("pianty")
UserDefaults.standard.removeObject(forKey: Profile.developerKey)
check(!devProfile.isCompanionUnlocked("gattino"), "senza la modalità sviluppatore resta bloccato")
UserDefaults.standard.set(true, forKey: Profile.developerKey)
check(pets.allSatisfy { devProfile.isCompanionUnlocked($0) } && devProfile.unlocked == ["pianty"], "sviluppatore: tutti sbloccati, profilo intatto")
UserDefaults.standard.removeObject(forKey: Profile.developerKey)
check(!devProfile.isCompanionUnlocked("gattino"), "spenta, torna come prima")
// un profilo di prima (senza questi campi) si legge
let legacyProfDir = tempDirectory()
try? "{\"version\": 1, \"name\": \"Marco\", \"introSeen\": true}".write(to: legacyProfDir.appendingPathComponent("profilo.json"), atomically: true, encoding: .utf8)
let legacyProfile = Profile(directory: legacyProfDir)
check(legacyProfile.name == "Marco" && legacyProfile.introSeen && legacyProfile.unlocked == nil && legacyProfile.isCompanionUnlocked("ciccio"), "un profilo di prima si legge e non blocca niente")

// ---------------------------------------------------------------- dati danneggiati
section("Dati danneggiati")
// una sola sessione rovinata: le altre restano, il file com'era resta come copia
let partialDir = tempDirectory()
let partial = """
{"version": 3, "sessions": [
 {"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000031", "plannedMinutes": 25, "seconds": 1500, "start": "2026-10-12T08:00:00Z", "subject": "Buona"},
 {"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000032", "plannedMinutes": 25, "start": "2026-10-12T09:00:00Z"},
 {"completed": false, "id": "9F6C1A2B-0000-4000-8000-000000000033", "plannedMinutes": 30, "seconds": 600, "start": "2026-10-13T08:00:00Z"}
]}
"""
try? partial.write(to: partialDir.appendingPathComponent("sessioni.json"), atomically: true, encoding: .utf8)
var partialMessages: [String] = []
let partialLog = SessionLog(directory: partialDir, timeZone: rome)
partialLog.onProblem = { partialMessages.append($0) }
check(partialLog.sessions.count == 2 && !partialLog.isReadOnly, "una sessione rovinata: le altre due restano (\(partialLog.sessions.count))")
check(partialMessages.count == 1 && partialMessages[0].contains("non erano leggibili"), "e l'utente viene avvisato, anche se ci si registra dopo (\(partialMessages))")
let partialFiles = (try? FileManager.default.contentsOfDirectory(atPath: partialDir.path)) ?? []
check(partialFiles.contains { $0.hasPrefix("sessioni.corrotto-") }, "il file com'era resta come copia")
check(SessionLog(directory: partialDir, timeZone: rome).sessions.count == 2, "e il file riscritto ha le sessioni buone")
// un file che c'è ma non si legge non è un file assente: non si sovrascrive
let lockedDir = tempDirectory()
let lockedFile = lockedDir.appendingPathComponent("sessioni.json")
try? "{\"version\": 3, \"sessions\": []}".write(to: lockedFile, atomically: true, encoding: .utf8)
try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedFile.path)
let lockedLog = SessionLog(directory: lockedDir, timeZone: rome)
check(lockedLog.isReadOnly, "file illeggibile: sola lettura")
check(lockedLog.add(start: date(2026, 10, 14, 9), seconds: 600, plannedMinutes: 10, completed: true, subject: nil) == nil, "e non si scrive")
try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: lockedFile.path)
check((try? String(contentsOf: lockedFile)) == "{\"version\": 3, \"sessions\": []}", "il file è rimasto com'era")
// profilo rovinato: messo da parte, non sovrascritto
let badProfileDir = tempDirectory()
try? "{ non e' json".write(to: badProfileDir.appendingPathComponent("profilo.json"), atomically: true, encoding: .utf8)
var profileMessages: [String] = []
let badProfile = Profile(directory: badProfileDir)
badProfile.onProblem = { profileMessages.append($0) }
let badProfileFiles = (try? FileManager.default.contentsOfDirectory(atPath: badProfileDir.path)) ?? []
check(badProfile.name == nil && !badProfile.introSeen && badProfileFiles.contains { $0.hasPrefix("profilo.corrotto-") },
      "profilo rovinato: valori di partenza e file messo da parte (\(badProfileFiles))")
check(profileMessages.count == 1, "e l'utente viene avvisato")
badProfile.setName("Anna")
check(Profile(directory: badProfileDir).name == "Anna", "dopo, il profilo si salva normalmente")

// un file di una versione più nuova: sola lettura, avvisato, e il focus interrotto non va perso
let futureDir = tempDirectory()
try? "{\"version\": 99, \"sessions\": []}".write(to: futureDir.appendingPathComponent("sessioni.json"), atomically: true, encoding: .utf8)
let futureWriter = SessionLog(directory: futureDir, now: { date(2026, 10, 14, 9, 20) }, timeZone: rome)
futureWriter.beginInProgress(start: date(2026, 10, 14, 9), plannedMinutes: 50, subject: "Segnali")
var futureMessages: [String] = []
let futureReader = SessionLog(directory: futureDir, now: { date(2026, 10, 14, 9, 30) }, timeZone: rome)
futureReader.onProblem = { futureMessages.append($0) }
check(futureReader.isReadOnly && futureMessages.count == 1 && futureMessages[0].contains("più nuova"), "versione più nuova: l'utente viene avvisato")
check(futureReader.recoverInterrupted() == nil, "in sola lettura il focus interrotto non si può salvare")
check((try? Data(contentsOf: futureDir.appendingPathComponent("in-corso.json")))?.isEmpty == false, "ma il segno «in corso» resta")

// una scrittura che non riesce non passa inosservata (la cartella dei dati è un file: non si può creare)
let blocker = tempDirectory().appendingPathComponent("occupato")
try? "x".write(to: blocker, atomically: true, encoding: .utf8)
let failingLog = SessionLog(directory: blocker, timeZone: rome)
var writeMessages: [String] = []
failingLog.onProblem = { writeMessages.append($0) }
let failedAdd = failingLog.add(start: date(2026, 10, 14, 9), seconds: 600, plannedMinutes: 10, completed: true, subject: "X")
_ = failingLog.add(start: date(2026, 10, 14, 10), seconds: 600, plannedMinutes: 10, completed: true, subject: "X")
check(failedAdd != nil && failingLog.sessions.count == 2, "la sessione resta in memoria")
check(failingLog.hasUnsavedChanges, "e si sa che non è sul disco")
check(writeMessages.count == 1 && writeMessages[0].contains("Non riesco a salvare"), "l'utente viene avvisato una volta sola (\(writeMessages.count))")
var progressMessages: [String] = []
failingLog.onProblem = { progressMessages.append($0) }
failingLog.beginInProgress(start: Date(), plannedMinutes: 25, subject: nil)
check(progressMessages.count == 1 && progressMessages[0].contains("focus in corso"), "anche il focus in corso: scrittura fallita segnalata")
check(!SessionLog(directory: tempDirectory(), timeZone: rome).hasUnsavedChanges, "con la cartella a posto non c'è niente da salvare")

// ---------------------------------------------------------------- pausa lunga
section("Pausa lunga")
var cycle = BreakCycle()
let base = date(2026, 10, 14, 9)
func at(_ minutes: Int) -> Date { base.addingTimeInterval(Double(minutes) * 60) }
check(!cycle.focusCompleted(at: at(50)) && cycle.completed == 1, "il primo focus: pausa normale")
check(!cycle.focusCompleted(at: at(105)) && !cycle.focusCompleted(at: at(160)), "secondo e terzo: pausa normale")
check(cycle.completed == 3, "tre fatti, ne manca uno")
check(cycle.focusCompleted(at: at(215)), "il quarto: pausa lunga")
check(cycle.completed == 0 && !cycle.focusCompleted(at: at(270)), "dopo la pausa lunga si riparte")
// una lunga assenza azzera il ciclo
var away = BreakCycle()
_ = away.focusCompleted(at: at(50)); _ = away.focusCompleted(at: at(105)); _ = away.focusCompleted(at: at(160))
check(!away.focusCompleted(at: at(160 + 3 * 60)), "dopo 3 ore di assenza il ciclo ricomincia (era il 4°, ora è il 1°)")
check(away.completed == 1, "e conta uno")
// una pausa di un'ora e mezza non lo azzera
var pauses = BreakCycle()
for i in 0..<3 { _ = pauses.focusCompleted(at: at(i * 90)) }
check(pauses.focusCompleted(at: at(3 * 90)), "pause di un'ora e mezza: il ciclo regge")
check(pauses.done(at: at(3 * 90)) == 0, "fatto il quarto: il ciclo è già ripartito")
var counting = BreakCycle()
_ = counting.focusCompleted(at: at(50)); _ = counting.focusCompleted(at: at(105))
check(counting.done(at: at(110)) == 2, "due fatti poco dopo")
check(counting.done(at: at(105 + 3 * 60)) == 0, "dopo troppo tempo risultano zero (senza cambiare il conteggio)")
check(counting.completed == 2, "il conteggio interno non cambia leggendo")
var manual = BreakCycle()
_ = manual.focusCompleted(at: at(50)); manual.reset()
check(manual.completed == 0, "reset")
check(BreakCycle.focusesPerCycle == 4 && BreakCycle.longBreakMinutes == 15, "quattro focus, quindici minuti")

// ---------------------------------------------------------------- scelta del sottofondo
section("Scelta del sottofondo")
check(BackgroundChoice.current(ambient: .none, music: .off) == .none, "niente acceso")
check(BackgroundChoice.current(ambient: .rain, music: .off) == .rain && BackgroundChoice.current(ambient: .wind, music: .off) == .wind, "un suono")
check(BackgroundChoice.current(ambient: .none, music: .bundled) == .music && BackgroundChoice.current(ambient: .none, music: .folder) == .music, "la musica")
check(BackgroundChoice.current(ambient: .brown, music: .folder) == .brown, "se per errore sono accesi entrambi vince il suono")
check(BackgroundChoice.rain.ambientSound == .rain && BackgroundChoice.music.ambientSound == nil && BackgroundChoice.none.ambientSound == AmbientSound.none,
      "la scelta e il suono corrispondente")
check(BackgroundChoice.allCases.map { $0.title } == ["Nessuno", "Pioggia", "Vento", "Marrone", "Musica"], "i nomi, nell'ordine della schermata")

// ---------------------------------------------------------------- serie ghiacciata
section("Serie ghiacciata")
func analysis(_ days: [Int], today: Int, hour: Int = 20) -> StudyStreak.Result {
    StudyStreak.analyze(sessions: days.map { s($0) }, now: date(2026, 10, today, hour), calendar: cal)
}
let straight = analysis([12, 13, 14], today: 14)
check(straight.days == 3 && straight.perDay[date(2026, 10, 12)] == 1 && straight.perDay[date(2026, 10, 14)] == 3
      && !straight.isFrozen && straight.studiedToday, "tre di fila, nessun ghiaccio")
let oneGap = analysis([11, 13, 14], today: 14)
check(oneGap.days == 3 && oneGap.perDay[date(2026, 10, 13)] == 2 && oneGap.perDay[date(2026, 10, 14)] == 3,
      "un giorno saltato: la serie resta ferma e poi riparte da lì")
let twoGaps = analysis([10, 13, 14], today: 14)
check(twoGaps.days == 2 && twoGaps.perDay[date(2026, 10, 13)] == 1, "due giorni di fila senza studio: ricomincia da uno")
let tooOften = analysis([10, 12, 14], today: 14)
check(tooOften.perDay[date(2026, 10, 12)] == 2 && tooOften.perDay[date(2026, 10, 14)] == 1 && tooOften.days == 1,
      "il ghiaccio non si usa due volte in meno di una settimana")
let reusable = analysis([1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 13], today: 13)
check(reusable.days == 11 && reusable.perDay[date(2026, 10, 13)] == 11, "dopo sette giorni il ghiaccio si può riusare")
let frozenNow = analysis([12, 13], today: 15, hour: 8)
check(frozenNow.days == 2 && frozenNow.isFrozen && !frozenNow.studiedToday, "ieri saltato, oggi ancora vuoto: ghiacciata")
let thawed = analysis([12, 13, 15], today: 15)
check(thawed.days == 3 && !thawed.isFrozen && thawed.studiedToday, "studiando oggi si scongela e continua")
let notYet = analysis([12, 13], today: 14, hour: 8)
check(notYet.days == 2 && !notYet.isFrozen, "oggi ancora vuoto ma ieri sì: niente ghiaccio, conta da ieri")
let lost = analysis([11], today: 14, hour: 8)
check(lost.days == 0 && !lost.isFrozen, "il ghiaccio non salva due giorni di fila")
check(analysis([], today: 14).days == 0 && !analysis([], today: 14).isFrozen, "senza sessioni")
check(analysis([14, 14], today: 14).perDay[date(2026, 10, 14)] == 1, "più sessioni nello stesso giorno = un giorno")

// ---------------------------------------------------------------- punti del giardino
section("Punti del giardino")
check(GardenPoints.multiplier(forStreak: 0) == 1 && GardenPoints.multiplier(forStreak: 2) == 1, "fino a due giorni: ×1")
check(GardenPoints.multiplier(forStreak: 3) == 1.25 && GardenPoints.multiplier(forStreak: 6) == 1.25, "da 3 giorni: ×1,25")
check(GardenPoints.multiplier(forStreak: 7) == 1.5 && GardenPoints.multiplier(forStreak: 13) == 1.5, "da 7 giorni: ×1,5")
check(GardenPoints.multiplier(forStreak: 14) == 2 && GardenPoints.multiplier(forStreak: 90) == 2, "da 14 giorni: ×2, e non sale più")
func studyHour(_ day: Int, minutes: Int = 60, completed: Bool = true) -> StudySession {
    StudySession(start: date(2026, 10, day, 10), seconds: minutes * 60, plannedMinutes: 60, completed: completed, subject: nil)
}
// 14 giorni di fila, un'ora al giorno: 2×60 + 4×60×1,25 + 7×60×1,5 + 1×60×2 = 1170 minuti
let fortnight = (1...14).map { studyHour($0) }
let fortnightMinutes = GardenPoints.weightedMinutes(sessions: fortnight, now: date(2026, 10, 14, 20), calendar: cal)
check(abs(fortnightMinutes - 1170) < 0.001, "i minuti pesati di due settimane (\(fortnightMinutes))")
check(GardenPoints.earned(sessions: fortnight, now: date(2026, 10, 14, 20), calendar: cal) == 19, "19 punti (e mezzo)")
check(abs(GardenPoints.progressToNextPoint(weightedMinutes: fortnightMinutes) - 0.5) < 0.001, "a metà del prossimo")
let spaced = [studyHour(1), studyHour(5), studyHour(12)]
check(GardenPoints.earned(sessions: spaced, now: date(2026, 10, 12, 20), calendar: cal) == 3, "senza serie un'ora è un punto")
check(GardenPoints.earned(sessions: [studyHour(1, minutes: 30, completed: false)], now: date(2026, 10, 1, 20), calendar: cal) == 0
      && abs(GardenPoints.weightedMinutes(sessions: [studyHour(1, minutes: 30, completed: false)], now: date(2026, 10, 1, 20), calendar: cal) - 30) < 0.001,
      "i minuti di un focus interrotto contano")
check(GardenPoints.earned(sessions: [], now: date(2026, 10, 1), calendar: cal) == 0, "senza sessioni niente punti")
check(GardenPoints.balance(earned: 5, spent: 3) == 2 && GardenPoints.balance(earned: 2, spent: 5) == 0, "il saldo non va sotto zero")
check(GardenPoints.multiplierToday(analysis([12, 13], today: 14, hour: 8)) == 1.25
      && GardenPoints.multiplierToday(analysis([12, 13, 14], today: 14)) == 1.25
      && GardenPoints.multiplierToday(analysis([], today: 14)) == 1, "il valore di un minuto oggi")
check(GardenPoints.text(forMultiplier: 1.25) == "1,25" && GardenPoints.text(forMultiplier: 1.5) == "1,5"
      && GardenPoints.text(forMultiplier: 2) == "2", "il moltiplicatore in italiano")
check(GardenPoints.finishLine(beforeMinutes: 50, afterMinutes: 70, factor: 1) == "Un punto in più per il giardino.", "un punto in più")
check(GardenPoints.finishLine(beforeMinutes: 50, afterMinutes: 170, factor: 1.25).hasPrefix("2 punti in più per il giardino")
      && GardenPoints.finishLine(beforeMinutes: 50, afterMinutes: 170, factor: 1.25).contains("×1,25"), "due punti, con la serie")
check(GardenPoints.finishLine(beforeMinutes: 10, afterMinutes: 30, factor: 1).contains("ancora 30 minuti"), "quanto manca")
check(GardenPoints.finishLine(beforeMinutes: 10, afterMinutes: 30, factor: 1.5).contains("ancora 20 minuti"), "con la serie manca meno")

// ---------------------------------------------------------------- giardino: catalogo e scena
section("Giardino: catalogo e scena")
let allItems = GardenCatalog.items
check(Set(allItems.map { $0.id }).count == allItems.count, "id tutti diversi")
check(allItems.count == 36 && GardenCategory.allCases.allSatisfy { !GardenCatalog.items(in: $0).isEmpty }, "36 oggetti, ogni scheda ne ha")
check(allItems.allSatisfy { $0.height > 0 && $0.price >= 0 && !$0.name.isEmpty }, "altezze, prezzi e nomi sensati")
check(allItems.filter { $0.price == 0 }.count == 4, "quattro oggetti ci sono fin dall'inizio")
check(GardenCatalog.item(withID: "tulipani")?.resource == "giardino_tulipani" && GardenCatalog.item(withID: "no") == nil, "le risorse")
check(allItems.allSatisfy { FileManager.default.fileExists(atPath: "assets/giardino/\($0.id).png") }
      && FileManager.default.fileExists(atPath: "assets/giardino/prato.png"), "ogni oggetto ha il suo disegno in assets/giardino")
check(GardenScene.depthScale(y: GardenScene.horizon) == GardenScene.farScale && GardenScene.depthScale(y: 1) == 1
      && GardenScene.depthScale(y: 0) == GardenScene.farScale, "la scala va da lontano a vicino")
check(GardenScene.depthScale(y: 0.6) < GardenScene.depthScale(y: 0.8), "più in basso è più grande")
let outside = GardenScene.clamped(GardenSpot(x: -3, y: 9))
check(outside.x == GardenScene.lawn.minX && outside.y == GardenScene.lawn.maxY, "fuori dal prato si riporta dentro")
let spots = (0..<4).map { GardenScene.defaultCompanionSpot(index: $0) }
check(Set(spots.map { "\($0.x)-\($0.y)" }).count == 4 && spots.allSatisfy { GardenScene.clamped($0) == $0 }, "posti di partenza diversi e nel prato")
let drops = (0..<9).map { GardenScene.defaultPlacementSpot(salt: $0) }
check(Set(drops.map { "\($0.x)-\($0.y)" }).count > 4 && drops.allSatisfy { GardenScene.clamped($0) == $0 }, "i posti sfalsati")
check(GardenCatalog.companionHeight(for: "gattino") > 0 && GardenCatalog.companionHeight(for: "sconosciuto") == 100, "altezze dei compagni")

// ---------------------------------------------------------------- giardino: sblocchi e copie
section("Giardino: sblocchi e copie")
UserDefaults.standard.removeObject(forKey: Profile.developerKey)
let gardenDir = tempDirectory()
let garden = Garden(directory: gardenDir)
check(garden.placements.isEmpty && garden.spent == 0 && garden.unlocked.isEmpty, "all'inizio è vuoto")
check(garden.isUnlocked("margherite") && !garden.isUnlocked("rosaio") && !garden.isUnlocked("inesistente"), "i gratuiti ci sono, gli altri no")
check(!garden.unlock("rosaio", balance: 7) && garden.spent == 0, "con 7 punti il rosaio (8) non si sblocca")
check(garden.unlock("rosaio", balance: 8) && garden.isUnlocked("rosaio") && garden.spent == 8, "con 8 sì, e si spendono")
check(!garden.unlock("rosaio", balance: 99) && garden.spent == 8, "già sbloccato: non si spende due volte")
check(!garden.unlock("margherite", balance: 99) && garden.spent == 8, "un gratuito non costa niente")
check(garden.place("lampione", at: GardenSpot(x: 0.5, y: 0.7)) == nil, "bloccato: non si mette")
let first = garden.place("margherite", at: GardenSpot(x: 0.4, y: 0.7))
check(first != nil && garden.placements.count == 1 && garden.count(of: "margherite") == 1, "una copia nel prato")
for i in 0..<9 { _ = garden.place("margherite", at: GardenSpot(x: 0.1 + 0.05 * Double(i), y: 0.8)) }
check(garden.count(of: "margherite") == 10, "se ne possono avere quante se ne vuole: dieci margherite")
let wild = garden.place("rosaio", at: GardenSpot(x: -2, y: 7))
check(wild?.x == GardenScene.lawn.minX && wild?.y == GardenScene.lawn.maxY, "fuori dal prato lo riporta dentro")
if let first { garden.move(first.id, to: GardenSpot(x: 0.9, y: 0.6)) }
check(garden.placements.first(where: { $0.id == first?.id })?.spot == GardenSpot(x: 0.9, y: 0.6), "spostata")
if let first { garden.remove(first.id) }
check(garden.count(of: "margherite") == 9 && garden.spent == 8, "tolta una copia: i punti spesi non tornano e l'oggetto resta tuo")
check(garden.isUnlocked("rosaio"), "l'oggetto sbloccato resta sbloccato anche senza copie")
garden.setCompanionSpot("gattino", to: GardenSpot(x: 0.5, y: 0.9))
check(garden.companionSpot("gattino", index: 3) == GardenSpot(x: 0.5, y: 0.9), "il compagno spostato")
check(garden.companionSpot("pianty", index: 0) == GardenScene.defaultCompanionSpot(index: 0), "gli altri al posto di partenza")
let reopenedGarden = Garden(directory: gardenDir)
check(reopenedGarden.placements == garden.placements && reopenedGarden.unlocked == garden.unlocked
      && reopenedGarden.spent == 8 && reopenedGarden.companionSpots == garden.companionSpots, "si ricorda alla riapertura")
var observed = 0
garden.addObserver { observed += 1 }
_ = garden.place("trifoglio", at: GardenSpot(x: 0.5, y: 0.7))
check(observed == 1, "chi guarda viene avvisato")
// il tetto di sicurezza
let crowd = Garden(directory: tempDirectory())
for i in 0..<(Garden.maxPlacements + 20) { _ = crowd.place("erba-alta", at: GardenSpot(x: 0.5, y: 0.7 + Double(i % 10) * 0.01)) }
check(crowd.placements.count == Garden.maxPlacements, "non più di \(Garden.maxPlacements) copie")

// ---------------------------------------------------------------- giardino: file e modalità sviluppatore
section("Giardino: file e sviluppatore")
let brokenDir = tempDirectory()
try? "{ non è un giardino".write(to: brokenDir.appendingPathComponent("giardino.json"), atomically: true, encoding: .utf8)
let broken = Garden(directory: brokenDir)
var problems: [String] = []
broken.onProblem = { problems.append($0) }
check(problems.count == 1 && problems[0].contains("giardino.corrotto-"), "il file rovinato si mette da parte e lo dice")
check(!FileManager.default.fileExists(atPath: brokenDir.appendingPathComponent("giardino.json").path)
      && (try? FileManager.default.contentsOfDirectory(atPath: brokenDir.path))?.contains { $0.hasPrefix("giardino.corrotto-") } == true,
      "la copia c'è")
check(broken.placements.isEmpty, "e si riparte da vuoto")
let newerGardenDir = tempDirectory()
let newerGardenFile = newerGardenDir.appendingPathComponent("giardino.json")
let newerGardenText = "{\"version\": 99, \"unlocked\": [\"rosaio\"], \"spent\": 3, \"placements\": [], \"companions\": {}}"
try? newerGardenText.write(to: newerGardenFile, atomically: true, encoding: .utf8)
let newerGarden = Garden(directory: newerGardenDir)
var newerGardenProblems: [String] = []
newerGarden.onProblem = { newerGardenProblems.append($0) }
check(newerGarden.isUnlocked("rosaio") && newerGarden.spent == 3 && newerGardenProblems.count == 1, "una versione più nuova si legge e si avvisa")
_ = newerGarden.place("margherite", at: GardenSpot(x: 0.5, y: 0.7))
check((try? String(contentsOf: newerGardenFile, encoding: .utf8)) == newerGardenText, "ma non si riscrive")
// una scrittura che non riesce si dice una volta sola
let gardenBlocker = tempDirectory().appendingPathComponent("occupato")
try? "x".write(to: gardenBlocker, atomically: true, encoding: .utf8)
let failing = Garden(directory: gardenBlocker.appendingPathComponent("sotto"))
var writeProblems: [String] = []
failing.onProblem = { writeProblems.append($0) }
_ = failing.place("margherite", at: GardenSpot(x: 0.5, y: 0.7))
_ = failing.place("margherite", at: GardenSpot(x: 0.6, y: 0.7))
check(writeProblems.count == 1 && failing.placements.count == 2, "scrittura fallita: un solo avviso, le copie restano in memoria")
// modalità sviluppatore: tutto sbloccato, senza spendere
UserDefaults.standard.set(true, forKey: Profile.developerKey)
check(GardenCatalog.items.allSatisfy { garden.isUnlocked($0.id) }, "sviluppatore: tutto sbloccato")
let devGarden = Garden(directory: tempDirectory())
check(devGarden.place("arco-rose", at: GardenSpot(x: 0.5, y: 0.7)) != nil && devGarden.spent == 0, "e si può mettere senza spendere")
UserDefaults.standard.removeObject(forKey: Profile.developerKey)
check(!garden.isUnlocked("arco-rose"), "spenta, torna come prima")
garden.reset()
check(garden.placements.isEmpty && garden.unlocked.isEmpty && garden.spent == 0 && garden.companionSpots.isEmpty
      && !FileManager.default.fileExists(atPath: gardenDir.appendingPathComponent("giardino.json").path), "«Cancella tutto» ricomincia")

print("\n\(checks) controlli, \(failures) falliti")
exit(failures == 0 ? 0 : 1)
