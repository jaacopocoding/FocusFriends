import CoreGraphics
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
check(GardenCatalog.companionHeight(for: "gattino") > 0 && GardenCatalog.companionHeight(for: "sconosciuto") == 100, "altezze dei compagni")

// l'isola a tessere: impronte, sentiero, dove ci stanno le cose
section("Giardino: l'isola a tessere")
check(allItems.allSatisfy { (1...2).contains($0.footprint.cols) && (1...2).contains($0.footprint.rows) }, "ogni oggetto occupa una o due tessere per lato")
check(GardenCatalog.item(withID: "altalena")?.footprint == GardenFootprint(cols: 2, rows: 2) && GardenCatalog.item(withID: "panchina")?.footprint == GardenFootprint(cols: 2, rows: 1)
      && GardenCatalog.item(withID: "lampione")?.footprint == GardenFootprint(cols: 1, rows: 1), "le impronte (altalena 2×2, panchina 2×1, lampione 1×1)")
check(GardenFootprint(cols: 2, rows: 1).turned == GardenFootprint(cols: 1, rows: 2) && GardenFootprint(cols: 2, rows: 1).applying(turned: false) == GardenFootprint(cols: 2, rows: 1),
      "girata, l'impronta scambia larghezza e profondità")
check(GardenIsland.size(completedSpreads: 0) == 8 && GardenIsland.size(completedSpreads: 1) == 9 && GardenIsland.size(completedSpreads: 2) == 10
      && GardenIsland.size(completedSpreads: 9) == 10 && GardenIsland.size(completedSpreads: -1) == 8, "l'isola: 8, una in più per ogni doppia pagina completa, al massimo 10")
let path8 = GardenIsland.pathTiles(size: 8), path10 = GardenIsland.pathTiles(size: 10)
check(path8.count == 10 && path10.count == 12 && Array(path10.prefix(10)) == path8 && Set(path10).count == 12, "il sentiero non cambia quando l'isola si allarga: si allunga soltanto")
let allTiles10 = (0..<10).flatMap { c in (0..<10).map { GardenTile(col: c, row: $0) } }
check(allTiles10.filter { GardenIsland.isPath($0) }.count == 12 && path10.allSatisfy { GardenIsland.isPath($0) }, "isPath e pathTiles dicono lo stesso")
let one = GardenFootprint(cols: 1, rows: 1), two = GardenFootprint(cols: 2, rows: 2)
let noTiles: Set<GardenTile> = []
check(GardenLayout.canPlace(one, at: GardenTile(col: 0, row: 0), size: 8, occupied: noTiles) && GardenLayout.canPlace(one, at: GardenTile(col: 7, row: 7), size: 8, occupied: noTiles),
      "una tessera libera ci sta, anche agli angoli")
check(!GardenLayout.canPlace(one, at: GardenTile(col: 8, row: 0), size: 8, occupied: noTiles) && !GardenLayout.canPlace(one, at: GardenTile(col: -1, row: 2), size: 8, occupied: noTiles)
      && GardenLayout.canPlace(one, at: GardenTile(col: 8, row: 0), size: 9, occupied: noTiles), "fuori dall'isola no (e l'isola più grande ha più posto)")
check(!GardenLayout.canPlace(one, at: GardenTile(col: 3, row: 4), size: 8, occupied: noTiles), "sul sentiero no")
check(!GardenLayout.canPlace(two, at: GardenTile(col: 7, row: 7), size: 8, occupied: noTiles) && GardenLayout.canPlace(two, at: GardenTile(col: 6, row: 6), size: 8, occupied: noTiles)
      && !GardenLayout.canPlace(two, at: GardenTile(col: 2, row: 2), size: 8, occupied: noTiles), "un 2×2 deve starci tutto, e senza toccare il sentiero")
let swingPlacement = GardenPlacement(item: "altalena", tile: GardenTile(col: 1, row: 1))
let swingTiles = GardenLayout.occupiedTiles([swingPlacement])
check(swingTiles == [GardenTile(col: 1, row: 1), GardenTile(col: 2, row: 1), GardenTile(col: 1, row: 2), GardenTile(col: 2, row: 2)], "l'altalena occupa quattro tessere")
check(!GardenLayout.canPlace(one, at: GardenTile(col: 2, row: 2), size: 8, occupied: swingTiles) && GardenLayout.canPlace(one, at: GardenTile(col: 0, row: 0), size: 8, occupied: swingTiles)
      && GardenLayout.occupiedTiles([swingPlacement], skipping: swingPlacement.id).isEmpty, "non si copre un'altra cosa (ma si ignora quella che si sta spostando)")
let benchTurned = GardenPlacement(item: "panchina", tile: GardenTile(col: 1, row: 0), turned: true)
check(GardenLayout.occupiedTiles([benchTurned]) == [GardenTile(col: 1, row: 0), GardenTile(col: 1, row: 1)], "la panchina girata occupa due tessere in fila nell'altro senso")
check(GardenLayout.nearestOrigin(to: GardenTile(col: 3, row: 3), footprint: one, size: 8, occupied: noTiles) == GardenTile(col: 3, row: 2), "il posto libero più vicino a una tessera del sentiero")
check(GardenLayout.nearestOrigin(to: GardenTile(col: 1, row: 1), footprint: one, size: 8, occupied: noTiles) == GardenTile(col: 1, row: 1), "se il posto è libero, è quello")
check(GardenLayout.nearestOrigin(to: GardenTile(col: 0, row: 0), footprint: two, size: 2, occupied: noTiles) == GardenTile(col: 0, row: 0)
      && GardenLayout.nearestOrigin(to: GardenTile(col: 0, row: 0), footprint: two, size: 1, occupied: noTiles) == nil, "se non c'è posto, nil")
check(GardenLayout.freeOrigins(for: one, size: 8, occupied: noTiles).count == 64 - 10 && GardenLayout.freeOrigins(for: two, size: 8, occupied: noTiles).allSatisfy { GardenLayout.canPlace(two, at: $0, size: 8, occupied: noTiles) },
      "ci sono 54 tessere libere in un'isola da 8, senza il sentiero")
let legacyCorners = [GardenSpot(x: 0, y: 0), GardenSpot(x: 1, y: 0), GardenSpot(x: 0, y: 1), GardenSpot(x: 1, y: 1), GardenSpot(x: 0.5, y: 0.775)]
check(legacyCorners.allSatisfy { GardenIsland.contains(GardenLayout.tile(fromLegacy: $0, size: 8), size: 8) && GardenIsland.contains(GardenLayout.tile(fromLegacy: $0, size: 10), size: 10) }, "i punti del vecchio prato cadono sempre sull'isola")
check(GardenLayout.tile(fromLegacy: GardenSpot(x: 0.5, y: 0.775), size: 8) == GardenTile(col: 4, row: 4), "il centro del prato è il centro dell'isola")
check(GardenLayout.tile(fromLegacy: GardenSpot(x: 0.1, y: 0.75), size: 8).col - GardenLayout.tile(fromLegacy: GardenSpot(x: 0.9, y: 0.75), size: 8).col < 0
      && GardenLayout.tile(fromLegacy: GardenSpot(x: 0.1, y: 0.75), size: 8).row > GardenLayout.tile(fromLegacy: GardenSpot(x: 0.9, y: 0.75), size: 8).row,
      "a sinistra del prato è a sinistra sull'isola")
let companionTilesDefault = (0..<4).map { GardenLayout.defaultCompanionTile(index: $0) }
check(Set(companionTilesDefault).count == 4 && companionTilesDefault.allSatisfy { GardenIsland.isPath($0) }, "i compagni partono sul sentiero, in posti diversi")
let starting = Garden(directory: tempDirectory())
check(starting.placements.count == 4 && Set(starting.placements.map { $0.tile }).count == 4
      && starting.placements.allSatisfy { GardenLayout.canPlace(GardenCatalog.item(withID: $0.item)!.footprint, at: $0.tile, size: 8, occupied: noTiles) },
      "la dotazione sta su quattro tessere libere")

// le pagine dell'album: sei figurine per pagina, una sezione per volta
let albumSpreads = GardenAlbum.spreads()
check(albumSpreads.count == 3 && albumSpreads.allSatisfy { $0.right != nil && $0.left.items.count == 6 && $0.right!.items.count == 6 },
      "36 oggetti: tre doppie pagine da dodici, una per sezione")
check(albumSpreads.map { $0.left.category } == GardenCategory.allCases && albumSpreads.flatMap { $0.left.items + ($0.right?.items ?? []) }.map { $0.id } == GardenCatalog.items.map { $0.id },
      "nell'ordine del catalogo (i numeri non cambiano)")
let albumExtra = GardenCatalog.items + (0..<3).map { GardenItem(id: "extra\($0)", name: "Extra", category: .furniture, height: 50, price: 3) }
let albumLonger = GardenAlbum.spreads(catalog: albumExtra)
check(albumLonger.count == 4 && albumLonger[3].left.items.count == 3 && albumLonger[3].right == nil, "una sezione più lunga: una doppia pagina in più, con la pagina di destra vuota")
check(GardenCatalog.number(of: "margherite") == 1 && GardenCatalog.number(of: "arco-rose") == 36 && GardenCatalog.number(of: "no") == nil, "i numeri delle figurine")
let firstSpreadItems = albumSpreads[0].left.items + albumSpreads[0].right!.items
check(GardenAlbum.completedSpreads(isFound: { _ in false }) == 0 && GardenAlbum.completedSpreads(isFound: { _ in true }) == 3
      && GardenAlbum.completedSpreads(isFound: { id in firstSpreadItems.contains { $0.id == id } }) == 1
      && GardenAlbum.completedSpreads(isFound: { id in id != firstSpreadItems[0].id }) == 2, "le doppie pagine complete")

// ---------------------------------------------------------------- giardino: l'album e le copie
section("Giardino: l'album e le copie")
UserDefaults.standard.removeObject(forKey: Profile.developerKey)
let gardenDir = tempDirectory()
let garden = Garden(directory: gardenDir)
check(garden.foundCount == 4 && garden.placements.count == 4 && garden.copies(of: "margherite") == 1 && garden.pendingGifts == 0 && garden.islandSize == 8, "all'inizio c'è la dotazione, già sull'isola da 8")
check(garden.isFound("margherite") && !garden.isFound("rosaio") && !garden.isFound("inesistente"), "la dotazione è nell'album, gli altri no")
check(garden.place("lampione", at: GardenTile(col: 5, row: 5)) == nil, "non trovato: non si mette")
check(garden.available("margherite") == 0 && garden.place("margherite", at: GardenTile(col: 5, row: 1)) == nil, "tutte le copie sono già sull'isola: non se ne mettono di più")
let firstDaisy = garden.placements.first { $0.item == "margherite" }
if let firstDaisy { garden.remove(firstDaisy.id) }
check(garden.count(of: "margherite") == 0 && garden.available("margherite") == 1 && garden.copies(of: "margherite") == 1, "tolta dall'isola, la copia torna tra quelle da mettere")
check(garden.place("margherite", at: GardenTile(col: 3, row: 4)) == nil && garden.place("margherite", at: GardenTile(col: 8, row: 0)) == nil
      && garden.place("margherite", at: GardenTile(col: 6, row: 6)) == nil, "sul sentiero, fuori dall'isola o sopra un'altra cosa no")
let backDaisy = garden.place("margherite", at: GardenTile(col: 5, row: 1))
check(backDaisy?.tile == GardenTile(col: 5, row: 1) && garden.available("margherite") == 0, "rimessa su una tessera libera")
if let backDaisy {
    check(garden.move(backDaisy.id, to: GardenTile(col: 6, row: 1)) && garden.placements.first(where: { $0.id == backDaisy.id })?.tile == GardenTile(col: 6, row: 1), "spostata")
    check(!garden.move(backDaisy.id, to: GardenTile(col: 6, row: 6)) && !garden.move(backDaisy.id, to: GardenTile(col: 3, row: 3))
          && garden.placements.first(where: { $0.id == backDaisy.id })?.tile == GardenTile(col: 6, row: 1), "sopra un'altra cosa o sul sentiero non si sposta: resta dov'era")
    check(garden.move(backDaisy.id, to: GardenTile(col: 6, row: 1)), "si può «spostare» sulla tessera dove sta già")
}
check(garden.placeSomewhere("lampione") == nil, "placeSomewhere: una cosa non trovata non si mette")
garden.setCompanionTile("gattino", to: GardenTile(col: 2, row: 2))
check(garden.companionTile("gattino", index: 3) == GardenTile(col: 2, row: 2), "il compagno spostato")
garden.setCompanionTile("pianty", to: GardenTile(col: 9, row: 9))
check(garden.companionTile("pianty", index: 0) == GardenLayout.defaultCompanionTile(index: 0), "fuori dall'isola il compagno non si sposta")
check(garden.companionTile("ciccio", index: 2) == GardenLayout.defaultCompanionTile(index: 2), "gli altri al posto di partenza")

