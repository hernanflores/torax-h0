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

## FASE 2: DOCE TRACKS EN EL MOTOR [checkpoint: 3d979c5]

> **Enmienda del 2026-09-02 — las cuatro tareas van en un commit.** El plan las
> separaba y no son separables: `trackCount` es **una** constante, y en cuanto
> pasa a 12 los dos paquetes dejan de pasar a la vez. No existe un estado
> intermedio verde, así que partirlo habría significado commits que no compilan o
> tests desactivados, y el `workflow.md` exige lo contrario. Se marcan las cuatro
> con el mismo SHA.
>
> **Lo que costó descubrirlo.** Al bajar la constante, la suite de MIDI moría con
> SIGBUS en un test que aislado pasaba. La causa no era el tipo sino tests que
> recorrían `0..<16` y hacían force-unwrap de `cycle(at: 12...15)`, ya `nil`.
> Está anotado en la git note del commit, con el detalle de cómo aflorarlo
> (`--sanitize=address`).
>
> **Un arreglo real que salió de camino:** `RingStack` calculaba el radio
> restando `spacing` de forma acumulada, y con doce bandas el error de coma
> flotante hacía que el anillo interior invadiera el hueco central por un bit.
> Ahora interpola entre los dos extremos, que salen exactos, y el test lo exige
> con igualdad — más fuerte que lo que había.


- [x] Task: `Pattern` guarda doce (FR1) [3d979c5]
  - [ ] Tests (Red): recorrer los doce huecos; `track(at: 11)` devuelve valor y
        `track(at: 12)` devuelve `nil`; `Pattern.init()` asigna Track N → canal N
        para 1–12; `_isPOD(Pattern.self)` sigue cierto.
  - [ ] Implementación (Green): `trackCount = 12`, tupla de doce, `init()`
        acotado.
  - [ ] Verificar que `Pattern.initial` sigue sonando igual — material solo en el
        Track 1.
  - [ ] Cobertura `Engine` ≥90%.
- [x] Task: Anillos, playhead y posición de Cycle derivan de doce (FR2) [3d979c5]
  - [ ] Tests (Red): `RingStack` produce doce bandas y el ancho de banda es el
        esperado para `trackCount − 1`; `Playhead` y `CyclePosition` devuelven
        doce entradas.
  - [ ] Implementación: comprobar que **no hace falta tocar nada** — si algún
        sitio tiene 16 escrito a mano, sale aquí y se sustituye por
        `Pattern.trackCount`.
- [x] Task: El scheduler y el transporte con doce (FR1) [3d979c5]
  - [ ] Tests (Red): `PatternScheduler` asigna doce schedulers; `Transport` apaga
        las doce voces al parar. Adaptar `StopWithSixteenTracksTests` y compañía,
        nombre incluido.
  - [ ] Implementación (Green).
  - [ ] Cobertura `MIDI` ≥80%.
- [x] Task: Los step buttons 13–16 no seleccionan Track (FR3) [3d979c5]
  - [ ] Tests (Red): el step button 12 selecciona el Track 12; los 13 a 16 no
        publican selección y no son error. `ControlMapping.declaredNumbers` sigue
        declarando dieciséis.
  - [ ] Implementación (Green): acotar en la selección de Track, no en el mapeo —
        la tabla del preset describe el hardware y `preset/` no cambia.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 3: EL SELECTOR DICE SOLO SU NÚMERO [checkpoint: 9ef9ff7]

> **Enmienda del 2026-09-02 — las dos tareas van en un commit.** Quitar el canal
> de la pastilla y quitar la fila que lo edita son la misma edición: los
> parámetros `channels` y `onChannelChange` sirven a las dos, y dejar una sin la
> otra no compila. Se marcan con el mismo SHA.


- [x] Task: Doce pastillas, un número cada una (FR4) [d582038]
  - [ ] Quitar el canal del `label` del botón y dejar el número centrado, con los
        tres estados intactos.
  - [ ] La fila pasa de dieciséis a doce posiciones, derivadas de
        `Pattern.trackCount` y no de un literal.
  - [ ] Actualizar la documentación de la vista: la razón de «una fila y no dos»
        sigue siendo válida y la de «el canal en pequeño y debajo» desaparece con
        el código.
- [x] Task: La pantalla Track pierde su fila `Channel` (FR7) [d582038]
  - [ ] Retirar `channelRow`, `selectedChannel` y los parámetros `channels` /
        `onChannelChange` de `TrackSelectorView`.
  - [ ] `ContentView` deja de pasárselos; `model.channels` y `model.setChannel`
        se conservan para la Fase 4.
- [x] Task: Corrección en vuelo — el anillo se queda el sitio que la fila de canal devolvió [9ef9ff7]
  - Salió de la verificación manual: el anillo no crecía. `reservedBelowStage`
    era el literal `324`, que seguía reservando la fila de canal y una pastilla
    de 56 puntos; pasa a ser una suma de constantes con nombre y da 216. El
    sobrante entre el lado del anillo y su columna se lo queda la lectura en vez
    de quedarse en blanco.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 4: LA PANTALLA MIDI [checkpoint: f12fa56]

- [x] Task: `3 · MIDI` deja de estar en discontinuo (FR5) [38d846f]
  - [ ] Añadir el caso a `Screen` con su etiqueta; `unavailableScreens` queda en
        `["4 · Banks", "5 · Tracks"]`.
  - [ ] Pantalla vacía con su título, para que el cambio de navegación se
        verifique aparte del contenido.
- [x] Task: La asignación de canal, los doce a la vez (FR6) [f12fa56]
  - [ ] Vista nueva en `App`: doce filas `Track N` con selector de canal 1–16,
        usando `Brutalist` y `Typography` — sin estilo propio (NFR5).
  - [ ] Cablear a `model.channels` y a un `setChannel(_:forTrack:)`, que hoy solo
        sabe del Track seleccionado.
  - [ ] Si esa función necesita lógica —acotar índice, validar canal—, va a `MIDI`
        o `Engine` con test, no a `App` (regla de cobertura del `workflow.md`).
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 5: EL ARNÉS QUEDA COHERENTE

- [ ] Task: Rejilla `12-tracks-cycles` (FR8)
  - [ ] Renombrar el caso y su cadena; `trackCount: 12`.
  - [ ] Actualizar las referencias en los `device-verification.md` de las
        rebanadas 2 y 3 y en `workflow.md`, que nombran la rejilla vieja.
  - [ ] **No se mide** — suspendido el 2026-09-02. La tarea deja la herramienta
        lista, no produce número.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
