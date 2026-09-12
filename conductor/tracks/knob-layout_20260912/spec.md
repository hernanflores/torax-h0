# Spec — Reordenar los knobs del preset del BeatStep Pro

**Tipo:** Chore · **Track:** `knob-layout_20260912`

## Overview

Desde el 2026-09-05 el orden de los knobs y el de la pantalla son dos órdenes
distintos, y la correspondencia sólo existe en la tabla de `preset/README.md`: no
se puede deducir mirando el iPad. La nota de aquel día lo dice con todas las
letras — «la pantalla conserva el orden del dominio y los knobs siguen el de la
mano».

Con los cuatro del Note Repeater dentro (2026-09-07) la fila física quedó además
intercalando familias: Shape en los knobs 1–4, Groove en los 5–9, Shape otra vez
en los 10–12. La mano cruza de card tres veces para recorrer una fila, y la
pantalla no predice dónde está nada.

Este track vuelve a alinear las dos superficies bajo una regla única: **una fila
de knobs por card de la pantalla**. La fila superior es el card Shape entero —el
ritmo y el Note Repeater, en sus dos líneas—; la inferior, el card Groove. El
Cycle en edición se va a la esquina.

**El `.beatsteppro` no cambia.** El archivo del controlador sólo declara dieciséis
encoders contiguos desde el CC 70 en `Relative #2`; qué significa cada uno lo
decide la app. Esto es un cambio de `ControlMapping` y de documentación, como ya
lo fueron los del 2026-09-05 y el 2026-09-07.

## La tabla nueva

| Knob | CC | Hoy | Nuevo |
|---|---|---|---|
| 1 | 70 | Steps | Steps |
| 2 | 71 | Pulses | Pulses |
| 3 | 72 | Rotate | Rotate |
| 4 | 73 | Division | Division |
| 5 | 74 | Velocity | **Repeats** |
| 6 | 75 | Sustain | **Time** |
| 7 | 76 | Delay | **Ramp** |
| 8 | 77 | Timing | **Pace** |
| 9 | 78 | Probability | **Velocity** |
| 10 | 79 | Repeats | **Sustain** |
| 11 | 80 | Time | **Probability** |
| 12 | 81 | Ramp | **Timing** |
| 13 | 82 | Cycle en edición | **Delay** |
| 14 | 83 | Pace | **sin asignar** |
| 15 | 84 | sin asignar | sin asignar |
| 16 | 85 | sin asignar | **Cycle en edición** |

## Functional Requirements

- **FR1 — Fila A = card Shape.** Knobs 1–8 (CC 70–77): `Steps · Pulses · Rotate ·
  Division · Repeats · Time · Ramp · Pace`. El orden es el del card, incluidas sus
  dos líneas: el ritmo primero, el Note Repeater después. Es la agrupación que
  FR15 dibuja en pantalla, ahora también bajo la mano.
- **FR2 — Fila B = card Groove.** Knobs 9–13 (CC 78–82): `Velocity · Sustain ·
  Probability · Timing · Delay`, en el orden del dominio que la pantalla ya usa.
  Esto revierte el intercambio de Delay y Probability del 2026-09-05.
- **FR3 — El Cycle en edición al knob 16 (CC 85).** `editingCycleKnobOffset` pasa
  de 12 a 15. Queda separado de los trece parámetros por un hueco físico de dos
  knobs, y en la esquina del bloque, que es un punto de referencia táctil. Es lo
  que la nota del 2026-09-05 buscaba —que no parezca el décimo parámetro— y que
  estando adyacente sólo conseguía a medias.
- **FR4 — Quedan libres los knobs 14 y 15 (CC 83 y 84).** Se ignoran en silencio,
  como hoy los 15 y 16. Siguen declarados a propósito y reservados para v2:
  Accent, Voicing, Range.
- **FR5 — Los mapeos aprendidos ganan.** Un proyecto guardado con MIDI Learn
  conserva su mapeo, como ya hace hoy; este track cambia sólo el default de
  fábrica. No hay migración y un proyecto viejo sigue con el orden viejo hasta
  que el usuario lo reasigne.
- **FR6 — La pantalla no cambia.** Ni el orden de los cards, ni su contenido, ni
  `TrackParameter`. Es la mano la que se mueve hacia la pantalla, no al revés: el
  orden del dominio es el que se lee, y ahora también el que se toca.

## Non-Functional Requirements

- **NFR1 — El preset, `ControlMapping` y la documentación dicen lo mismo.**
  `preset/README.md`, `preset/torax-h0.beatstep-pro.json` y `ControlMapping.swift`
  se actualizan en la misma rebanada. `PresetFileTests` ya fija ese invariante y
  tiene que quedar verde sin relajar ninguna aserción.
- **NFR2 — Nota fechada.** La nota del 2026-09-05 declara explícitamente que la
  pantalla y los knobs llevan órdenes distintos *a propósito*. Este track la
  revierte, así que el paso 8 del *Task Workflow* aplica: una nota del 2026-09-12
  en `preset/README.md`, en el JSON y en `ControlMapping` explicando qué la
  sustituye y por qué.
- **NFR3 — Cobertura de `MIDI` ≥80%**, sin bajar respecto a `main`.
- **NFR4 — Sin medición de jitter.** No se toca `MusicalTimeline`, el scheduler
  ni ningún parámetro que desplace eventos respecto a la rejilla: cambia qué knob
  mueve qué, no cuándo cae nada. Y la medición está suspendida desde el
  2026-09-02.
- **NFR5 — Vocabulario sin traducir** (NFR7 del producto). `Time` sigue siendo lo
  que lee el usuario aunque el caso del enum se llame `repeatTime`.

## Acceptance Criteria

1. `ControlMapping.beatStepPro.assignments` declara exactamente la tabla de FR1 y
   FR2, y `editingCycleController` devuelve el CC 85.
2. Girar el knob 5 mueve Repeats; el 9, Velocity; el 13, Delay; el 16, el Cycle
   en edición. Los knobs 14 y 15 no publican nada y no son un error.
3. Cada knob mueve el parámetro que la pantalla muestra en la misma posición
   relativa de su card.
4. Temp (step 13) y Ctrl All (step 14) siguen acotando los mismos trece knobs de
   parámetro, y siguen excluyendo el del Cycle, ahora en el CC 85.
5. Un mapeo guardado con el orden anterior se restaura tal cual, sin migrarse.
6. `preset/README.md` y el JSON reflejan la tabla nueva, con la nota del
   2026-09-12, y ningún texto del repositorio sigue afirmando que los knobs y la
   pantalla llevan órdenes distintos.
7. `swift test` verde en `MIDI`, `Engine` y `Persistence`; cobertura de `MIDI`
   ≥80%.
8. Verificado en dispositivo: los dieciséis knobs recorridos contra la pantalla,
   sin discrepancias.

## Out of Scope

- **Re-exportar `Torax.beatsteppro`.** Su contenido no cambia: declara dieciséis
  encoders en CC 70–85 en modo relativo, que sigue siendo cierto.
- **Asignar los knobs 14 y 15.** Siguen reservados para v2.
- **Migrar mapeos de MIDI Learn guardados** (FR5).
- **Cambiar la pantalla, los pads o los step buttons.**
- **Cualquier medición de jitter** (NFR4).
