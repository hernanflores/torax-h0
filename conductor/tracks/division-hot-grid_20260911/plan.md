# Plan — La Division no mueve la rejilla mientras suena

Sigue el `workflow.md`: tests antes de implementación, un commit por tarea, git
note por commit y checkpoint verificado al cerrar cada fase.

**De dentro afuera.** La pieza que decide —la rejilla con ancla— es valor puro y
vive en `Engine`, donde se prueba sin CoreMIDI, sin hilo y sin reloj (NFR5). Va
primera. El hilo del scheduler solo decide *cuándo* reanclar, y eso llega cuando
el *cómo* ya está probado.

**El defecto reportado se cierra en la Fase 2.** Con un Cycle activo —que es como
se reportó y como se verificará— girar Division ya cambia la velocidad de la
línea. Las fases siguientes amplían el mismo mecanismo a los demás caminos; si
alguna no llegara a existir, lo entregado sirve y nada queda a medias.

**El riesgo está en la Fase 3 y está localizado.** El avance de Cycle ocurre
*dentro* del bucle de Steps de una ventana ya calculada con la rejilla vieja, así
que reanclar ahí es lo único de este track que puede perder o duplicar una nota.
Va sola, después de que la Fase 2 haya dejado el mecanismo probado en el caso
fácil, y con FR7 como criterio duro.

**Sin medición de jitter** (NFR4), por la suspensión del 2026-09-02. Queda
anotado que este track es justo el caso que la regla anterior cubría: la Fase 7
incluye por eso una escucha larga en dispositivo, que es lo único que queda.

## FASE 1: LA REJILLA APRENDE UN ANCLA [checkpoint: 304eb6b]

- [x] Task: Tests de la rejilla anclada en `MusicalTimeline` — `d31cd99`
  - [x] Sin ancla, `nanosecondOffset(forStep:)` da exactamente lo de hoy: los
        tests actuales siguen pasando sin tocarlos.
  - [x] Anclada en el Step *n* con el instante que *n* tenía en la rejilla
        anterior, el offset de *n* es ese mismo instante (FR6).
  - [x] Del ancla en adelante, los Steps se separan según la Division nueva;
        1/16 → 1/8 dobla, 1/16 → 1/32 divide (criterio 1).
  - [x] Anclar dos y tres veces seguidas no acumula deriva: el offset coincide
        con el cálculo directo desde el último ancla (NFR3, criterio 4).
  - [x] Índices anteriores al ancla no se consultan nunca; queda escrito qué
        devuelven para que nadie lo dé por definido.
  - [x] Reanclar con la **misma** Division no mueve ningún offset.
- [x] Task: Implementar la rejilla anclada — `304eb6b`
  - [x] `MusicalTimeline` gana ancla —índice de Step e instante— y sigue
        multiplicando desde ella, nunca acumulando (NFR3).
  - [x] El inicializador de hoy sigue existiendo y significa «anclada en el Step
        0 al instante 0», que es la rejilla de siempre (FR11).
  - [x] `Sendable`, `Equatable` y sin asignaciones, como el tipo que ya era.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)
  - [x] Suite de `Engine` en verde y cobertura ≥90%. **933 tests, 0 fallos;
        cobertura 98,71% de líneas y `MusicalTime.swift` al 100%.**

## FASE 2: EL SCHEDULER REANCLA CUANDO GIRA EL KNOB [checkpoint: 194d185]

- [x] Task: Tests del reanclaje en `LookAheadScheduler` — `24cf886`
  - [x] Reanclar no mueve la marca de agua: el Step siguiente es el siguiente
        (FR5).
  - [x] Sobre ventanas sucesivas con un reanclaje en medio, **cada Step se emite
        exactamente una vez** y los rangos no retroceden (FR7, criterio 3).
  - [x] Ningún Step posterior al reanclaje cae antes del horizonte ya entregado
        (FR7).
