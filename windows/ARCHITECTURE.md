# FocusFriends for Windows — Architecture and code walkthrough

> Purpose: a factual description of how the Windows version works, written so that another reader (human or AI) can judge
> whether the code is acceptable as written or needs revision. It is the counterpart of `../ARCHITECTURE.md`, which describes
> the Mac app; features are numbered and named alike where they correspond, and `PARITA.md` compares them one by one.
> Snapshot described: branch `main` after commit `5e201c1` (the release `windows-v1.0.0`, version `1.0.0`, is at `75d07e9`; the
> commits after it only change documentation). First release: **everything except the garden** (see `../PIANO_WINDOWS.md`).
> Everything here was read from the files in the repository; statements that could not be fully verified are marked
> **[uncertain]**. Rationales are labelled **[documented]** (comes from code comments, `PIANO_WINDOWS.md`, `FORMATI.md` or git
> history) or **[inferred]** (deduced from the code).
> UI strings and code comments are in Italian (as on the Mac); identifiers are English. UI strings quoted here are glossed.
> **What was and was not exercised on a real Windows machine:** the code runs on macOS during development (Electron is
> cross-platform); the Windows CI job runs the type check, the 247 logic tests and the build on a Windows runner, and the author
> installed the released installer on a Windows computer for a brief check (see `PARITA.md`, "Prova su Windows"). The parts that
> only exist on Windows (real click-through, task-bar sides, scale factors, two monitors, sleep, fullscreen apps, virtual
> desktops) are listed in `PROVE_SU_WINDOWS.md` and have **not** been verified one by one.

---

## 1. Overview

### 1.1 What the app does

Same product as the Mac app: a desktop companion (one of four characters) that walks on the desktop, speaks, and keeps a
Pomodoro-style timer ("Pomofocus") with a notebook-like card, background sounds, statistics and companion unlocking. Study
sessions are stored in the same JSON files as on the Mac (`../FORMATI.md`). The garden (points, shop, meadow) is not part of
this release. All data stays on the machine; the app makes no network requests (`connect-src ff:` in the page's CSP, no
HTTP client in the code **[inferred]**).

### 1.2 Stack and versions (read from `package.json`, `tsconfig.json`, `electron-builder.yml`)

| Item | Value | Source |
|---|---|---|
| Shell | Electron **44.9.0** (Chromium + Node), main process and pages in TypeScript | `package.json` |
| Language | TypeScript **7.0.2**, `strict`, `noUncheckedIndexedAccess`, `erasableSyntaxOnly`, `verbatimModuleSyntax`; `tsc --noEmit` only type-checks | `tsconfig.json` |
| Bundler | esbuild **0.28.2**: main and preload → CommonJS for `node22`, pages → IIFE for `chrome140`, the audio worklet in a separate file | `tools/build.mjs` |
| Runtime dependencies | **none** (only `devDependencies`: electron, electron-builder 26.15.3, esbuild, typescript, @types/node, lucide-static 1.59.0). Everything is bundled | `package.json` |
| Tests | Node's built-in runner (`node --test`) on `.ts` files via Node ≥ 24 type stripping; no test framework, no dependencies | `package.json` (`engines.node >= 24`) |
| Packaging | electron-builder, NSIS one-click installer **per user** (no administrator rights), `x64` and `arm64`, `asar`, maximum compression | `electron-builder.yml` |
| Font | **Chewy** (Apache 2.0), bundled as `resources/fonts/chewy-latin-400.woff2`; icons are Lucide (ISC), pre-rendered into `icons.generated.ts` | `card.css`, `tools/genera-icone.mjs` |
| Target OS | Windows 10 and 11 (x64, ARM64). It also runs on macOS for development, with a separate data folder (§4.12) | `PIANO_WINDOWS.md` §0 |
| Size | ≈ 8,700 lines of TypeScript in `src/` (core ≈ 3,600, main ≈ 1,300, renderer ≈ 3,500, shared and preload ≈ 270), ≈ 3,000 in `test/` | `wc -l` |

### 1.3 How to run it

```bash
cd windows
npm install          # Electron, TypeScript, esbuild, electron-builder (devDependencies)
npm run check        # tsc --noEmit
npm test             # 247 tests, no dependencies needed
npm start            # builds dist/ and opens the companion (on macOS: data in a test folder)
npm run pacchetto    # build + stage resources + electron-builder --win → release/*.exe
```

`npm run build` (`tools/build.mjs`) writes `dist/`. `tools/prepara-risorse.mjs` stages exactly the images, phrase files and music the app
uses (`build/assets`, 114 files) plus `resources/` (`build/resources`) for the installer. `RILASCIO.md` describes the release procedure.

---

## 2. Project structure

```
windows/
├── package.json, tsconfig.json, electron-builder.yml
├── README.md · ARCHITECTURE.md (this file) · PARITA.md · PROVE_SU_WINDOWS.md · RILASCIO.md · NOTE_DI_RILASCIO.md
├── data/pets.json                  the four companions' data, GENERATED from Pet.swift by ../tools/genera-pets.sh (so Mac and Windows cannot differ)
├── resources/                      fine-focus.wav (the end-of-focus chime, generated from scratch), fonts/ (Chewy + licence)
├── installer/icon.png              the installer and program icon
├── src/
│   ├── core/       (26 files)      pure logic, no Electron, no DOM: runs in Node tests, in the main process and in the pages
│   ├── main/       (11 files)      main process: windows, tray, timer service, files, protocol, dialogs, power events
│   ├── preload/    (2 files)       the secure bridges (`preload.cjs` for the overlay, `preload-stats.cjs` for the statistics window)
│   ├── shared/     (2 files)       the typed contract between main and pages (`api.ts`, `statsApi.ts`)
│   └── renderer/                   the overlay page (companion, bubble, clock, card, dialogs, sounds) and the statistics page
├── test/           (25 files)      23 test files + 2 helpers (`util.ts`, `atteso.ts`); see §7
└── tools/                          build.mjs, genera-icone.mjs, prepara-risorse.mjs
```