// i regali: un focus che tira mette la figurina nel prato, una volta sola per focus
func gardenSession(_ minutes: Int, completed: Bool = true, id: UUID = UUID()) -> StudySession {
    StudySession(id: id, start: date(2026, 10, 5, 9), localStart: "2026-10-05T09:00", seconds: minutes * 60, plannedMinutes: minutes, completed: completed, subject: nil)
}
check(garden.rollGift(for: gardenSession(50, completed: false), streakDays: 1) == .notEligible && garden.rollGift(for: gardenSession(10), streakDays: 1) == .notEligible
      && garden.drops == GardenDropState.starting(), "un focus interrotto o troppo corto non tira e non cambia niente")
var gardenFound: GardenDrop?
var gardenSessions: [StudySession] = []
for _ in 0..<40 where gardenFound == nil {
    let session = gardenSession(30)
    gardenSessions.append(session)
    let before = garden.placements.count
    if case .found(let drop) = garden.rollGift(for: session, streakDays: 1) {
        gardenFound = drop
        check(garden.placements.count == before + 1 && garden.unseen.contains(drop.item) && garden.copies(of: drop.item) == drop.copies, "una figurina trovata va nel prato e nell'album (NUOVA)")
    }
}
check(gardenFound != nil, "entro quaranta focus esce qualcosa")
if let last = gardenSessions.last {
    check(garden.rollGift(for: last, streakDays: 1) == .notEligible, "lo stesso focus non tira due volte")
}
garden.markSeen()
check(garden.unseen.isEmpty, "aperto l'album, non c'è più niente di nuovo")
let reopenedGarden = Garden(directory: gardenDir)
check(reopenedGarden.placements == garden.placements && reopenedGarden.drops == garden.drops && reopenedGarden.lastRolled == garden.lastRolled
      && reopenedGarden.companionTiles == garden.companionTiles, "si ricorda alla riapertura")
check(Set(garden.placements.map { $0.tile }).count == garden.placements.count && garden.placements.allSatisfy { GardenIsland.contains($0.tile, size: garden.islandSize) && !GardenIsland.isPath($0.tile) },
      "dopo i regali, ogni cosa sta su una tessera sua, fuori dal sentiero")
var observed = 0
garden.addObserver { observed += 1 }
_ = garden.rollGift(for: gardenSession(30), streakDays: 1)
check(observed == 1, "chi guarda viene avvisato")
// con la modalità sviluppatore si possono mettere copie a volontà: l'isola da 10 si riempie, e basta
UserDefaults.standard.set(true, forKey: Profile.developerKey)
let crowd = Garden(directory: tempDirectory())
check(crowd.islandSize == 10, "sviluppatore: l'album è tutto completo, l'isola è da 10")
for tile in allTiles10 { _ = crowd.place("erba-alta", at: tile) }
check(crowd.placements.count == 88, "tutta l'isola riempita, tranne le 12 tessere del sentiero")
check(crowd.place("erba-alta", at: GardenTile(col: 0, row: 0)) == nil, "e poi non ci sta più niente")
// girare: la panchina (2×1) girata ha bisogno dell'altra tessera
let turnDir = tempDirectory()
let turnGarden = Garden(directory: turnDir)
let turnBench = turnGarden.place("panchina", at: GardenTile(col: 0, row: 0))
check(turnBench != nil && turnGarden.occupiedTiles() .contains(GardenTile(col: 1, row: 0)), "la panchina occupa due tessere")
if let turnBench {
    _ = turnGarden.place("lampione", at: GardenTile(col: 0, row: 1))
    check(!turnGarden.rotate(turnBench.id) && turnGarden.placements.first(where: { $0.id == turnBench.id })?.turned == false, "girata, ci darebbe contro il lampione: resta com'era")
    if let lamp = turnGarden.placements.first(where: { $0.item == "lampione" }) { turnGarden.remove(lamp.id) }
    check(turnGarden.rotate(turnBench.id) && turnGarden.placements.first(where: { $0.id == turnBench.id })?.turned == true
          && turnGarden.occupiedTiles().contains(GardenTile(col: 0, row: 1)) && !turnGarden.occupiedTiles().contains(GardenTile(col: 1, row: 0)), "girata, occupa l'altro senso")
    check(Garden(directory: turnDir).placements.first(where: { $0.id == turnBench.id })?.turned == true, "e si ricorda alla riapertura")
}
UserDefaults.standard.removeObject(forKey: Profile.developerKey)
// l'isola cresce con le doppie pagine complete (e non si rimpicciolisce sotto a quello che c'è già)
func writeGardenFile(_ directory: URL, version: Int, drops: GardenDropState, placements: [[String: Any]], companions: [String: Any] = [:]) {
    let dropsObject = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(drops))) ?? [:]
    let object: [String: Any] = ["version": version, "drops": dropsObject, "placements": placements, "companions": companions]
    if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) { try? data.write(to: directory.appendingPathComponent("giardino.json")) }
}
var grownDrops = GardenDropState.starting()
for item in firstSpreadItems { grownDrops.found[item.id] = 1 }
let growDir = tempDirectory()
writeGardenFile(growDir, version: 3, drops: grownDrops, placements: [])
check(Garden(directory: growDir).islandSize == 9 && GardenAlbum.completedSpreads(isFound: { Garden(directory: growDir).copies(of: $0) > 0 }) == 1, "una doppia pagina completa: l'isola è da 9")
let extentDir = tempDirectory()
writeGardenFile(extentDir, version: 3, drops: GardenDropState.starting(),
                placements: [["id": "00000000-0000-4000-8000-0000000000A1", "item": "margherite", "col": 8, "row": 2, "turned": false]])
check(Garden(directory: extentDir).islandSize == 9 && Garden(directory: extentDir).placements.count == 1, "mai più piccola di quello che c'è già sopra")
// un file della versione 3 fatto male: una cosa sul sentiero, fuori dall'isola, sopra un'altra, oppure sconosciuta
let sloppyDir = tempDirectory()
writeGardenFile(sloppyDir, version: 3, drops: GardenDropState.starting(), placements: [
    ["id": "00000000-0000-4000-8000-0000000000B1", "item": "margherite", "col": 1, "row": 1, "turned": false],
    ["id": "00000000-0000-4000-8000-0000000000B2", "item": "trifoglio", "col": 3, "row": 4, "turned": false],
    ["id": "00000000-0000-4000-8000-0000000000B3", "item": "erba-alta", "col": 11, "row": 0, "turned": false],
    ["id": "00000000-0000-4000-8000-0000000000B4", "item": "mughetti", "col": 1, "row": 1, "turned": false],
    ["id": "00000000-0000-4000-8000-0000000000B5", "item": "cosa-sconosciuta", "col": 0, "row": 0, "turned": false],
])
let sloppy = Garden(directory: sloppyDir)
check(sloppy.placements.map { $0.item } == ["margherite", "cosa-sconosciuta"], "sul sentiero, fuori dall'isola o sopra un'altra cosa: tolta (resta tra quelle da mettere); le sconosciute si tengono")
check(sloppy.available("trifoglio") == 1 && sloppy.available("erba-alta") == 1 && sloppy.available("mughetti") == 1, "…e le copie tolte sono di nuovo da mettere")
// un giardino della versione 2 (il prato libero): ogni cosa va sulla tessera libera più vicina e il file vecchio si tiene da parte
let gardenV2Dir = tempDirectory()
let gardenV2Text = """
{"version": 2, "drops": {"found": {"margherite": 1, "trifoglio": 1, "erba-alta": 1, "mughetti": 1, "lavanda": 3}, "nothingInARow": 0, "sinceRare": 2, "sinceLegendary": 5},
 "lastRolled": "00000000-0000-4000-8000-0000000000C0", "unseen": ["lavanda"], "pendingGifts": 0,
 "placements": [{"id": "00000000-0000-4000-8000-0000000000C1", "item": "lavanda", "x": 0.5, "y": 0.775},
                {"id": "00000000-0000-4000-8000-0000000000C2", "item": "lavanda", "x": 0.5, "y": 0.775},
                {"id": "00000000-0000-4000-8000-0000000000C3", "item": "lavanda", "x": 0.5, "y": 0.775},
                {"id": "00000000-0000-4000-8000-0000000000C4", "item": "margherite", "x": 0.03, "y": 0.99}],
 "companions": {"gattino": {"x": 0.5, "y": 0.775}, "ciccio": {"col": 1, "row": 1}}}
"""
try? gardenV2Text.write(to: gardenV2Dir.appendingPathComponent("giardino.json"), atomically: true, encoding: .utf8)
let gardenV2 = Garden(directory: gardenV2Dir)
check(gardenV2.placements.count == 4 && Set(gardenV2.placements.map { $0.tile }).count == 4
      && gardenV2.placements.allSatisfy { GardenIsland.contains($0.tile, size: 8) && !GardenIsland.isPath($0.tile) && $0.legacy == nil },
      "versione 2: quattro copie, ognuna sulla sua tessera (anche le tre che stavano nello stesso punto)")
check(gardenV2.placements[0].tile == GardenTile(col: 4, row: 4) || GardenLayout.nearestOrigin(to: GardenTile(col: 4, row: 4), footprint: one, size: 8, occupied: noTiles) != nil, "la prima va dove stava")
check(gardenV2.copies(of: "lavanda") == 3 && gardenV2.unseen == ["lavanda"] && gardenV2.lastRolled != nil, "album e regali restano")
let gardenV2Cat = gardenV2.companionTile("gattino", index: 3)
check(abs(gardenV2Cat.col - 4) + abs(gardenV2Cat.row - 4) <= 1 && !gardenV2.occupiedTiles().contains(gardenV2Cat) && gardenV2.companionTile("ciccio", index: 2) == GardenTile(col: 1, row: 1),
      "i compagni: il punto del prato diventa una tessera libera lì vicino, quella già in tessere resta")
check((try? String(contentsOf: gardenV2Dir.appendingPathComponent("giardino.json"), encoding: .utf8)) == gardenV2Text, "finché non si cambia niente, il file non si tocca")
gardenV2.setCompanionTile("gattino", to: GardenTile(col: 5, row: 5))
check((try? String(contentsOf: gardenV2Dir.appendingPathComponent("giardino-formato2.json"), encoding: .utf8)) == gardenV2Text, "al primo salvataggio il file della versione 2 si tiene da parte")
let gardenV2Again = Garden(directory: gardenV2Dir)
check(gardenV2Again.placements == gardenV2.placements && gardenV2Again.companionTile("gattino", index: 3) == GardenTile(col: 5, row: 5), "e la versione 3 si rilegge uguale")
check(!(((try? String(contentsOf: gardenV2Dir.appendingPathComponent("giardino.json"), encoding: .utf8)) ?? "").contains("\"x\"")), "nel file nuovo non ci sono più le vecchie coordinate")

// ---------------------------------------------------------------- giardino: file, versione 1 e modalità sviluppatore
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
check(broken.foundCount == 4 && broken.placements.count == 4, "e si riparte dalla dotazione")
let newerGardenDir = tempDirectory()
let newerGardenFile = newerGardenDir.appendingPathComponent("giardino.json")
let newerGardenText = "{\"version\": 99, \"unlocked\": [\"rosaio\"], \"spent\": 3, \"placements\": [], \"companions\": {}}"
try? newerGardenText.write(to: newerGardenFile, atomically: true, encoding: .utf8)
let newerGarden = Garden(directory: newerGardenDir)
var newerGardenProblems: [String] = []
newerGarden.onProblem = { newerGardenProblems.append($0) }
check(newerGarden.isFound("rosaio") && newerGardenProblems.count == 1, "una versione più nuova si legge e si avvisa")
_ = newerGarden.rollGift(for: gardenSession(30), streakDays: 1)
check((try? String(contentsOf: newerGardenFile, encoding: .utf8)) == newerGardenText, "ma non si riscrive")