- [x] Task: Implementar el reanclaje en `LookAheadScheduler` — `6c7ba17`
  - [x] Toma la Division nueva y ancla en el Step aún no entregado, con el
        instante que ese Step tenía en la rejilla anterior.
  - [x] Realtime: sin asignaciones, sin locks, sin await.
- [x] Task: Tests de `TrackScheduler` con la Division cambiando entre ventanas — `5211a77`
  - [x] Publicar un Track con otra Division cambia el espaciado de los Steps
        emitidos a partir de la ventana siguiente (FR1, FR2, criterio 1).
  - [x] No se reinicia nada: mismo índice de Step, `turnStartStep` quieto, cursor
        de Cycles quieto (FR5, criterio 2).
  - [x] Los eventos ya sellados en la ventana en curso no se reescriben (FR4).
  - [x] Reanclar con la misma Division no emite nada distinto — el caso de cada
        ventana, que es el que no puede costar nada.
- [x] Task: Implementar la detección en `refresh(with: Track)` — `171175d`
  - [x] `stepDurationNanoseconds` deja de ser `let` y pasa a salir de la rejilla
        vigente; una comparación de enteros por ventana decide si hay que
        reanclar (NFR1, NFR2).
  - [x] La vía del arnés —`PatternScheduler(timeline:material:)`— no reancla
        nunca: mide la rejilla, no el material (FR18).
- [x] Task: Tests de aislamiento entre Tracks — `194d185`
  - [x] Cambiar la Division del Track 1 no mueve ni un offset de los otros
        quince (criterio 6).
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)
  - [x] Suite de `MIDI` en verde y cobertura ≥80%. **912 tests; los 7 fallos son
        los cuatro `VirtualLoopbackTests` con `clientCreationFailed(-50)`, el
        flake conocido, idénticos a la base. Cobertura 91,79%;
        `TrackScheduler` 98,17% y `LookAheadScheduler` 97,67%. `Engine` 933
        tests en verde. `xcodebuild build` correcto.**
  - [x] **Verificación manual: el defecto reportado ya no ocurre** — con un Cycle
        activo, girar Division mientras suena cambia la velocidad de la línea.
        **Verificado en iPad el 2026-09-11, con un solo Cycle activo:** la línea
        cambia de velocidad al girar, no salta al principio del anillo y no se
        oye nota repetida ni perdida en el corte. El desfase del anillo es
        esperado hasta la Fase 5.

## FASE 3: EL AVANCE DE CYCLE TRAE SU PROPIA REJILLA [checkpoint: a620e3e]

- [x] Task: Tests del cambio de rejilla en el límite de vuelta — `2074f88`
  - [x] Un Track con Cycle 1 en 1/16 y Cycle 2 en 1/8 cambia de espaciado al
        entrar el Cycle 2, en el límite de vuelta (FR3, criterio 5).
  - [x] El primer Step de la vuelta nueva ya suena con la rejilla nueva, como ya
        suena con el material nuevo (FR5 de la rebanada de Cycles).
  - [x] Ni se pierde ni se repite ningún Step cuando el cambio cae **a mitad de
        ventana** (FR7) — el caso que hace falta escribir antes de tocar nada.
  - [x] Volver al Cycle 1 devuelve la rejilla, anclada al cierre de vuelta y no
        al origen de Play (FR6).
