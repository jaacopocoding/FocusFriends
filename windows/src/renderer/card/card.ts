// La scheda di carta (MenuCard.swift): il compagno che sbuca dal bordo, i tre focus, il riepilogo di oggi, le impostazioni più
// usate; poi le pagine del quadrante, del focus e della pausa. Sta dentro la finestra trasparente: mentre è aperta la finestra
// riceve i clic (un clic fuori la chiude) e la tastiera (Esc la chiude).

import type { CardData } from "../../core/card.ts";
import type { Rating } from "../../core/log.ts";
import { PETS, petInfo } from "../../core/pets.ts";
import type { PetData } from "../../core/pets.ts";
import type { PomodoroSnapshot } from "../../core/pomodoro.ts";
import {
  ALLOWED_TIMERS, AMBIENT_TITLES, BACKGROUND_CHOICES, BACKGROUND_TITLES, CHATTINESS_TITLES, FOCUSES_PER_CYCLE,
} from "../../core/rules.ts";
import type { TimerKind } from "../../core/rules.ts";
import { duration } from "../../core/stats.ts";
import type { CardAnchor, CardCommand, CardOpenRequest, FocusFriendsApi } from "../../shared/api.ts";
import { button, h, icon } from "./dom.ts";
import type { IconName } from "./icons.generated.ts";
import { ACCENT, REST_GREEN, RATING_TITLE, createDial, createPostIt, createTomato, cycleDots, faceIcon, sticker } from "./widgets.ts";
import type { Dial, Tomato } from "./widgets.ts";

type Page = "main" | "timers" | "focus" | "rest";

const CARD_WIDTH = 300;
/** Quanto il compagno esce dal bordo alto della carta (nella scheda e nel quadrante). */
const OVERFLOW = 30;
const GAP_FROM_PET = 10;
const EDGE = 8;

export interface CardHost {
  api: FocusFriendsApi;
  container: HTMLElement;
  /** L'ultimo stato del timer, e quando è arrivato. */
  timer(): PomodoroSnapshot | null;
  petBox(): { left: number; top: number; width: number; height: number };
  scene(): { width: number; height: number };
  urlOf(path: string): string;
  /** La scheda si apre o si chiude (la pagina deve smettere o riprendere di decidere da sola quando lasciar passare i clic). */
  onOpenChange(open: boolean): void;
}

const defaultPage = (phase: PomodoroSnapshot["phase"]): Page => (phase === "focus" ? "focus" : phase === "rest" ? "rest" : "main");

export class MenuCard {
  private readonly host: CardHost;
  private readonly api: FocusFriendsApi;
  private backdrop: HTMLElement | null = null;
  private root: HTMLElement | null = null;
  private data: CardData | null = null;
  private anchor: CardAnchor = null;
  private onLeft = true;
  private page: Page = "main";
  private dialKind: TimerKind = "focus";
  private dialMinutes = 50;
  private timerMessage: string | null = null;
  private lockHint: string | null = null;
  private draftNote = "";
  private dial: Dial | null = null;
  private tomato: Tomato | null = null;
  private clock: HTMLElement | null = null;
  private shown: { phase: PomodoroSnapshot["phase"]; paused: boolean } = { phase: null, paused: false };
  private refreshTimer: number | undefined;
  private closedAt = 0;
  private readonly onKey = (event: KeyboardEvent): void => {
    if (event.key === "Escape") { event.preventDefault(); this.close(); }
  };
  private readonly onBlur = (): void => this.close();

  constructor(host: CardHost) {
    this.host = host;
    this.api = host.api;
  }

  get isOpen(): boolean { return this.root !== null; }

  /** Un clic sull'icona: apre o chiude. Subito dopo una chiusura (il clic che l'ha chiusa) non riapre. */
  toggle(request: CardOpenRequest): void {
    if (this.isOpen) {
      if (request.toggle) this.close(); else if (request.page === "timers") this.showTimers();
      return;
    }
    if (performance.now() - this.closedAt < 300) return;
    void this.open(request.anchor, request.page);
  }

  /** Riapre la scheda dov'era (per esempio dopo una finestra di sistema). */
  reopen(): void {
    if (!this.isOpen) void this.open(this.anchor, undefined);
  }

