// Le cose da fare (FORMATI.md §9, ToDo.swift): i giorni di scadenza, la pulizia del testo, i gruppi della lista e la frase del
// compagno. Logica pura: la usano il processo principale, la pagina e le prove. Il file `dafare.json` lo legge e lo scrive
// `todoList.ts`.

import { prefixCharacters } from "./text.ts";
import { dayString, wallOf } from "./time.ts";

/** Una cosa da fare. `due` è un giorno «AAAA-MM-GG» (senza ora né fuso); le date sono istanti in millisecondi. */
export interface ToDoItem {
  id: string;
  text: string;
  due: string | null;
  subject: string | null;
  createdAt: number;
  doneAt: number | null;
}

export type ToDoGroup = "overdue" | "today" | "upcoming" | "noDate";

export interface ToDoSection {
  group: ToDoGroup;
  items: ToDoItem[];
}

export const TODO_TEXT_MAX = 120;
export const TODO_MAX_ITEMS = 200;
export const TODO_KEEP_DONE_DAYS = 7;
export const TODO_REMINDER_QUOTED = 36;

export const GROUP_TITLES: Record<ToDoGroup, string> = {
  overdue: "Scadute", today: "Oggi", upcoming: "Prossime", noDate: "Senza data",
};

// ---- i giorni

const DAY_MS = 86_400_000;
const DAY_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;

/** Il giorno come istante UTC a mezzanotte, o null se non è un giorno che esiste (il 31 giugno, l'anno 0). */
function dayInstant(day: string): number | null {
  const match = DAY_PATTERN.exec(day);
  if (!match) return null;
  const year = Number(match[1]), month = Number(match[2]), date = Number(match[3]);
  if (year < 1) return null;
  const at = new Date(Date.UTC(2000, 0, 1));
  at.setUTCFullYear(year, month - 1, date);
  if (at.getUTCFullYear() !== year || at.getUTCMonth() !== month - 1 || at.getUTCDate() !== date) return null;
  return at.getTime();
}

function dayOfInstant(instant: number): string {
  const at = new Date(instant);
  const pad = (n: number, width = 2): string => String(n).padStart(width, "0");
  return `${pad(at.getUTCFullYear(), 4)}-${pad(at.getUTCMonth() + 1)}-${pad(at.getUTCDate())}`;
}

/** «AAAA-MM-GG», solo se è un giorno che esiste. */
export function isValidDay(day: string): boolean {
  return dayInstant(day) !== null;
}

/** Il giorno di oggi sull'orologio del computer (o nel fuso dato). */
export function todayOf(now: number, zone?: string): string {
  return dayString(wallOf(now, zone));
}

/** Quanti giorni da `from` a `to` (negativo = prima); null se uno dei due non è valido. */
export function daysBetween(from: string, to: string): number | null {
  const a = dayInstant(from), b = dayInstant(to);
  return a === null || b === null ? null : Math.round((b - a) / DAY_MS);
}

export function addDays(day: string, count: number): string | null {
  const at = dayInstant(day);
  return at === null ? null : dayOfInstant(at + count * DAY_MS);
}

const WEEKDAYS = ["dom", "lun", "mar", "mer", "gio", "ven", "sab"];
const MONTHS = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"];

/** «ieri», «oggi», «domani», «ven 23» (entro la settimana), «26 ott» (e l'anno, se non è questo). */
export function dueLabel(due: string, today: string): string {
  const diff = daysBetween(today, due);
  const at = dayInstant(due), now = dayInstant(today);
  if (diff === null || at === null || now === null) return due;
  if (diff === -1) return "ieri";
  if (diff === 0) return "oggi";
  if (diff === 1) return "domani";
  const date = new Date(at);
  if (diff >= 2 && diff <= 6) return `${WEEKDAYS[date.getUTCDay()]} ${date.getUTCDate()}`;
  const base = `${date.getUTCDate()} ${MONTHS[date.getUTCMonth()]}`;
  return date.getUTCFullYear() === new Date(now).getUTCFullYear() ? base : `${base} ${date.getUTCFullYear()}`;
}

// ---- il testo

const WHITESPACE = /[\s\u0085]+/u;
const CONTROL = /[\p{Cc}\p{Cf}]/gu;

/** Spazi in eccesso e caratteri di controllo tolti, al massimo 120 caratteri; vuoto = niente. */
export function cleanToDoText(text: string | null | undefined): string | null {
  if (text == null) return null;
  const joined = text.split(WHITESPACE).map((w) => w.replace(CONTROL, "")).filter((w) => w !== "").join(" ");
  return joined === "" ? null : prefixCharacters(joined, TODO_TEXT_MAX);
}

// ---- la lista

export function openItems(items: readonly ToDoItem[]): ToDoItem[] {
  return items.filter((item) => item.doneAt === null);
}

/** Le voci fatte, la più recente per prima. */
export function doneItems(items: readonly ToDoItem[]): ToDoItem[] {
  return items.filter((item) => item.doneAt !== null).sort((a, b) => (b.doneAt ?? 0) - (a.doneAt ?? 0));
}

function groupOf(item: ToDoItem, today: string): ToDoGroup {
  const diff = item.due === null ? null : daysBetween(today, item.due);
  if (diff === null) return "noDate";
  return diff < 0 ? "overdue" : diff === 0 ? "today" : "upcoming";
}

/** Le voci da fare raggruppate (senza i gruppi vuoti); in ogni gruppo per scadenza e poi dalla più vecchia. */
export function sections(items: readonly ToDoItem[], today: string): ToDoSection[] {
  const open = openItems(items);
  const order: ToDoGroup[] = ["overdue", "today", "upcoming", "noDate"];
  return order.flatMap((group) => {
    const inGroup = open.filter((item) => groupOf(item, today) === group).sort((a, b) => {
      if (a.due !== b.due) return (a.due ?? "") < (b.due ?? "") ? -1 : 1;
      return a.createdAt - b.createdAt;
    });
    return inGroup.length === 0 ? [] : [{ group, items: inGroup }];
  });
}

// ---- la frase del compagno

const graphemes = new Intl.Segmenter("it", { granularity: "grapheme" });

function shortened(text: string): string {
  const parts = Array.from(graphemes.segment(text), (part) => part.segment);
  if (parts.length <= TODO_REMINDER_QUOTED) return text;
  let cut = parts.slice(0, TODO_REMINDER_QUOTED - 1);
  const space = cut.lastIndexOf(" ");
  if (space > Math.floor(TODO_REMINDER_QUOTED / 2)) cut = cut.slice(0, space);
  return cut.join("").replace(/^[ \t]+|[ \t]+$/g, "") + "…";
}

function sentence(items: readonly ToDoItem[], when: string): string | null {
  const first = items[0];
  if (!first) return null;
  const quoted = `«${shortened(first.text)}»`;
  if (items.length === 1) return `${when} scade ${quoted}. Un focus adesso?`;
  const others = items.length - 1;
  return `${when} scadono ${items.length} cose: ${quoted} e ${others === 1 ? "un'altra" : `altre ${others}`}.`;
}

/** Cosa dice il compagno: le scadenze di oggi o, se non ce ne sono, di domani; le scadute non si nominano. */
export function reminderMessage(items: readonly ToDoItem[], today: string): string | null {
  const open = openItems(items).sort((a, b) => a.createdAt - b.createdAt);
  const forToday = sentence(open.filter((item) => item.due === today), "Oggi");
  if (forToday !== null) return forToday;
  const tomorrow = addDays(today, 1);
  return tomorrow === null ? null : sentence(open.filter((item) => item.due === tomorrow), "Domani");
}
