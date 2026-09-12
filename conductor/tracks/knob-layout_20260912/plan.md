# Implementation Plan — `knob-layout_20260912`

Cuatro fases. Las dos primeras son el cambio de mapeo, partido en dos porque el
Cycle en edición no vive en `assignments` y su knob se mueve por otra vía. La
tercera cierra el invariante de las tres fuentes —preset, JSON y código— y la
cuarta verifica en el aparato.

**Sin fase de jitter** (NFR4): no se mueve ningún instante, y la medición está
suspendida desde el 2026-09-02.

## FASE 1: El mapeo por defecto

- [ ] Task: Tests rojos del nuevo orden de los trece parámetros
  - [ ] En `ControlMappingTests`: cada `TrackParameter` contra su CC nuevo —74
        Repeats, 75 Time, 76 Ramp, 77 Pace, 78 Velocity, 79 Sustain, 80
        Probability, 81 Timing, 82 Delay—
  - [ ] En `PresetMappingTests`: girar el knob 5 mueve Repeats, el 9 Velocity y
        el 13 Delay
  - [ ] En `UnassignedInputTests`: los CC 83 y 84 no publican nada
  - [ ] Correr `swift test` y confirmar que fallan
- [ ] Task: Reasignar `assignments` en `ControlMapping.beatStepPro`
  - [ ] Escribir la tabla de FR1 y FR2
  - [ ] Confirmar verde
- [ ] Task: Phase Verification & Checkpoint (ver `workflow.md`)

## FASE 2: El Cycle en edición al knob 16

- [ ] Task: Tests rojos del knob del Cycle
  - [ ] En `ControlMappingTests`: `editingCycleController` devuelve el CC 85
  - [ ] En `MappingNumbersTests`: `hasConflict` con un parámetro en 85, y sin
        conflicto con uno en 82
  - [ ] En `EditingCycleInputTests`: el CC 85 mueve el cursor de edición y el 82
        mueve Delay
  - [ ] Correr y confirmar que fallan
- [ ] Task: Mover `editingCycleKnobOffset` de 12 a 15
  - [ ] Confirmar verde
- [ ] Task: Temp y Ctrl All acotan los trece knobs de parámetro y excluyen el 85
  - [ ] Revisar `TempModifierInputTests`, `CtrlAllModifierInputTests` y
        `EditingCycleTouchPathTests`
  - [ ] Corregir las referencias a «knob 10», al CC 79 y al CC 82 que queden en
        código, comentarios y tests
- [ ] Task: Phase Verification & Checkpoint

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
