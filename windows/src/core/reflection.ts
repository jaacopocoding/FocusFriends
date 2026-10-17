// «Com'è andata?»: una parolina del compagno per ogni risposta, e come si salva (ReflectionCard.swift).

import type { Rating, SessionLog } from "./log.ts";
import { cleanNote } from "./text.ts";

const REPLIES: Record<Rating, readonly string[]> = {
  good: ["Che bello! Segnato nel diario.", "Così si fa! Ne sono contento.", "Bene! Ora una pausa vera."],
  soso: ["Capita. L'importante è esserci stati.", "Va bene così: un passo alla volta.", "Segnato. Ci riproviamo dopo la pausa."],
  poor: ["Capita a tutti. Una pausa vera e poi si riparte.", "Nessun problema: oggi la testa era altrove.", "Grazie di averlo detto. Riposati un po'."],
};

export function reflectionReply(rating: Rating, random: () => number = Math.random): string {
  const variants = REPLIES[rating];
  return variants[Math.floor(random() * variants.length)] ?? "Segnato!";
}

/** I testi di tutte le risposte (per le prove). */
export const ALL_REPLIES = REPLIES;

/**
 * Salva voto e nota di una sessione. Con la sola nota non si cancella un voto già dato (per esempio dalla schermata della pausa);
 * senza voto né nota non si scrive niente.
 */
export function saveReflection(log: SessionLog, sessionId: string, rating: Rating | null, rawNote: string | null): boolean {
  const note = cleanNote(rawNote);
  if (rating === null && note === null) return false;
  const existing = log.sessions.find((s) => s.id === sessionId)?.rating ?? null;
  log.setReflection(sessionId, rating ?? existing, note);
  return true;
}
