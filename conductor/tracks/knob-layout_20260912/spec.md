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

**El `.beatsteppro` no cambia.** El archivo del controlador declara qué CC manda
cada encoder; qué significa cada CC lo decide la app. Esto es un cambio de
`ControlMapping` y de documentación, como ya lo fueron los del 2026-09-05 y el
2026-09-07.

> **Nota del 2026-09-12 — el bloque 70–85 empieza en la fila de abajo, y este
> spec decía lo contrario.** La primera versión daba por hecho que el encoder
> físico N manda el CC 69+N, así que la fila de arriba sería el 70–77. Es falso:
> `Torax.beatsteppro` asigna los controlId 32–39 —la fila de arriba— a los **CC
> 78–85**, y los 40–47 —la de abajo— a los **CC 70–77**. Verificado en
> dispositivo: el knob de arriba a la izquierda mueve Probability, que es el CC
> 78, y los cuatro últimos de la fila de abajo mueven Velocity, Sustain, Delay y
> Timing, que son los CC 74–77.
>
> **El diseño no cambia; cambian los números.** La regla sigue siendo una fila de
> knobs por card, con el Cycle en la esquina inferior derecha. Lo que cambia es
> qué CC hay que poner en cada sitio, y la tabla de abajo ya está corregida.
>
> Se descubrió en la verificación manual de la Fase 1, que entregó el Cycle al CC
> 85 creyendo que era la esquina de abajo: es el knob 8, arriba a la derecha.

## La tabla nueva

**La fila de arriba son los CC 78–85 y la de abajo los 70–77.** No es un despiste
de la tabla: es lo que el controlador manda.

### Fila de arriba — el card Shape

| Knob | CC | Hoy | Nuevo |
|---|---|---|---|
| 1 | 78 | Probability | **Steps** |
| 2 | 79 | Repeats | **Pulses** |
| 3 | 80 | Time | **Rotate** |
| 4 | 81 | Ramp | **Division** |
| 5 | 82 | sin asignar | **Repeats** |
| 6 | 83 | Pace | **Time** |
| 7 | 84 | sin asignar | **Ramp** |
| 8 | 85 | Cycle en edición | **Pace** |

### Fila de abajo — el card Groove, y el Cycle en la esquina

| Knob | CC | Hoy | Nuevo |
|---|---|---|---|
| 9 | 70 | Steps | **Velocity** |
| 10 | 71 | Pulses | **Sustain** |
| 11 | 72 | Rotate | **Probability** |
| 12 | 73 | Division | **Timing** |
| 13 | 74 | Velocity | **Delay** |
| 14 | 75 | Sustain | **sin asignar** |
| 15 | 76 | Delay | **sin asignar** |
| 16 | 77 | Timing | **Cycle en edición** |

## Functional Requirements

- **FR1 — Fila de arriba = card Shape.** Knobs 1–8 (CC 78–85): `Steps · Pulses · Rotate ·
  Division · Repeats · Time · Ramp · Pace`. El orden es el del card, incluidas sus
  dos líneas: el ritmo primero, el Note Repeater después. Es la agrupación que
  FR15 dibuja en pantalla, ahora también bajo la mano.
- **FR2 — Fila de abajo = card Groove.** Knobs 9–13 (CC 70–74): `Velocity · Sustain ·
  Probability · Timing · Delay`, en el orden del dominio que la pantalla ya usa.
  Esto revierte el intercambio de Delay y Probability del 2026-09-05.
- **FR3 — El Cycle en edición al knob 16 (CC 77).** `editingCycleKnobOffset` pasa
  de 12 a 7 — el knob 16 es la esquina inferior derecha, y su CC es el 77 porque
  el bloque empieza en esa fila. Queda separado de los trece parámetros por un hueco físico de dos
  knobs, y en la esquina del bloque, que es un punto de referencia táctil. Es lo
  que la nota del 2026-09-05 buscaba —que no parezca el décimo parámetro— y que
  estando adyacente sólo conseguía a medias.
- **FR4 — Quedan libres los knobs 14 y 15 (CC 75 y 76).** Se ignoran en silencio,
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
   FR2, y `editingCycleController` devuelve el CC 77.
2. Girar el knob 5 mueve Repeats; el 9, Velocity; el 13, Delay; el 16, el Cycle
   en edición. Los knobs 14 y 15 no publican nada y no son un error.
3. Cada knob mueve el parámetro que la pantalla muestra en la misma posición
   relativa de su card.
4. Temp (step 13) y Ctrl All (step 14) siguen acotando los mismos trece knobs de
   parámetro, y siguen excluyendo el del Cycle, ahora en el CC 77.
5. Un mapeo guardado con el orden anterior se restaura tal cual, sin migrarse.
6. `preset/README.md` y el JSON reflejan la tabla nueva, con la nota del
   2026-09-12, y ningún texto del repositorio sigue afirmando que los knobs y la
   pantalla llevan órdenes distintos.
7. `swift test` verde en `MIDI`, `Engine` y `Persistence`; cobertura de `MIDI`
   ≥80%.
8. Verificado en dispositivo: los dieciséis knobs recorridos contra la pantalla,
   sin discrepancias.

## Out of Scope

- **Re-exportar `Torax.beatsteppro`.** Su contenido no cambia: declara los
  dieciséis encoders en CC 70–85 en modo relativo, con la fila de arriba en el
  78–85 y la de abajo en el 70–77. Sigue siendo cierto, y ahora además está
  escrito.
- **Asignar los knobs 14 y 15.** Siguen reservados para v2.
- **Migrar mapeos de MIDI Learn guardados** (FR5).
- **Cambiar la pantalla, los pads o los step buttons.**
- **Cualquier medición de jitter** (NFR4).