| Area | Files (lines) |
|---|---|
| `core/` | `log.ts` (637), `pomodoro.ts` (457), `stats.ts` (284), `walker.ts` (275), `profile.ts` (221), `settings.ts` (156), `rules.ts` (155), `time.ts` (151), `dashboard.ts` (146), `noise.ts` (146), `card.ts` (125), `pets.ts` (112), `phrases.ts` (92), `text.ts` (84), `displays.ts` (86), `audioPlan.ts` (72), `diagnostics.ts` (69), `points.ts` (57), `music.ts` (55), `files.ts` (53), `tracks.ts` (40), `rewards.ts` (40), `unlocks.ts` (33), `reflection.ts` (30), `csv.ts` (27), `colors.ts` (22) |
| `main/` | `main.ts` (331), `card.ts` (223), `tray.ts` (229), `statsWindow.ts` (146), `protocol.ts` (69), `music.ts` (69), `stage.ts` (75), `timer.ts` (79), `overlay.ts` (46), `paths.ts` (31), `login.ts` (18) |
| `renderer/` | `overlay.ts` (642, the page controller), `card/card.ts` (615), `petView.ts` (380), `stats/stats.ts` (278), `clockView.ts` (255), `card/widgets.ts` (236), `audio/music.ts` (160), `audio/ambient.ts` (159), `speaker.ts` (156), `dialogs/*` (5 files, ≈ 300), `extendPrompt.ts` (71), `card/dom.ts` (60), `bubble.ts` (51), `audio/noiseWorklet.ts` (40), `avatar.ts` (26), `fonts.ts` (14), CSS and HTML |

Notes:

- The rule that keeps `core/` reusable: modules imported by a page must not import `node:*`. Where a module needed both, it was split:
  `rules.ts`/`settings.ts`, `tracks.ts`/`music.ts`. Nothing enforces this except the page bundle failing to build **[inferred]**.
- `core/points.ts` (garden points) is **not imported by any app module**; it exists for the garden release and for the contract tests (`test/atteso.ts`).
  `PomodoroDeps.gardenLine` and `StatsDeps.onDeleteAll` are the empty hooks the garden will fill (§4.7, §4.13).

---

## 3. Process model and data flow

```
                       ┌───────────────────────────── main process (Node) ─────────────────────────────┐
  Windows ────────────►│ tray · single-instance lock · power events · displays · file dialogs · login │
  (clicks, power,      │ TimerService: PomodoroEngine + SessionLog   (tick every 200 ms)               │
   displays, shell)    │ Settings · Profile · AppLog · CardService · MusicService · Stage              │
                       │ custom protocol  ff://app/…  (pages, assets, resources, music with Range)     │
                       └───────────┬───────────────────────────────────────────────┬──────────────────┘
        IPC (typed channels in shared/api.ts)                                       │ IPC (shared/statsApi.ts)
                       ┌───────────▼───────────────┐                    ┌───────────▼───────────────┐
                       │ overlay page (1 window)   │                    │ statistics page           │
                       │ transparent, topmost,     │                    │ normal window, created on │
                       │ covers the work area      │                    │ demand, destroyed on close│
                       │ pet · bubble · clock ·    │                    └───────────────────────────┘
                       │ "+5" · card · dialogs ·   │
                       │ ambient/music/chime audio │
                       └───────────────────────────┘
```

Principles (all **[documented]** in `PIANO_WINDOWS.md` unless stated):

- **One transparent window** the size of the work area of the companion's display, instead of one small window per element (as the Mac
  app does). The companion, the bubble, the clock, the "+5 minutes" prompt, the card and the dialogs are elements of one page.
- **The timer lives in the main process**, not in the page: Chromium throttles timers of hidden pages, and the timer must not stop when the
  card closes. The page receives snapshots and draws them.
- **Pure logic in `core/`**, shared by the main process, the pages and the tests; the same TypeScript runs in all three.
- **The pages have no Node and no file access**: `contextIsolation: true`, `sandbox: true`, `nodeIntegration: false`, a CSP of
  `default-src 'none'` with only `ff:` allowed for images, scripts, styles, fonts, media and connections, and a preload that exposes a fixed
  set of functions (`window.focusfriends`, `window.focusfriendsStats`). Disk access goes through typed messages.
- **Data compatibility with the Mac app** is a contract, checked both ways by tests (§7).

### 3.1 The IPC contract (`shared/api.ts`, `shared/statsApi.ts`)