// un giardino della versione 1: gli oggetti sbloccati restano, i punti non spesi diventano regali, e il file vecchio si tiene da parte
let legacyDir = tempDirectory()
let legacyFile = legacyDir.appendingPathComponent("giardino.json")
let legacyText = """
{"version": 1, "unlocked": ["rosaio", "lampione"], "spent": 14,
 "placements": [{"id": "00000000-0000-4000-8000-000000001001", "item": "margherite", "x": 0.4, "y": 0.7},
                {"id": "00000000-0000-4000-8000-000000001002", "item": "margherite", "x": 0.5, "y": 0.7},
                {"id": "00000000-0000-4000-8000-000000001003", "item": "lampione", "x": 0.6, "y": 0.8}],
 "companions": {"gattino": {"x": 0.5, "y": 0.9}}}
"""
try? legacyText.write(to: legacyFile, atomically: true, encoding: .utf8)
let legacy = Garden(directory: legacyDir)
check(legacy.copies(of: "rosaio") == 1 && legacy.copies(of: "lampione") == 1 && legacy.copies(of: "margherite") == 2 && legacy.placements.count == 3,
      "versione 1: gli oggetti sbloccati restano (con le copie che aveva nel prato)")
check(legacy.isFound("rosaio") && legacy.available("rosaio") == 1 && legacy.available("lampione") == 0, "…e quelle non ancora nel prato sono da mettere")
check((try? String(contentsOf: legacyFile, encoding: .utf8)) == legacyText, "finché non si cambia niente, il file non si tocca")
legacy.convertLegacyPoints(earned: 19)
check(legacy.pendingGifts == 5, "19 punti guadagnati e 14 spesi: cinque regali da aprire")
check((try? String(contentsOf: legacyDir.appendingPathComponent("giardino-formato1.json"), encoding: .utf8)) == legacyText, "il file della versione 1 si tiene da parte")
let legacyBefore = legacy.placements.count
let legacyGifts = legacy.openPendingGifts()
check(legacyGifts.count == 5 && legacy.pendingGifts == 0 && legacy.placements.count == legacyBefore + 5 && legacy.unseen.count >= 1, "si aprono: cinque figurine, nel prato e «NUOVE»")
check(Garden(directory: legacyDir).placements.count == legacyBefore + 5 && Garden(directory: legacyDir).pendingGifts == 0, "e restano aperte alla riapertura")
legacy.convertLegacyPoints(earned: 99)
check(legacy.pendingGifts == 0, "la conversione dei punti si fa una volta sola")
let legacyAgain = Garden(directory: tempDirectory())
legacyAgain.convertLegacyPoints(earned: 50)
check(legacyAgain.pendingGifts == 0, "un giardino nuovo non ha punti da convertire")
var legacyTwin = Garden(directory: { let d = tempDirectory(); try? legacyText.write(to: d.appendingPathComponent("giardino.json"), atomically: true, encoding: .utf8); return d }())
legacyTwin.convertLegacyPoints(earned: 19)
check(legacyTwin.openPendingGifts().map { $0.item } == legacyGifts.map { $0.item }, "gli stessi punti danno sempre gli stessi regali")
legacyTwin.convertLegacyPoints(earned: 3)
let fewPoints = Garden(directory: { let d = tempDirectory(); try? legacyText.write(to: d.appendingPathComponent("giardino.json"), atomically: true, encoding: .utf8); return d }())
fewPoints.convertLegacyPoints(earned: 5)
check(fewPoints.pendingGifts == 0, "se i punti guadagnati sono meno di quelli spesi (sessioni cancellate), niente regali")

// una scrittura che non riesce si dice una volta sola
let gardenBlocker = tempDirectory().appendingPathComponent("occupato")
try? "x".write(to: gardenBlocker, atomically: true, encoding: .utf8)
let failing = Garden(directory: gardenBlocker.appendingPathComponent("sotto"))
var writeProblems: [String] = []
failing.onProblem = { writeProblems.append($0) }
_ = failing.rollGift(for: gardenSession(30), streakDays: 1)
_ = failing.rollGift(for: gardenSession(30), streakDays: 1)
check(writeProblems.count == 1, "scrittura fallita: un solo avviso, il resto resta in memoria")
// modalità sviluppatore: tutto trovato, copie a volontà
UserDefaults.standard.set(true, forKey: Profile.developerKey)
check(GardenCatalog.items.allSatisfy { garden.isFound($0.id) }, "sviluppatore: tutto nell'album")
let devGarden = Garden(directory: tempDirectory())
check(devGarden.place("arco-rose", at: GardenTile(col: 0, row: 6)) != nil && devGarden.place("arco-rose", at: GardenTile(col: 0, row: 7)) != nil, "e se ne mettono quanti si vuole")
UserDefaults.standard.removeObject(forKey: Profile.developerKey)
// (con un giardino nuovo: in quello dei tiri l'arco potrebbe essere uscito davvero, gli identificativi delle sessioni sono casuali)
check(!Garden(directory: tempDirectory()).isFound("arco-rose"), "spenta, torna come prima")
garden.reset()
check(garden.foundCount == 4 && garden.placements.count == 4 && garden.drops == GardenDropState.starting() && garden.companionTiles.isEmpty && garden.unseen.isEmpty
      && !FileManager.default.fileExists(atPath: gardenDir.appendingPathComponent("giardino.json").path), "«Cancella tutto» ricomincia dalla dotazione")

// ---------------------------------------------------------------- giardino: cielo e stagioni
section("Giardino: cielo e stagioni")
check(Season.of(date(2026, 3, 1, 12)) == .spring && Season.of(date(2026, 5, 31, 12)) == .spring && Season.of(date(2026, 6, 1, 12)) == .summer
      && Season.of(date(2026, 9, 1, 12)) == .autumn && Season.of(date(2026, 12, 1, 12)) == .winter && Season.of(date(2027, 2, 28, 12)) == .winter, "le stagioni dai mesi")
check(Season.allCases.allSatisfy { GardenSky.sunrise($0) < GardenSky.sunset($0) } && GardenSky.sunset(.summer) > GardenSky.sunset(.winter) && GardenSky.sunrise(.summer) < GardenSky.sunrise(.winter),
      "d'estate il giorno è più lungo che d'inverno")
for season in Season.allCases {
    let noon = GardenSky.light(hour: 13, season: season), midnight = GardenSky.light(hour: 0, season: season)
    check(noon.darkness == 0 && noon.tintStrength == 0 && noon.lamp == 0 && noon.multiplier == GardenRGB(red: 255, green: 255, blue: 255), "\(season.title): a mezzogiorno nessuna tinta, lampioni spenti")
    check(midnight.darkness == 0.55 && midnight.lamp == 1 && midnight.multiplier.blue < 255 && midnight.multiplier.red < midnight.multiplier.blue, "\(season.title): di notte è buio, i lampioni sono accesi e la scena vira all'azzurro")
    check(GardenSky.light(hour: 24, season: season) == midnight && GardenSky.light(hour: -1, season: season) == GardenSky.light(hour: 23, season: season), "\(season.title): le ore si chiudono a cerchio")
    // senza salti: un minuto dopo l'altro la luce cambia pochissimo
    var maxStep = 0.0, lampsRise = true, last = GardenSky.light(hour: 0, season: season)
    for minute in 1...1440 {
        let now = GardenSky.light(hour: Double(minute) / 60, season: season)
        maxStep = max(maxStep, abs(now.darkness - last.darkness), abs(now.tintStrength - last.tintStrength) / 4, abs(now.multiplier.red - last.multiplier.red) / 255)
        last = now
    }
    check(maxStep < 0.02, "\(season.title): la luce cambia senza salti (al massimo \(maxStep) a minuto)")
    let sunsetHour = GardenSky.sunset(season)
    let evening = (0...8).map { GardenSky.light(hour: sunsetHour - 1 + Double($0) * 0.4, season: season).darkness }
    lampsRise = zip(evening, evening.dropFirst()).allSatisfy { $0 <= $1 }
    check(lampsRise && GardenSky.light(hour: sunsetHour - 2, season: season).lamp == 0 && GardenSky.light(hour: sunsetHour + 2, season: season).lamp == 1, "\(season.title): dopo il tramonto il buio cresce e i lampioni si accendono")
}
check(GardenSky.light(hour: 19, season: .winter).lamp > 0.9 && GardenSky.light(hour: 19, season: .summer).lamp == 0, "alle sette di sera d'inverno è già notte, d'estate no")
check(GardenSky.light(hour: 6, season: .summer).darkness < GardenSky.light(hour: 6, season: .winter).darkness, "e al mattino d'estate è già chiaro")
check(GardenSky.hour(of: date(2026, 10, 25, 21), calendar: StudyPeriod.calendar()) == 21, "l'ora con la virgola")
// le lucciole
check(GardenSky.fireflyAmount(season: .summer, light: GardenSky.light(hour: 23, season: .summer)) == 1
      && GardenSky.fireflyAmount(season: .winter, light: GardenSky.light(hour: 23, season: .winter)) == 0
      && GardenSky.fireflyAmount(season: .summer, light: GardenSky.light(hour: 13, season: .summer)) == 0
      && GardenSky.fireflyAmount(season: .autumn, light: GardenSky.light(hour: 23, season: .autumn)) < GardenSky.fireflyAmount(season: .spring, light: GardenSky.light(hour: 23, season: .spring)),
      "lucciole: di notte e d'estate soprattutto, mai d'inverno né di giorno")
let fireflies = (0..<GardenSky.fireflyCount).flatMap { index in (0..<20).map { GardenSky.firefly(index: index, time: Double($0) * 7.3, width: 1000, height: 600) } }
check(fireflies.allSatisfy { $0.x > 0 && $0.x < 1000 && $0.y > 0 && $0.y < 600 && $0.glow >= 0 && $0.glow <= 1 }, "le lucciole restano nella scena")
check(GardenSky.firefly(index: 3, time: 12.5, width: 1000, height: 600) == GardenSky.firefly(index: 3, time: 12.5, width: 1000, height: 600)
      && GardenSky.firefly(index: 3, time: 12.5, width: 1000, height: 600).x != GardenSky.firefly(index: 4, time: 12.5, width: 1000, height: 600).x, "ognuna ha il suo posto, sempre lo stesso")
// quello che cade
check(GardenSky.particleKind(.spring) == .petal && GardenSky.particleKind(.autumn) == .leaf && GardenSky.particleKind(.winter) == .snow && GardenSky.particleKind(.summer) == nil, "cosa cade in ogni stagione")
for kind in [GardenParticleKind.petal, .leaf, .snow] {
    let count = GardenSky.particleCount(kind)
    let samples = (0..<count).flatMap { index in (0..<30).map { GardenSky.particle(kind: kind, index: index, time: Double($0) * 5.7, width: 1000, height: 600) } }
    check(samples.allSatisfy { $0.x >= -30 && $0.x <= 1030 && $0.y >= -20 && $0.y <= 620 && $0.size > 0 && $0.alpha > 0 && $0.alpha <= 1 && $0.tone >= 0 && $0.tone < 1 }, "\(kind): sempre dentro la scena (con un bordo)")
    let a = GardenSky.particle(kind: kind, index: 2, time: 10, width: 1000, height: 600), b = GardenSky.particle(kind: kind, index: 2, time: 11, width: 1000, height: 600)
    check(a == GardenSky.particle(kind: kind, index: 2, time: 10, width: 1000, height: 600) && b.y != a.y, "\(kind): sempre uguale per lo stesso istante, e si muove")
    let descends = (0..<count).allSatisfy { index in
        let p0 = GardenSky.particle(kind: kind, index: index, time: 0, width: 1000, height: 600), p1 = GardenSky.particle(kind: kind, index: index, time: 0.5, width: 1000, height: 600)
        return p1.y > p0.y || p0.y > 560      // scende (o è appena rientrata dall'alto)
    }
    check(descends, "\(kind): scende")
}
check(Set((0..<26).map { GardenSky.particle(kind: .petal, index: $0, time: 0, width: 1000, height: 600).x }).count == 26, "ogni petalo parte da un punto diverso")

