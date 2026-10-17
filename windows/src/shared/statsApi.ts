// Il contratto tra il processo principale e la finestra delle statistiche.

import type { Rating, StudySession } from "../core/log.ts";
import type { PeriodKind } from "../core/stats.ts";

export interface StatsData {
  sessions: StudySession[];
  /** «Adesso», in millisecondi (l'istante). */
  now: number;
  /** «Le statistiche di Marco» o «Statistiche e riepilogo». */
  title: string;
  /** Quale scheda aprire (solo quando la finestra viene aperta). */
  kind: PeriodKind | null;
}

/** Una sessione modificata dalla finestra di modifica. */
export interface SessionEdit {
  id: string;
  subject: string | null;
  /** La materia com'era prima, per cambiarla in tutte le sessioni che la hanno. */
  originalSubject: string | null;
  everywhere: boolean;
  rating: Rating | null;
  note: string | null;
  notes: string[];
}

export interface StatsApi {
  getData(): Promise<StatsData>;
  /** Il registro è cambiato (una sessione modificata, un focus finito): i dati nuovi. */
  onData(callback: (data: StatsData) => void): void;
  editSession(edit: SessionEdit): void;
  deleteSession(id: string): void;
  exportCsv(): void;
  deleteAll(): void;
  /** «‹ Menu»: la finestra si chiude e si torna alla scheda. */
  back(): void;
}

export const STATS_CHANNEL = {
  getData: "stats:get-data",
  data: "stats:data",
  edit: "stats:edit",
  delete: "stats:delete",
  exportCsv: "stats:export-csv",
  deleteAll: "stats:delete-all",
  back: "stats:back",
} as const;
