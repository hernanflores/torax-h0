# Plan — Pitch y Harmony

Sigue el `workflow.md`: tests antes de implementación, un commit por tarea, git
note por commit y checkpoint verificado al cerrar cada fase. Todo en la rama
`feat/pitch-harmony` y entra por un solo PR.

**El orden va de dentro afuera, y Pitch primero.** Primero se escribe la
desviación de la Pre Spec, que el Task Workflow §8 exige *antes* de implementar.
Después viene la matemática de grados en `Engine`, sin relojes. Luego Pitch
completo, del modelo a la pantalla, así que a mitad del track ya suena algo
usable. Harmony va encima, reutilizando lo que Pitch dejó.

**El pool que suena se calcula en el hilo de control, no en el del scheduler.**
`Cycle.pitch(atStep:)` es el único consumidor del pool en la emisión
(`TrackScheduler`). Si el `Cycle` lleva ya derivado un `PitchPool` que suena,
que se recalcula al construirse, el hilo de tiempo real sigue leyendo un pool
inline sin hacer aritmética de grados (NFR1).

**Todas las fases cargan con AC 11.** Con Pitch 0 y Harmony limpio la salida
tiene que ser idéntica a la de antes. Cada fase que toque la emisión deja su
test de no regresión.

**Ninguna fase mide jitter** (NFR4): no se desplaza ningún instante.

## FASE 1: LA DESVIACIÓN QUEDA ESCRITA [checkpoint: e1298c8]

- [x] Task: Anotar Pitch y Harmony en la Pre Spec — 9ada5fd
  - [x] Nota fechada en `Pre Spec Torax H-0.md`, sección *Tonal*: Pitch transpone
        en **grados de escala**, no en «semitonos dentro del marco tonal», con la
        razón: dos semitonos cuantizados pueden dar la misma nota.
  - [x] Harmony: round robin con histéresis, sin cruces ni choques. **Sin Reset
        Harmony**: se limpia al editar el pool o cambiar Scale o Root.
  - [x] Fijar vocabulario: pitch del pool, no *voice*. Pitch y Harmony sin
        traducir.
- [x] Task: Sacar Harmony de «Fuera de v1» en `product.md` — e1298c8
  - [x] Nota fechada en *MVP Scope* e *Interaction Model*: Pitch y Harmony
        transforman el pool que suena, y los pads siguen editando el pool base.
  - [x] Anotar las limitaciones conocidas: Harmony sin histéresis bajo Ctrl All,
        y Ctrl All frente a Temp.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 2: LOS GRADOS — MATEMÁTICA PURA EN `Engine` [checkpoint: fd87d17]

- [x] Task: Altura ↔ grado en `TonalFrame` (FR2, FR3) — fd87d17
  - [x] Tests (Red): en Do mayor, C4 es un grado y B3 el anterior. Grado +1 desde
        B3 da C4. La ida y vuelta altura→grado→altura es exacta para toda altura
        del marco en 0–127, en las ocho escalas y los doce Roots.
  - [x] Tests (Red): un grado cuya altura cae fuera de 0–127 devuelve `nil`.
  - [x] Tests (Red): pentatonic y hirajoshi (5 grados) cruzan la octava bien.
  - [x] Implementación (Green): conversión sin asignaciones, derivada de
        `pitchClassMask`, sin escribir intervalos en un segundo sitio.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 3: PITCH

- [x] Task: `pitch` dentro del `Cycle` y el pool que suena (FR1, FR2, FR4, FR7, NFR1) — 1985664
  - [x] Tests (Red): AC 1 (C4 E4 G4 con +1 dan D4 F4 A4, con −1 dan B3 D4 F4).
        `pitch(atStep:)` recorre el pool que suena.
  - [x] Tests (Red): AC 7, intervalos en grados conservados (propiedad).
  - [x] Tests (Red): AC 11, con `pitch` 0 la salida es idéntica al pool base.
  - [x] Tests (Red): `_isPOD(Cycle.self)` sigue siendo cierto. `with(...)`
        conserva `pitch` (se extienden `CycleEditsKeepEverythingElseTests` y
        similares).
  - [x] Implementación (Green): campo en `Cycle`, pool que suena derivado en
        `init`, `with(pitch:)`.