| Channel | Direction | Payload / purpose |
|---|---|---|
| `renderer:ready` | page → main | the page can receive messages; before it, main queues them (`pageReady` + `waiting` in `main.ts`) |
| `settings:get` / `settings:changed` | invoke / main → page | `SettingsSnapshot` (pet, movement, phrase frequency, ask-how-it-went, ambient sound and volume, music source/folder/volume) |
| `phrase:next` | invoke | next phrase of that companion's shuffled deck (file re-read each time) |
| `timer:get-state` / `timer:state` | invoke / main → page | `PomodoroSnapshot`; sent when what is visible changes (§4.7) |
| `timer:event` | main → page | `PomodoroEvent`: say, dismissSpeech, sound, focusActive, focusCompleted, focusRecorded, reset, graceBegan, graceEnded |
| `timer:extend` | page → main | the "+5 minutes" button |
| `card:data` / `card:command` / `card:add-timer` | invoke / send / invoke | `CardData` (§4.9), `CardCommand` (a closed union of 27 commands), custom-timer saving with its result |
| `card:toggle` / `card:reopen` | main → page | open/close the card (with an anchor rectangle or none), or reopen it where it was |
| `overlay:input-mode` | page → main | `{interactive, keyboard}`: whether the window should receive clicks and the keyboard (§4.3) |
| `overlay:visibility` | main → page | hide/show |
| `stage:moved` / `stage:dragging` | main → page / page → main | work-area rectangle of the window's display; start/stop of a drag (§4.4) |
| `focus:ask-subject`, `name:ask`, `intro:show`, `speech:now` | main → page | tray menu actions that need the page to show something |
| `music:tracks` | invoke | `MusicList {version, tracks[{id,title}]}` for a source |
| `system:resumed` | main → page | the computer woke up or the screen was unlocked (§4.15) |
| `stats:get-data`, `stats:data`, `stats:edit`, `stats:delete`, `stats:export-csv`, `stats:delete-all`, `stats:back` | statistics page ↔ main | all calls check `event.sender === window.webContents` (`trusted`) |

### 3.2 The custom protocol `ff://app/` (`main/protocol.ts`)

Registered before `ready` as `standard`, `secure`, `supportFetchAPI`. One origin for everything, so images can be read from a canvas without
cross-origin rules. Routes: `/music/<version>/<id>` (only tracks of the *current* list; the version changes at each listing, so an old id
stops working; served with `Range` support, 200/206/416) · `/assets/…` (`assets/` of the repository, or `resources/assets` when packaged) ·
`/resources/…` (the Windows-only resources) · everything else from `dist/renderer`. A resolved path that leaves its root gets 403; a missing
file gets 404 instead of throwing.

---

## 4. Features

### 4.1 App launch and wiring (`main/main.ts`, `start()`)

Order of what `start()` does (the module's top level first registers the scheme and takes the single-instance lock):

1. `app.setAppUserModelId("com.jacopo.focusfriends")`; the data folder is created (§4.12); `AppLog` is opened and the first line is written
   (version, OS version, architecture, Electron version).
2. `Settings`, the music service, the protocol handler, `Profile` (with `developer: () => settings.developerMode`).
3. `createOverlay(primaryDisplay())` → the transparent window (§4.2). A `render-process-gone` handler reloads the page at most three times in ten minutes.
4. `send()` — a queue that holds messages until the page sends `renderer:ready`.
5. `createStage` (§4.4), settings/profile observers, `profile.keepAllCompanions(PET_IDS)` (someone who used the app before gets all companions).
6. `startTimer` (§4.7) → `TimerService`; `recoverInterrupted()` runs inside it.
7. Statistics controller, `CardService`, tray (their constructors reference each other lazily: `tray?.refresh()`).
8. IPC handlers, `session-end` and `before-quit` → `shutdown()` (records a running focus as interrupted), `second-instance` → show the companion.
9. `service.engine.onEvent`: on `sound` it shows the companion if it was hidden; on `focusRecorded` it evaluates unlocks (§4.14).
10. Display and power listeners (§4.4, §4.15). If `FF_SELFTEST` is set, the self-test harness starts (§5.3).

On the first `renderer:ready`, if `profile.introSeen` is false the main process sends `intro:show` after 800 ms.

### 4.2 The overlay window and click-through (`main/overlay.ts`, `renderer/overlay.ts`)

- **Window:** `transparent`, `frame: false`, `hasShadow: false`, not resizable/movable/minimisable, `focusable: false`, `skipTaskbar: true`, `alwaysOnTop`
  at level `screen-saver`, bounds = work area of the display. `setVisibleOnAllWorkspaces(true, {visibleOnFullScreen: true, …})` is called but **does
  nothing on Windows** (virtual desktops, `PARITA.md` §10). `setIgnoreMouseEvents(true, {forward: true})` at start. `backgroundThrottling: false` and
  `autoplayPolicy: "no-user-gesture-required"` (the end-of-focus chime and the background sound must play without a click).
- **Passing clicks through:** with `forward: true` the page keeps receiving `mousemove` while clicks go to the windows below. On every move the page
  asks `isOverSomething(event)`: a pixel of the companion (`PetView.hitTest`), the "+5" prompt, or the reflection card. If the answer changes,
  `setInteractive()` sends `overlay:input-mode`; the main process then calls `setIgnoreMouseEvents(!interactive, {forward: true})`.
- **Hit test:** at load each frame is decoded into an `OffscreenCanvas` and its alpha channel stored (`LoadedImage.alpha`, one byte per pixel); a point counts
  as "on the drawing" if its alpha is above 25 (of 255) (`OPAQUE`), mapped from the page box to image pixels. The transparent area never gets clicks.
- **Cursor leaves the page** (`mouseleave` on the document element): `lastMouse` is cleared; when the card or the "+5" prompt closes, `refreshHover()` turns clicks off if no pointer position is known or it is over nothing of ours.
- This mechanism was exercised with simulated input events on macOS and in a brief manual check on Windows, **not** item by item on the real system — see §10.

### 4.3 Input mode, keyboard and focus (`overlay:input-mode`)

`needs = {card, modal, keyboard}` in the page (`syncInput()`): while the card or a dialog is open the window is interactive and focusable (it receives every
click, so a click outside closes the card); while a text field of the reflection card is being used only the keyboard is requested. The main process
applies `setFocusable(keyboard)` and, on a change, `focus()` or `blur()` — so the window never takes focus from the user's other application unless a field
needs typing. (How focus returns to the other application on Windows is one of the unverified points.)

### 4.4 Several displays and the work area (`main/stage.ts`, `core/displays.ts`)

- One window, **on one display at a time**: `place(display, keepPosition)` sets the window bounds to the display's `workArea` (DIP, so the task bar —
  at any side — is excluded) and sends `stage:moved {x, y, width, height, keepPosition}` to the page.
