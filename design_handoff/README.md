# Handoff: Torax H-0 App Screens

> ## Implementado — v2 rebanada 2 (2026-09-02)
>
> Este handoff se implementó en `screen-handoff_20260901`. Lo que sigue es el
> documento original, sin tocar; esta nota dice qué entró, qué no y en qué se
> divergió, para que quien lo lea después no tenga que deducirlo.
>
> **Entró:** la pantalla 1 (Track/anillos) y la 2 (Scale & Root), enteras. El
> lenguaje visual completo — Figtree, los acentos definitivos y el tratamiento
> neo-brutalista como sistema.
>
> **No entró:** las pantallas 3 (MIDI/Learn), 4 (Banks) y 5 (Track × Pattern).
> Se dibujan como pestañas deshabilitadas con borde discontinuo, que es el signo
> que este mismo documento define para «todavía no». MIDI Learn es la rebanada 8
> de la v1; Banks necesita persistencia y Track × Pattern necesita Patterns, y
> ninguna de las dos existe todavía.
>
> **Tres divergencias, decididas y escritas:**
>
> 1. **El anillo se lleva la columna ancha, no la estrecha.** El mock le da 190px
>    de 924, proporción dibujada para **cinco** anillos; con dieciséis cada banda
>    quedaba en unos 6px y dejaba de contarse. Se invierte el reparto con la
>    lectura.
> 2. **Los anillos son arcos y no puntos** — como este documento dice
>    («a conic-gradient of colored arcs vs dark gaps»), y no como se implementó
>    primero. Con una marca por Step, los dieciséis Tracks alinean sus marcas
>    radialmente y la pantalla se lee como dieciséis *radios*.
> 3. **Las notas fuera de la escala siguen siendo tocables** en el gráfico de
>    Root, donde el mock las dibuja inertes. «¿Está C# en Do menor?» es una
>    pregunta sobre el marco actual; elegir C# como raíz construye un marco nuevo
>    donde es la fundamental. Con la regla del mock, qué tonalidades son
>    alcanzables dependería de la vigente.
>
> **Dos cosas que el documento no decía y hubo que decidir:** la app se bloquea
> en **landscape** —las cinco capturas son 924×540 y el layout de tres columnas
> no cabe en portrait— y no lleva el nombre de la app en pantalla, porque ninguna
> de las cinco lo dibuja.
>
> **Sobre los tokens:** la tabla se titula «illustrative — not final» y la
> sección *Fidelity* dice que los colores y la fuente son definitivos. Gana
> *Fidelity*, que es lo más reciente.
>
> Detalle completo en
> [`conductor/tracks/screen-handoff_20260901/spec.md`](../conductor/tracks/screen-handoff_20260901/spec.md).

## Overview
Wireframes and an interactive click-through for the Torax H-0 iPad app — a MIDI algorithmic sequencer controlled primarily by an external hardware controller (BeatStep Pro), with the iPad screen as a secondary mirror/detail view. Covers 5 screens: Track/ring view, Scale & Root, MIDI mapping, Bank save/load, and Track×Pattern browser.

## About the Design Files
The bundled `.dc.html` files are **design references built in HTML**, not production code. The task is to recreate these designs in the target codebase's actual environment — this project is a native SwiftUI iPad app (see `App/ContentView.swift`, `App/TransportModel.swift`, `Packages/Engine/`) — using SwiftUI views, layout, and animation, following the existing code's patterns (CoreMIDI/MIDI package usage, `Engine`/`EuclideanRhythm` model). Do not port the HTML/CSS directly.

## Fidelity
**Mid-fidelity.** Layout, structure, and screen flow are settled. Colors (green/mauve/purple/plum palette) and font (Figtree) are final. Component styling now follows a neo-brutalist treatment — see **Component Styling** below — apply it consistently to any new components built in SwiftUI.

## Files
- `Torax H-0 Wireframes.dc.html` — exploration board, multiple layout directions per screen (ids 1a–7c), open in a browser and click ids to jump.
- `Torax H-0 Click-through.dc.html` — single interactive prototype combining the chosen directions (1b, 2b, 3a, 6a/4a+4c combo, 6b/5c+5b combo, 7a ring update) with real tab/nav/toggle interactions. This is the primary reference.

## Screens / Views