  async open(anchor: CardAnchor, page: "timers" | undefined): Promise<void> {
    if (this.isOpen) return;
    this.anchor = anchor;
    this.onLeft = true;
    this.data = await this.api.getCardData();
    const timer = this.host.timer();
    this.page = page === "timers" ? "timers" : defaultPage(timer?.phase ?? null);
    if (page === "timers") { this.dialKind = "focus"; this.dialMinutes = 50; this.timerMessage = null; }

    this.backdrop = h("div", { class: "card-backdrop" });
    this.backdrop.addEventListener("mousedown", () => this.close());
    this.backdrop.addEventListener("contextmenu", (event) => { event.preventDefault(); this.close(); });
    this.root = h("div", { class: "card-root", role: "dialog", "aria-label": "FocusFriends" });
    this.host.container.append(this.backdrop, this.root);
    this.host.onOpenChange(true);
    window.addEventListener("keydown", this.onKey, true);
    window.addEventListener("blur", this.onBlur);
    this.shown = { phase: timer?.phase ?? null, paused: timer?.isPaused ?? false };
    this.rebuild(true);
    requestAnimationFrame(() => this.root?.classList.add("visible"));
  }

  close(): void {
    if (!this.root) return;
    this.closedAt = performance.now();
    const root = this.root, backdrop = this.backdrop;
    this.root = null;
    this.backdrop = null;
    this.dial = null;
    this.tomato = null;
    this.clock = null;
    window.removeEventListener("keydown", this.onKey, true);
    window.removeEventListener("blur", this.onBlur);
    window.clearTimeout(this.refreshTimer);
    backdrop?.remove();
    root.classList.remove("visible");
    window.setTimeout(() => root.remove(), 120);
    this.host.onOpenChange(false);
  }

  // ---- comandi e dati

  private command(command: CardCommand, close = false): void {
    this.api.cardCommand(command);
    if (close) this.close(); else this.scheduleRefresh();
  }

  /** Rilegge i dati (dopo un comando, o quando cambia qualcosa che si vede) e ricostruisce la scheda. */
  scheduleRefresh(): void {
    window.clearTimeout(this.refreshTimer);
    this.refreshTimer = window.setTimeout(() => { void this.refresh(); }, 40);
  }

  private async refresh(): Promise<void> {
    if (!this.isOpen) return;
    this.data = await this.api.getCardData();
    this.rebuild(false);
  }

  /** Ogni secondo (e a ogni messaggio del timer) mentre è aperta: il tempo che scorre. Se il timer è partito o finito si ricostruisce. */
  onTimerState(state: PomodoroSnapshot): void {
    if (!this.isOpen) return;
    if (state.phase !== this.shown.phase) {
      this.page = defaultPage(state.phase);
      void this.refresh();
      return;
    }
    if (state.isPaused !== this.shown.paused) { void this.refresh(); return; }
    if (this.clock) this.clock.textContent = state.remainingText;
    this.tomato?.update(state.progress, state.remainingText, this.tomatoSmall(state));
    // A fine focus cambiano i dati (i minuti di oggi, i compagni sbloccati): si rileggono.
    if (state.lastFocus?.sessionId !== this.lastSession) { this.lastSession = state.lastFocus?.sessionId ?? null; void this.refresh(); }
  }
  private lastSession: string | null = null;

  // ---- posizione

  /** Mette la scheda accanto al compagno (dal lato in cui già sta, se c'è posto, con il bordo basso ai suoi piedi) o vicino all'icona. */
  reposition(): void {
    const root = this.root;
    if (!root) return;
    const scene = this.host.scene();
    const width = root.offsetWidth, height = root.offsetHeight;
    let left: number, bottom: number;
    if (this.anchor) {
      left = this.anchor.x + this.anchor.width / 2 - width / 2;
      // L'icona sta nella barra delle applicazioni: sotto l'area di lavoro (la scheda sta sopra di lei) o sopra (sta sotto).
      bottom = this.anchor.y + this.anchor.height / 2 > scene.height / 2 ? scene.height - 6 : this.anchor.y + this.anchor.height + 6 + height;
    } else {
      const pet = this.host.petBox();
      left = this.onLeft ? pet.left - width - GAP_FROM_PET : pet.left + pet.width + GAP_FROM_PET;
      if (this.onLeft && left < EDGE) { this.onLeft = false; left = pet.left + pet.width + GAP_FROM_PET; }
      else if (!this.onLeft && left + width > scene.width - EDGE) { this.onLeft = true; left = pet.left - width - GAP_FROM_PET; }
      bottom = pet.top + pet.height;
    }
    left = Math.min(Math.max(left, EDGE), Math.max(scene.width - width - EDGE, EDGE));
    bottom = Math.min(Math.max(bottom, height + 0), scene.height - EDGE);
    root.style.transform = `translate(${Math.round(left)}px, ${Math.round(bottom - height)}px)`;
  }

