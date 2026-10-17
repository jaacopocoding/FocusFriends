// Quando si sbloccano i compagni e come lo dice il compagno (evaluateCompanionRewards in MenuController.swift).

import { petInfo } from "./pets.ts";
import type { StudySession } from "./log.ts";
import { earned, focuses, order } from "./rewards.ts";

export interface UnlockProfile {
  readonly unlocked: ReadonlySet<string> | null;
  readonly firstCompanion: string | null;
  unlock(ids: readonly string[]): void;
}

/**
 * Sblocca i compagni guadagnati con lo studio fatto e ritorna quali sono nuovi (nell'ordine di sblocco). In modalità sviluppatore è
 * tutto già aperto (niente da annunciare e niente da registrare); senza una scelta del primo compagno non c'è niente di bloccato.
 */
export function evaluateUnlocks(profile: UnlockProfile, sessions: readonly StudySession[], ids: readonly string[], developer: boolean): string[] {
  const current = profile.unlocked;
  if (developer || current === null) return [];
  const total = focuses(sessions.reduce((sum, s) => sum + s.seconds, 0));
  const got = earned(profile.firstCompanion, ids, total);
  const fresh = order(profile.firstCompanion, ids).filter((id) => got.has(id) && !current.has(id));
  if (fresh.length > 0) profile.unlock(fresh);
  return fresh;
}

/** «Hai sbloccato Porcellino! Lo trovi nel menu, tra i compagni.» */
export function unlockMessage(ids: readonly string[]): string {
  const names = ids.map((id) => petInfo(id).name);
  return names.length === 1
    ? `Hai sbloccato ${names[0]}! Lo trovi nel menu, tra i compagni.`
    : `Hai sbloccato ${names.join(" e ")}! Li trovi nel menu, tra i compagni.`;
}