// ---------------------------------------------------------------- giardino: la vita ferma
section("Giardino: vento, acqua e fumo")
check(Season.allCases.allSatisfy { GardenSky.wind($0) > 0 && GardenSky.wind($0) <= 1 } && GardenSky.wind(.summer) < GardenSky.wind(.autumn), "il vento: d'estate soffia meno che d'autunno")
let swaySamples = (0..<200).flatMap { i in [0.0, 0.3, 0.7, 1.0].map { GardenSky.sway(time: Double(i) * 0.37, col: i % 10, row: (i / 3) % 10, seed: Double(i % 7) / 7, height: $0) } }
check(swaySamples.allSatisfy { abs($0) <= 1 }, "l'ondeggiamento sta fra −1 e 1")
check((0..<100).allSatisfy { GardenSky.sway(time: Double($0) * 0.5, col: 3, row: 4, seed: 0.4, height: 0) == 0 }, "la base di una pianta sta ferma")
check((0..<100).allSatisfy { abs(GardenSky.sway(time: Double($0) * 0.5, col: 3, row: 4, seed: 0.4, height: 0.4)) <= abs(GardenSky.sway(time: Double($0) * 0.5, col: 3, row: 4, seed: 0.4, height: 1)) + 1e-12 }, "più in alto, più si muove")
check(GardenSky.sway(time: 7, col: 2, row: 2, seed: 0.1, height: 1) != GardenSky.sway(time: 7, col: 2, row: 2, seed: 0.6, height: 1)
      && GardenSky.sway(time: 7, col: 1, row: 1, seed: 0.1, height: 1) != GardenSky.sway(time: 7, col: 5, row: 5, seed: 0.1, height: 1), "ogni pianta ha il suo ritmo e l'onda la attraversa")
check(GardenSky.sway(time: 7, col: 2, row: 2, seed: 0.1, height: 1) == GardenSky.sway(time: 7, col: 2, row: 2, seed: 0.1, height: 1), "sempre uguale per lo stesso istante")
let sway1 = (0..<300).map { GardenSky.sway(time: Double($0) * 0.1, col: 3, row: 3, seed: 0.2, height: 1) }
check(zip(sway1, sway1.dropFirst()).allSatisfy { abs($0 - $1) < 0.35 }, "e cambia piano, senza scatti (a 10 fotogrammi al secondo)")
check(GardenCatalog.item(withID: "lavanda")?.swayStrength == 1 && GardenCatalog.item(withID: "bandierine")?.swayStrength == 1.8
      && GardenCatalog.item(withID: "funghi")?.swayStrength == 0 && GardenCatalog.item(withID: "panchina")?.swayStrength == 0
      && GardenCatalog.items.filter { $0.swayStrength > 0 }.count == 12, "ondeggiano i fiori (non i funghi né i vasi), le bandierine e il carillon")
check(GardenCatalog.items.filter { $0.waterSpot != nil }.map { $0.id } == ["bagnetto"], "l'acqua sta nel bagnetto")
let water = GardenCatalog.item(withID: "bagnetto")!.waterSpot!
check(water.u - water.halfWidth > 0 && water.u + water.halfWidth < 1 && water.v - water.halfHeight > 0 && water.v + water.halfHeight < 1, "l'ovale dell'acqua sta dentro il disegno")
let sparkles = (0..<GardenSky.sparkleCount).flatMap { i in (0..<300).map { GardenSky.sparkle(index: i, time: Double($0) * 0.31) } }
check(sparkles.allSatisfy { $0.x * $0.x + $0.y * $0.y <= 1 && $0.glow >= 0 && $0.glow <= 1 } && sparkles.contains { $0.glow > 0.8 } && sparkles.contains { $0.glow == 0 }, "i luccichii restano nell'acqua, a volte brillano e a volte no")
check(Set((0..<GardenSky.sparkleCount).map { GardenSky.sparkle(index: $0, time: 5).x }).count == GardenSky.sparkleCount, "ognuno nel suo punto")
let ripples = (0..<400).map { GardenSky.ripple(time: Double($0) * 0.23, seed: 0.3) }
check(ripples.allSatisfy { $0.phase >= 0 && $0.phase < 1 && $0.alpha >= 0 && $0.alpha <= 0.55 && abs($0.x) <= 0.5 && abs($0.y) <= 0.35 }, "il cerchio sull'acqua: nasce, cresce, svanisce, dentro l'acqua")
check(GardenSky.ripple(time: 1, seed: 0.3) == GardenSky.ripple(time: 1, seed: 0.3) && Set(ripples.map { $0.x }).count > 20, "e ogni volta nasce in un posto diverso")
check(GardenSky.smokeAmount(.winter) == 1 && GardenSky.smokeAmount(.summer) < GardenSky.smokeAmount(.spring) && GardenSky.smokeAmount(.spring) < GardenSky.smokeAmount(.autumn), "il camino fuma più d'inverno")
let puffs = (0..<GardenSky.smokeCount).flatMap { i in (0..<400).map { GardenSky.smoke(index: i, time: Double($0) * 0.17, wind: 1) } }
check(puffs.allSatisfy { $0.dy <= 0 && $0.dy >= -92 && $0.radius >= 3 && $0.radius <= 18 && $0.alpha >= 0 && $0.alpha <= 0.6 && abs($0.dx) < 45 }, "il fumo sale (fino a 92 punti), si allarga fino a 18 e svanisce")
check(Set((0..<GardenSky.smokeCount).map { GardenSky.smoke(index: $0, time: 3, wind: 1).dy }).count == GardenSky.smokeCount, "gli sbuffi sono a quote diverse")
check(GardenSky.smoke(index: 2, time: 4, wind: 1.0).dx > GardenSky.smoke(index: 2, time: 4, wind: 0.2).dx, "col vento il fumo si piega di più")
check(GardenSky.smoke(index: 0, time: 0, wind: 1).alpha < 0.05, "uno sbuffo nasce quasi invisibile")

// ---------------------------------------------------------------- da fare
section("Da fare: giorni e testi")
check(ToDoDay.isValid("2026-10-23") && ToDoDay.isValid("2028-02-29"), "giorni che esistono")
check(!ToDoDay.isValid("2026-02-30") && !ToDoDay.isValid("2026-13-01") && !ToDoDay.isValid("2027-02-29"), "giorni che non esistono")
check(!ToDoDay.isValid("26-10-23") && !ToDoDay.isValid("2026-1-3") && !ToDoDay.isValid("2026/10/23") && !ToDoDay.isValid("") && !ToDoDay.isValid("abcd-ef-gh"),
      "il formato è solo AAAA-MM-GG")
check(ToDoDay.days(from: "2026-10-20", to: "2026-10-23") == 3 && ToDoDay.days(from: "2026-10-20", to: "2026-10-19") == -1, "giorni tra due date")
check(ToDoDay.days(from: "2026-12-30", to: "2027-01-02") == 3 && ToDoDay.days(from: "2028-02-28", to: "2028-03-01") == 2, "a cavallo di anno e febbraio bisestile")
check(ToDoDay.days(from: "2026-10-20", to: "boh") == nil, "una data non valida non ha distanza")
check(ToDoDay.adding(days: 7, to: "2026-10-20") == "2026-10-27" && ToDoDay.adding(days: 12, to: "2026-12-25") == "2027-01-06", "somma di giorni")
check(ToDoDay.string(for: date(2026, 10, 20, 23, 30), calendar: cal) == "2026-10-20", "il giorno sull'orologio del computer, non in UTC")
let todoToday = "2026-10-20"          // un martedì
check(ToDoDay.label(due: "2026-10-19", today: todoToday) == "ieri" && ToDoDay.label(due: todoToday, today: todoToday) == "oggi"
      && ToDoDay.label(due: "2026-10-21", today: todoToday) == "domani", "ieri, oggi, domani")
check(ToDoDay.label(due: "2026-10-23", today: todoToday) == "ven 23" && ToDoDay.label(due: "2026-10-26", today: todoToday) == "lun 26", "entro la settimana: giorno e numero")
check(ToDoDay.label(due: "2026-10-27", today: todoToday) == "27 ott" && ToDoDay.label(due: "2026-10-18", today: todoToday) == "18 ott", "oltre la settimana, o scaduta da più di un giorno")
check(ToDoDay.label(due: "2027-01-05", today: todoToday) == "5 gen 2027", "un altro anno si scrive")
check(ToDoDay.date(from: "2026-10-23").map { ToDoDay.string(for: $0, calendar: ToDoDay.calendar()) } == "2026-10-23" && ToDoDay.date(from: "2026-02-30") == nil,
      "da un giorno si torna al giorno")
check(ToDoText.clean("  comprare   il libro \t\n di anatomia ") == "comprare il libro di anatomia", "il testo si pulisce")
check(ToDoText.clean("   ") == nil && ToDoText.clean(nil) == nil, "testo vuoto = niente")
check(ToDoText.clean(String(repeating: "è", count: 300))?.count == ToDoText.maxLength, "testo accorciato a \(ToDoText.maxLength)")

section("Da fare: la lista")
let todoDir = tempDirectory()
var todoClock = date(2026, 10, 20, 9, 0)
let todo = ToDoList(directory: todoDir, now: { todoClock })
check(todo.items.isEmpty && todo.openCount == 0 && !FileManager.default.fileExists(atPath: todoDir.appendingPathComponent("dafare.json").path),
      "all'inizio è vuota e non scrive niente")
check(todo.add(text: "   ") == .empty && todo.items.isEmpty, "una voce vuota non si aggiunge")
guard case .added(let todoFirst) = todo.add(text: "  Esercizi di analisi  4–6 ", due: "2026-10-21", subject: " Analisi ") else { fatalError("add") }
check(todoFirst.text == "Esercizi di analisi 4–6" && todoFirst.due == "2026-10-21" && todoFirst.subject == "Analisi" && !todoFirst.isDone, "voce con scadenza e materia, pulite")
guard case .added(let todoSecond) = todo.add(text: "Cercare un libro per Storia", due: "2026-02-30", subject: "   ") else { fatalError("add") }
check(todoSecond.due == nil && todoSecond.subject == nil, "scadenza che non esiste e materia vuota: tolte")
todoClock += 60
_ = todo.add(text: "Consegnare il modulo", due: "2026-10-19")
todoClock += 60
_ = todo.add(text: "Riassunto del capitolo 7", due: "2026-10-20", subject: "Anatomia")
todoClock += 60
_ = todo.add(text: "Relazione di laboratorio", due: "2026-10-26", subject: "Fisica")
todoClock += 60
_ = todo.add(text: "Prenotare l'esame", due: "2026-10-20", subject: "Fisiologia")
check(todo.openCount == 6, "sei voci da fare")
let todoGroups = todo.sections(today: todoToday)
check(todoGroups.map(\.group) == [.overdue, .today, .upcoming, .noDate], "i gruppi, nell'ordine: scadute, oggi, prossime, senza data")
check(todoGroups[0].items.map(\.text) == ["Consegnare il modulo"], "scadute")
check(todoGroups[1].items.map(\.text) == ["Riassunto del capitolo 7", "Prenotare l'esame"], "oggi: la più vecchia per prima")
check(todoGroups[2].items.map(\.text) == ["Esercizi di analisi 4–6", "Relazione di laboratorio"], "prossime: la scadenza più vicina per prima")
check(todoGroups[3].items.map(\.text) == ["Cercare un libro per Storia"], "senza data")
check(todo.sections(today: "2026-10-25").map { $0.items.count } == [4, 1, 1], "con un altro giorno cambia tutto: 4 scadute, 1 prossima, 1 senza data")

// modificare una voce: testo, scadenza e materia; il resto non cambia
check(todo.update(id: todoFirst.id, text: "  Esercizi di analisi 7–9 ", due: "2026-10-30", subject: " Analisi  matematica ") == .updated, "una voce si modifica")
let todoEdited = todo.items.first { $0.id == todoFirst.id }
check(todoEdited?.text == "Esercizi di analisi 7–9" && todoEdited?.due == "2026-10-30" && todoEdited?.subject == "Analisi matematica"
      && todoEdited?.createdAt == todoFirst.createdAt && todoEdited?.isDone == false, "modificata: testo, scadenza e materia puliti; il resto resta")