  // ---- costruzione

  /** Ricostruisce tutta la scheda dallo stato attuale (dopo un tocco, o quando cambia fase del timer). */
  private rebuild(first: boolean): void {
    const root = this.root, data = this.data;
    if (!root || !data) return;
    const timer = this.host.timer();
    const phase = timer?.phase ?? null;
    this.shown = { phase, paused: timer?.isPaused ?? false };
    // Le schermate del focus e della pausa ci sono solo finché c'è quella fase.
    if ((this.page === "focus" && phase !== "focus") || (this.page === "rest" && phase !== "rest")) this.page = "main";
    const focusedKey = document.activeElement instanceof HTMLElement ? document.activeElement.getAttribute("aria-label") : null;
    const draft = root.querySelector<HTMLInputElement>(".postit-input");
    if (draft) this.draftNote = draft.value;
    const scroll = root.scrollTop;

    root.replaceChildren();
    this.dial = null; this.tomato = null; this.clock = null;
    root.classList.toggle("notebook", this.page === "focus" || this.page === "rest");
    const state = timer ?? emptyTimer();
    const body = h("div", { class: `card page-${this.page}` });
    root.append(body);
    switch (this.page) {
      case "main": this.buildMain(root, body, data, state); break;
      case "timers": this.buildTimers(root, body, data, state); break;
      case "focus": this.buildFocus(body, data, state); break;
      case "rest": this.buildRest(body, data, state); break;
    }
    root.scrollTop = scroll;
    this.reposition();
    if (first) {
      (root.querySelector<HTMLElement>("button, [role=slider]"))?.focus({ preventScroll: true });
    } else if (focusedKey) {
      Array.from(root.querySelectorAll<HTMLElement>("[aria-label]")).find((el) => el.getAttribute("aria-label") === focusedKey)?.focus({ preventScroll: true });
    }
  }

  private avatar(pet: PetData, size: number, onClick: () => void): HTMLButtonElement {
    const circle = h("span", { class: "avatar-image" });
    circle.style.width = `${size}px`;
    circle.style.height = `${size}px`;
    // La testa del compagno ritagliata dall'immagine, centrata sul muso (iconFocus).
    const probe = new Image();
    probe.onload = () => {
      const crop = pet.iconCrop ?? { x: 0, y: 0, width: 1, height: 1 };
      const cropHeight = crop.height * probe.naturalHeight;
      const scale = (size / cropHeight) * 1.12;
      const shownWidth = crop.width * probe.naturalWidth * scale, shownHeight = cropHeight * scale;
      const fullWidth = probe.naturalWidth * scale, fullHeight = probe.naturalHeight * scale;
      circle.style.backgroundImage = `url("${this.host.urlOf(pet.iconImage)}")`;
      circle.style.backgroundSize = `${fullWidth}px ${fullHeight}px`;
      const x = size / 2 - shownWidth * pet.iconFocus - crop.x * fullWidth;
      const y = size / 2 - shownHeight * 0.48 - (1 - crop.y - crop.height) * fullHeight;
      circle.style.backgroundPosition = `${x}px ${y}px`;
    };
    probe.src = this.host.urlOf(pet.iconImage);
    const element = button("avatar", `Fai parlare ${pet.name}`, onClick, circle);
    element.style.width = `${size}px`;
    element.style.height = `${size}px`;
    return element;
  }

