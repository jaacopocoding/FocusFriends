// La musica del focus (MusicPlayer.swift): parte con il focus e si ferma a fine focus, in ordine casuale, a volume basso. Suona i
// brani inclusi nell'app oppure i file della cartella scelta; l'ordine lo decide core/audioPlan.ts.

import { FADE_SECONDS, MUSIC_PREVIEW_MS, MusicQueue, musicWanted } from "../../core/audioPlan.ts";
import { clampVolume } from "../../core/rules.ts";
import type { MusicSource } from "../../core/rules.ts";
import type { FocusFriendsApi, MusicList } from "../../shared/api.ts";

export interface MusicOptions {
  api: FocusFriendsApi;
  source: MusicSource;
  volume: number;
}

export class MusicPlayer {
  private readonly api: FocusFriendsApi;
  private audio: HTMLAudioElement | null = null;
  private readonly queue = new MusicQueue();
  private list: MusicList | null = null;
  private fadeTimer: number | undefined;
  private stopTimer: number | undefined;
  private previewTimer: number | undefined;
  private generation = 0;
  source: MusicSource;
  volume: number;
  focusActive = false;
  currentTitle: string | null = null;

  constructor(options: MusicOptions) {
    this.api = options.api;
    this.source = options.source;
    this.volume = clampVolume(options.volume);
  }

  // ---- comandi

  setFocusActive(active: boolean): void {
    this.focusActive = active;
    this.apply(false);
  }

  /** Cambia sorgente (o cartella): ricomincia da un brano nuovo. */
  setSource(source: MusicSource, preview: boolean): void {
    this.source = source;
    this.stopNow();
    this.apply(preview && !this.focusActive);
  }

  /** La cartella è un'altra: l'elenco si rilegge e si ricomincia. */
  folderChanged(): void {
    if (this.source !== "folder") return;
    this.stopNow();
    this.apply(!this.focusActive);
  }

  setVolume(volume: number, preview: boolean): void {
    this.volume = clampVolume(volume);
    if (this.audio && !this.audio.paused) this.fade(this.volume, 0.2);
    if (preview && !this.focusActive && this.source !== "off") this.apply(true);
  }

  /** Dopo uno sleep o un cambio di uscita audio il brano può essersi fermato da solo: se doveva suonare, riparte. */
  recover(): void {
    if (!musicWanted(this.source, this.focusActive, this.previewTimer !== undefined)) return;
    const audio = this.audio;
    if (audio && !audio.paused) return;
    if (audio && !audio.ended) {
      audio.play().catch(() => { this.stopNow(); this.apply(false); });
      return;
    }
    this.stopNow();
    this.apply(false);
  }

  // ---- riproduzione

  private apply(previewing: boolean): void {
    window.clearTimeout(this.previewTimer);
    this.previewTimer = undefined;
    if (musicWanted(this.source, this.focusActive, previewing)) {
      window.clearTimeout(this.stopTimer);
      this.stopTimer = undefined;
      if (this.audio && !this.audio.paused) this.fade(this.volume, 0.3);
      else void this.playNext(true);
      if (previewing) this.previewTimer = window.setTimeout(() => this.apply(false), MUSIC_PREVIEW_MS);
    } else if (this.audio && !this.audio.paused) {
      // Si spegne con una dissolvenza, poi si ferma del tutto.
      this.fade(0, FADE_SECONDS);
      window.clearTimeout(this.stopTimer);
      this.stopTimer = window.setTimeout(() => this.stopNow(), (FADE_SECONDS + 0.2) * 1000);
    }
  }

  private stopNow(): void {
    window.clearTimeout(this.stopTimer);
    window.clearInterval(this.fadeTimer);
    this.stopTimer = undefined;
    this.generation += 1;
    if (this.audio) { this.audio.pause(); this.audio.removeAttribute("src"); this.audio.load(); }
    this.audio = null;
    this.queue.reset();
    this.currentTitle = null;
  }

  /** Porta il volume a `target` in `seconds` secondi (lineare). */
  private fade(target: number, seconds: number): void {
    window.clearInterval(this.fadeTimer);
    const audio = this.audio;
    if (!audio) return;
    const from = audio.volume, started = performance.now();
    this.fadeTimer = window.setInterval(() => {
      const t = Math.min((performance.now() - started) / (seconds * 1000), 1);
      audio.volume = Math.min(Math.max(from + (target - from) * t, 0), 1);
      if (t >= 1) window.clearInterval(this.fadeTimer);
    }, 50);
  }

  /** Il prossimo brano della coda; salta i file che non si riescono a leggere, e se nessuno si legge si ferma. */
  private async playNext(fadeIn: boolean): Promise<void> {
    const generation = ++this.generation;
    if (this.queue.remaining === 0) this.list = await this.api.musicTracks(this.source);
    const list = this.list;
    if (generation !== this.generation || !list) return;
    const titles = new Map(list.tracks.map((track) => [String(track.id), track.title]));
    for (let attempts = 0; attempts <= list.tracks.length; attempts += 1) {
      const id = this.queue.next(list.tracks.map((track) => String(track.id)));
      if (id === null) break;
      const audio = new Audio(`ff://app/music/${list.version}/${id}`);
      audio.volume = fadeIn ? 0 : this.volume;
      try {
        await audio.play();
      } catch {
        continue;
      }
      if (generation !== this.generation) { audio.pause(); return; }
      this.audio = audio;
      this.currentTitle = titles.get(id) ?? null;
      if (fadeIn) this.fade(this.volume, FADE_SECONDS);
      audio.addEventListener("ended", () => {
        if (this.audio !== audio) return;
        if (this.focusActive || this.previewTimer !== undefined) void this.playNext(false); else this.stopNow();
      });
      return;
    }
    this.audio = null;
    this.currentTitle = null;
  }

  get playing(): boolean { return this.audio !== null && !this.audio.paused; }

  /** Solo nelle prove: come se il sistema fermasse il brano. */
  interruptForTest(): void {
    this.audio?.pause();
  }

  /** Solo nelle prove: porta il brano a un secondo dalla fine, per vedere che parta il prossimo. */
  seekNearEnd(): void {
    if (this.audio && Number.isFinite(this.audio.duration)) this.audio.currentTime = Math.max(this.audio.duration - 1, 0);
  }
}
