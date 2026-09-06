# torax h-0 — coding agent brief

Implement four landscape iPadOS screens in SwiftUI: `track`, `scale`, `midi`, and `banks`.

The app is an algorithmic MIDI sequencer. The external controller is the instrument; the iPad is a high-contrast state mirror. Prioritize legibility at one metre and in low light.

## design tokens

- Background: `#111211`.
- Font: Figtree, weights 400, 600, and 700.
- **Every visible UI string must be lower case.**
- Borders: 2 pt; selected controls: 3 pt.
- Corner radii: 3–8 pt.
- Use flat fills. Apply a small hard shadow without blur only to selected controls.
- Do not use gradients, glass effects, blur, ornamental graphics, piano rolls, or keyboard UI.
- Functional accents: shape `#9aab79`; groove `#aa6da8`; tonal `#7c5fd9`.

## shared chrome

Every screen has a top bar: `torax h-0` on the left, the active module in the centre, then a connection dot, `midi: beatstep pro`, clock source, `124 bpm`, and transport at right.

Below it, add persistent navigation with `track`, `scale`, `midi`, and `banks`. The active item has a 3 pt off-white underline.

## track

- Main split: 68% pattern visualisation, 32% readout.
- Show twelve concentric rings. Each has 16 circular steps and sparse active pulses.
- The off-white playhead must be highly visible and move only when transport advances.
- Highlight selected track 04 with a 3 pt outline.
- Right column contains transient feedback `pulses` / `5 / 16`; a cycle card `03 / 08` with cells `01`–`08` and `03` selected; compact shape, groove, and tonal cards.
- Tonal card displays `scale dorian`, `root d`, and the pool `d e f g a b c d`. Do not map pitches to individual steps.
- Bottom strip contains tracks `01`–`12` with `m` / `s`; track 04 is selected and track 09 has mute active.
- A muted track remains visually in time: it suppresses MIDI output only, never its cycle or playhead.

## scale

- Display context `track 04`.
- Selectable scale cards: `minor`, `major`, `dorian`, `mixolydian`, `phrygian`, `lydian`; select `dorian` using tonal violet.
- Root selector: `c`, `c#`, `d`, `d#`, `e`, `f`, `f#`, `g`, `g#`, `a`, `a#`, `b`; select `d` off-white.
- Show a `pitch pool` as a 4×4 pad matrix. Eight pads are active in tonal violet, others stay neutral. Include `8 notes active`.
- Pads are scale degrees, not a per-step melody.

## midi

- `clock source` segmented control: `internal` / `external`; default internal. Show `internal clock · 124 bpm`.
- `midi input`: connected `beatstep pro`; disabled `network session` with dashed outline and `unavailable`.
- `midi output`: `external midi device`, plus `channel routing active`.
- `track channels`: rows `track 01` through `track 12`, routed to `ch 01` through `ch 12`; highlight track 04.

## banks

- Left: `bank 01` and a 4×4 bank grid `01`–`16`; bank 01 selected. Footer: `124 bpm · 16 patterns`.
- Centre: a 4×4 grid of patterns `01`–`16`; pattern 04 selected in shape olive and labelled `playing`. Other patterns can be `ready` or `empty`.
- Right: `track assignments`, twelve rows mapping each track to a pattern. Emphasise track 04 → pattern 04.

## implementation shape

Create reusable views: `appChrome`, `moduleNavigation`, `ringPatternView`, `cycleStrip`, `parameterFamilyCard`, `trackPill`, `scalePicker`, `rootPicker`, `pitchPoolGrid`, `midiChannelRow`, `bankGrid`, and `patternGrid`.

Keep visual tokens centralised. Do not add local colours, fonts, borders, or shadow styles outside the shared token system.

## supplied references

- `track.png`
- `scale.png`
- `midi.png`
- `banks.png`