- [ ] Task: `TrackParameter.pitch` (FR4, FR5, FR6, FR19)
  - [ ] Tests (Red): rango −28…+28, freno en extremos. Freno atómico si algún
        pitch saldría de 0–127. Con pool vacío se mueve libre dentro del rango.
  - [ ] Tests (Red): familia `.tonal`, `description` «Pitch», valor `+2`, `0`,
        `-1`. `displacementRange` −28…28. `value(of:)` y `setting(_:to:)`.
  - [ ] Tests (Red): actualizar `ParameterFamilyTests`, que hoy fija que ningún
        parámetro es Tonal.
  - [ ] Implementación (Green): casos en `applying(_:to:)`, `value(of:)`,
        `value(in:)`, `displacementRange`.
- [ ] Task: Pitch sobrevive al disco (FR22, FR23)
  - [ ] Tests (Red): ida y vuelta de `CycleRecord` con `pitch`. Un JSON anterior
        sin el campo decodifica con 0. La lista de claves de
        `RecordRoundTripTests` incluye la nueva.
  - [ ] Tests (Red): copiar Pattern o Cycle conserva `pitch`.
  - [ ] Implementación (Green): `ProjectRecord`.
- [ ] Task: Scale o Root conservan Pitch (FR13)
  - [ ] Tests (Red): cambiar el marco (`ControlInput`, reencuadre) deja `pitch`
        intacto y el pool que suena en la escala nueva.
  - [ ] Implementación (Green) si hace falta.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 4: HARMONY — EL PASO

- [ ] Task: Estado de Harmony en el `Cycle` (FR1, NFR1)
  - [ ] Tests (Red): 8 offsets con signo y cursor, inline. `_isPOD(Cycle.self)`.
        Defaults a 0. `with(...)` los conserva.
  - [ ] Tests (Red): el pool que suena suma los offsets. AC 11 con estado limpio.
  - [ ] Implementación (Green): valor `Harmony` inline (en el idioma de
        `PitchPool`, huecos en un entero), campo en `Cycle`.
- [ ] Task: Un paso de Harmony (FR8–FR12, NFR2)
  - [ ] Tests (Red): AC 4 literal (D4 E4 G4 → D4 F4 G4 → D4 F4 A4 → C4 F4 A4).
  - [ ] Tests (Red): AC 5 combinado con Pitch (D4 G4 B4, y C4 F4 A4 con Pitch 0).
  - [ ] Tests (Red): candidato que choca o cruza con su vecino se salta y prueba
        el siguiente. Borde MIDI con Pitch aplicado. Todos bloqueados: Cycle
        idéntico (AC 8).
  - [ ] Tests (Red): pool de 0 y 1 no hace nada ni avanza el cursor. Delta *n*
        igual a *n* pasos de 1.
  - [ ] Tests (Red) de propiedades (AC 3, AC 6): un paso cambia como mucho un
        pitch que suena; toda altura en el marco y en 0–127; mismo estado y
        mismos deltas dan misma salida.
  - [ ] Implementación (Green): paso en `Engine`, sin UI ni MIDI.
- [ ] Task: `TrackParameter.harmony` (FR8, FR20)
  - [ ] Tests (Red): familia `.tonal`, `description` «Harmony». El valor escrito
        es el pool que suena (`D4 F4 A4`), y con pool vacío `empty`.
  - [ ] Tests (Red): Pitch mantiene freno atómico con offsets de Harmony activos.
  - [ ] Implementación (Green): caso en `applying(_:to:)` y `value(in:)`. Decidir
        y documentar `displacementRange` y `value(of:)` para Harmony según
        FASE 6.
- [ ] Task: Harmony se limpia (FR13, AC 9)
  - [ ] Tests (Red): insertar o quitar un pitch con pad limpia offsets y cursor y
        conserva `pitch`. Cambiar Scale o Root igual. Mover el registro de pads
        (`padOctaveShift`) **no** limpia.
  - [ ] Implementación (Green): operaciones de dominio en `Cycle` para editar el
        pool y reencuadrar, que limpian Harmony. `ControlInput` las usa en lugar
        de `with(pool:)` y `with(frame:)` sueltos. `with(...)` sigue sin limpiar,
        porque copia, persistencia y restauración lo necesitan literal.