- [x] Task: Implementar el reanclaje en `advanceCycleIfTheTurnClosed` — `a620e3e`
  - [x] El rango de la ventana ya está calculado con la rejilla vieja: la
        decisión de cómo respetar FR7 —truncar la ventana y reentrar, o emitir el
        resto ya anclado— se toma aquí, con los tests delante, y se deja escrita
        en el código con su porqué. **Truncar y reentrar**, con
        `LookAheadScheduler.rebase(to:reopeningAt:)`: emitir el resto anclado
        adelanta Steps muy por delante del horizonte hacia más lento y los
        entrega tarde hacia más rápido.
  - [x] Realtime: sin asignaciones, y el coste solo cuando el Cycle entrante
        declara otra Division (NFR2).
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)
  - [x] Suite de `MIDI` en verde, cobertura ≥80%. **919 tests; los 7 fallos son
        los cuatro `VirtualLoopbackTests` con `clientCreationFailed(-50)`, el
        flake conocido. Cobertura 91,89%; `TrackScheduler` 98,36% y
        `LookAheadScheduler` 97,87%. `Engine` 933 tests en verde.
        `xcodebuild build` correcto.**
  - [x] **Verificado en iPad el 2026-09-11:** Cycle 1 en 1/16 y Cycle 2 en 1/8,
        y después en 1/32. La línea cambia de velocidad en el límite de vuelta
        y vuelve en la siguiente, sin golpes repetidos ni perdidos.

## FASE 4: LO QUE SE ARREGLA DE PASO [checkpoint: bdcd478]

- [x] Task: Tests de la ventana de repeticiones — `28948f2`
  - [x] El corte de las repeticiones y el hueco base se miden contra el mismo
        Step tras un cambio de Division (FR15, criterio 7).
  - [x] Una repetición que cabía no se descarta; una que no cabía no cae encima
        del Pulse siguiente.
  - **Verdes desde el primer intento sobre HEAD**, porque `171175d` ya
    recalcula `stepDurationNanoseconds` al reanclar. Sobre `5211a77`, anterior a
    ese arreglo, el test del hueco base falla (31,25 ms en vez de 62,5 ms): el
    test detecta el defecto.
- [x] Task: Implementar la coherencia de la ventana de repeticiones — `a39a9bb`
  - [x] `repeatWindowNanoseconds` y `gapNanoseconds(forStep:division:)` leen el
        mismo Step (`TrackScheduler.swift:538` y `:540`). **Sin código: ya
        convergían desde la Fase 2.** Queda escrito en `emitRepetitions`.
- [x] Task: Tests de gate y Sustain contra la rejilla nueva — `8c74436`
  - [x] Sustain 100% sobre la Division nueva: el note-off cae exactamente donde
        empieza el note-on siguiente (FR16, criterio 8).
  - [x] Sustain 200%: solapa como corresponde, sin quedarse en la Division vieja.
  - [x] 1/32 a 300 BPM, que es el extremo que `Division.ordered` documenta.
  - **Verdes sobre HEAD; sobre `5211a77` fallan 36 aserciones**, con el
    note-off un Step de 1/16 después del note-on siguiente: el defecto
    reportado.
- [x] Task: Implementar lo que haga falta para el gate — `097f607`
  - [x] Puede no hacer falta código: `Transport.swift:699` ya lee la Division
        viva y la rejilla pasa a coincidir con ella. Si los tests pasan tal cual,
        **la tarea es dejar escrito que convergen y por qué**, no inventar un
        cambio. **Sin código**; escrito junto a la expresión de `Transport`.
- [x] Task: Tests de no-regresión de Delay negativo — `af6bdb7`
  - [x] Tras un cambio de Division, ningún evento se pide para un instante ya
        pasado (FR17, criterio 9). **Rojo, con un defecto real**: con Delay
        negativo y una Division más lenta, el Step del corte se pedía tarde,
        hasta 110 ms con −100%. Pasaba por el knob y por el avance de Cycle.
  - [x] Con Delay ≥ 0 el presupuesto sigue siendo cero y nada cambia.