check(todo.update(id: todoFirst.id, text: "Esercizi di analisi 7–9", due: nil, subject: nil) == .updated
      && todo.items.first { $0.id == todoFirst.id }?.due == nil && todo.items.first { $0.id == todoFirst.id }?.subject == nil, "si può togliere la scadenza e la materia")
check(todo.update(id: todoFirst.id, text: "   ", due: "2026-10-30", subject: nil) == .empty
      && todo.items.first { $0.id == todoFirst.id }?.text == "Esercizi di analisi 7–9", "un testo vuoto non cambia niente")
check(todo.update(id: todoFirst.id, text: "x", due: "2026-02-30", subject: nil) == .updated
      && todo.items.first { $0.id == todoFirst.id }?.due == nil, "una data che non esiste si toglie")
check(todo.update(id: UUID(), text: "boh", due: nil, subject: nil) == .missing, "una voce che non c'è non si modifica")
_ = todo.update(id: todoFirst.id, text: "Esercizi di analisi 4–6", due: "2026-10-21", subject: "Analisi")
check(ToDoList(directory: todoDir, now: { todoClock }).items.first { $0.id == todoFirst.id }?.subject == "Analisi", "la modifica si salva")

// «Hai finito?» a fine focus: segnare fatta una voce ancora da fare
check(todo.markDone(id: todoFirst.id) == true && todo.items.first { $0.id == todoFirst.id }?.doneAt == todoClock, "una voce da fare si segna come fatta")
check(todo.markDone(id: todoFirst.id) == false, "se è già fatta non cambia niente (e non cambia l'ora)")
check(todo.markDone(id: UUID()) == false, "una voce che non c'è non si segna")
todo.toggleDone(id: todoFirst.id)
check(todo.items.first { $0.id == todoFirst.id }?.isDone == false, "(si rimette da fare per le prove che seguono)")
check(ToDoReminder.finishedQuestion(for: todoFirst) == "Hai finito «Esercizi di analisi 4–6»?", "la domanda a fine focus")
let longItem = ToDoItem(id: UUID(), text: String(repeating: "parola ", count: 20), due: nil, subject: nil, createdAt: Date(), doneAt: nil)
check(ToDoReminder.finishedQuestion(for: longItem) == "Hai finito «parola parola parola parola parola…»?", "la domanda accorcia il testo lungo a una parola intera")
check((0..<3).allSatisfy { ToDoReminder.doneMessage(for: todoFirst, variant: $0).contains("«Esercizi di analisi 4–6»") }
      && ToDoReminder.doneMessage(for: todoFirst, variant: 3) == ToDoReminder.doneMessage(for: todoFirst, variant: 0)
      && !ToDoReminder.doneMessage(for: todoFirst, variant: -1).isEmpty, "le frasi per «Fatta» nominano la voce, e la variante è sempre valida")

let todoReloaded = ToDoList(directory: todoDir, now: { todoClock })
check(todoReloaded.items == todo.items, "riaprendo la lista, le voci sono quelle")
let todoText = (try? String(contentsOf: todoDir.appendingPathComponent("dafare.json"), encoding: .utf8)) ?? ""
check(todoText.contains("\"version\" : 1") && todoText.contains("\"due\" : \"2026-10-21\"") && todoText.contains("\"createdAt\" : \"2026-10-20T07:00:00Z\""),
      "il file: versione, scadenza «AAAA-MM-GG», date ISO 8601")
check(!todoText.contains("\"doneAt\""), "senza «fatta» il campo non c'è")

todo.toggleDone(id: todoFirst.id)
check(todo.openCount == 5 && todo.doneItems.map(\.id) == [todoFirst.id] && todo.sections(today: todoToday).flatMap(\.items).allSatisfy { $0.id != todoFirst.id },
      "una voce fatta esce dalla lista e va tra le fatte")
check(ToDoList(directory: todoDir, now: { todoClock }).doneItems.first?.doneAt == todoClock, "«fatta» si salva, con l'ora")
todo.toggleDone(id: todoFirst.id)
check(todo.openCount == 6 && todo.doneItems.isEmpty, "si può rimettere da fare")
todo.remove(id: todoSecond.id)
check(todo.openCount == 5 && todo.items.allSatisfy { $0.id != todoSecond.id }, "si toglie una voce")
todo.remove(id: UUID())
check(todo.openCount == 5, "togliere una voce che non c'è non fa niente")

// le voci fatte spariscono dopo una settimana
todo.toggleDone(id: todoFirst.id)
todoClock += 6 * 86_400
check(ToDoList(directory: todoDir, now: { todoClock }).doneItems.count == 1, "dopo 6 giorni la voce fatta c'è ancora")
todoClock += 2 * 86_400
let todoPurged = ToDoList(directory: todoDir, now: { todoClock })
check(todoPurged.doneItems.isEmpty && todoPurged.openCount == 4, "dopo 8 giorni la voce fatta è sparita, le altre no")

// il limite
let todoFullDir = tempDirectory()
let todoFull = ToDoList(directory: todoFullDir)
for i in 0..<ToDoList.maxItems { _ = todoFull.add(text: "voce \(i)") }
check(todoFull.add(text: "una di troppo") == .full && todoFull.items.count == ToDoList.maxItems, "al massimo \(ToDoList.maxItems) voci")

// file di altre versioni e rovinati
let todoDirtyDir = tempDirectory()
let todoDirty = """
{
  "version" : 1,
  "items" : [
    { "id" : "00000000-0000-4000-8000-000000000001", "text" : "  vuota   da pulire ", "due" : "2026-02-31", "subject" : "  ", "createdAt" : "2026-10-14T07:00:00Z" },
    { "id" : "00000000-0000-4000-8000-000000000002", "text" : "   ", "createdAt" : "2026-10-14T07:00:00Z" },
    { "id" : "00000000-0000-4000-8000-000000000003", "text" : "ok", "due" : "2026-10-30", "subject" : "Fisica", "createdAt" : "2026-10-14T07:00:00Z", "doneAt" : "2026-10-15T07:00:00Z" }
  ]
}
"""
try? todoDirty.write(to: todoDirtyDir.appendingPathComponent("dafare.json"), atomically: true, encoding: .utf8)
let todoCleaned = ToDoList(directory: todoDirtyDir, now: { date(2026, 10, 20, 9, 0) })
check(todoCleaned.items.count == 2 && todoCleaned.items[0].text == "vuota da pulire" && todoCleaned.items[0].due == nil && todoCleaned.items[0].subject == nil,
      "letta da file: testo pulito, scadenza inesistente tolta, voce vuota scartata")
check(todoCleaned.items[1].isDone && todoCleaned.items[1].due == "2026-10-30", "letta da file: voce fatta e scadenza buona restano")

let todoNewerDir = tempDirectory()
try? "{ \"version\": 9, \"items\": [ { \"id\": \"00000000-0000-4000-8000-000000000001\", \"text\": \"dal futuro\", \"createdAt\": \"2026-10-14T07:00:00Z\" } ] }"
    .write(to: todoNewerDir.appendingPathComponent("dafare.json"), atomically: true, encoding: .utf8)
var todoNewerProblems: [String] = []
let todoNewer = ToDoList(directory: todoNewerDir)
todoNewer.onProblem = { todoNewerProblems.append($0) }
_ = todoNewer.add(text: "non deve scrivere")
check(todoNewer.isReadOnly && todoNewer.items.count == 2 && todoNewerProblems.count == 1, "file più nuovo: si legge, non si riscrive, un avviso")
check(((try? String(contentsOf: todoNewerDir.appendingPathComponent("dafare.json"), encoding: .utf8)) ?? "").contains("dal futuro")
      && !((try? String(contentsOf: todoNewerDir.appendingPathComponent("dafare.json"), encoding: .utf8)) ?? "").contains("non deve scrivere"), "il file più nuovo è intatto")

let todoBrokenDir = tempDirectory()
try? "questo non è json".write(to: todoBrokenDir.appendingPathComponent("dafare.json"), atomically: true, encoding: .utf8)
var todoBrokenProblems: [String] = []
let todoBroken = ToDoList(directory: todoBrokenDir)
todoBroken.onProblem = { todoBrokenProblems.append($0) }
check(todoBroken.items.isEmpty && todoBrokenProblems.count == 1 && !FileManager.default.fileExists(atPath: todoBrokenDir.appendingPathComponent("dafare.json").path)
      && ((try? FileManager.default.contentsOfDirectory(atPath: todoBrokenDir.path)) ?? []).contains { $0.hasPrefix("dafare.corrotto-") },
      "file rovinato: messo da parte e si riparte da vuoto, con un avviso")
_ = todoBroken.add(text: "di nuovo")
check(ToDoList(directory: todoBrokenDir).items.count == 1, "dopo un file rovinato si scrive di nuovo")

section("Da fare: il compagno ricorda le scadenze")
func reminderItem(_ text: String, due: String?, done: Bool = false, n: Int = 0) -> ToDoItem {
    ToDoItem(id: UUID(), text: text, due: due, subject: nil, createdAt: Date(timeIntervalSince1970: 1_760_000_000 + Double(n)), doneAt: done ? Date() : nil)
}
check(ToDoReminder.message(for: [], today: "2026-10-20") == nil, "niente voci: niente da dire")
check(ToDoReminder.message(for: [reminderItem("Consegnare il modulo", due: "2026-10-19"), reminderItem("Senza data", due: nil),
                                 reminderItem("Tra una settimana", due: "2026-10-27")], today: "2026-10-20") == nil,
      "scadute, senza data o lontane: non se ne parla")
check(ToDoReminder.message(for: [reminderItem("Esercizi di analisi", due: "2026-10-21")], today: "2026-10-20")
      == "Domani scade «Esercizi di analisi». Un focus adesso?", "una scadenza domani")
check(ToDoReminder.message(for: [reminderItem("Prenotare l'esame", due: "2026-10-20")], today: "2026-10-20")
      == "Oggi scade «Prenotare l'esame». Un focus adesso?", "una scadenza oggi")
check(ToDoReminder.message(for: [reminderItem("Per domani", due: "2026-10-21"), reminderItem("Per oggi", due: "2026-10-20")], today: "2026-10-20")
      == "Oggi scade «Per oggi». Un focus adesso?", "se ci sono sia oggi sia domani, si dice oggi")
check(ToDoReminder.message(for: [reminderItem("Prima", due: "2026-10-20", n: 1), reminderItem("Seconda", due: "2026-10-20", n: 2)], today: "2026-10-20")
      == "Oggi scadono 2 cose: «Prima» e un'altra.", "due oggi: la più vecchia e «un'altra»")
check(ToDoReminder.message(for: [reminderItem("A", due: "2026-10-21", n: 3), reminderItem("B", due: "2026-10-21", n: 1), reminderItem("C", due: "2026-10-21", n: 2)],
                           today: "2026-10-20") == "Domani scadono 3 cose: «B» e altre 2.", "tre domani: la più vecchia e «altre 2»")
check(ToDoReminder.message(for: [reminderItem("Fatta", due: "2026-10-20", done: true)], today: "2026-10-20") == nil, "le voci fatte non si ricordano")
let longReminder = ToDoReminder.message(for: [reminderItem(String(repeating: "parola ", count: 20), due: "2026-10-20")], today: "2026-10-20") ?? ""
check(longReminder == "Oggi scade «parola parola parola parola parola…». Un focus adesso?", "un testo lungo si accorcia a una parola intera")
check(ToDoReminder.message(for: [reminderItem("Ultimo dell'anno", due: "2027-01-01")], today: "2026-12-31") == "Domani scade «Ultimo dell'anno». Un focus adesso?",
      "domani a cavallo d'anno")