- `refit()` runs on `display-metrics-changed`, `display-added`, `display-removed` and after wake-up; if the current display disappeared the window goes to the primary one.
- **Dragging across displays:** the page sends `stage:dragging`; while it is on, the main process polls `screen.getCursorScreenPoint()` every 50 ms
  (`FOLLOW_MS`) and moves the window to the display under the cursor (`displayToFollow`); the page keeps the companion where it is on screen
  (`keepPosition`). From the tray, "Schermo" moves the companion to another display and it starts from the ground (`keepPosition: false`).
- `core/displays.ts` is pure geometry (`displayAt`, `displayToFollow`, `currentOrPrimary`, `relativeTo`, `cardPlacement`, `taskbarSide`, `describeDisplay`), tested with invented displays.
  With `FF_FAKE_DISPLAYS` (JSON) the stage uses invented displays (tests only).

### 4.5 The companion on screen (`renderer/petView.ts`, `renderer/overlay.ts`, `core/walker.ts`, `core/pets.ts`)

- **Drawing:** a `<canvas>` moved with a CSS transform (it is not redrawn to walk; `needsRender` is true only when the image, fade, picked-up wobble or "Zzz" changes).
  Frames come from `ff://app/assets/…`; a shadow on the ground, mirroring when facing left, a cross-fade between growth stages (0.8 s), "Zzz" letters drawn on the canvas
  with the marker font (`fonts.ts` reads `--marker`).
- **Data:** `data/pets.json` (generated from `Pet.swift`): images, sizes, shadow, frame lists, stage rules, "picked" drawing with its grab point. `core/pets.ts` derives stages
  (`stageForProgress`, `focusGrowthStage`, `restImageIndex`…); a test checks the stages against the Mac's.
- **Walking (`Walker`, 30 Hz while moving, 1 Hz when idle/hidden):** a state machine `resting → walking → eating | sleeping | popcorning`, 42 pt/s, bounces at the edges,
  chances after a rest: eat 30 %, sleep 15 %, popcorn 12 % (only for pets that have those frames); frozen while dragged or speaking; `eatNow` for 7–10 s at the end of a focus
  (the page triggers it on `focusCompleted`). The loop in `overlay.ts` is a self-rescheduling `setTimeout` whose delay comes from `walker.intervalMs(...)`.
- **Drag:** `mousedown` on a pixel starts a drag; after 3 px (`PICK_DISTANCE`) pets with a "picked" drawing switch to it, keeping the cursor on its grab point; the others follow the pointer
  by offset. On release the box returns to its normal size with the feet where the pet is.
- **Growth during a focus:** pets with growth images (Ciccio, Porcellino) show them in place of the walking art and stand still (the box widens around the feet if the image is wider);
  Pianty (`growsWithTimer`) changes stage with progress; after a "+5" the progress stays at 1 so the plant does not shrink.
- **Room for the clock:** if there is no room under the feet (task bar), `ensureRoomBelowPet()` raises the companion with an eased 220 ms tween and `restorePetHeight()` lowers it afterwards.

### 4.6 Speech bubbles (`renderer/speaker.ts`, `bubble.ts`, `core/phrases.ts`)

First phrase 5 s after start (unless frequency is "never"), then every `chattinessInterval(...)` seconds (e.g. "sometimes": 40–110 s, 240–480 s during a focus; "often", "rarely"
have their own ranges). The bubble is a DOM element: `bubble.png` scaled to the text; the text wrap width is chosen among 110…260 px so that the ellipse gets
the image's proportions (`bubbleSize`, measured in a hidden `#measure` span). It follows the companion (`follow(now)`: it rises at once, descends at most 140 px/s), sits beside the pet when
there is no room above, and stays `max(4.5, 2.5 + 0.06 × characters)` seconds. Phrases come from `loadPhrases`: the user's file in the data folder, else the bundled one, else the
pet's fallback; a `PhraseDeck` per companion shuffles and never repeats until the deck is used (`FORMATI.md` §7). The main process answers `phrase:next` (so files are re-read for each phrase).

### 4.7 The timer engine and its service (`core/pomodoro.ts`, `main/timer.ts`)

- **`PomodoroEngine`** has no clock, window or sound: it takes `now()` (milliseconds) and a `SessionLog`, and emits `PomodoroEvent`s. It holds the phase (`focus`/`rest`/none),
  `phaseStart`, `endDate`, `pausedTotal`, grace, extensions, subject, notes, the break length and a `BreakCycle`. Commands: `startFocus(minutes, subject)`, `startBreak`, `stop`,
  `addMinutes`, `toggleFocusPause`, `addNote`, `discardFocus`, `extendFocus`, `recordInterruptedFocusOnQuit`; `tick()` every 0.2 s.
- **Time rules:** the end is fixed on the wall clock (`endDate`), pausing shifts it; a gap larger than `SLEEP_GAP_SECONDS` (10 s) between two ticks during a focus (no grace running) is counted as
  paused time and written to `in-corso.json`; when the countdown reaches zero a chime event and a 10 s grace (`GRACE_SECONDS`) start — a click extends by 5 minutes, otherwise `finish()` records the
  focus as completed, decides the long break (`BreakCycle`: 4 completed focuses, 15 minutes, reset after 2 h), starts the rest and emits `focusCompleted` and `focusRecorded`.
  A focus under 60 s is never saved (`SessionLog.add`). `growthProgress` is the elapsed fraction, or 1 after any "+5".
