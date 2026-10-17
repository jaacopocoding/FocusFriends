// La finestra delle statistiche (DashboardView in DashboardWindow.swift). Il riepilogo è calmo: un grande numero, una barra con le
// materie, i giorni di fila e come è andata. «Mostra le sessioni» apre il diario: le sessioni una per una, con la nota e la faccia.

import { subjectColor } from "../../core/colors.ts";
import {
  RATING_ORDER, canGoNext, chartLabel, diaryEntries, focusNotesLine, periodTitle, secondaryLine, sessionHeading, streakLabel, subjectRows, subtitle,
} from "../../core/dashboard.ts";
import type { DiaryEntry, SubjectRow } from "../../core/dashboard.ts";
import type { Rating, StudySession } from "../../core/log.ts";
import { analyzeStreak, duration, insights, periodContaining, shiftedPeriod, startTime, summarize } from "../../core/stats.ts";
import type { Period, PeriodKind, Summary } from "../../core/stats.ts";
import { startOfDay, wallOf } from "../../core/time.ts";
import type { StatsApi, StatsData } from "../../shared/statsApi.ts";
import { button, h, icon } from "../card/dom.ts";
import { RATING_TITLE, faceIcon } from "../card/widgets.ts";

declare global {
  interface Window { focusfriendsStats: StatsApi }
}

const api = window.focusfriendsStats;
const app = document.getElementById("app")!;

let sessions: StudySession[] = [];
let nowMs = Date.now();
let kind: PeriodKind = "day";
let period: Period = periodContaining(wallOf(nowMs), "day");
let showsDiary = false;

const MUTED = "rgba(102, 77, 51, 0.5)";
const KIND_LABELS: Array<[PeriodKind, string]> = [["day", "Oggi"], ["week", "Settimana"], ["month", "Mese"]];

const colorOf = (row: Pick<SubjectRow, "subject" | "muted">): string => (row.muted ? MUTED : subjectColor(row.subject));

// ---- scheletro

const periodTitleEl = h("div", { class: "period-title", "aria-live": "polite" });
const previousButton = button("arrow", "Periodo precedente", () => { period = shiftedPeriod(period, -1); render(true); }, icon("back", 18));
const nextButton = button("arrow", "Periodo successivo", () => { if (canGoNext(period, wallOf(nowMs))) { period = shiftedPeriod(period, 1); render(true); } }, icon("forward", 18));
const tabs = h("div", { class: "tabs", role: "tablist", "aria-label": "Periodo" });
const page = h("main", { class: "page" });
const modalRoot = h("div", { class: "modal-root" });

app.append(
  h("header", { class: "top" },
    button("back-pill", "Torna al menu", () => api.back(), icon("back", 13), "Menu"),
    tabs,
    h("div", { class: "period-row" }, previousButton, periodTitleEl, nextButton)),
  page,
  h("footer", { class: "bottom" },
    button("link", "Cancella tutto", () => api.deleteAll(), "Cancella tutto…"),
    button("link", "Esporta CSV", () => api.exportCsv(), "Esporta CSV…")),
  modalRoot,
);

for (const [value, label] of KIND_LABELS) {
  const tab = button("tab", label, () => select(value), label);
  tab.setAttribute("role", "tab");
  tab.dataset["kind"] = value;
  tabs.append(tab);
}

function select(next: PeriodKind): void {
  kind = next;
  period = periodContaining(wallOf(nowMs), next);
  showsDiary = false;
  render(true);
}

// ---- disegno

function render(resetScroll: boolean): void {
  const wall = wallOf(nowMs);
  const summary = summarize(sessions, period, undefined);
  const streak = analyzeStreak(sessions, nowMs, undefined);
  document.title = "Statistiche";
  periodTitleEl.textContent = periodTitle(period);
  nextButton.classList.toggle("dim", !canGoNext(period, wall));
  nextButton.toggleAttribute("disabled", !canGoNext(period, wall));
  tabs.querySelectorAll<HTMLElement>(".tab").forEach((tab) => {
    const on = tab.dataset["kind"] === kind;
    tab.classList.toggle("on", on);
    tab.setAttribute("aria-selected", String(on));
  });
  const scroll = page.scrollTop;
  page.replaceChildren();

  const empty = summary.totalSeconds === 0;
  const isCurrent = wall >= period.start && wall < period.end;
  page.append(h("div", { class: `big${empty ? " empty" : ""}` }, empty ? "0 min" : duration(summary.totalSeconds)));
  const sub = subtitle(summary);
  if (sub !== "") page.append(h("div", { class: "subtitle" }, sub));
  const more = secondaryLine(summary, kind, isCurrent);
  if (more !== "") page.append(h("div", { class: "secondary" }, more));

  if (!empty) {
    if (kind !== "day") page.append(miniChart(summary, wall));
    const rows = subjectRows(summary);
    page.append(subjectBar(rows), legend(rows));
    if (streak.days > 0) page.append(streakLine(streak.days, streak.isFrozen));
    if (summary.ratingCounts.good !== undefined || summary.ratingCounts.soso !== undefined || summary.ratingCounts.poor !== undefined) page.append(ratings(summary));
    const lines = insights(sessions, undefined);
    if (lines.length > 0) page.append(h("div", { class: "insights" }, ...lines.map((line) => h("div", {}, line))));
  }
  if (summary.sessions.length > 0) {
    const toggle = button("diary-toggle", showsDiary ? "Nascondi le sessioni" : "Mostra le sessioni", () => {
      showsDiary = !showsDiary;
      render(false);
      if (showsDiary) page.querySelector(".diary-toggle")?.scrollIntoView({ block: "start" });
    }, showsDiary ? "Nascondi le sessioni" : "Mostra le sessioni", icon(showsDiary ? "up" : "down", 14));
    toggle.setAttribute("aria-expanded", String(showsDiary));
    page.append(h("div", { class: "diary-toggle-row" }, toggle));
    if (showsDiary) page.append(diary(summary));
  }
  page.scrollTop = resetScroll ? 0 : scroll;
}