- [ ] Task: Harmony sobrevive al disco (FR22, FR23)
  - [ ] Tests (Red): ida y vuelta de offsets y cursor. JSON anterior decodifica
        limpio. Guardar y cargar reproduce la salida sin rehacer giros (AC 10).
  - [ ] Implementación (Green): `ProjectRecord`.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 5: KNOBS, MIDI LEARN Y PRESET

- [ ] Task: CC 75 y 76 en `ControlMapping` (FR14)
  - [ ] Tests (Red): knob 14 mueve Pitch y knob 15 mueve Harmony en el Track
        seleccionado. Ningún otro CC cambia de dueño. El knob del Cycle sigue en
        CC 77.
  - [ ] Implementación (Green): asignaciones de fábrica.
- [ ] Task: MIDI Learn y proyectos guardados (FR15)
  - [ ] Tests (Red): Pitch y Harmony se aprenden. Un `ControlNumbers` guardado
        sin ellos se completa con 75 y 76 solo si están libres; si uno está
        ocupado, ese parámetro queda sin control y nada aprendido se pisa.
  - [ ] Implementación (Green).
- [ ] Task: Tabla del preset
  - [ ] Actualizar `preset/README.md`. Confirmar que `Torax.beatsteppro` no cambia.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 6: TEMP Y CTRL ALL

- [ ] Task: Pitch bajo Temp y Ctrl All (FR16, FR17)
  - [ ] Tests (Red): Temp iguala Pitch en los Cycles activos y restaura al
        soltar. Ctrl All desplaza con base + offset, tope ±28, freno atómico por
        Cycle, y restaura exacto (AC 12).
  - [ ] Implementación (Green) si hace falta más allá de los casos genéricos.
- [ ] Task: Harmony bajo Ctrl All — base + neto (FR16)
  - [ ] Tests (Red): cada Cycle se recalcula como estado base + |neto| pasos. +1
        luego −1 vuelve a la base (sin histéresis, decisión explícita). Al soltar
        vuelve el estado capturado.
  - [ ] Implementación (Green): la base de Harmony no es un `Int`. Ampliar la
        captura de `CtrlAllOffset` para guardar el estado de Harmony por Cycle,
        sin romper la de los `Int`.
- [ ] Task: Harmony bajo Temp — un paso por Cycle (FR17)
  - [ ] Tests (Red): cada clic da un paso en cada Cycle activo con su propio
        estado (sin igualar). Al soltar vuelve el estado capturado de cada Cycle.
        Cursores de reproducción intactos.
  - [ ] Implementación (Green): captura del estado de Harmony en
        `ParameterOverlay`.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 7: LA PANTALLA

- [ ] Task: Card Tonal y valor transitorio (FR19, FR20, FR18)
  - [ ] Pitch como `±n`. Harmony muestra el pool que suena. Giro bloqueado sin
        aviso. La regla de texto vive en `Engine` con tests y la vista solo
        dibuja.
- [ ] Task: Rejilla `scale` y pads (FR21)
  - [ ] Tests (Red) en `Engine`/`MIDI`: la iluminación sale del pool base.
  - [ ] `ScaleScreen`: pool base en la rejilla, pool que suena en el readout.
- [ ] Task: Compilar la app para iPadOS y revisar en simulador
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 8: DISPOSITIVO Y CIERRE

- [ ] Task: Verificación en iPad con BeatStep Pro (AC 13)
  - [ ] Knobs 14 y 15 mueven Pitch y Harmony. Evaluación de oído con pools de 2,
        3 y 4 pitches en major, minor y pentatonic, con giros lentos y rápidos y
        cambios de sentido. Registrar casos abruptos o estancados en
        `device-verification.md`.
  - [x] Temp y Ctrl All con Pitch y Harmony. Guardar, recargar y comprobar que
        suena igual.
- [ ] Task: Cobertura y suite completa
- [ ] Task: Pull Request a `main`
- [ ] Task: Actualizar el registro y cerrar el track
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