- **`TimerService`** (`main/timer.ts`): creates `SessionLog` and the engine, runs `setInterval(tick, 200)`, and **broadcasts a snapshot when `visibleKey(snapshot)` changes** — the key includes the
  displayed `remainingText` (so about once a second), phase, pause, subject, notes count, grace, and the growth in 1 % steps — and always right after an event or a command (`run()`). It also calls
  `onChange` to refresh the tray. The page extrapolates between messages with `timerAt`.
- **Garden hook:** `gardenLine` (empty in this release) is where the garden's sentence about points will be added to the end-of-focus message.

### 4.8 The clock and the "+5 minutes" prompt (`renderer/clockView.ts`, `extendPrompt.ts`)

- The clock is a canvas: a dark case, a paper screen cut from `bubble.png`, seven-segment digits with shear. It is shown for the first 2 minutes of each phase, during the last 5, and while the
  pointer is over the companion plus 1 s (`clockWanted`), opening and closing like a curtain in 350 ms. It sits under the feet.
- The prompt is a DOM card with a bar that drains over the grace period; it is placed above what is visible of the companion, or beside it when there is no room, and counts as "over something" for click-through.
- The chime is `ff://app/resources/fine-focus.wav`, played by the page's `Audio` on the `sound` event (the main process only sends the event).

### 4.9 The card and the tray menu (`renderer/card/*`, `core/card.ts`, `main/card.ts`, `main/tray.ts`)

- **Data flow:** `CardService.data()` (main) builds a `CardData` with the pure function `buildCardData` from the engine snapshot, the sessions, the profile and the settings: today's minutes, focus
  count, streak, companions with locks, saved timers, quick settings, recent subjects, last note. The page asks `card:data` when opening and after each command (a 40 ms debounce, `scheduleRefresh`).
- **Pages:** `main` (companions, 30/50/break, "Altri timer…", today tiles, quick settings), `timers` (the tomato-shaped dial, 5–120 min focus / 1–30 rest, saved timers up to 6 per kind), `focus`
  (notebook page with subject, time range, cycle dots, tomato with progress arc, "+5", Ferma/Riprendi, "Termina e salva", background sound chips and volume, notes post-it, discard) and `rest` (green variant).
  `onTimerState` updates only the clock text and tomato each second and **rebuilds** only when the phase, the pause state or the last session changes.
- **Position:** `reposition()` places it beside the companion (it follows it, flipping side at the edges) or, when opened from the tray, next to the icon (`cardPlacement`, any task-bar side); a transparent backdrop catches
  outside clicks (left or right) and `Esc` closes it.
- **Tray menu** (`tray.ts`, rebuilt each time it opens): Fai parlare, Pomofocus (timers, custom timers, pause/extend/discard during a focus, stop), statistics, ambient sound, music (including "Scegli la cartella…"),
  phrase frequency, character, movement, "Schermo" (only with several displays), name, "Chiedi com'è andata", long break, "Avvia al login" (enabled only in the installed app), "Modifica le frasi…", hide/show, quit.
  A click on the tray icon toggles the card, a right click pops the menu. The tooltip shows the remaining time during a timer.
- **Dialogs run in the main process** for system things: folder picker, save-CSV dialog, confirmation of "discard focus" and "delete all" (`dialog.showMessageBox`).

### 4.10 Dialogs inside the overlay (`renderer/dialogs/*`)

`ModalHost` shows a centred card on a backdrop (a click outside does **not** close it; Esc or the buttons do): "Cosa studi adesso?" (`subjectPrompt.ts`: free text, up to 6 recent subjects as chips,
"Senza materia", back arrow, last-note hint), the welcome card (`introCard.ts`: name + first companion), the name dialog. `ReflectionCard` ("Com'è andata?", three faces + a 80-character note) sits beside the companion,
**does not take the keyboard until its field is clicked**, and disappears on its own when the timer restarts or stops (`reset` event). All flow through `overlay:input-mode` (§4.3).

### 4.11 Sounds (`renderer/audio/*`, `core/audioPlan.ts`, `core/noise.ts`, `main/music.ts`)

- **Decisions are pure** (`audioPlan.ts`): when a background must be heard (only during an *active* focus — not paused, not rest — or during a preview), the gain, the fade (2 s, 0.25 s for quick volume changes),
  previews (3 s for noise, 5 s for music), and the shuffled music queue that never restarts with the track just played. `rules.ts` has the volume steps (10/25/40/60 %) and the one-background-at-a-time choice.
- **Noise:** `NoiseSynth` (rain, brown, wind) is a step-by-step port of the Mac class (same numbers and random generator, 44,100 Hz). It runs in an **AudioWorklet** (`noise-worklet.js`); `AmbientPlayer`
  creates the `AudioContext` at 44,100 Hz, loads the worklet through the protocol, posts `{kind, gain, fadeSeconds}` messages, **suspends the context 2.3 s after the sound is turned off** (the 2 s fade plus 0.3 s) so no CPU is used for a sound that
  is not playing, and resumes it when needed. If the engine does not start, the companion says so. A `statechange` to `suspended` while sound should be playing triggers `recover()`.
- **Music:** `MusicPlayer` plays with an `HTMLAudioElement` from `ff://app/music/<version>/<id>`, fading with a 50 ms timer, chaining tracks on `ended`; unreadable files are skipped. `MusicService` (main) lists the bundled tracks
  (`assets/music/*.m4a`) or the user's folder (recursive scan, cached by folder and modification date, prepared in the background at start and on selection).