### 1. Track / Ring view (main screen)
**Purpose:** Live view of the currently playing Bank/Pattern; shows all tracks as concentric rings, one selected track's detail large-format.
**Layout:** Top status bar (Bank/Pattern name left, BPM + transport right). Below: 3-column row — ring stack (190px) | detail readout panel (flex) | 3 stacked param-family tabs (170px, SHAPE/GROOVE/TONAL). Bottom: horizontal row of per-track selector buttons (KICK/SNARE/CHH/RIDE/PERC — represents first 5 of up to 16 tracks).
**Components:**
- Ring stack: 5 concentric rings, outer→inner = track 1→5, diameters 180/148/116/84/52px. Each ring is a `conic-gradient` of colored arcs (its own step/pulse pattern) vs dark gaps. Only the selected track's ring is drawn in bright accent color; others render in dim gray with the same arc pattern. Small dark center dot at 22px.
- Detail readout panel: large numeric/label readout (46px bold) + small caption, color-matched to the active param tab.
- Param tabs (SHAPE/GROOVE/TONAL): left-border-accented rows, colors: SHAPE=green, GROOVE=mauve, TONAL=purple (see tokens). Selected tab gets an outline.
- Track selector row: 5 pill buttons, 52px tall; selected track gets a 2px colored border matching the active param-family color.
**Interactions:** Tap a param tab → detail readout switches value/label/color. Tap a track button → that ring brightens (its own pulse arcs shown in color) and the readout retitles to "<TRACK> selected · <tab> — …".

### 2. Scale & Root
**Purpose:** Pick the active scale and root note that constrains the TONAL layer's pitch pool.
**Layout:** Vertical stack: header label → 6-column scale grid → flexible-height root-note bar chart → status line.
**Components:**
- Scale grid: 6 buttons (Minor, Major, Dorian, Phrygian, Pentatonic, +User). Selected = solid purple fill; others = outlined.
- Root note chart: bar-per-note (C D E F G A B), only in-scale notes are tall/interactive; out-of-scale notes are short dark gray filler bars (non-interactive). The selected **root** note gets a 3px white border + colored fill + bold larger label — visually distinct from merely-in-scale notes.
- Status line: "Scale · <name>  Root · <note>" (bold, root note colored).
**Interactions:** Tap a scale button → grid selection updates, in-scale bars recompute. Tap an in-scale note bar → becomes root.

### 3. MIDI mapping / Learn
**Purpose:** View/assign which hardware knob or pad controls which app parameter.
**Layout:** Top: full-width "Learn mode" toggle banner. Below: device connection chip. Below: mapping table (Param | CC | Knob columns), each row left-border-colored by its param family.
**Components:**
- Learn banner: tap to toggle; ON state fills bright green with "LEARN MODE ON — turn a knob to assign"; OFF state is dim with "Tap to enter Learn Mode".
- Device chip: rounded pill, purple border/text when connected, with device name + "— connected".
- Mapping rows: Steps/Pulses (green), Velocity (mauve), Pitch pool (purple) — each row's left border and label colored by family.
**Interactions:** Tap banner toggles Learn mode (visual only in the prototype — real app would then await the next incoming CC and bind it).

### 4. Banks (Save / Load / Backup)
**Purpose:** Manage Bank save state, reload with confirmation, and export/import backups.
**Layout:** Autosave status line → scrollable list of Bank rows → Export/Import footer buttons. A confirm dialog overlays the whole screen when reload is requested.
**Components:**
- Bank row: name + BPM, save-state tag ("saved" gray / "unsaved •" mauve), Save button (filled when current bank, else neutral), Reload button (mauve outline when there are unsaved changes).
- Empty bank row: dashed border, no actions.
- Confirm dialog: centered card over a dimmed full-screen scrim, message + Discard (mauve outline) / Cancel (neutral outline) actions.
**Interactions:** Tap "Reload" on a bank with unsaved changes → opens confirm dialog. Discard closes dialog (would trigger actual reload); Cancel closes without action.

### 5. Track × Pattern browser
**Purpose:** Overview of which tracks have data in which patterns, with per-track mute/solo.
**Layout:** Grid: row header (track name + M/S toggles, ~110px) × 8 pattern columns (A–H), one row per track (3 shown, 13 more scroll below in the real app with 16 tracks).
**Components:**
- Column headers: pattern letters A–H.
- Per-track M/S toggle pair: plain gray by default; M active = mauve; S active = purple (and implies mute of non-soloed tracks — shown as a caption note, not simulated across rows in the prototype).
- Matrix cells: filled colored cell = track has data in that pattern; dashed empty cell = no data; color intensity ties to the track's own accent.
**Interactions:** Tap M or S on a row → toggles that row's mute/solo color state.

