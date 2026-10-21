// Le frasi «di contesto» viste dal processo principale (AppDelegate.swift e Speaker.swift, sul Mac): il saluto dell'avvio e il riepilogo
// della settimana in coda per la prima frase spontanea, i numeri detti ogni tanto, il saluto al risveglio dallo sleep e i traguardi
// a fine focus. Le regole stanno in core/remarks.ts e core/phraseChooser.ts; qui si raccolgono i dati e si decide quando parlare.

import type { StudySession } from "../core/log.ts";
import type { SessionLog } from "../core/log.ts";
import { PhraseChooser } from "../core/phraseChooser.ts";
import type { Profile } from "../core/profile.ts";
import { insight, launchGreeting, milestone, wakeGreeting, weeklyRecap } from "../core/remarks.ts";
import type { RemarksContext } from "../core/remarks.ts";
import type { Settings } from "../core/settings.ts";
import { reminderMessage, todayOf } from "../core/todo.ts";
import type { ToDoList } from "../core/todoList.ts";
import type { QuietSpeech } from "../shared/api.ts";

export interface RemarksOptions {
  settings: Settings;
  profile: Profile;
  todo: ToDoList;
  log: () => SessionLog;
  /** Come sta il timer adesso: "focus", "rest" o null (fermo). */
  timerPhase: () => string | null;
  /** Il compagno è sullo schermo (non nascosto). */
  isVisible: () => boolean;
  sayWhenQuiet: (speech: QuietSpeech) => void;
  now?: () => number;
  random?: () => number;
}

export interface RemarksService {
  /** Il saluto dell'avvio e, il lunedì (fino al mercoledì), il riepilogo della settimana: si dicono alla prima frase spontanea. */
  greetOnLaunch(): void;
  /** La frase da dire quando il compagno parla di sua iniziativa; `deck` dà la prossima del mazzo se non c'è altro. */
  nextPhrase(deck: () => string): string;
  /** Il computer va in sleep. */
  suspended(): void;
  /** Il computer si risveglia: «Rieccoti!» se è passata almeno un'ora. */
  resumed(): void;
  /** Il saluto del risveglio dopo `awaySeconds` secondi (se le regole lo permettono). */
  wake(awaySeconds: number): void;
  /** Un focus è stato registrato: se ha fatto passare un traguardo, lo dice dopo la frase di fine focus. */
  focusRecorded(session: StudySession): void;
}

export function createRemarks(options: RemarksOptions): RemarksService {
  const { settings, profile, todo } = options;
  const now = options.now ?? Date.now;
  const random = options.random ?? Math.random;
  const pick = (count: number): number => Math.floor(random() * count);
  let sleptAt: number | null = null;
  let lastInsight: string | null = null;

  const dueMessage = (at: number): string | null => reminderMessage(todo.items, todayOf(at));
  const context = (): RemarksContext => {
    const at = now();
    return { now: at, name: profile.name, sessions: options.log().sessions, openTodoCount: todo.openCount, due: dueMessage(at) };
  };

  const chooser = new PhraseChooser({
    now, random,
    // Le scadenze di oggi e domani: mai durante un focus.
    reminder: () => (options.timerPhase() === "focus" ? null : dueMessage(now())),
    // Un numero dello studio: mai durante un focus e mai due volte di fila lo stesso.
    insight: () => {
      if (options.timerPhase() === "focus") return null;
      const text = insight(context(), pick(10));
      if (text === null || text === lastInsight) return null;
      lastInsight = text;
      return text;
    },
  });

  const service: RemarksService = {
    greetOnLaunch() {
      if (!profile.introSeen) return;
      const ctx = context();
      const greeting = launchGreeting(ctx, pick(12));
      chooser.enqueue({ text: greeting.text, coversReminder: greeting.coversReminder });
      const recap = weeklyRecap(ctx);
      if (recap !== null && settings.lastWeeklyRecap !== recap.key) {
        chooser.enqueue({ text: recap.text, onSaid: () => { settings.lastWeeklyRecap = recap.key; } });
      }
    },

    nextPhrase: (deck) => chooser.next(deck),

    suspended() {
      sleptAt = now();
    },

    resumed() {
      if (sleptAt === null) return;
      const away = (now() - sleptAt) / 1000;
      sleptAt = null;
      service.wake(away);
    },

    wake(awaySeconds) {
      if (!profile.introSeen || settings.phraseFrequency === "never" || !options.isVisible() || options.timerPhase() === "focus") return;
      const remark = wakeGreeting(context(), awaySeconds, pick(9));
      if (remark === null) return;
      if (remark.coversReminder) chooser.markReminderSaid();
      options.sayWhenQuiet({ text: remark.text, after: 5, only: "outsideFocus" });
    },

    focusRecorded(session) {
      const all = options.log().sessions;
      const text = milestone(all.filter((s) => s.id !== session.id), all, now());
      if (text !== null) options.sayWhenQuiet({ text, after: 9, only: "inBreak" });
    },
  };
  return service;
}