  private option(iconName: IconName, title: string, value: string | null, toggle: boolean | null, onClick: () => void): HTMLButtonElement {
    const element = button("option", title, onClick,
      icon(iconName, 14),
      h("span", { class: "option-title" }, title),
      value !== null ? h("span", { class: "option-value" }, value) : null,
      toggle !== null ? h("span", { class: `switch${toggle ? " on" : ""}` }, h("span", { class: "knob" })) : null,
    );
    if (toggle !== null) { element.setAttribute("role", "switch"); element.setAttribute("aria-checked", String(toggle)); }
    return element;
  }

  private slider(value: number, label: string, onChange: (value: number) => void): HTMLElement {
    const input = h("input", { type: "range", min: 0, max: 1, step: 0.01, "aria-label": label, class: "volume" });
    input.value = String(value);
    const paint = (): void => input.style.setProperty("--filled", `${Number(input.value) * 100}%`);
    paint();
    input.addEventListener("input", () => { paint(); onChange(Number(input.value)); });
    return input;
  }

  // ---- la scheda

  private buildMain(root: HTMLElement, body: HTMLElement, data: CardData, timer: PomodoroSnapshot): void {
    const pet = petInfo(this.petId());
    root.prepend(this.avatar(pet, 70, () => this.command({ name: "speak" }, true)));
    body.append(
      h("div", { class: "greeting" }, data.userName !== null ? `Ciao ${data.userName}` : "Ciao!"),
      h("div", { class: "status" }, this.statusText(data, timer, pet)),
    );

    // I compagni: i nomi, quello scelto sottolineato. Una riga sola se ci stanno tutti; altrimenti due, con lo stesso numero di nomi.
    const names = data.companions.map((entry) => {
      const selected = entry.id === pet.id;
      const label = entry.lock !== null ? `${entry.name}, bloccato: ${entry.lock}` : `Compagno: ${entry.name}`;
      return button(`companion${selected ? " selected" : ""}${entry.lock !== null ? " locked" : ""}`, label, () => {
        if (entry.lock !== null) { this.lockHint = `${entry.name} ${entry.lock}`; this.rebuild(false); return; }
        this.lockHint = null;
        this.command({ name: "selectPet", id: entry.id });
      }, entry.lock !== null ? icon("lock", 10) : null, entry.name);
    });
    const companions = h("div", { class: "companions" });
    const fill = (perLine: number): void => {
      companions.replaceChildren();
      for (let start = 0; start < names.length; start += perLine) {
        const row = h("div", { class: "companion-row" });
        names.slice(start, start + perLine).forEach((name, i) => {
          if (i > 0) row.append(h("span", { class: "sep", "aria-hidden": "true" }, "·"));
          row.append(name);
        });
        companions.append(row);
      }
    };
    fill(names.length);
    body.append(companions);
    if (companions.firstElementChild && companions.firstElementChild.scrollWidth > companions.clientWidth + 1) fill(Math.ceil(names.length / 2));
    const locked = data.companions.filter((entry) => entry.lock !== null);
    if (locked.length > 0) {
      const next = locked[0]!;
      body.append(h("div", { class: "lock-hint" }, this.lockHint ?? `${next.name} ${next.lock}`));
    }

    // Focus e pausa, oppure il timer che sta andando.
    if (timer.phase !== null) body.append(this.running(timer)); else body.append(this.durations(data));

    // Riepilogo di oggi
    const tiles: Array<[string, string]> = [
      [duration(data.todaySeconds), "oggi"],
      [String(data.todayFocusCount), "focus"],
      [String(data.streak), data.streakFrozen ? "ghiacciata" : data.streak === 1 ? "giorno di fila" : "di fila"],
    ];
    const today = h("div", { class: "tiles" });
    for (const [value, caption] of tiles) {
      today.append(button("tile", `${value} ${caption}`, () => this.command({ name: "showStats" }, true),
        h("span", { class: "tile-value" }, value), h("span", { class: "tile-caption" }, caption)));
    }
    body.append(today);

    // Statistiche (il giardino arriva con la seconda uscita)
    body.append(h("div", { class: "pills" },
      button("pill", "Statistiche", () => this.command({ name: "showStats" }, true), icon("chart", 14), "Statistiche")));

    // Linea e impostazioni rapide
    body.append(h("hr", { class: "rule" }));
    body.append(this.option("chat", "Frasi", CHATTINESS_TITLES[data.chattiness], null, () => this.command({ name: "cycleChattiness" })));
    const ambientIcon: IconName = data.ambient === "none" ? "mute" : data.ambient;
    body.append(this.option(ambientIcon, "Suono ambiente", AMBIENT_TITLES[data.ambient], null, () => this.command({ name: "cycleAmbient" })));
    if (data.ambient !== "none") body.append(this.volumeRow(data.ambientVolume, "Volume del suono", (value) => this.api.cardCommand({ name: "setAmbientVolume", value })));
    body.append(this.option("music", "Musica", data.musicLabel, null, () => this.command({ name: "cycleMusic" })));
    if (data.music !== "off") body.append(this.volumeRow(data.musicVolume, "Volume della musica", (value) => this.api.cardCommand({ name: "setMusicVolume", value })));
    if (pet.walks) body.append(this.option("walk", "Cammina per lo schermo", null, data.movementOn, () => this.command({ name: "toggleMovement" })));
    body.append(this.option("smile", "Chiedi com'è andata", null, data.askOn, () => this.command({ name: "toggleAsk" })));
    body.append(this.option(data.petVisible ? "eyeOff" : "eye", data.petVisible ? `Nascondi ${pet.name}` : `Mostra ${pet.name}`, null, null,
      () => this.command({ name: "toggleVisibility" }, true)));

    body.append(h("div", { class: "footer" },
      button("link", "Altre impostazioni", () => this.command({ name: "moreSettings" }, true), "Altre impostazioni…"),
      button("link", "Esci", () => this.command({ name: "quit" }, true), "Esci"),
    ));
  }