> **Nota del 2026-09-02 — el par M/S se implementa en la pantalla Track, no
> aquí.** El prototipo pone mute y solo en esta pantalla 5, que no existe en la
> app: las pantallas disponibles son `1 · Track`, `2 · Tonal` y `3 · MIDI`, y
> `4 · Banks` y `5 · Tracks` siguen sin construirse. El track
> `mute-solo_20260902` pone el par debajo de cada pastilla de la fila de Tracks
> de la pantalla `1 · Track`, que es donde ya se elige el Track y donde el gesto
> cae bajo el dedo sin cambiar de pantalla.
>
> **Cuando la pantalla 5 exista, enseñará este mismo estado.** Mute y solo viven
> por encima del Pattern, en una sola capa: las dos pantallas serán dos vistas de
> lo mismo, no dos estados que sincronizar.
>
> **Se conserva el vocabulario de color de este documento:** `M` activo en mauve
> —el acento de GROOVE— y `S` activo en purple —el de TONAL—, con el reposo en el
> borde apagado de los controles vacíos. Lo que el prototipo dejó como nota al
> pie sí se implementa: el solo **implica** el silencio de los no soleados, y el
> Track que calla por el solo de otro se atenúa para que once silencios no
> parezcan un fallo.

## State Management (as prototyped)
- `screen`: which of the 5 screens is active (top nav in the click-through; in the real app this maps to actual navigation/tab state).
- `paramTab`: 'shape' | 'groove' | 'tonal' — drives the readout panel's value/label/color on screen 1.
- `selectedTrack`: which of the 5 (of 16) tracks is highlighted in the ring stack.
- `scale`, `root`: current scale name and root note on screen 2.
- `learnOn`: MIDI Learn mode toggle on screen 3.
- `reloadOpen`: confirm-dialog visibility on screen 4.
- Per-track `mute`/`solo` booleans (kick/snare/chh) on screen 5.

## Design Tokens (illustrative — not final)
**Colors:**
- Background (dark plum): `#211823` (panel), `#1a1420` (header/toolbar), `#0e0a10` (inset panels)
- Borders/dividers: `#3a2c3d`, `#4a3d4d`
- Muted text: `#8a7d8d`, `#a99cab`
- SHAPE family accent (green): `#9AAB79`
- GROOVE family accent (mauve): `#AA6DA8`
- TONAL family accent (purple): `#7C5FD9`
- Warm neutral fill (page bg outside app frame): `#e9e6e1`

**Typography:** Figtree (400/600/700) for all UI text — labels, buttons, numeric readouts, table text. No monospace font is used in the current version.

**Radii:** 3–8px on cards/buttons/panels (neo-brutalist — small and consistent, never full pills); full circle (50%) only for rings and the round toggle buttons.

**Borders/shadows:** 2px solid strokes on all interactive elements (3px on the selected root key); hard offset shadows `2px 2px 0 rgba(0,0,0,.4)` on selected/primary elements, `6px 6px 0` on the modal. Dashed 2px borders mark disabled/empty states.

## Component Styling (neo-brutalist)
All interactive components (buttons, tabs, badges, toggles, list rows, modals) share one visual language, adapted to the app's dark palette:
- **Thick strokes:** 2px solid borders on every interactive element (3px on the selected root-note key). Borders use white on dark surfaces, or the element's own accent color — never a soft/faint border.
- **Limited, small radii:** 3–8px corners throughout (never fully rounded pills, never sharp 0px) — badges, buttons, cells, and the confirm modal all sit in that range.
- **Solid accent blocks:** active/selected states are a flat, fully-saturated accent fill with dark (`#1a1420`) or white text for contrast — no gradients, no tints, no soft outlines-only states.
- **Hard offset shadows:** selected/primary elements get a `2px 2px 0 rgba(0,0,0,.4)` hard drop shadow (no blur) — nav tabs, active param tabs, active scale/track buttons, root key, Save button, MIDI Learn banner. The confirm modal uses a larger `6px 6px 0` offset.
- **Dashed border = disabled/empty:** unavailable options (empty bank row, unscheduled +User scale, out-of-scope future controls) use a 2px dashed border instead of solid — a consistent "not yet available" signal.
- **Bold weight on active state:** selected/active text is Figtree 700; inactive/secondary text is 400–600.
Apply this system to any new SwiftUI control (toggles, pickers, alerts) rather than inventing a new button/border style.

## Assets
None — all visuals are CSS-drawn (conic-gradient rings, flat shapes). No bitmap/icon assets used.

## Screenshots
`screenshots/` contains one PNG per screen from the click-through prototype: 01-track, 02-scale, 03-midi, 04-banks, 05-tracks.