/** Le barre sottili, una per giorno: niente numeri, solo la forma della settimana o del mese. */
function miniChart(summary: Summary, wall: number): HTMLElement {
  const maxSeconds = Math.max(...summary.buckets.map((b) => b.seconds), 1);
  const today = startOfDay(wall);
  const chart = h("div", { class: `chart ${kind}`, role: "img", "aria-label": "Ore di studio per giorno" });
  for (const bucket of summary.buckets) {
    const bar = h("div", { class: `bar${bucket.seconds === 0 ? " none" : ""}${startOfDay(bucket.start) === today ? " today" : ""}` });
    bar.style.height = `${bucket.seconds === 0 ? 3 : Math.max((bucket.seconds / maxSeconds) * 56, 5)}px`;
    const label = chartLabel(kind, bucket.start);
    chart.append(h("div", { class: "slot" }, h("div", { class: "bar-area" }, bar), h("div", { class: "bar-label" }, label)));
  }
  return chart;
}

/** Una sola barra, a segmenti, con le materie del periodo. */
function subjectBar(rows: SubjectRow[]): HTMLElement {
  const bar = h("div", { class: "subject-bar", role: "img", "aria-label": "Materie del periodo" });
  for (const row of rows) {
    const part = h("div", { class: "sub-segment" });
    part.style.flexGrow = String(row.seconds);
    part.style.background = colorOf(row);
    bar.append(part);
  }
  return bar;
}

function legend(rows: SubjectRow[]): HTMLElement {
  return h("div", { class: "legend" }, ...rows.map((row) => {
    const dot = h("span", { class: "dot" });
    dot.style.background = colorOf(row);
    return h("span", { class: "legend-item" }, dot, `${row.subject} ${duration(row.seconds)}`);
  }));
}

function streakLine(days: number, frozen: boolean): HTMLElement {
  const line = h("div", { class: `streak${frozen ? " frozen" : ""}` }, icon(frozen ? "snowflake" : "flame", 15), streakLabel(days, frozen));
  return line;
}

/** Quante volte bene, così così, poca testa nel periodo. */
function ratings(summary: Summary): HTMLElement {
  return h("div", { class: "ratings" }, ...RATING_ORDER.map((rating) => {
    const count = summary.ratingCounts[rating] ?? 0;
    return h("span", { class: `rating${count > 0 ? "" : " zero"}` }, faceIcon(rating, 20), `${RATING_TITLE[rating]} ${count}`);
  }));
}

// ---- il diario

function diary(summary: Summary): HTMLElement {
  const root = h("div", { class: "diary" });
  for (const entry of diaryEntries(summary.sessions, kind, undefined)) {
    if (entry.type === "strip") root.append(strip(entry));
    else if (entry.type === "header") root.append(h("div", { class: "diary-header" }, h("span", { class: "diary-day" }, entry.title), h("span", { class: "diary-total" }, duration(entry.seconds))));
    else root.append(sessionRow(entry));
  }
  return root;
}

/** Le ore del giorno in orizzontale, con un blocco per ogni focus (colore della materia). */
function strip(entry: Extract<DiaryEntry, { type: "strip" }>): HTMLElement {
  const span = Math.max(entry.lastHour - entry.firstHour, 1);
  const track = h("div", { class: "strip-track" });
  for (const block of entry.blocks) {
    const part = h("div", { class: "strip-block", title: block.session.subject ?? "Senza materia" });
    part.style.left = `${((block.startHour - entry.firstHour) / span) * 100}%`;
    part.style.width = `max(${((block.endHour - block.startHour) / span) * 100}%, 6px)`;
    part.style.background = block.session.subject !== undefined ? subjectColor(block.session.subject) : MUTED;
    track.append(part);
  }
  const ticks = h("div", { class: "strip-ticks" });
  const step = entry.lastHour - entry.firstHour > 12 ? 3 : 2;
  for (let hour = entry.firstHour; hour <= entry.lastHour; hour += step) {
    const tick = h("span", { class: "tick" }, String(hour));
    tick.style.left = `${((hour - entry.firstHour) / span) * 100}%`;
    ticks.append(tick);
  }
  return h("div", { class: "strip", "aria-hidden": "true" }, track, ticks);
}