  private petId(): string {
    return this.currentPetId ?? PETS[0]!.id;
  }
  /** Il compagno scelto adesso (lo dice chi ha creato la scheda). */
  currentPetId: string | null = null;

  private statusText(data: CardData, timer: PomodoroSnapshot, pet: PetData): string {
    if (timer.phase === "focus") return timer.subject !== null ? `Focus · ${timer.subject}` : "Focus";
    if (timer.phase === "rest") return timer.isLongBreak ? "Pausa lunga" : "Pausa";
    return data.petVisible ? `${pet.name} è qui con te` : `${pet.name} è nascosto`;
  }

  private volumeRow(value: number, label: string, onChange: (value: number) => void): HTMLElement {
    return h("div", { class: "volume-row" }, h("span", { class: "volume-label" }, "Volume"), this.slider(value, label, onChange));
  }

  private durations(data: CardData): HTMLElement {
    const items: Array<{ number: string; caption: string; primary: boolean; label: string; run: CardCommand }> = [
      { number: "30", caption: "minuti", primary: false, label: "Focus di 30 minuti", run: { name: "startFocus", minutes: 30 } },
      { number: "50", caption: "minuti", primary: true, label: "Focus di 50 minuti", run: { name: "startFocus", minutes: 50 } },
      { number: String(this.breakMinutes(data)), caption: "pausa", primary: false, label: `Pausa di ${this.breakMinutes(data)} minuti`, run: { name: "startBreak", minutes: this.breakMinutes(data) } },
    ];
    const row = h("div", { class: "durations" });
    for (const item of items) {
      row.append(button(`duration${item.primary ? " primary" : ""}`, item.label, () => this.command(item.run, true),
        h("span", { class: "duration-number" }, item.number), h("span", { class: "duration-caption" }, item.caption)));
    }
    return h("div", { class: "durations-block" }, row,
      button("link small", "Altri timer", () => { this.showTimers(); }, "Altri timer…"));
  }

  /** La durata della pausa scelta (quella che parte da sola dopo il focus). */
  private breakMinutes(data: CardData): number {
    void data;
    return this.host.timer()?.breakMinutes ?? 5;
  }