- **Wake-up:** on `system:resumed` both players run `recover()`: resume the suspended context / restart a paused track, but only if the sound was supposed to play.

### 4.12 Data: log, recovery, settings, profile (`core/log.ts`, `settings.ts`, `profile.ts`, `files.ts`, `main/paths.ts`)

- **Folder:** `%APPDATA%\FocusFriends` on Windows; on other systems (development) `<userData>/dati-di-prova` — **never** the Mac app's folder; `FF_DATA_DIR` overrides it.
- **Files** (formats in `../FORMATI.md`): `sessioni.json` (v3), `in-corso.json`, `profilo.json`, `impostazioni.json`, `frasi_<pet>.txt`, `backup/`, `registro-app.log`.
- **Writing:** `writeFileAtomic` (temporary file in the same folder + rename), UTF-8, keys sorted, `"key" : value` spacing like the Mac writes (`stringifyJson`).
- **`SessionLog`:** loads in the constructor with the same rules as Swift: a missing file is empty; unreadable → read-only + message; older versions → intact copy in `backup/sessioni-formato<N>.json` and rewrite as v3; bare list (v0) → copy
  `sessioni-formato0.json`; newer version → read-only; partly corrupt → keep the readable sessions and put the original aside as `sessioni.corrotto-<epoch>.json`; wholly corrupt → move aside and start empty. Subject spellings are unified
  (latest wins) and `localStart` is filled. `save()` makes a once-a-day backup (keeps 7), writes atomically, and on failure sets `hasUnsavedChanges` and reports **once** until a write succeeds. Problems go to `onProblem` (the companion says them).
- **In-progress file:** `beginInProgress` (on start and on every "+5"), `updateInProgressPause`, `updateInProgressNotes`, `heartbeat` (rewrites `lastSeen` at most every 30 s), `finishInProgress`; `recoverInterrupted()` at start saves the focus as interrupted with
  `seconds = lastSeen − start − paused time`, capped at the plan.
- **`Settings`:** a flat object read once; every setter rewrites the file and notifies observers; any missing, wrongly typed or out-of-list value is the default; unknown keys are kept. Custom timers: 1–180 minutes (focus) / 1–60 (rest), at most 6 per kind,
  no duplicates of the built-ins (focus 30/50, rest 5/10).
- **`Profile`:** name (cleaned, ≤ 24 characters), `introSeen`, unlocked companions, first companion; the name is not stored in the sessions (titles are composed when shown); a developer flag makes every companion usable without writing anything.
- **Time:** `core/time.ts` represents a clock reading as a `Wall` number (the day and hour read as if they were UTC) so that days are always 24 hours and weeks 7 days; only instant → wall depends on the time zone (`wallOf`). The computer's zone is **re-read every 5 seconds
  and after wake-up** (a cached `Intl.DateTimeFormat` would keep the zone of the first call); sessions use their stored `localStart`, so a later zone or DST change never moves a session to another day.

### 4.13 The statistics window (`main/statsWindow.ts`, `renderer/stats/stats.ts`, `core/stats.ts`, `core/dashboard.ts`)