- [x] Task: Implementar el ancla que conserva el instante que suena — `bdcd478`
  *(Añadida el 2026-09-11: el usuario decidió arreglarlo aquí y no aceptarlo
  como limitación. Ver la enmienda de FR17 en `spec.md`.)*
  - [x] `MusicalTimeline.rebased(to:atStep:delayedBy:)`, con tests en `Engine`.
  - [x] Cuando un reanclaje hace crecer el presupuesto respecto al que decidió
        la ventana, el ancla se retrasa lo que crece.
  - [x] En el avance de Cycle, la reentrada mide con el presupuesto nuevo, y un
        Step del corte que ya no cabe espera a su ventana sin repetirse.
  - [x] `DelayBudgetDivisionTests` en verde.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)
  - [x] Suite de `MIDI` en verde, cobertura ≥80%. **931 tests; los 7 fallos son
        los cuatro `VirtualLoopbackTests` con `clientCreationFailed(-50)`, el
        flake conocido. Cobertura 92,01%; `TrackScheduler` 98,52%. `Engine`
        935 tests en verde. `xcodebuild build` correcto.**
  - [x] Verificación manual en iPad (repeticiones, Sustain y Delay negativo tras
        girar Division): **el usuario respondió «ok» el 2026-09-11**, sin
        detallar qué pasos ejecutó.

## FASE 5: EL ANILLO MIDE CON EL MISMO ANCLA [checkpoint: b35ef92]

- [x] Task: Tests de la publicación del ancla — `7fe0676`
  - [x] El hilo del scheduler publica el ancla vigente de cada Track y el hilo de
        dibujo la lee sin locks, con la forma de `CyclePlaybackClock` (FR10).
  - [x] Lo que cruza son enteros, no un snapshot (NFR5b).
  - [x] Un Track que no ha reanclado publica el ancla de Play (FR11).
- [x] Task: Implementar la publicación del ancla — `35f2ccd`
  - `CyclePlaybackClock` publica por Track la rejilla vigente y la anterior
    —la anterior cubre el look-ahead— como seis enteros bajo un seqlock. El
    scheduler escribe sin esperar y la interfaz reintenta. En `Engine`,
    `PlaybackGrid` y el init anclado de `MusicalTimeline`, ahora público.
- [x] Task: Tests de `Playhead` contra el ancla — `b913040`
  - [x] Un Track reanclado marca el Step que suena, no el que marcaría midiendo
        desde el origen de Play (FR9, criterio 10).
  - [x] Un Track que no reancló se dibuja exactamente como hoy: los tests
        actuales de `Playhead` siguen pasando sin tocarlos (FR11).
  - [x] *(Ampliación del 2026-09-11.)* `CyclePosition` deduce el Cycle en curso
        con la misma rejilla. La Fase 3 hizo falsa su premisa: la rejilla ya no
        sale del Cycle 1, que era la limitación 8 de `cycles_20260901`.
- [x] Task: Implementar `Playhead` con ancla — `8f17674`
  - [x] `Playhead.forEachTrack` deja de asumir la rejilla desde el origen de
        Play; el comentario que promete que ver y oír no discrepan pasa a ser
        cierto también después de girar el knob.
  - [x] `CyclePosition` recibe la misma rejilla; `Transport` se la pasa a los
        dos.
- [x] Task: Arreglar el salto del anillo con el ancla retrasada — `b35ef92`
  *(Añadida el 2026-09-11: la verificación en iPad encontró que, con Delay
  −100% y una Division más lenta, el playhead se desfasaba.)* Se diagnosticó
  con una simulación y eran dos efectos:
  - [x] **Un salto atrás, de este track.** `PlaybackGrid` cambiaba de rejilla
        en el ancla. Con el ancla retrasada, la rejilla anterior seguía
        contando más allá del corte: 9,2, 9,6 y vuelta a 9,0. Pasa a cambiar
        en el instante en que las dos rejillas marcan la misma posición, que
        sin Delay es el ancla.
  - [x] **Un desfase constante de un Step, de la rebanada 6** (su decisión 9:
        el playhead sigue la rejilla). El usuario decidió mantenerlo. Queda en
        *Known Limitations* del spec.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)
  - [x] Verificado en iPad el 2026-09-11. Los casos 1-3 dieron bien a la
        primera. El caso 4 —Delay −100% y una Division más lenta— encontró el
        salto del anillo, arreglado en `b35ef92`, y el usuario confirmó con
        «ok» al repetirlo.
  - [x] Suites de `Engine` y `MIDI` en verde, con sus umbrales. **`Engine` 943
        tests, cobertura 98,74%. `MIDI` 939 tests; los 7 fallos son los cuatro
        `VirtualLoopbackTests` con `clientCreationFailed(-50)`, el flake
        conocido. Cobertura 92,00%. `xcodebuild build` correcto.**