  /** Mentre il timer va: il tempo che manca e il pulsante per fermarlo. */
  private running(timer: PomodoroSnapshot): HTMLElement {
    const title = timer.phase === "focus" ? (timer.subject !== null ? `FOCUS · ${timer.subject.toUpperCase()}` : "FOCUS") : "PAUSA";
    this.clock = h("div", { class: "running-clock" }, timer.remainingText);
    return h("div", { class: "running" },
      h("div", { class: "running-text" }, h("div", { class: "running-title" }, title), this.clock),
      button("pill-button primary", "Ferma il timer", () => this.command({ name: "stopTimer" }), "Ferma"),
    );
  }

  // ---- la pagina dei timer

  private showTimers(): void {
    this.dialKind = "focus";
    this.dialMinutes = 50;
    this.timerMessage = null;
    this.page = "timers";
    this.rebuild(false);
  }

  private buildTimers(root: HTMLElement, body: HTMLElement, data: CardData, timer: PomodoroSnapshot): void {
    const kind = this.dialKind;
    const maxMinutes = kind === "focus" ? 120 : 30, step = kind === "focus" ? 5 : 1;
    const hardMax = ALLOWED_TIMERS[kind].max;
    root.prepend(h("div", { class: "avatar-spacer" }));
    body.append(h("div", { class: "page-header" },
      button("back", "Torna alla scheda", () => { this.page = "main"; this.rebuild(false); }, icon("back", 18)),
      h("div", { class: "page-title" }, "Gira il timer"),
    ));
    // Focus o pausa
    const switcher = h("div", { class: "segmented", role: "tablist" });
    for (const k of ["focus", "rest"] as const) {
      const tab = button(`segment${kind === k ? " on" : ""}`, k === "focus" ? "Focus" : "Pausa", () => {
        if (this.dialKind === k) return;
        this.dialKind = k;
        this.dialMinutes = k === "rest" ? this.breakMinutes(data) : 50;
        this.timerMessage = null;
        this.rebuild(false);
      }, k === "focus" ? "Focus" : "Pausa");
      tab.setAttribute("role", "tab");
      tab.setAttribute("aria-selected", String(kind === k));
      switcher.append(tab);
    }
    body.append(switcher);

    // Il quadrante
    const dial = createDial((minutes) => { this.dialMinutes = minutes; this.timerMessage = null; this.updateTimersFooter(data); });
    dial.update(this.dialMinutes, maxMinutes, step, hardMax);
    this.dial = dial;
    body.append(h("div", { class: "dial-wrap" }, dial.element));
    body.append(h("div", { class: "dial-link", id: "dial-link" }));
    body.append(h("div", { class: "chips", id: "dial-chips" }));
    const start = button("start", kind === "focus" ? "Avvia il focus" : "Avvia la pausa", () => {
      this.command(kind === "focus" ? { name: "startFocus", minutes: this.dialMinutes } : { name: "startBreak", minutes: this.dialMinutes }, true);
    }, icon("play", 14), kind === "focus" ? "Avvia il focus" : "Avvia la pausa");
    body.append(start);
    if (timer.phase !== null) {
      body.append(button("link", "Ferma il timer", () => this.command({ name: "stopTimer" }), `Ferma il timer in corso (${timer.remainingText})`));
    }
    this.updateTimersFooter(data);
  }