section("Frasi di contesto: saluti, numeri e traguardi")
func rkSession(_ m: Int, _ d: Int, _ h: Int = 10, seconds: Int = 3000, y: Int = 2026) -> StudySession {
    StudySession(start: date(y, m, d, h), localStart: StudySession.localString(for: date(y, m, d, h), calendar: cal),
                 seconds: seconds, plannedMinutes: 50, completed: true, subject: "Anatomia")
}
func rkContext(_ now: Date, name: String? = "Jacopo", sessions: [StudySession] = [], todos: Int = 0, due: String? = nil) -> Remarks.Context {
    Remarks.Context(now: now, calendar: cal, name: name, sessions: sessions, openTodoCount: todos, due: due)
}
let rkTuesdayMorning = date(2026, 10, 20, 9)
check([4, 5, 11, 12, 17, 18, 22, 23, 0].map { Remarks.dayPart(hour: $0) } == [.night, .morning, .morning, .afternoon, .afternoon, .evening, .evening, .night, .night],
      "le fasce della giornata")
check(Remarks.launchGreeting(rkContext(rkTuesdayMorning), variant: 0).text == "Buongiorno, Jacopo! Si comincia quando vuoi.", "saluto del mattino con il nome")
check(Remarks.launchGreeting(rkContext(rkTuesdayMorning, name: nil), variant: 0).text == "Buongiorno! Si comincia quando vuoi.", "senza nome")
check(Remarks.launchGreeting(rkContext(date(2026, 10, 20, 15)), variant: 0).text.hasPrefix("Buon pomeriggio, Jacopo!"), "saluto del pomeriggio")
check(Remarks.launchGreeting(rkContext(date(2026, 10, 20, 20)), variant: 0).text.hasPrefix("Buonasera, Jacopo!"), "saluto della sera")
check(Remarks.launchGreeting(rkContext(date(2026, 10, 18, 10)), variant: 0).text.hasPrefix("Buona domenica, Jacopo!"), "la domenica")
check(Remarks.launchGreeting(rkContext(date(2026, 10, 20, 0, 30)), variant: 0).text == "Jacopo, è tardi. Un ultimo focus e poi a dormire?", "di notte")
check(Remarks.launchGreeting(rkContext(date(2026, 10, 20, 0, 30), name: nil), variant: 0).text == "È tardi. Un ultimo focus e poi a dormire?", "di notte, senza nome")
check(Remarks.launchGreeting(rkContext(date(2026, 10, 20, 0, 30)), variant: 1).text.contains("riposo"), "di notte, un'altra frase")
check(Remarks.launchGreeting(rkContext(rkTuesdayMorning, sessions: [rkSession(10, 19)]), variant: 0).text == "Buongiorno, Jacopo! Ieri hai studiato 50 min: si riparte?",
      "ieri hai studiato, oggi ancora no")
check(Remarks.launchGreeting(rkContext(date(2026, 10, 20, 15), sessions: [rkSession(10, 20, 9)]), variant: 0).text == "Buon pomeriggio, Jacopo! Oggi hai già studiato 50 min.",
      "oggi hai già studiato")
let rkStreak = [rkSession(10, 17), rkSession(10, 18), rkSession(10, 19)]
let rkLines = (0..<3).map { Remarks.launchGreeting(rkContext(rkTuesdayMorning, sessions: rkStreak, todos: 2), variant: $0).text }
check(rkLines == ["Buongiorno, Jacopo! Ieri hai studiato 50 min: si riparte?", "Buongiorno, Jacopo! Sei a 3 giorni di fila.", "Buongiorno, Jacopo! Hai 2 cose da fare."],
      "ieri, la serie e le cose da fare: una per volta (\(rkLines))")
check(Remarks.launchGreeting(rkContext(rkTuesdayMorning, sessions: rkStreak, todos: 2), variant: 3).text == rkLines[0]
      && !Remarks.launchGreeting(rkContext(rkTuesdayMorning, todos: 1), variant: -1).text.isEmpty, "la variante rientra sempre")
check(Remarks.launchGreeting(rkContext(rkTuesdayMorning, todos: 1), variant: 0).text == "Buongiorno, Jacopo! Hai 1 cosa da fare.", "una sola cosa da fare")
let rkDue = "Oggi scade «Esercizi di analisi». Un focus adesso?"
let rkWithDue = Remarks.launchGreeting(rkContext(rkTuesdayMorning, todos: 3, due: rkDue), variant: 2)
check(rkWithDue.text == "Buongiorno, Jacopo! \(rkDue)" && rkWithDue.coversReminder, "se scade qualcosa, è la prima cosa che dice (e non va ripetuta)")
check(!Remarks.launchGreeting(rkContext(rkTuesdayMorning), variant: 0).coversReminder, "senza scadenze non copre il promemoria")

check(Remarks.wakeGreeting(rkContext(rkTuesdayMorning), away: 1800, variant: 0) == nil, "meno di un'ora di sleep: nessun saluto")
check(Remarks.wakeGreeting(rkContext(rkTuesdayMorning), away: 7200, variant: 0)?.text == "Rieccoti!", "dopo un po', «Rieccoti!»")
check(Remarks.wakeGreeting(rkContext(rkTuesdayMorning), away: 7200, variant: 1)?.text == "Eccoti di nuovo!", "e un'altra variante")
check(Remarks.wakeGreeting(rkContext(rkTuesdayMorning, todos: 3), away: 7200, variant: 0)?.text == "Rieccoti! Hai 3 cose da fare.", "con le cose da fare")
check(Remarks.wakeGreeting(rkContext(date(2026, 10, 20, 15), sessions: [rkSession(10, 20, 9)], todos: 3), away: 7200, variant: 0)?.text == "Rieccoti! Oggi sei a 50 min.",
      "con lo studio di oggi")
check(Remarks.wakeGreeting(rkContext(rkTuesdayMorning, due: rkDue), away: 7200, variant: 0)?.coversReminder == true, "e con una scadenza")

// il riepilogo della settimana (lunedì–mercoledì)
let rkWeek = [rkSession(10, 12, 9, seconds: 3600), rkSession(10, 14, 15, seconds: 7800), rkSession(10, 16, 11, seconds: 1800)]
let rkMonday = date(2026, 10, 19, 9)
let rkRecap = Remarks.weeklyRecap(rkContext(rkMonday, sessions: rkWeek))
check(rkRecap?.key == "2026-10-12" && rkRecap?.text == "Settimana scorsa: 3 h 40 in 3 giorni, 3 focus. Il giorno più forte: mercoledì (2 h 10).",
      "riepilogo della settimana scorsa (\(rkRecap?.text ?? "nil"))")
check(Remarks.weeklyRecap(rkContext(date(2026, 10, 21, 9), sessions: rkWeek))?.key == "2026-10-12", "ancora fino al mercoledì")
check(Remarks.weeklyRecap(rkContext(date(2026, 10, 22, 9), sessions: rkWeek)) == nil && Remarks.weeklyRecap(rkContext(date(2026, 10, 18, 9), sessions: rkWeek)) == nil,
      "da giovedì a domenica non lo dice")
check(Remarks.weeklyRecap(rkContext(rkMonday, sessions: [rkSession(10, 20)])) == nil && Remarks.weeklyRecap(rkContext(rkMonday)) == nil, "se la settimana scorsa non hai studiato: niente")
check(Remarks.weeklyRecap(rkContext(rkMonday, sessions: [rkSession(10, 14, 15, seconds: 7800)]))?.text == "Settimana scorsa: 2 h 10 in 1 giorno, 1 focus.", "un giorno solo: niente «giorno più forte»")
check(Remarks.weeklyRecap(rkContext(rkMonday, sessions: [rkSession(10, 15, 9, seconds: 3600), rkSession(10, 13, 9, seconds: 3600)]))?.text.contains("martedì") == true, "a pari merito, il giorno prima")

let rkInsight = Remarks.insight(rkContext(rkTuesdayMorning, sessions: many), variant: 0)
check(rkInsight == found[0] && Remarks.insight(rkContext(rkTuesdayMorning, sessions: many), variant: found.count) == found[0]
      && Remarks.insight(rkContext(rkTuesdayMorning), variant: 0) == nil, "una frase «quando rendi meglio», se ce n'è")

// i traguardi
func rkDays(_ days: [Int], month: Int = 10) -> [StudySession] { days.map { rkSession(month, $0) } }
check(Remarks.milestone(before: rkDays([17, 18]), after: rkDays([17, 18, 19]), now: date(2026, 10, 19, 12), calendar: cal) == "Tre giorni di fila!", "tre giorni di fila")
check(Remarks.milestone(before: rkDays([17, 18, 19]), after: rkDays([17, 18, 19]) + [rkSession(10, 19, 14)], now: date(2026, 10, 19, 16), calendar: cal) == nil,
      "un altro focus lo stesso giorno: niente")
check(Remarks.milestone(before: rkDays([13, 14, 15, 16, 17, 18]), after: rkDays([13, 14, 15, 16, 17, 18, 19]), now: date(2026, 10, 19, 12), calendar: cal)
      == "Sette giorni di fila! Una settimana intera.", "sette giorni di fila")
let rkSameDay = (0..<9).map { rkSession(9, 1, 8 + $0 / 3, seconds: 600 + $0) }
check(Remarks.milestone(before: rkSameDay, after: rkSameDay + [rkSession(9, 1, 20, seconds: 600)], now: date(2026, 9, 1, 21), calendar: cal) == "10 focus insieme!", "il decimo focus")
let rkFifty = (0..<49).map { rkSession(8, 1 + $0 / 3, 8 + $0 % 3, seconds: 600) }
check(Remarks.milestone(before: rkFifty, after: rkFifty + [rkSession(9, 20, 9, seconds: 600)], now: date(2026, 9, 20, 10), calendar: cal) == "50 focus: un traguardo tondo!", "il cinquantesimo focus")
check(Remarks.milestone(before: [rkSession(9, 1, 8, seconds: 35_940)], after: [rkSession(9, 1, 8, seconds: 35_940), rkSession(9, 20, 9, seconds: 120)], now: date(2026, 9, 20, 10), calendar: cal)
      == "10 ore di studio insieme!", "le prime dieci ore")
check(Remarks.milestone(before: [rkSession(7, 1, 8, seconds: 359_400)], after: [rkSession(7, 1, 8, seconds: 359_400), rkSession(9, 20, 9, seconds: 1200)], now: date(2026, 9, 20, 10), calendar: cal)
      == "100 ore passate insieme a me. Grazie!", "le cento ore")
check(Remarks.milestone(before: rkDays([17, 18]) + (0..<7).map { rkSession(9, 1, 8, seconds: 600 + $0) }, after: rkDays([17, 18, 19]) + (0..<7).map { rkSession(9, 1, 8, seconds: 600 + $0) },
                        now: date(2026, 10, 19, 12), calendar: cal) == "Tre giorni di fila!", "se ne scattano due insieme, vince la serie")
check(Remarks.milestone(before: [rkSession(9, 19)], after: [rkSession(9, 19), rkSession(10, 19)], now: date(2026, 10, 19, 12), calendar: cal) == "Oggi è un mese che studiamo insieme.", "un mese insieme")
check(Remarks.milestone(before: [rkSession(9, 19), rkSession(10, 19, 8)], after: [rkSession(9, 19), rkSession(10, 19, 8), rkSession(10, 19, 14)], now: date(2026, 10, 19, 16), calendar: cal) == nil,
      "l'anniversario si dice solo al primo focus del giorno")
check(Remarks.milestone(before: [rkSession(10, 19, y: 2025)], after: [rkSession(10, 19, y: 2025), rkSession(10, 19)], now: date(2026, 10, 19, 12), calendar: cal) == "Oggi è un anno che studiamo insieme!", "un anno")
check(Remarks.milestone(before: [rkSession(10, 19, y: 2024)], after: [rkSession(10, 19, y: 2024), rkSession(10, 19)], now: date(2026, 10, 19, 12), calendar: cal) == "Oggi sono 2 anni che studiamo insieme!", "due anni")
check(Remarks.milestone(before: [rkSession(7, 19)], after: [rkSession(7, 19), rkSession(10, 19)], now: date(2026, 10, 19, 12), calendar: cal) == "Oggi sono 3 mesi che studiamo insieme.", "tre mesi")
check(Remarks.milestone(before: [rkSession(9, 5)], after: [rkSession(9, 5), rkSession(10, 19)], now: date(2026, 10, 19, 12), calendar: cal) == nil, "un giorno qualunque: niente")
check(Remarks.milestone(before: [rkSession(1, 31)], after: [rkSession(1, 31), rkSession(2, 28)], now: date(2026, 2, 28, 12), calendar: cal) == "Oggi è un mese che studiamo insieme.",
      "un mese insieme, anche se il primo focus era un 31")