## FASE 6: TEMP Y CTRL ALL SOBRE DIVISION [checkpoint: eef5f63]

- [x] Task: Tests del overlay de Division, ida y vuelta — `64a8b31`
  - [x] Mantener Temp y girar Division cambia la velocidad mientras dura (FR12,
        criterio 11).
  - [x] Soltar devuelve la Division anterior, anclada al instante de la soltada y
        sin rebobinar la fase (FR14).
  - [x] Ninguno de los dos reanclajes pierde, duplica ni adelanta un Step (FR13).
  - [x] Con Cycles activos de Divisions distintas, el overlay iguala el valor
        absoluto y al soltar cada Cycle recupera **el suyo**, como ya promete
        `ParameterOverlay`.
  - **Verdes a la primera**: el overlay publica un `Pattern` normal y el
    reanclaje de las Fases 2 y 3 ya lo cubre.
- [x] Task: Tests de Ctrl All sobre Division — `f02e096`
  - [x] Dieciséis reanclajes en la misma ventana: ningún Track pierde ni duplica
        un Step (FR13, criterio 11). **Son doce**: `Pattern.trackCount` es 12
        desde `ui-declutter_20260902`.
- [x] Task: Implementar lo que falte — `eef5f63`
  - [x] Igual que el gate: el overlay ya publica un `Pattern` normal por el
        handoff de siempre, así que puede no hacer falta código. Si los tests
        pasan, la tarea es dejarlo escrito. **Sin código**; escrito en
        `ParameterOverlay`.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)
  - [x] Verificación en iPad (fill de Temp, Temp con dos Cycles, Ctrl All):
        **el usuario respondió «ok» el 2026-09-11.**
  - [x] **`Engine` 945 tests, cobertura 98,74%. `MIDI` 944 tests; los 7
        fallos son los cuatro `VirtualLoopbackTests` con
        `clientCreationFailed(-50)`, el flake conocido. Cobertura 92,00%.
        `xcodebuild build` correcto.**

## FASE 7: DISPOSITIVO Y CIERRE

- [ ] Task: Suite completa y cobertura
  - [ ] `Engine` ≥90%, `MIDI` ≥80%, todo en verde (criterio 13).
  - [ ] La vía del arnés sigue midiendo lo mismo (criterio 12).
- [ ] Task: Verificación en dispositivo
  - [ ] **Con una pista rítmica de one-shots y un solo Cycle activo**, que es
        como se reportó: girar Division mientras suena cambia la velocidad de la
        línea de forma audible e inmediata, sin cortes, sin duplicados y sin que
        el Track salte al principio (criterio 14).
  - [ ] El anillo sigue marcando lo que suena después de girar (criterio 10).
  - [ ] Un Temp de Division como fill, en directo (criterio 11).
  - [ ] **Escucha larga**: varios minutos con cambios de Division repetidos, para
        dar la cara donde no hay medición de jitter (NFR4).
  - [ ] Registrar lo observado en `device-verification.md`, como hizo
        `pattern-copy_20260910`.
- [ ] Task: Anotar lo que queda fuera
  - [ ] En el registry: el rediseño del origen adelantado de Delay
        (`advanceBudgetNanoseconds` y el desplazamiento de origen de
        `SchedulerThread`) frente a una rejilla que cambia en caliente.
  - [ ] En el registry: que el cursor de edición sigue pudiendo tapar el knob con
        varios Cycles activos, y que eso es de `cycle-edit-cursor_20260908`.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