  /** La riga sotto il quadrante (salva, rimuovi, o un suggerimento) e i timer che hai: cambiano girando il quadrante. */
  private updateTimersFooter(data: CardData): void {
    const root = this.root;
    if (!root) return;
    const kind = this.dialKind;
    const all = kind === "focus" ? data.focusTimers : data.restTimers;
    const mine = kind === "focus" ? data.customFocus : data.customRest;
    const link = root.querySelector<HTMLElement>("#dial-link")!;
    link.replaceChildren();
    if (this.timerMessage !== null) {
      link.append(h("span", { class: "message" }, this.timerMessage));
    } else if (mine.includes(this.dialMinutes)) {
      link.append(button("link", "Rimuovi dai miei timer", () => {
        this.api.cardCommand({ name: "removeTimer", kind, minutes: this.dialMinutes });
        this.scheduleRefresh();
      }, "Rimuovi dai miei timer"));
    } else if (!all.includes(this.dialMinutes)) {
      link.append(button("link accent", "Salva tra i miei timer", () => {
        void this.api.addCustomTimer(kind, this.dialMinutes).then((result) => {
          if (result.result === "tooMany") this.timerMessage = `Puoi salvarne al massimo ${result.max}: togline uno.`;
          else if (result.result === "outOfRange") this.timerMessage = `Da ${result.min} a ${result.max} minuti.`;
          void this.refresh();
        });
      }, "Salva tra i miei timer"));
    } else {
      link.append(h("span", { class: "hint" }, kind === "rest" ? "Parte da sola dopo ogni focus." : "Trascina il pallino per cambiare i minuti."));
    }
    // I timer che hai: si toccano per metterli sul quadrante.
    const chips = root.querySelector<HTMLElement>("#dial-chips")!;
    chips.replaceChildren();
    for (const minutes of all) {
      chips.append(button(`chip${minutes === this.dialMinutes ? " on" : ""}${mine.includes(minutes) ? " mine" : ""}`, `${minutes} minuti`, () => {
        this.dialMinutes = minutes;
        this.timerMessage = null;
        this.dial?.update(minutes, kind === "focus" ? 120 : 30, kind === "focus" ? 5 : 1, ALLOWED_TIMERS[kind].max);
        this.updateTimersFooter(data);
      }, String(minutes)));
    }
  }

  // ---- le schermate del focus e della pausa

  private tomatoSmall(timer: PomodoroSnapshot): string {
    return timer.phase === "rest" ? "di pausa" : timer.isPaused ? "fermo" : "rimasti";
  }

  /** Il titolo e la riga sotto, con il compagno a destra (un tocco e parla). */
  private header(body: HTMLElement, title: string, detail: string): void {
    const pet = petInfo(this.petId());
    body.append(h("div", { class: "notebook-header" },
      h("div", { class: "notebook-text" }, h("div", { class: "notebook-title" }, title), h("div", { class: "notebook-detail" }, detail)),
      this.avatar(pet, 44, () => this.command({ name: "speak" }, true)),
    ));
  }

  private tomatoBlock(timer: PomodoroSnapshot, ring: string): HTMLElement {
    const tomato = createTomato(ring);
    tomato.update(timer.progress, timer.remainingText, this.tomatoSmall(timer));
    this.tomato = tomato;
    return h("div", { class: "tomato-wrap" }, tomato.element);
  }

  private stickerPair(secondTitle: string, secondIcon: IconName, secondClass: string, second: () => void): HTMLElement {
    return h("div", { class: "stickers" },
      sticker("accent", "Aggiungi 5 minuti", () => this.command({ name: "addMinutes" }), icon("plus", 16), "5 minuti"),
      sticker(secondClass, secondTitle, second, icon(secondIcon, 14), secondTitle),
    );
  }

  private menuLink(): HTMLElement {
    return button("link left", "Torna alla scheda completa", () => { this.page = "main"; this.rebuild(false); }, icon("back", 12), "Menu completo");
  }

