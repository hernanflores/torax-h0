# Plan — Temp: parámetros temporales

Sigue el `workflow.md`: tests antes de implementación, un commit por tarea, git
note por commit y checkpoint verificado al cerrar cada fase.

**El orden va de dentro afuera.** Primero la nota de la desviación, porque el
Task Workflow §8 la exige antes de implementar y Temp no existe en la Pre Spec.
Después el overlay como valor puro en `Engine`, que es de quien todo lo demás
depende; luego el gesto en `ControlInput`, que lo acciona; y por último la
pantalla, que lo enseña. Al cerrar la Fase 3 el Temp ya funciona de verdad con el
controlador aunque la pantalla todavía no lo distinga.

**Ninguna fase mide jitter** (NFR5, suspendido el 2026-09-02), ni siquiera las
tareas que tocan Timing y Delay.

**Nada nuevo cruza al hilo del scheduler** (NFR2). Si una tarea empuja hacia
`LookAheadScheduler`, `MusicalTimeline` o `SchedulerThread`, es la señal de que
el overlay se está filtrando al camino de timing: parar y revisar el diseño antes
de seguir.

## FASE 1: LA DESVIACIÓN QUEDA ESCRITA

- [ ] Task: Anotar Temp en la Pre Spec y actualizar el preset (FR11, NFR6)
  - [ ] Nota fechada 2026-09-04 en `Pre Spec Torax H-0.md`: qué es Temp, que se
        mantiene [step 13] y que **no escribe en el Pattern**. La Pre Spec no lo
        tiene en absoluto.
  - [ ] Dejar dicho en la nota lo que un lector daría por supuesto al revés: el
        overlay **iguala** el parámetro girado en todos los Cycles activos, y
        cada uno recupera el suyo al soltar.
  - [ ] Fijar el vocabulario: «Temp», no «momentary», «override» ni «latch».
  - [ ] `preset/torax-h0.beatstep-pro.json`: declarar el step 13 como Temp y
        **corregir el knob 10 (CC 79)**, que sigue marcado libre desde
        `cycles_20260901`. Actualizar `preset/README.md` y subir
        `version`/`updated`.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 2: EL OVERLAY COMO VALOR DE DOMINIO

- [ ] Task: `ParameterOverlay` — qué se superpuso y qué había debajo (FR2, FR3, FR12, NFR3)
  - [ ] Tests (Red): superponer un parámetro guarda el valor base **de cada Cycle
        activo**; superponer el mismo dos veces no re-guarda la base; un
        parámetro no tocado no aparece en el snapshot.
  - [ ] Tests (Red): el tipo acepta cualquier caso de `TrackParameter` — barrido
        sobre `allCases`, sin enumerar los nueve.
  - [ ] Tests (Red): el snapshot vacío es el estado de reposo y restaurar desde
        él no cambia nada.
  - [ ] Implementación (Green): `ParameterOverlay` en `Packages/Engine`, valor
        puro con el juego base por (Cycle, parámetro).
  - [ ] Documentar **por qué guarda por Cycle y no un valor único**: el overlay
        iguala, así que la base es distinta en cada Cycle y un solo valor no
        podría devolverla.
  - [ ] `Engine` sigue sin importar nada más allá de la stdlib.
- [ ] Task: Aplicar y restaurar sobre el Track (FR2, FR3, FR4)
  - [ ] Tests (Red): aplicar un delta escribe el **mismo valor absoluto** en
        todos los Cycles activos, calculado desde el Cycle en edición; los Cycles
        inactivos no se tocan.
  - [ ] Tests (Red): girar dos veces acumula sobre el valor superpuesto, no sobre
        el base.
  - [ ] Tests (Red): restaurar devuelve **cada** Cycle a su valor propio; un
        parámetro no tocado conserva su valor distinto por Cycle antes, durante y
        después.
  - [ ] Tests (Red): restaurar **no toca** `cursor`, `editing`, `activeCount`,
        pool, marco tonal, canal ni `padOctaveShift` — aunque el cursor haya
        avanzado durante el hold.
  - [ ] Tests (Red): un delta que choca contra un extremo no cambia el Track y se
        puede detectar sin publicar.
  - [ ] Implementación (Green): apoyarse en `Cycle.applying(_:to:)` y en
        `Track.replacing(_:at:)`; no duplicar la aritmética de parámetros.
  - [ ] Cobertura `Engine` ≥90%.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 3: EL GESTO EN EL CONTROLADOR

