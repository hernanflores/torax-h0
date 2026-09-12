# Implementation Plan — `knob-layout_20260912`

Cuatro fases. La primera movió el knob del Cycle y quedó mal por una premisa
falsa sobre el orden físico de los CC; la segunda sustituye el bloque entero con
los números reales. La tercera cierra el invariante de las tres fuentes —preset,
JSON y código— y la cuarta verifica en el aparato.

**Sin fase de jitter** (NFR4): no se mueve ningún instante, y la medición está
suspendida desde el 2026-09-02.

> **Nota del 2026-09-12 — el plan se reescribió dos veces el mismo día.**
>
> **Primero, por el orden.** Movía los trece parámetros antes que el knob del
> Cycle, y no se puede: `hasConflict` rechaza que un parámetro caiga sobre el CC
> del Cycle (`ControlMapping.swift:322`). El Cycle pasó a ir primero.
>
> **Después, por los números.** La verificación en dispositivo de la Fase 1
> encontró que el bloque 70–85 **empieza en la fila de abajo**: la de arriba son
> los CC 78–85. Todo el plan suponía lo contrario. Con los números reales se
> mueven los dieciséis knobs a la vez, así que las dos fases se funden en una.
> El detalle está en la nota del `spec.md`.

## FASE 1: El Cycle en edición al knob 16

- [x] Task: Tests rojos del knob del Cycle `57ef412`
  - [ ] En `ControlMappingTests`: `editingCycleController` devuelve el CC 85
  - [ ] En `MappingNumbersTests`: `hasConflict` con un parámetro en 85, y sin
        conflicto con uno en 82
  - [ ] En `EditingCycleInputTests`: el CC 85 mueve el cursor de edición y el 82
        mueve Delay
  - [ ] Correr y confirmar que fallan
- [x] Task: Mover `editingCycleKnobOffset` de 12 a 15 `57ef412`
  - [ ] Confirmar verde
- [x] Task: Temp y Ctrl All acotan los trece knobs de parámetro y excluyen el 85 `38015b7`
  - [ ] Revisar `TempModifierInputTests`, `CtrlAllModifierInputTests` y
        `EditingCycleTouchPathTests`
  - [ ] Corregir las referencias a «knob 10», al CC 79 y al CC 82 que queden en
        código, comentarios y tests
> **Fase cerrada con el resultado equivocado, y por eso no se marca completa.**
> La verificación en dispositivo del 2026-09-12 encontró que el knob 16 no manda
> el CC 85 sino el 77: el bloque empieza en la fila de abajo. El Cycle acabó en
> el knob 8, arriba a la derecha. Los dos commits quedan en la historia; lo que
> dejaron mal lo corrige la Fase 2.

## FASE 2: El mapeo entero, de una vez

> **Era «los trece parámetros» y ahora es todo el bloque.** El plan movía primero
> el Cycle y después los parámetros. Con los números reales se mueven los
> dieciséis knobs a la vez y cualquier orden parcial deja un CC significando dos
> cosas, que es lo que `hasConflict` rechaza. Una sola tabla, sustituida entera.

- [x] Task: Tests rojos del bloque entero
  - [ ] En `PresetMappingTests`: la tabla de los trece parámetros con sus CC
        nuevos —78 Steps, 79 Pulses, 80 Rotate, 81 Division, 82 Repeats, 83 Time,
        84 Ramp, 85 Pace, 70 Velocity, 71 Sustain, 72 Probability, 73 Timing,
        74 Delay—
  - [ ] `editingCycleController` devuelve el CC 77, y los CC 75 y 76 no mueven
        nada
  - [ ] En `ControlMappingTests`: los CC de Shape y de Groove, que hoy afirman la
        tabla vieja
  - [ ] Correr y confirmar que fallan
- [x] Task: Sustituir `assignments` y `editingCycleKnobOffset` (de 15 a 7)
  - [ ] Confirmar verde
- [ ] Task: Phase Verification & Checkpoint (ver `workflow.md`)

## FASE 3: Preset y documentación

- [ ] Task: Actualizar `preset/torax-h0.beatstep-pro.json`
  - [ ] Tabla nueva de knobs, `version` 5 y `updated` 2026-09-12
  - [ ] Nota por knob en los que se mueven, y la nota de bloque que sustituye a
        la del 2026-09-05
- [ ] Task: Actualizar `preset/README.md`
  - [ ] Tabla de los dieciséis knobs
  - [ ] Nota fechada del 2026-09-12 que revierte la del 2026-09-05, con la regla
        nueva escrita: una fila de knobs por card (NFR2)
  - [ ] Tabla de síntomas: el rango de los knobs es 70–85
- [ ] Task: Nota fechada en `ControlMapping.swift`
  - [ ] En `beatStepPro` y en `editingCycleKnobOffset`
- [ ] Task: Corregir `Pre Spec Torax H-0.md` donde nombra los CC del Note
      Repeater
- [ ] Task: `PresetFileTests` verde sin relajar ninguna aserción (NFR1)
- [ ] Task: Phase Verification & Checkpoint

## FASE 4: Cobertura, dispositivo y cierre

- [ ] Task: Suite completa verde y cobertura de `MIDI` ≥80% (NFR3)
- [ ] Task: Verificación en dispositivo
  - [ ] BeatStep Pro contra el iPad, recorrer los dieciséis knobs
  - [ ] Cada knob mueve lo que la pantalla enseña en su misma posición de card
  - [ ] Los knobs 14 y 15 no hacen nada; el 16 mueve el Cycle en edición
  - [ ] Temp y Ctrl All sobre un knob de cada fila
  - [ ] Escribir `device-verification.md`
- [ ] Task: Pull Request a `main`
- [ ] Task: Phase Verification & Checkpoint