  private buildFocus(body: HTMLElement, data: CardData, timer: PomodoroSnapshot): void {
    body.append(h("div", { class: "spiral", "aria-hidden": "true" }, ...Array.from({ length: 9 }, () => h("span", { class: "hole" }))));
    this.header(body, timer.subject ?? "Focus", `${timer.rangeText}  ·  ${timer.focusMinutes} minuti`);
    if (timer.cycleDone !== null) {
      const current = Math.min(timer.cycleDone + 1, FOCUSES_PER_CYCLE);
      body.append(cycleDots(timer.cycleDone, true, `Focus ${current} di ${FOCUSES_PER_CYCLE}`));
    }
    body.append(this.tomatoBlock(timer, ACCENT));
    body.append(this.stickerPair(timer.isPaused ? "Riprendi" : "Ferma", timer.isPaused ? "play" : "stop", timer.isPaused ? "chip-on" : "paper",
      () => this.command({ name: "togglePause" })));
    // Da fermo c'è anche «Termina e salva»: chiude il focus tenendo i minuti fatti.
    if (timer.isPaused) {
      body.append(button("link accent strong", "Termina il focus e salvalo", () => this.command({ name: "stopTimer" }, true), icon("checkCircle", 14), "Termina e salva"));
    }

    // Il sottofondo: uno alla volta, e il volume.
    body.append(h("div", { class: "section-title" }, "Sottofondo"));
    const chips = h("div", { class: "background-chips" });
    for (const choice of BACKGROUND_CHOICES) {
      chips.append(button(`bg-chip${data.background === choice ? " on" : ""}`, `Sottofondo: ${BACKGROUND_TITLES[choice]}`,
        () => this.command({ name: "setBackground", choice }), BACKGROUND_TITLES[choice]));
    }
    body.append(chips);
    body.append(data.background === "none"
      ? h("div", { class: "hint" }, "Scegli un suono o la musica per concentrarti.")
      : this.slider(data.backgroundVolume, "Volume del sottofondo", (value) => this.api.cardCommand({ name: "setBackgroundVolume", value })));

    // Le note: un foglietto.
    const postit = createPostIt(timer.notes, this.draftNote, (text) => {
      this.draftNote = "";
      this.api.cardCommand({ name: "addNote", text });
      this.scheduleRefresh();
      window.setTimeout(() => this.root?.querySelector<HTMLInputElement>(".postit-input")?.focus(), 120);
    });
    body.append(postit.element);

    body.append(button("danger", "Elimina questo focus", () => this.command({ name: "discardFocus" }, true), icon("trash", 14), "Elimina questo focus"));
    body.append(this.menuLink());
  }

  private buildRest(body: HTMLElement, data: CardData, timer: PomodoroSnapshot): void {
    body.append(h("div", { class: "spiral", "aria-hidden": "true" }, ...Array.from({ length: 9 }, () => h("span", { class: "hole" }))));
    const last = timer.lastFocus;
    const detail = last !== null ? `Hai fatto ${last.minutes} minuti${last.subject !== null ? ` di ${last.subject}` : ""}` : "Stacca un attimo.";
    this.header(body, timer.isLongBreak ? "Pausa lunga" : "Pausa", detail);
    if (timer.cycleDone !== null) {
      body.append(cycleDots(timer.cycleDone, false,
        timer.isLongBreak ? `${timer.cycleDone} di ${FOCUSES_PER_CYCLE}: ciclo completo` : `${timer.cycleDone} di ${FOCUSES_PER_CYCLE} fatti`));
    }
    body.append(this.tomatoBlock(timer, REST_GREEN));
    body.append(this.stickerPair("Salta", "skip", "paper", () => this.command({ name: "stopTimer" })));
    body.append(h("div", { class: "tip" }, timer.isLongBreak ? "Alzati e muoviti un po': è una pausa lunga." : "Bevi un po' d'acqua e guarda lontano."));

    // Un altro focus
    const again = last?.minutes ?? 50;
    body.append(sticker("accent big", `Nuovo focus · ${again} min`, () => this.command({ name: "startFocus", minutes: again }, true), `Nuovo focus · ${again} min`));

    // Com'è andata?
    if (data.hasLastSession) {
      body.append(h("div", { class: "section-title" }, "Com'è andata?"));
      if (data.lastRating !== null) {
        body.append(h("div", { class: "rated" }, faceIcon(data.lastRating, 30, true), h("span", {}, `Segnato: ${RATING_TITLE[data.lastRating]}`)));
      } else {
        const faces = h("div", { class: "faces" });
        for (const rating of ["good", "soso", "poor"] as Rating[]) {
          faces.append(button("face-button", RATING_TITLE[rating], () => this.command({ name: "rateLast", rating }), faceIcon(rating, 34), h("span", {}, RATING_TITLE[rating])));
        }
        body.append(faces);
      }
    }
    body.append(h("div", { class: "footer" }, this.menuLink(),
      button("link", "Statistiche", () => this.command({ name: "showStats" }, true), "Statistiche")));
  }
}

function emptyTimer(): PomodoroSnapshot {
  return {
    phase: null, label: "", remainingText: "00:00", isPaused: false, progress: 0, growthProgress: null, elapsedSeconds: 0,
    remainingSeconds: 0, rangeText: "", focusMinutes: 0, breakMinutes: 5, subject: null, notes: [], lastFocus: null,
    isLongBreak: false, cycleDone: null, graceSecondsLeft: null,
  };
}