- [ ] Task: [step 13] mantiene y suelta (FR1, FR7, FR9)
  - [ ] Tests (Red): CC 114 con 127 entra en Temp y **no publica por sí solo**;
        con 0 sale y publica una vez el snapshot restaurado.
  - [ ] Tests (Red): con Temp activo, girar Pulses publica un Pattern con el
        overlay; soltar publica el Pattern base. Girar sin Temp sigue escribiendo
        permanente.
  - [ ] Tests (Red): un giro nulo o contra un extremo no publica, con Temp activo
        igual que sin él.
  - [ ] Tests (Red): el comportamiento es idéntico con el transporte parado — el
        gesto no consulta el transporte.
  - [ ] Implementación (Green): `tempModifierIndex = ControlMapping.controlsPerFamily - 4`
        junto a `muteModifierIndex` y `soloModifierIndex`, despachado en
        `stepButton(_:value:)` antes de la selección.
  - [ ] Documentar por qué el índice vive en `ControlInput` y no en
        `ControlMapping`: la tabla describe el hardware, el consumidor acota el
        significado.
- [ ] Task: Con Temp hundido, Temp manda (FR6)
  - [ ] Tests (Red): con Temp activo, un step button 1–12 **no** cambia
        `selectedTrackIndex`; los modificadores 15 y 16 no publican `MixGesture`;
        el knob 10 no mueve el Cycle en edición; ningún pad toca el pool ni el
        registro.
  - [ ] Tests (Red): ninguno de esos mensajes ignorados publica ni devuelve
        `true` — se ignoran como un CC sin asignar, no como un error.
  - [ ] Tests (Red): al soltar Temp, los cuatro vuelven a responder.
  - [ ] Implementación (Green): un solo punto de corte en `receive(_:)`, no una
        comprobación repartida por cada rama.
- [ ] Task: Soltar sin soltada — reconexión y notas en vuelo (FR8, FR13)
  - [ ] Tests (Red): `releaseModifiers()` con Temp hundido restaura, publica y
        deja el estado en reposo.
  - [ ] Tests (Red): tras un hold completo, el Pattern es igual al de partida
        salvo lo que avanzó el cursor de reproducción (FR5).
  - [ ] Tests (Red): entrar y salir del overlay no emite ningún mensaje de
        apagado — el camino de emisión no gana un all-notes-off.
  - [ ] Implementación (Green): extender `releaseModifiers()`, documentando que
        ahora suelta tres modificadores y por qué la restauración va con ella.
  - [ ] Cobertura `MIDI` ≥80%.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 4: LA PANTALLA ENSEÑA LO QUE SUENA

- [ ] Task: Distintivo de Temp y valores superpuestos (FR10, NFR1)
  - [ ] Tests (Red) en `Engine`: el estado de lectura que la vista consume
        distingue «con overlay» de «sin overlay» y devuelve los valores
        superpuestos — la lógica va donde sí se mide (`FamilyReadout` y vecinos).
  - [ ] Implementación (Green): cableado en `App` —`ContentView`, `RingView`,
        `TrackSelectorView` según toque— reutilizando el valor grande transitorio
        de `mvp-ring-feedback`. Sin lógica nueva en la vista.
  - [ ] El anillo redistribuye con los valores superpuestos mientras dura el hold
        y vuelve solo al soltar, sin acción de nadie.
  - [ ] `swift format --in-place --recursive App Packages` y
        `xcodebuild build -scheme ToraxH0 -destination 'generic/platform=iOS'`.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
  - [ ] Verificación manual en iPad con BeatStep Pro: mantener [step 13], girar
        Pulses y Velocity, comprobar que el fill entra y que soltar lo deshace
        sin notas colgadas; repetir con dos Cycles activos y confirmar que cada
        uno recupera su valor.
  - [ ] Confirmar en el mismo pase que el step 13 es **momentary** (127/0) y no
        toggle. Si el hardware lo desmiente, parar: es el riesgo declarado en el
        spec y cambia el gesto, no la implementación.
