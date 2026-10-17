// Quello che la scheda mostra oltre al timer (che arriva a parte, ogni secondo): il compagno, le statistiche di oggi, i timer
// salvati, le impostazioni rapide, i compagni bloccati. Si ricava dai dati con una funzione pura, così si prova da sola
// (MenuCardState in MenuCard.swift e cardState() in MenuController.swift).

import type { Rating, StudySession } from "./log.ts";
import { PETS, petInfo } from "./pets.ts";
import { need, focuses } from "./rewards.ts";
import { analyzeStreak, periodContaining, summarize } from "./stats.ts";
import { backgroundCurrent } from "./rules.ts";
import type { AmbientSound, BackgroundChoice, Chattiness, MusicSource } from "./rules.ts";
import { wallOf } from "./time.ts";

export interface CompanionEntry {
  id: string;
  name: string;
  /** Se è bloccato, cosa manca: «si sblocca a 20 focus: ne hai 12». */
  lock: string | null;
}

export interface CardData {
  userName: string | null;
  companions: CompanionEntry[];
  petVisible: boolean;
  todaySeconds: number;
  todayFocusCount: number;
  streak: number;
  /** La serie è ghiacciata: ieri non si è studiato, studiando oggi continua. */
  streakFrozen: boolean;
  focusTimers: number[];
  restTimers: number[];
  customFocus: number[];
  customRest: number[];
  chattiness: Chattiness;
  movementOn: boolean;
  askOn: boolean;
  ambient: AmbientSound;
  ambientVolume: number;
  music: MusicSource;
  musicLabel: string;
  musicVolume: number;
  background: BackgroundChoice;
  backgroundVolume: number;
  /** Il voto dell'ultimo focus finito, se già dato. */
  lastRating: Rating | null;
  hasLastSession: boolean;
  /** Le materie usate di recente (fino a sei), per «Cosa studi adesso?», e l'ultima nota scritta. */
  recentSubjects: string[];
  lastNote: { subject: string | null; note: string } | null;
}

export interface CardInput {
  now: number;
  zone?: string;
  sessions: readonly StudySession[];
  profile: {
    name: string | null;
    unlocked: ReadonlySet<string> | null;
    firstCompanion: string | null;
    isCompanionUnlocked(id: string): boolean;
  };
  petVisible: boolean;
  timers: { focus: number[]; rest: number[]; customFocus: number[]; customRest: number[] };
  chattiness: Chattiness;
  movementOn: boolean;
  askOn: boolean;
  ambient: AmbientSound;
  ambientVolume: number;
  music: MusicSource;
  musicFolder: string | null;
  musicVolume: number;
  lastSessionId: string | null;
  recentSubjects: string[];
  lastNote: { subject?: string; note: string } | null;
}

/** Per ogni compagno bloccato, la frase che dice quanto manca («si sblocca a 20 focus: ne hai 12»). */
export function companionLocks(profile: CardInput["profile"], sessions: readonly StudySession[], ids: readonly string[]): Map<string, string> {
  const result = new Map<string, string>();
  if (profile.unlocked === null) return result;
  const have = focuses(sessions.reduce((total, s) => total + s.seconds, 0));
  for (const id of ids) {
    if (profile.isCompanionUnlocked(id)) continue;
    const required = need(id, profile.firstCompanion, ids);
    result.set(id, `si sblocca a ${required} focus: ne hai ${Math.min(have, required)}`);
  }
  return result;
}

/** Cosa mostrare accanto alla riga «Musica». */
export function musicLabel(source: MusicSource, folder: string | null): string {
  switch (source) {
    case "off": return "Spenta";
    case "bundled": return "Brani inclusi";
    case "folder": return folder === null ? "La mia cartella" : `Cartella: ${folder.split(/[\\/]/).filter(Boolean).at(-1) ?? folder}`;
  }
}

export function buildCardData(input: CardInput): CardData {
  const today = wallOf(input.now, input.zone);
  const summary = summarize(input.sessions, periodContaining(today, "day"), input.zone);
  const streak = analyzeStreak(input.sessions, input.now, input.zone);
  const background = backgroundCurrent(input.ambient, input.music);
  const locks = companionLocks(input.profile, input.sessions, PETS.map((p) => p.id));
  const last = input.lastSessionId === null ? undefined : input.sessions.find((s) => s.id === input.lastSessionId);
  return {
    userName: input.profile.name,
    companions: PETS.map((pet) => ({ id: pet.id, name: petInfo(pet.id).name, lock: locks.get(pet.id) ?? null })),
    petVisible: input.petVisible,
    todaySeconds: summary.totalSeconds,
    todayFocusCount: summary.focusCount,
    streak: streak.days,
    streakFrozen: streak.isFrozen,
    focusTimers: input.timers.focus, restTimers: input.timers.rest,
    customFocus: input.timers.customFocus, customRest: input.timers.customRest,
    chattiness: input.chattiness, movementOn: input.movementOn, askOn: input.askOn,
    ambient: input.ambient, ambientVolume: input.ambientVolume,
    music: input.music, musicLabel: musicLabel(input.music, input.musicFolder), musicVolume: input.musicVolume,
    background,
    backgroundVolume: background === "music" ? input.musicVolume : input.ambientVolume,
    lastRating: last?.rating ?? null,
    hasLastSession: last !== undefined,
    recentSubjects: input.recentSubjects,
    lastNote: input.lastNote === null ? null : { subject: input.lastNote.subject ?? null, note: input.lastNote.note },
  };
}