A normal `BrowserWindow` (560 × 660, not resizable, no menu bar, background `#fff6de`) created on the first request and **destroyed when closed**, so it costs no memory meanwhile; its title follows the profile name.
The main process sends all sessions, "now", the title and the tab to open; **the page computes everything** (`summarize`, `analyzeStreak`, `insights` and the Italian texts of `dashboard.ts`) from the same pure functions the tests compare with the Mac.
Tabs Oggi / Settimana (from Monday) / Mese with arrows; the diary ("Mostra le sessioni") with a day strip; editing a session (subject, "apply to all sessions", note, rating, focus notes) or deleting it, CSV export (save dialog, formula-guarded
fields), and "Cancella tutto…" (confirmation; removes sessions, in-progress file, backups and the profile; `onDeleteAll` is the garden's future hook). The window re-sends its data whenever the log changes.

### 4.14 Companion unlocking (`core/rewards.ts`, `core/unlocks.ts`, `main/card.ts`)

The first companion is free; the others unlock at 20, 50 and 100 "full focuses" (50 minutes of study each, interrupted minutes included). After every recorded focus `evaluateCompanionRewards(true)` unlocks what was earned and the companion says so
9 seconds after the end-of-focus phrase; at start the same runs silently. Locked companions cannot be chosen from the card or the menu.

### 4.15 System integration

- **Tray** (`Tray` with the head of the current companion, 32 px), **no taskbar button** (`skipTaskbar`).
- **Single instance:** `requestSingleInstanceLock()` (bypassed only by `FF_NO_LOCK=1`); a second launch quits and the first shows the companion.
- **Login item:** `setLoginItemSettings({openAtLogin})`, enabled only when `app.isPackaged` (otherwise it would register Electron itself).
- **Power:** `suspend` (logged), `resume` and `unlock-screen` → `awake()`: refresh the time-zone cache, log the displays, `stage.refit()`, send `system:resumed`. The timer needs nothing (the 10 s gap rule).
- **Shutdown:** `before-quit` and `session-end` (Windows closing the session) → `service.shutdown()` → a running focus is saved as interrupted.
- **Crash handling:** `uncaughtException` / `unhandledRejection` / `child-process-gone` go to the app log; the page is reloaded after a render-process crash (max 3 per 10 min).
- **App log** (`core/diagnostics.ts`): `registro-app.log` in the data folder, one line per fact, 200 KB then rotated to `registro-app.1.log`; no names, subjects or notes, and the user's home path in messages becomes `~`. Since 1.0.0 it also records the Windows version
  and, for every display, size, scale factor, work area and the side of the task bar (at start, on change, on wake-up).

---

## 5. Contracts, environment and self-test

### 5.1 Data contract
`../FORMATI.md` is the specification; `../tests/fixtures/` holds sample data folders and `attesi/` the results derived by the Mac app with a fixed "now" (14 Oct 2026, 20:00, Europe/Rome); `rumore.json` holds measured noise statistics. See §7.

### 5.2 Environment variables

| Variable | Effect | Gated by `FF_SELFTEST`? |
|---|---|---|
| `FF_DATA_DIR` | use this folder for the data | no |
| `FF_NO_LOCK=1` | skip the single-instance lock | no |
| `FF_FAKE_DISPLAYS` | JSON array of invented displays | no |
| `FF_SELFTEST_SAVE`, `FF_SELFTEST_CONFIRM=1` | pre-answer the CSV save dialog and the "delete all" confirmation | no |
| `FF_SELFTEST`, `FF_SELFTEST_OUT`, `FF_SELFTEST_FILE`, `FF_SELFTEST_SCRIPT` | enable the self-test harness (§5.3) and `window.__ff` | — |
| `FF_SWITCHES`, `FF_NO_GPU` | extra Chromium switches / hardware acceleration off (memory experiments) | yes |

### 5.3 The self-test harness (`main.ts` `runSelfTest`, `renderer/overlay.ts` `window.__ff`)

With `FF_SELFTEST`, the preload exposes `selfTest: true` and the page defines `window.__ff` (say, state, hit test, open/close the card, audio state, interrupt audio…). `FF_SELFTEST=<seconds list>` takes screenshots and process
metrics at those moments; `FF_SELFTEST_FILE=<script.cjs>` runs a script that receives tools: the window, `js()` (run code in the page), `shot()`, `metrics()`, `mouse()`/`key()` (simulated input events), the settings, the timer service
(`run`, `engine`, `log`), the card and statistics controllers, the stage, `power()` (emit `suspend`/`resume`/`lock-screen`/`unlock-screen`) and `quit()`. **The scenario scripts used during development are not in the repository** (§10).

---

## 6. Build, packaging, CI and release

- **Build** (`tools/build.mjs`): six esbuild runs (main, preload, overlay page, stats preload, stats page, noise worklet); the two HTML files are copied; the CSS is concatenated (`overlay.css + card.css` and `card.css + stats.css`), so the card styles exist in both pages.
- **Installer** (`electron-builder.yml`): files = `dist/**` + `package.json` (no source maps); `extraResources` puts `build/assets` and `build/resources` next to the asar; per-user NSIS (`%LOCALAPPDATA%\Programs\FocusFriends`), Start-menu shortcut only, **does not delete the data on uninstall**,
  one installer per architecture (`FocusFriends-Windows-<version>-<x64|arm64>-Setup.exe`, ≈ 127 / 121 MB). The Electron and Chromium licence texts are included by the packager. The installer is **not code-signed** (SmartScreen warning; options in `RILASCIO.md`).
- **CI** (`../.github/workflows/windows.yml`): on a Windows runner `npm ci` → `npm run check` → `npm test` → `npm run build` for every change under `windows/**`, `assets/**`, `tests/fixtures/**`, `FORMATI.md`; on a `windows-v*` tag (or by hand) it also builds the x64 and arm64 installers in parallel, writes a `.sha256` for each and, **only for a tag**, creates a **draft** release
  with the notes of `NOTE_DI_RILASCIO.md` and `SHA256SUMS.txt`. `mac.yml` has a job that runs the same logic tests on macOS, which is where the Swift side of the contract runs.
- **Release procedure:** `RILASCIO.md` (version in `package.json`, tag `windows-v<version>`, review and publish the draft). `windows-v1.0.0` was published as a normal release **without** being marked "Latest" (that stays on the Mac's `v0.8.0`).

---

## 7. Tests (`test/`, `npm test`)

247 tests in 23 files, no framework, no dependencies. They run unchanged in the main process's code paths because the logic is pure.

| File(s) | What they cover |
|---|---|
| `contratto.test.ts` + `atteso.ts` | for every sample folder in `../tests/fixtures/` the TypeScript code derives exactly what the Swift app derived (`attesi/*.json`): counts, files created, warnings, summaries, streak, points, companions |
| `ritorno.test.ts` | the **reverse** contract: folders written by this code (migration from v2, accents/emoji/quotes/formula-like text, rating, rename, delete, an in-progress focus with pause, a profile) are read by the **Swift** generator and must give the same results; runs only on macOS with `swiftc` (skipped elsewhere); verified to fail when a file is altered |
| `registro`, `profilo`, `impostazioni`, `registroapp`, `frasi` | log load/save/recovery/backups/migrations, profile, settings and their defaults, the app log (incl. home-path stripping), phrase files and the shuffled deck |
| `statistiche`, `cruscotto`, `colori`, `testo` | periods, summaries, streak with its frozen day, insights, CSV, the dashboard's Italian texts, subject colours (64-bit hash equal to Swift), text cleaning |
| `timer`, `camminata`, `personaggi`, `sblocchi`, `riflessione`, `scheda` | the timer engine with a fake clock (pause, grace, "+5", discard, sleep gap, long break), the walker, pet stages (compared with Swift), unlock rules, reflection replies, card data |
| `musica`, `elencomusica`, `suoni`, `rumore` | music queue and listing, audio plan decisions, the noise synthesiser against measurements from the Mac (rain and brown within 1 %, wind within 3 %: the Mac accumulates the phase in Float32) |
| `schermi`, `fusi` | display geometry and the task-bar side; time zones: DST days of 23 and 25 hours, a zone changed while running, Sydney, Lord Howe, India/Nepal, the date line |

**Not covered by automated tests:** everything that needs Electron or a real display — the overlay window, click-through, the tray, dialogs, protocol, the real audio output, the pages' DOM code (card, dialogs, speaker, bubble, clock, pet drawing), power events, installers.
Those were exercised with scripted runs of the real app on macOS (simulated mouse/keyboard events, screenshots, process metrics) that are not stored in the repository.

---

## 8. Design decisions

- **D1. One big transparent window, not one window per element.** Chosen after weighing a per-element window moved at 30 Hz (the Mac approach). Reasons **[documented]**: fewer processes and less memory, one click-through mechanism, the elements animate in one page.
  Cost: the whole work area is a window (a "one window per display" move is needed for several displays, §4.4) and the click-through relies on `setIgnoreMouseEvents(…, {forward: true})`, which is the riskiest Windows-specific piece. The fallback plan (A) is in `PIANO_WINDOWS.md` M1.
- **D2. The engine in the main process.** Hidden pages are throttled; the timer must not stop. Cost: snapshots over IPC (about once a second, plus on events).
- **D3. A pure `core/`.** The same code serves main, pages and tests, and the Mac contract can be checked without a window. Cost: the split rules (§2) must be respected by hand.
- **D4. Custom protocol instead of `file://`.** One origin, a CSP that allows only `ff:`, no disk access from the page, path-traversal guard, `Range` support for audio.
- **D5. DOM cards inside the overlay, not extra windows.** No extra processes; focus is handled with `setFocusable`. Cost: the window must flip between click-through and interactive (§4.3).
- **D6. No UI framework.** Svelte was in the first plan; the card is rebuilt from a snapshot as on the Mac, and a small `h()` helper (`card/dom.ts`) was enough **[documented]**.
- **D7. Same data files and formats as the Mac**, preferences in `impostazioni.json` with the Mac's key names; compatibility enforced by the contract tests in both directions.
- **D8. Free font and icons** instead of Marker Felt and SF Symbols: Chewy was picked among 44 candidates by measuring against Marker Felt Wide (letter shape, stroke weight, width, cap height) and then in the real UI; Lucide for icons **[documented]**.
- **D9. Noise synthesis ported, not replaced by sound files**, and run in an AudioWorklet so the main/page threads are not involved (no licences, same sound as the Mac).
- **D10. Per-user NSIS installer, no auto-update.** No admin rights, data kept on uninstall; updates are done by running the new installer over the old one. `electron-updater` is left for later (`RILASCIO.md`).

---

## 9. Differences from the Mac app

See `PARITA.md` for the row-by-row table. In short: one window instead of several; no Dock but a tray icon (Windows 11 may hide it in the "^" overflow); a generated chime instead of the system sound "Glass"; Chewy and Lucide instead of Marker Felt and SF Symbols; no
"all desktops" behaviour (not available on Windows) and no automatic hiding over fullscreen apps (like the Mac, the companion stays above); more memory (Electron); preferences in `impostazioni.json` instead of `UserDefaults`; installer unsigned; garden not included yet.

---

## 10. Review notes

1. **Windows-specific behaviour is only partly verified.** Real click-through, keyboard focus hand-off, task bar at each side, 125–200 % scales, two monitors with different scales, a real sleep/wake, audio device changes, fullscreen apps and virtual desktops were not checked item by item (`PROVE_SU_WINDOWS.md`). A quick manual run measured ≈ 200 MB and ≈ 0 % CPU at rest.
2. **No navigation hardening.** None of the three `BrowserWindow`s sets `will-navigate`, `setWindowOpenHandler` or a permission handler. The pages have no links and the CSP is `default-src 'none'` (only `ff:`), so the exposure is small, but these three are the usual Electron hardening steps and are missing.
3. **Test-only environment variables are read in production** (`FF_DATA_DIR`, `FF_NO_LOCK`, `FF_FAKE_DISPLAYS`, `FF_SELFTEST_SAVE`, `FF_SELFTEST_CONFIRM` are not gated by `FF_SELFTEST`). Setting them needs control of the process environment, which already means control of the user's account; still, `FF_SELFTEST_CONFIRM=1` makes "delete all" skip its confirmation.
4. **The live-run scenario scripts are not in the repository.** The "S" entries in `PARITA.md` (dynamic checks on macOS) cannot be repeated by anyone else from the repo, only the 247 automated tests can.
5. **Unused code for the next release:** `core/points.ts` (garden points) is imported only by tests; `gardenLine` and `onDeleteAll` are empty hooks. Intended, but dead in 1.0.0.
6. **Possible hot spots [inferred, not measured]:** the statistics page gets **all sessions** at every log change (a structured clone) and recomputes the summary in the page; `buildCardData` summarises all sessions on every card refresh; `loadPhrases` re-reads the phrase file for each phrase. Fine for thousands of sessions; not tested with tens of thousands.
7. **One stylesheet pair per page, with `card.css` duplicated** in both bundles (a few tens of KB, no functional effect).
8. **The single-instance lock** relies on Electron's `requestSingleInstanceLock()`; how it behaves with two different Windows users or after a crash on Windows was not examined **[uncertain]**.
9. **`erasableSyntaxOnly`** forbids parameter properties and enums: classes in `core/` declare fields explicitly. A newcomer may be surprised; it is required for Node's type stripping in the tests.
