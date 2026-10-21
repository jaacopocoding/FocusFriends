// Quale frase dice il compagno quando parla di sua iniziativa (Speaker.sayRandom, sul Mac). In quest'ordine: una frase «di contesto»
// in coda (il saluto dell'avvio, il riepilogo della settimana); il promemoria delle scadenze (non più di uno ogni tre ore);
// ogni tanto (una volta su sei) un numero dello studio; altrimenti la prossima del mazzo. Logica pura, con le dipendenze passate dal chiamante.

/** Ogni quanto, al massimo, un promemoria prende il posto di una frase a caso. */
export const REMINDER_EVERY_MS = 3 * 3_600_000;
/** Una volta su tanti un numero dello studio prende il posto di una frase a caso. */
export const INSIGHT_ONE_IN = 6;

/** Una frase «di contesto» da dire alla prossima occasione, prima delle frasi a caso. */
export interface Occasion {
  text: string;
  /** Dice già le scadenze: il promemoria non va ripetuto subito dopo. */
  coversReminder?: boolean;
  /** Chiamata quando la frase è stata scelta (per ricordare che è stata detta). */
  onSaid?: () => void;
}

export interface PhraseChooserDeps {
  now: () => number;
  /** Un numero da 0 (incluso) a 1 (escluso). */
  random: () => number;
  /** Le scadenze di oggi e domani, se ce ne sono e se è il momento di dirle (mai durante un focus). */
  reminder: () => string | null;
  /** Una frase «quando rendi meglio», se ce n'è una da dire adesso. */
  insight: () => string | null;
}

export class PhraseChooser {
  private readonly deps: PhraseChooserDeps;
  private queued: Occasion[] = [];
  private lastReminder = -Infinity;

  constructor(deps: PhraseChooserDeps) {
    this.deps = deps;
  }

  /** Mette una frase in coda: la dice al prossimo momento in cui il compagno parla di sua iniziativa (mai, se le frasi sono su «Mai»). */
  enqueue(occasion: Occasion): void {
    this.queued.push(occasion);
  }

  /** Il promemoria delle scadenze è già stato detto adesso: il prossimo non prima di qualche ora. */
  markReminderSaid(): void {
    this.lastReminder = this.deps.now();
  }

  /** La frase da dire adesso; `deck` dà la prossima del mazzo quando non c'è altro da dire. */
  next(deck: () => string): string {
    const occasion = this.queued.shift();
    if (occasion !== undefined) {
      if (occasion.coversReminder === true) this.markReminderSaid();
      occasion.onSaid?.();
      return occasion.text;
    }
    if (this.deps.now() - this.lastReminder >= REMINDER_EVERY_MS) {
      const reminder = this.deps.reminder();
      if (reminder !== null) {
        this.markReminderSaid();
        return reminder;
      }
    }
    if (Math.floor(this.deps.random() * INSIGHT_ONE_IN) === 0) {
      const insight = this.deps.insight();
      if (insight !== null) return insight;
    }
    return deck();
  }
}
