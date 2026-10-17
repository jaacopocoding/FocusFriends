// Dove sta la finestra trasparente tra gli schermi: su uno alla volta (area di lavoro), e si sposta con il compagno. Trascinandolo oltre il
// bordo la finestra segue il cursore sull'altro schermo; se lo schermo sparisce torna sul principale. (Con FF_FAKE_DISPLAYS, solo nelle
// prove, gli schermi sono quelli indicati.)

import { screen } from "electron";
import type { BrowserWindow, Display } from "electron";
import { currentOrPrimary, displayAt, displayToFollow } from "../core/displays.ts";
import type { DisplayInfo, Rect } from "../core/displays.ts";
import { CHANNEL } from "../shared/api.ts";

const FOLLOW_MS = 50;

export interface Stage {
  readonly current: DisplayInfo;
  displays(): DisplayInfo[];
  /** Porta la finestra su quello schermo; `keepPosition` = il compagno resta dov'è (trascinamento), altrimenti riparte da terra. */
  moveTo(id: number, keepPosition: boolean): void;
  /** L'area di lavoro è cambiata, o uno schermo è stato tolto o aggiunto. */
  refit(): void;
  /** Si comincia o si finisce di trascinare il compagno: si segue il cursore. */
  setDragging(on: boolean): void;
  /** Lo schermo che contiene questo rettangolo (per sapere se l'icona è sullo stesso schermo del compagno). */
  displayOf(rect: Rect): DisplayInfo | null;
}

function info(display: Display, primaryId: number): DisplayInfo {
  return { id: display.id, workArea: display.workArea, bounds: display.bounds, primary: display.id === primaryId };
}

export function createStage(win: BrowserWindow, send: (channel: string, payload?: unknown) => void): Stage {
  const fake = process.env["FF_FAKE_DISPLAYS"] ? (JSON.parse(process.env["FF_FAKE_DISPLAYS"]) as DisplayInfo[]) : null;
  const displays = (): DisplayInfo[] => fake ?? screen.getAllDisplays().map((d) => info(d, screen.getPrimaryDisplay().id));
  let current: DisplayInfo = currentOrPrimary(displays(), null) ?? { id: 0, primary: true, bounds: { x: 0, y: 0, width: 1280, height: 720 }, workArea: { x: 0, y: 0, width: 1280, height: 720 } };
  let timer: NodeJS.Timeout | undefined;

  const place = (display: DisplayInfo, keepPosition: boolean): void => {
    current = display;
    const area = display.workArea;
    const bounds = win.getBounds();
    if (bounds.x !== area.x || bounds.y !== area.y || bounds.width !== area.width || bounds.height !== area.height) win.setBounds(area);
    send(CHANNEL.stageMoved, { x: area.x, y: area.y, width: area.width, height: area.height, keepPosition });
  };

  const stage: Stage = {
    get current() { return current; },
    displays,
    moveTo(id, keepPosition) {
      const target = displays().find((d) => d.id === id);
      if (target && target.id !== current.id) place(target, keepPosition);
    },
    refit() {
      if (win.isDestroyed()) return;
      const all = displays();
      const display = currentOrPrimary(all, current.id);
      if (!display) return;
      // Lo schermo del compagno non c'è più: torna sul principale e riparte da terra.
      place(display, display.id === current.id);
    },
    setDragging(on) {
      clearInterval(timer);
      timer = undefined;
      if (!on) return;
      timer = setInterval(() => {
        if (win.isDestroyed()) return;
        const cursor = fake ? null : screen.getCursorScreenPoint();
        const target = cursor ? displayToFollow(displays(), current.id, cursor) : null;
        if (target) place(target, true);
      }, FOLLOW_MS);
    },
    displayOf(rect) {
      return displayAt(displays(), rect.x + rect.width / 2, rect.y + rect.height / 2);
    },
  };
  return stage;
}
