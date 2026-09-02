# Plan — Reducción a 12 Tracks, pantalla MIDI y limpieza del selector

Sigue el `workflow.md`: tests antes de implementación, un commit por tarea, git
note por commit y checkpoint verificado al cerrar cada fase.

**El orden no es arbitrario.** La nota de la desviación va primera porque el Task
Workflow §8 exige documentar antes de implementar; el motor va antes que la
pantalla porque `trackCount` es de quien todo lo demás deriva.

**Ninguna fase mide jitter** (NFR6, suspendido el 2026-09-02).

## FASE 1: LA DESVIACIÓN QUEDA ESCRITA [checkpoint: 98ad6dd]

- [x] Task: Anotar el 16 → 12 en la Pre Spec y en `product.md` (FR9) [98ad6dd]
  - [ ] Nota fechada 2026-09-02 en `Pre Spec Torax H-0.md`: doce Tracks por
        Pattern, y el porqué — con dieciséis, cada banda del anillo queda en un
        ancho que no se lee a un metro, que es el requisito de
        `product-guidelines.md`.
  - [ ] Nota equivalente en `conductor/product.md`, en el Core Model y en el MVP
        Scope.
  - [ ] Dejar dicho que **el modelo no cambia de forma**: doce es un límite de
        legibilidad, no un concepto nuevo; si el ancho deja de ser el problema,
        la constante vuelve a subir.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 2: DOCE TRACKS EN EL MOTOR

- [ ] Task: `Pattern` guarda doce (FR1)
  - [ ] Tests (Red): recorrer los doce huecos; `track(at: 11)` devuelve valor y
        `track(at: 12)` devuelve `nil`; `Pattern.init()` asigna Track N → canal N
        para 1–12; `_isPOD(Pattern.self)` sigue cierto.
  - [ ] Implementación (Green): `trackCount = 12`, tupla de doce, `init()`
        acotado.
  - [ ] Verificar que `Pattern.initial` sigue sonando igual — material solo en el
        Track 1.
  - [ ] Cobertura `Engine` ≥90%.
- [ ] Task: Anillos, playhead y posición de Cycle derivan de doce (FR2)
  - [ ] Tests (Red): `RingStack` produce doce bandas y el ancho de banda es el
        esperado para `trackCount − 1`; `Playhead` y `CyclePosition` devuelven
        doce entradas.
  - [ ] Implementación: comprobar que **no hace falta tocar nada** — si algún
        sitio tiene 16 escrito a mano, sale aquí y se sustituye por
        `Pattern.trackCount`.
- [ ] Task: El scheduler y el transporte con doce (FR1)
  - [ ] Tests (Red): `PatternScheduler` asigna doce schedulers; `Transport` apaga
        las doce voces al parar. Adaptar `StopWithSixteenTracksTests` y compañía,
        nombre incluido.
  - [ ] Implementación (Green).
  - [ ] Cobertura `MIDI` ≥80%.
- [ ] Task: Los step buttons 13–16 no seleccionan Track (FR3)
  - [ ] Tests (Red): el step button 12 selecciona el Track 12; los 13 a 16 no
        publican selección y no son error. `ControlMapping.declaredNumbers` sigue
        declarando dieciséis.
  - [ ] Implementación (Green): acotar en la selección de Track, no en el mapeo —
        la tabla del preset describe el hardware y `preset/` no cambia.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 3: EL SELECTOR DICE SOLO SU NÚMERO

- [ ] Task: Doce pastillas, un número cada una (FR4)
  - [ ] Quitar el canal del `label` del botón y dejar el número centrado, con los
        tres estados intactos.
  - [ ] La fila pasa de dieciséis a doce posiciones, derivadas de
        `Pattern.trackCount` y no de un literal.
  - [ ] Actualizar la documentación de la vista: la razón de «una fila y no dos»
        sigue siendo válida y la de «el canal en pequeño y debajo» desaparece con
        el código.
- [ ] Task: La pantalla Track pierde su fila `Channel` (FR7)
  - [ ] Retirar `channelRow`, `selectedChannel` y los parámetros `channels` /
        `onChannelChange` de `TrackSelectorView`.
  - [ ] `ContentView` deja de pasárselos; `model.channels` y `model.setChannel`
        se conservan para la Fase 4.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 4: LA PANTALLA MIDI

- [ ] Task: `3 · MIDI` deja de estar en discontinuo (FR5)
  - [ ] Añadir el caso a `Screen` con su etiqueta; `unavailableScreens` queda en
        `["4 · Banks", "5 · Tracks"]`.
  - [ ] Pantalla vacía con su título, para que el cambio de navegación se
        verifique aparte del contenido.
- [ ] Task: La asignación de canal, los doce a la vez (FR6)
  - [ ] Vista nueva en `App`: doce filas `Track N` con selector de canal 1–16,
        usando `Brutalist` y `Typography` — sin estilo propio (NFR5).
  - [ ] Cablear a `model.channels` y a un `setChannel(_:forTrack:)`, que hoy solo
        sabe del Track seleccionado.
  - [ ] Si esa función necesita lógica —acotar índice, validar canal—, va a `MIDI`
        o `Engine` con test, no a `App` (regla de cobertura del `workflow.md`).
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 5: EL ARNÉS QUEDA COHERENTE

- [ ] Task: Rejilla `12-tracks-cycles` (FR8)
  - [ ] Renombrar el caso y su cadena; `trackCount: 12`.
  - [ ] Actualizar las referencias en los `device-verification.md` de las
        rebanadas 2 y 3 y en `workflow.md`, que nombran la rejilla vieja.
  - [ ] **No se mide** — suspendido el 2026-09-02. La tarea deja la herramienta
        lista, no produce número.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