check(Remarks.milestone(before: [rkSession(1, 31)], after: [rkSession(1, 31), rkSession(4, 30)], now: date(2026, 4, 30, 12), calendar: cal) == "Oggi sono 3 mesi che studiamo insieme.",
      "tre mesi, dal 31 gennaio al 30 aprile")

// ---------------------------------------------------------------- anno
section("Anno: mappa, numeri e andamento")
func yrSession(_ m: Int, _ d: Int, _ h: Int = 10, seconds: Int = 3000, y: Int = 2026, subject: String? = "Anatomia") -> StudySession {
    StudySession(start: date(y, m, d, h), localStart: StudySession.localString(for: date(y, m, d, h), calendar: cal),
                 seconds: seconds, plannedMinutes: 50, completed: true, subject: subject)
}
let yr2026 = StudyPeriod.containing(date(2026, 10, 22, 12), kind: .year, calendar: cal)
check(PeriodKind.year.rawValue == 3 && yr2026.start == date(2026, 1, 1) && yr2026.end == date(2027, 1, 1), "il periodo «anno»: dal 1 gennaio all'anno dopo")
check(yr2026.shifted(by: -1, calendar: cal).start == date(2025, 1, 1) && yr2026.shifted(by: 1, calendar: cal).start == date(2027, 1, 1), "l'anno prima e quello dopo")
check(StudyStats.summary(sessions: [], period: yr2026, calendar: cal).buckets.count == 365
      && StudyStats.summary(sessions: [], period: StudyPeriod.containing(date(2024, 5, 1), kind: .year, calendar: cal), calendar: cal).buckets.count == 366,
      "una barra per giorno: 365, o 366 in un anno bisestile")

check([0, 1, 1799, 1800, 5399, 5400, 10799, 10800, 40_000].map { YearStats.level(seconds: $0) } == [0, 1, 1, 2, 2, 3, 3, 4, 4], "i livelli di colore (soglie a 30, 90 e 180 minuti)")

let yrSessions = [yrSession(10, 12, 9, seconds: 1800), yrSession(10, 12, 15, seconds: 3000), yrSession(10, 13, 10, seconds: 600), yrSession(10, 14, 10, seconds: 1500),
                  yrSession(3, 3, 10, seconds: 7200, subject: "Chimica"), yrSession(3, 4, 10, seconds: 1000, subject: "chimica"),
                  yrSession(12, 31, 23, seconds: 3000, y: 2025), yrSession(1, 2, 8, seconds: 900, y: 2026, subject: nil)]
let yrDays = YearStats.days(sessions: yrSessions, period: yr2026, calendar: cal)
check(yrDays.count == 365 && yrDays.first?.start == date(2026, 1, 1) && yrDays.last?.start == date(2026, 12, 31), "un elemento per ogni giorno dell'anno")
let yrOct12 = yrDays.first { $0.start == date(2026, 10, 12) }
check(yrOct12 == YearStats.Day(start: date(2026, 10, 12), seconds: 4800, focusCount: 2, level: 2), "un giorno con due focus: 80 minuti, livello 2 (\(String(describing: yrOct12)))")
check(yrDays.first { $0.start == date(2026, 1, 2) }?.level == 1 && yrDays.first { $0.start == date(2026, 1, 3) }?.level == 0, "un focus breve è il livello 1; senza studio è 0")
check(yrDays.reduce(0) { $0 + $1.seconds } == 1800 + 3000 + 600 + 1500 + 7200 + 1000 + 900, "una sessione del 31 dicembre dell'anno prima non conta")

// la griglia: una colonna per settimana (da lunedì), una riga per giorno
check(YearStats.cell(of: date(2026, 1, 1), in: yr2026, calendar: cal) == (0, 3) && YearStats.cell(of: date(2026, 1, 5), in: yr2026, calendar: cal) == (1, 0),
      "il 1 gennaio 2026 è un giovedì (colonna 0, riga 3); il lunedì dopo apre la colonna 1")
check(YearStats.cell(of: date(2026, 12, 31), in: yr2026, calendar: cal) == (52, 3) && YearStats.columns(of: yr2026, calendar: cal) == 53, "53 colonne nel 2026")
check(YearStats.columns(of: StudyPeriod.containing(date(2012, 6, 1), kind: .year, calendar: cal), calendar: cal) == 54, "54 in un anno bisestile che comincia di domenica (il 2012)")
check(YearStats.columns(of: StudyPeriod.containing(date(2028, 6, 1), kind: .year, calendar: cal), calendar: cal) == 53, "53 nel 2028 (bisestile, comincia di sabato)")
let yrMonths = YearStats.monthStarts(in: yr2026, calendar: cal)
check(yrMonths.count == 12 && yrMonths.first == YearStats.MonthMark(month: 1, column: 0) && yrMonths.last?.month == 12, "dodici mesi")
check(yrMonths.first { $0.month == 2 }?.column == 4 && yrMonths.first { $0.month == 10 }?.column == 39, "febbraio nella colonna 4, ottobre nella 39")

// i tre numeri
let yrHighlights = YearStats.highlights(sessions: yrSessions, period: yr2026, now: date(2026, 10, 22, 12), calendar: cal)
check(yrHighlights.studiedDays == 6, "giorni di studio: 6 (\(yrHighlights.studiedDays))")
check(yrHighlights.bestDay == StudyBucket(start: date(2026, 3, 3), seconds: 7200), "il giorno più forte")
check(yrHighlights.bestMonth == StudyBucket(start: date(2026, 3, 1), seconds: 8200), "il mese migliore: marzo (8200 s contro i 6900 di ottobre)")
check(yrHighlights.longestStreak == 3, "la serie più lunga: 12–14 ottobre (\(yrHighlights.longestStreak))")
let yrIce = YearStats.highlights(sessions: [yrSession(10, 12), yrSession(10, 13), yrSession(10, 15)], period: yr2026, now: date(2026, 10, 22, 12), calendar: cal)
check(yrIce.longestStreak == 3, "il giorno di ghiaccio non interrompe la serie")
let yrTie = YearStats.highlights(sessions: [yrSession(5, 20, seconds: 3600), yrSession(2, 10, seconds: 3600)], period: yr2026, now: date(2026, 10, 22, 12), calendar: cal)
check(yrTie.bestDay?.start == date(2026, 2, 10) && yrTie.bestMonth?.start == date(2026, 2, 1), "a pari merito, il primo")
check(YearStats.highlights(sessions: [], period: yr2026, now: date(2026, 10, 22, 12), calendar: cal) == YearStats.Highlights(), "senza studio, niente")

// l'andamento per settimana
let yrThrough = date(2026, 10, 22, 12)
let yrAll = YearStats.weeklyTrend(sessions: yrSessions, period: yr2026, subject: nil, through: yrThrough, calendar: cal)
check(yrAll.count == 43 && yrAll.first?.start == date(2025, 12, 29) && yrAll.last?.start == date(2026, 10, 19), "43 settimane fino a oggi, la prima da lunedì 29 dicembre (\(yrAll.count))")
check(yrAll.first?.seconds == 900, "la prima settimana prende i giorni dell'anno nuovo (2 gennaio) e non quelli dell'anno prima")
check(yrAll.first { $0.start == date(2026, 10, 12) }?.seconds == 1800 + 3000 + 600 + 1500, "la settimana del 12 ottobre")
let yrChemistry = YearStats.weeklyTrend(sessions: yrSessions, period: yr2026, subject: "CHIMICA", through: yrThrough, calendar: cal)
check(yrChemistry.first { $0.start == date(2026, 3, 2) }?.seconds == 8200 && yrChemistry.reduce(0) { $0 + $1.seconds } == 8200, "una materia: scritture diverse della stessa contano insieme")
check(YearStats.weeklyTrend(sessions: yrSessions, period: yr2026, subject: "Fisica", through: yrThrough, calendar: cal).allSatisfy { $0.seconds == 0 }, "una materia mai studiata: tutto a zero")
check(YearStats.weeklyTrend(sessions: yrSessions, period: yr2026, subject: nil, through: date(2030, 1, 1), calendar: cal).count == 53, "un anno passato: tutte le 53 settimane")
let yrSummary = StudyStats.summary(sessions: yrSessions, period: yr2026, calendar: cal)
check(YearStats.trendSubjects(of: yrSummary) == ["Chimica", "Anatomia"] || YearStats.trendSubjects(of: yrSummary) == ["chimica", "Anatomia"], "le materie tra cui scegliere, senza «Senza materia» (\(YearStats.trendSubjects(of: yrSummary)))")
check(YearStats.trendSubjects(of: StudyStats.summary(sessions: [yrSession(3, 3)], period: yr2026, calendar: cal)).isEmpty, "con una materia sola non c'è da scegliere")
let yrMany = (0..<8).map { yrSession(3, 1 + $0, seconds: 600 * ($0 + 1), subject: "Materia \($0)") }
check(YearStats.trendSubjects(of: StudyStats.summary(sessions: yrMany, period: yr2026, calendar: cal)).count == YearStats.maxTrendSubjects, "al massimo cinque materie")
// i testi
check(YearStats.dayText(YearStats.Day(start: date(2026, 10, 2), seconds: 0, focusCount: 0, level: 0), calendar: cal) == "Venerdì 2 ottobre · nessun focus", "il testo di un giorno senza studio")
check(YearStats.dayText(YearStats.Day(start: date(2026, 10, 14), seconds: 7800, focusCount: 3, level: 3), calendar: cal) == "Mercoledì 14 ottobre · 2 h 10 · 3 focus", "il testo di un giorno")
check(YearStats.dayText(YearStats.Day(start: date(2026, 10, 14), seconds: 1500, focusCount: 1, level: 1), calendar: cal) == "Mercoledì 14 ottobre · 25 min · 1 focus", "un focus solo")
check(YearStats.weekText(StudyBucket(start: date(2026, 6, 29), seconds: 34_500), calendar: cal) == "Settimana del 29 giu · 9 h 35", "il testo di una settimana")
check(YearStats.trendCaption(maxSeconds: 55_800) == "al massimo 15 h 30 in una settimana", "la didascalia dell'andamento")
check(YearStats.tiles(yrHighlights, calendar: cal) == [YearStats.Tile(value: "3 giorni", caption: "la serie più lunga"),
                                                       YearStats.Tile(value: "2 h", caption: "il giorno più forte · 3 mar"),
                                                       YearStats.Tile(value: "Marzo", caption: "il mese migliore · 2 h 17")],
      "le tre caselle (\(YearStats.tiles(yrHighlights, calendar: cal)))")
check(YearStats.tiles(YearStats.Highlights(longestStreak: 1), calendar: cal) == [YearStats.Tile(value: "1 giorno", caption: "la serie più lunga")], "senza studio, la sola serie")
check((1...12).map { YearStats.monthLabel($0) }.joined(separator: " ") == "gen feb mar apr mag giu lug ago set ott nov dic", "i nomi dei mesi")
check(!YearStats.showsTrend([StudyBucket(start: date(2026, 1, 5), seconds: 600), StudyBucket(start: date(2026, 1, 12), seconds: 600), StudyBucket(start: date(2026, 1, 19), seconds: 600),
                             StudyBucket(start: date(2026, 1, 26), seconds: 0)])
      && YearStats.showsTrend((0..<4).map { StudyBucket(start: date(2026, 1, 5 + 7 * $0), seconds: 60) }), "l'andamento si mostra da quattro settimane con studio")

