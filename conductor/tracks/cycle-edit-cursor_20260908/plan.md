# Plan — En pantalla no se puede elegir qué Cycle se edita

Sigue el `workflow.md`: tests antes de implementación, un commit por tarea, git
note por commit y checkpoint verificado al cerrar cada fase.

**El orden va de dentro afuera.** Primero la vía pública en `ControlInput`, que
es donde hay tests y donde la decisión se puede probar sin dedo ni controlador;
después el gesto en la vista, que es cableado; después el dispositivo.

**El riesgo está en la Fase 2, y es de gesto, no de código.** Partir un toque en
dos gestos sobre el mismo control es donde SwiftUI suele dejar un estado colgado:
mantener y arrastrar fuera, mantener y soltar, o el mantenido disparando además
el simple (FR7). Se prueba con el dedo porque ahí no hay test que valga.

**Cada fase deja el producto mejor que como lo encontró.** Al cerrar la Fase 1 el
cursor ya se puede mover desde código y desde el knob por la misma puerta; si la
2 no llegara a existir, no se ha roto nada.

**Sin medición de jitter** (NFR5): no mueve ningún instante.

## FASE 1: LA VÍA PÚBLICA EN `ControlInput`

- [x] Task: `ControlInput` fija el Cycle en edición (FR1, FR2, FR3, FR4) — `5da26f9`
  - [x] Tests (Red): fijar el Cycle 3 con cuatro activos mueve `editing` a 3 y
        **publica** el snapshot.
  - [x] Tests (Red): el siguiente giro de knob edita **ese** Cycle y deja los
        otros quince intactos — que es el fallo reportado, escrito como test.
  - [x] Tests (Red): fijar un índice **fuera del rango activo** se acota, no
        revienta y no inventa un Cycle (FR2).
  - [x] Tests (Red): fijar el índice que ya estaba **no publica** (FR4).
  - [x] Tests (Red): el cursor de **reproducción** no se mueve, y ni una nota de
        material cambia (FR3).
  - [x] Tests (Red): con el toque congelado —`isTouchFrozen`— no hace nada, como
        `setActiveCycleCount`.
  - [x] Implementación (Green): la vía pública junto a `setActiveCycleCount` y
        `setChannel`, apoyada en `Track.withEditing(_:)` sin duplicar el acotado.
- [x] Task: El knob y la pantalla entran por la misma puerta (FR10, NFR1) — `1560f9a`
  - [x] Tests (Red): mover el cursor con el knob 13 y con la vía nueva deja el
        mismo `Track`; alternarlos no descuadra nada.
  - [x] Implementación (Green): `moveEditingCycle(by:)` pasa por la vía pública
        en vez de escribir el Pattern por su cuenta.
  - [x] Comprobar que `Engine` no se toca (NFR1). Si hiciera falta tocarlo,
        **parar** y anotar por qué antes de seguir.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md) — `1560f9a`
  - Suite de `MIDI`: 874 tests, 1 skipped, 0 fallos.
  - Cobertura de `MIDI` ignorando `Engine/Sources`: **91,51%** de líneas (≥80%).
  - `Engine` sin tocar (NFR1); sin medición de jitter (NFR5).
  - Sin verificación manual en esta fase: la vía todavía no tiene gesto detrás.
    El knob 13 sigue moviendo el mismo cursor, que es la no regresión que cubre
    `EditingCycleSameDoorTests`.

## FASE 2: EL GESTO EN EL `CycleStrip`

- [x] Task: Pulsar elige el Cycle en edición (FR5, NFR4) — `e8a47d8`
  - [x] La celda llama a la vía de la Fase 1 a través del modelo solo si
        `number <= activeCount`.
  - [x] Una celda fuera del rango activo no hace nada al pulsarla: el gesto
        descarta `number > activeCount` antes de invocar la vía.
  - [ ] Comprobar en simulador que el contorno del Cycle en edición se mueve, que
        es lo único que el simulador puede verificar de este track. **Pendiente:
        lo hace el usuario, no hay forma de tocar la pantalla desde aquí.**
- [x] Task: Mantener cambia cuántos están activos (FR6, FR7) — `e8a47d8`, mismo commit que la anterior: partir un toque en dos gestos no se entrega a medias
  - [x] El mantenido llama a `setActiveCycleCount`, que es lo que la celda hacía
        hasta hoy.
  - [x] **Dispara al cumplirse el tiempo, no al soltar** (FR6).
  - [x] **Después de disparar, soltar no elige** (FR7): un toque, una cosa.
  - [ ] Probar los estados feos con el dedo: mantener y arrastrar fuera de la
        celda, mantener y soltar sobre otra, dos dedos a la vez. Ninguno deja el
        cursor ni el rango en un valor que nadie pidió. **Pendiente: con el
        dedo.**
  - [x] Revisar que ninguna otra vista dependía de que la celda cambiara el
        rango al primer toque.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md) — `e8a47d8`
  - `xcodebuild build -scheme ToraxH0 -destination 'generic/platform=iOS'`:
    BUILD SUCCEEDED.
  - Suites verdes: `Engine` 888, `MIDI` 874 (1 skipped), `Persistence` 64.
  - Sin tests para el cambio de `App`, que no se mide (`workflow.md`). La lógica
    que sí se testea —el acotado y el publicar— se quedó en la Fase 1.
  - **Verificación manual pendiente**, y es la que decide esta fase: el reparto
    tap/hold de SwiftUI no se comprueba compilando. Los pasos están en los dos
    subtasks abiertos de arriba.

## FASE 3: DISPOSITIVO Y CIERRE

- [x] Task: Verificación en iPad con BeatStep Pro — verificado el 2026-09-09, con
      cuatro comprobaciones no ejecutadas y anotadas
  - [ ] **El fallo reportado, primero**: cuatro Cycles activos, pulsar el 3,
        girar Steps, volver al 1 y comprobar que **los dos valores conviven**.
        **No se probó**; lo cubre `testTwoCyclesCanHoldDifferentValues`.
  - [ ] Con el transporte corriendo: el relleno del que suena avanza solo y el
        contorno del que se edita se queda donde lo dejó el dedo. **No se
        probó.**
  - [x] Mantener una celda sube el rango al cumplirse el tiempo y soltar después
        no elige ese Cycle. **Bajar el rango no se probó.**
  - [x] El knob 13 mueve el mismo contorno. **Cambiar de Track y volver no se
        probó**; lo cubre `testEachTrackKeepsItsOwnEditingCycleAcrossSelection`.
  - [x] Escribir `device-verification.md` con lo que se probó y lo que no.
- [x] Task: Cobertura y suite completa
  - [x] `MIDI` ≥80% medida en un proceso e ignorando `Engine/Sources`, como dice
        `workflow.md` — **91,51%** de líneas, y `ControlInput.swift` al 100%.
  - [x] Suites verdes: `Engine` 888, `MIDI` 874 (1 skipped), `Persistence` 64.
- [ ] Task: Pull Request
  - [ ] Rama `fix/cycle-edit-cursor`, PR contra `main`. Cuerpo corto.
- [ ] Task: Cerrar el defecto en el registro
  - [ ] Marcarlo en `tracks.md` con lo que se verificó en dispositivo.
  - [ ] Anotar en el `spec.md` lo que se haya corregido al implementar, con
        fecha.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