function sessionRow(entry: Extract<DiaryEntry, { type: "session" }>): HTMLElement {
  const { session } = entry;
  const dot = h("span", { class: "dot" });
  dot.style.background = session.subject !== undefined ? subjectColor(session.subject) : MUTED;
  const status = session.completed ? `${entry.minutes} min` : `${entry.minutes} min · interrotto`;
  const notes = focusNotesLine(session);
  const row = button("session", `Modifica la sessione delle ${entry.time}`, () => openEdit(session),
    h("span", { class: "session-time" }, dot, entry.time),
    h("span", { class: "session-main" },
      h("span", { class: "session-subject" }, session.subject ?? "Senza materia"),
      session.note !== undefined ? h("span", { class: "session-line" }, session.note) : null,
      notes !== null ? h("span", { class: "session-line" }, notes) : null),
    session.rating !== undefined ? faceIcon(session.rating, 18) : null,
    h("span", { class: `session-status${session.completed ? "" : " interrupted"}` }, status));
  return row;
}

// ---- modifica di una sessione

function openEdit(session: StudySession): void {
  if (modalRoot.childElementCount > 0) return;
  const subject = h("input", { type: "text", class: "field", placeholder: "Materia", "aria-label": "Materia" });
  subject.value = session.subject ?? "";
  const everywhere = h("input", { type: "checkbox", id: "everywhere" });
  const note = h("input", { type: "text", class: "field", placeholder: "Cosa hai fatto? (facoltativo)", "aria-label": "Cosa hai fatto" });
  note.value = session.note ?? "";
  let chosen: Rating | null = session.rating ?? null;
  const segments = h("div", { class: "rating-choice", role: "radiogroup", "aria-label": "Com'è andata" });
  const options: Array<[Rating | null, string]> = [[null, "Nessun voto"], ...RATING_ORDER.map((r): [Rating, string] => [r, RATING_TITLE[r]])];
  const paint = (): void => segments.querySelectorAll<HTMLElement>("button").forEach((b, i) => {
    const on = options[i]![0] === chosen;
    b.classList.toggle("on", on);
    b.setAttribute("aria-checked", String(on));
  });
  options.forEach(([value, label]) => {
    const choice = button("rating-option", label, () => { chosen = value; paint(); }, label);
    choice.setAttribute("role", "radio");
    segments.append(choice);
  });
  const notes = h("textarea", { class: "field notes", rows: 3, "aria-label": "Note del focus (una per riga)" });
  notes.value = (session.notes ?? []).join("\n");

  const close = (): void => { modalRoot.replaceChildren(); window.removeEventListener("keydown", onKey, true); };
  const onKey = (event: KeyboardEvent): void => { if (event.key === "Escape") { event.preventDefault(); close(); } };
  window.addEventListener("keydown", onKey, true);

  const dialog = h("div", { class: "edit", role: "dialog", "aria-modal": "true", "aria-label": "Modifica sessione" },
    h("div", { class: "edit-title" }, "Modifica sessione"),
    h("div", { class: "edit-heading" }, sessionHeading(session, undefined)),
    subject,
    session.subject !== undefined ? h("label", { class: "check" }, everywhere, `Cambia la materia in tutte le sessioni «${session.subject}»`) : null,
    note,
    segments,
    h("label", { class: "caption", for: "notes" }, "Note del focus (una per riga)"),
    notes,
    h("div", { class: "edit-buttons" },
      button("text-button danger-text", "Elimina questa sessione", () => { api.deleteSession(session.id); close(); }, "Elimina"),
      button("text-button", "Annulla", close, "Annulla"),
      button("pill-action", "Salva", () => {
        api.editSession({
          id: session.id, subject: subject.value, originalSubject: session.subject ?? null, everywhere: everywhere.checked,
          rating: chosen, note: note.value, notes: notes.value.split(/\r?\n/),
        });
        close();
      }, "Salva")));
  notes.id = "notes";
  paint();
  modalRoot.append(h("div", { class: "modal-backdrop" }), dialog);
  subject.focus();
}

// ---- dati

function load(data: StatsData): void {
  sessions = data.sessions;
  nowMs = data.now;
  if (data.kind !== null) select(data.kind); else render(false);
}

api.onData(load);
void api.getData().then((data) => { if (data) load(data); });