// ---------------------------------------------------------------- fumetto
section("Fumetto: dove sta")
let bpScreen = CGRect(x: 0, y: 0, width: 1512, height: 944)
func bpPet(x: CGFloat, y: CGFloat = 0, width: CGFloat = 84) -> CGRect { CGRect(x: x, y: y, width: width, height: 141) }
func bpPlace(_ size: CGSize, pet: CGRect, topY: CGFloat? = nil, obstacles: [CGRect] = [], previous: Bool? = nil) -> BubblePlacement.Result {
    BubblePlacement.place(bubble: size, anchorX: pet.midX, topY: topY ?? pet.minY + 70, pet: pet, screen: bpScreen, obstacles: obstacles, previousTailOnRight: previous)
}
let bpBubble = CGSize(width: 213, height: 174)
let bpCenter = bpPlace(bpBubble, pet: bpPet(x: 600))
check(bpCenter.layout == .above && bpCenter.tailOnRight && abs(bpCenter.tipX - 642) < 0.001, "al centro: sopra, con la punta sul compagno")
check(abs(bpCenter.origin.x - (642 - 213 * 0.825)) < 0.001 && bpCenter.origin.y == 64, "…e la punta entra di 6 pt nel disegno")
let bpLeft = bpPlace(bpBubble, pet: bpPet(x: 10))
check(bpLeft.layout == .above && !bpLeft.tailOnRight && abs(bpLeft.tipX - 52) <= BubblePlacement.tolerance && bpLeft.origin.x >= 6,
      "vicino al bordo sinistro il fumetto si specchia e la punta arriva al compagno (\(bpLeft))")
let bpRight = bpPlace(CGSize(width: 260, height: 174), pet: bpPet(x: 1400))
check(bpRight.tailOnRight && abs(bpRight.tipX - 1442) <= BubblePlacement.tolerance, "vicino al bordo destro basta la codina a destra")
check(bpPlace(bpBubble, pet: bpPet(x: 600), previous: false).tailOnRight == false, "se la codina stava a sinistra e va ancora bene, resta lì")
check(bpPlace(CGSize(width: 260, height: 174), pet: bpPet(x: 1400), previous: false).tailOnRight, "…ma se non arriva più, passa a destra")

// compagno in alto: sopra non c'è posto, il fumetto sta di fianco, intero nello schermo e senza coprirlo
let bpHigh = bpPet(x: 700, y: 780)
let bpSide = bpPlace(bpBubble, pet: bpHigh, topY: 780 + 70)
check(bpSide.layout == .besideLeft || bpSide.layout == .besideRight, "in alto: di fianco (\(bpSide.layout))")
let bpSideRect = CGRect(origin: bpSide.origin, size: bpBubble)
check(!bpSideRect.intersects(bpHigh) && bpScreen.insetBy(dx: 5, dy: 3).contains(bpSideRect), "…senza coprirlo e dentro lo schermo")
check(bpSideRect.minY <= 850 && bpSideRect.maxY >= 850, "…all'altezza della sua testa")
check(bpSide.tailOnRight == (bpSide.layout == .besideLeft), "…con la codina verso di lui")

// la scheda «Com'è andata?» a sinistra: il fumetto si apre dall'altra parte
let bpCard = CGRect(x: 600 - 412, y: 0, width: 400, height: 300)
let bpClear = bpPlace(bpBubble, pet: bpPet(x: 600), obstacles: [bpCard])
check(bpClear.layout == .above && !bpClear.tailOnRight, "con la scheda a sinistra la codina passa a sinistra")
check(!CGRect(origin: bpClear.origin, size: bpBubble).intersects(bpCard.insetBy(dx: -BubblePlacement.obstacleMargin, dy: -BubblePlacement.obstacleMargin)), "…e il fumetto non la copre")
let bpBoxed = bpPlace(bpBubble, pet: bpPet(x: 600), obstacles: [CGRect(x: 0, y: 0, width: 1512, height: 944)])
check(bpBoxed.origin.x >= 6 && bpBoxed.origin.x + bpBubble.width <= 1512 - 6 && bpBoxed.origin.y.isFinite, "con ingombri dappertutto sceglie comunque una disposizione dentro lo schermo")

// camminando da un bordo all'altro: sempre sopra, la punta sempre sul compagno, mai fuori dallo schermo, e la codina cambia lato una volta sola
for width in [130, 157, 213, 260] as [CGFloat] {
    let size = CGSize(width: width, height: 174)
    var previous: Bool?
    var changes = 0
    var ok = true
    var x: CGFloat = 1400
    while x >= 6 {
        let pet = bpPet(x: x)
        let r = bpPlace(size, pet: pet, previous: previous)
        let rect = CGRect(origin: r.origin, size: size)
        if r.layout != .above || abs(r.tipX - pet.midX) > BubblePlacement.tolerance || rect.minX < 5.99 || rect.maxX > 1512 - 5.99 || rect.minY < 64 { ok = false }
        if let previous, previous != r.tailOnRight { changes += 1 }
        previous = r.tailOnRight
        x -= 3
    }
    check(ok && changes <= 1, "dal bordo destro al sinistro con un fumetto largo \(Int(width)): sempre sopra, punta sul compagno, \(changes) cambio di lato")
    var back = 0
    x = 6
    while x <= 1400 {
        let r = bpPlace(size, pet: bpPet(x: x), previous: previous)
        if let previous, previous != r.tailOnRight { back += 1 }
        previous = r.tailOnRight
        x += 3
    }
    check(back <= 1, "…e tornando indietro, \(back) cambio di lato")
}

// ---------------------------------------------------------------- regali del giardino
section("Regali di fine focus")
check(GardenDrops.hash("a") == 0xE40C292C && GardenDrops.hash("foobar") == 0xBF9CF968, "FNV-1a a 32 bit: i valori noti")
var gdOne = GardenDrops.Stream(seed: 1)
check([gdOne.next(), gdOne.next(), gdOne.next()].map { ($0 * 1e12).rounded() / 1e12 } == [0.627073940588, 0.00273572118, 0.52744703996], "Mulberry32: i valori noti (gli stessi di TypeScript)")
var gdSeeded = GardenDrops.Stream(seed: GardenDrops.hash("A1B2C3D4-0000-4000-8000-000000000001"))
check([gdSeeded.next(), gdSeeded.next()].map { ($0 * 1e12).rounded() / 1e12 } == [0.404550580308, 0.712755646091], "…e dal seme di una sessione")

func gdSession(_ minutes: Int, completed: Bool = true, day: Int = 5) -> StudySession {
    StudySession(start: date(2026, 10, day, 9), localStart: StudySession.localString(for: date(2026, 10, day, 9), calendar: cal),
                 seconds: minutes * 60, plannedMinutes: minutes, completed: completed, subject: nil)
}
check(!GardenDrops.isEligible(gdSession(19)) && GardenDrops.isEligible(gdSession(20)) && !GardenDrops.isEligible(gdSession(50, completed: false)),
      "tira solo un focus completato con almeno 20 minuti: un interrotto non dà niente")
check(GardenCatalog.items.filter { $0.rarity == .common }.count == 16 && GardenCatalog.items.filter { $0.rarity == .rare }.count == 15
      && GardenCatalog.items.filter { $0.rarity == .legendary }.count == 5, "36 oggetti: 16 comuni, 15 rari, 5 leggendari (dal vecchio prezzo)")
let gdStart = GardenDropState.starting()
check(gdStart.found.count == 4 && gdStart.found["margherite"] == 1 && gdStart.nothingInARow == 0, "l'album parte con la dotazione (4 oggetti)")

let gdFirst = GardenDrops.chances(streakDays: 1, seconds: 25 * 60)
check(abs(gdFirst.rare - 0.22) < 1e-9 && abs(gdFirst.legendary - 0.03) < 1e-9, "probabilità di partenza: 22% raro, 3% leggendario")
check(abs(GardenDrops.chances(streakDays: 7, seconds: 25 * 60).rare - 0.30) < 1e-9 && abs(GardenDrops.chances(streakDays: 14, seconds: 25 * 60).legendary - 0.04) < 1e-9, "la serie le alza")
check(abs(GardenDrops.chances(streakDays: 1, seconds: 50 * 60).rare - 0.26) < 1e-9, "un focus lungo anche")

// un tiro è sempre lo stesso per la stessa sessione, e non dipende da altro
var gdA = GardenDropState.starting(), gdB = GardenDropState.starting()
let gdDrop1 = GardenDrops.roll(sessionID: "A1B2C3D4-0000-4000-8000-000000000001", streakDays: 3, seconds: 1800, state: &gdA)
let gdDrop2 = GardenDrops.roll(sessionID: "a1b2c3d4-0000-4000-8000-000000000001", streakDays: 3, seconds: 1800, state: &gdB)
check(gdDrop1 == gdDrop2 && gdA == gdB, "stesso identificativo (anche in minuscolo), stesso regalo")

// molti tiri: «niente» una volta su cinque ma mai tre volte di fila; le copie tornano
var gdState = GardenDropState.starting()
var gdNothing = 0, gdRun = 0, gdLongest = 0, gdGifts = 0, gdNew = 0
for i in 0..<2000 {
    let drop = GardenDrops.roll(sessionID: String(format: "00000000-0000-4000-8000-%012d", i), streakDays: 1, seconds: 1800, state: &gdState)
    if let drop {
        gdGifts += 1; gdRun = 0
        if drop.isNew { gdNew += 1 }
    } else { gdNothing += 1; gdRun += 1; gdLongest = max(gdLongest, gdRun) }
}
check(gdLongest <= 2, "mai più di due focus di fila senza regalo (\(gdLongest))")
check(gdNothing > 300 && gdNothing < 500, "circa un focus su cinque non dà niente (\(gdNothing) su 2000)")
check(gdState.found.values.reduce(0, +) == 4 + gdGifts && gdState.found.count == 36 && gdNew == 32, "le copie tornano, e l'album si completa (\(gdState.found.count) di 36)")

// le garanzie
var gdPity = GardenDropState.starting()
gdPity.sinceRare = GardenDrops.rarePity - 1
let gdRarePity = GardenDrops.roll(sessionID: "11111111-1111-4111-8111-111111111111", streakDays: 1, seconds: 1800, state: &gdPity)
check(gdRarePity == nil || gdRarePity!.rarity >= .rare, "dopo nove regali senza un raro, il prossimo lo è (o non esce niente)")
var gdPity2 = GardenDropState.starting()
gdPity2.sinceLegendary = GardenDrops.legendaryPity - 1
gdPity2.nothingInARow = GardenDrops.maxNothingInARow            // così il regalo c'è di sicuro
check(GardenDrops.roll(sessionID: "22222222-2222-4222-8222-222222222222", streakDays: 1, seconds: 1800, state: &gdPity2)?.rarity == .legendary, "dopo trentanove senza un leggendario, il prossimo lo è")
check(gdPity2.sinceLegendary == 0 && gdPity2.sinceRare == 0, "…e i contatori ripartono")

// con tutto trovato escono doppioni; con un solo oggetto per rarità non si blocca
var gdFull = GardenDropState.starting()
for item in GardenCatalog.items { gdFull.found[item.id] = 1 }
var gdDuplicates = 0
for i in 0..<200 {
    if let drop = GardenDrops.roll(sessionID: String(format: "33333333-0000-4000-8000-%012d", i), streakDays: 1, seconds: 1800, state: &gdFull), !drop.isNew { gdDuplicates += 1 }
}
check(gdDuplicates > 100 && gdFull.found.count == 36, "con l'album completo i regali sono copie in più")
var gdTiny = GardenDropState()
check(GardenDrops.roll(sessionID: "44444444-0000-4000-8000-000000000000", streakDays: 1, seconds: 1800, state: &gdTiny, pool: [GardenCatalog.items[4]])?.item == "tulipani", "con un solo oggetto possibile esce quello (si scende o si sale di rarità)")
check(GardenDrops.roll(sessionID: "55555555-0000-4000-8000-000000000000", streakDays: 1, seconds: 1800, state: &gdTiny, pool: []) == nil, "senza oggetti non esce niente")

// il registro intero: salta gli interrotti e i focus corti, e dà lo stesso risultato ogni volta
let gdLog = [gdSession(25, day: 1), gdSession(50, day: 1), gdSession(15, day: 2), gdSession(50, completed: false, day: 2), gdSession(30, day: 3), gdSession(30, day: 4)]
let gdRun1 = GardenDrops.simulate(sessions: gdLog, now: date(2026, 10, 6, 12), calendar: cal)
let gdRun2 = GardenDrops.simulate(sessions: gdLog, now: date(2026, 10, 6, 12), calendar: cal)
check(gdRun1.count == 4 && gdRun1.map { $0.drop } == gdRun2.map { $0.drop }, "il registro: quattro focus validi su sei, sempre gli stessi regali")

print("\n\(checks) controlli, \(failures) falliti")
exit(failures == 0 ? 0 : 1)
