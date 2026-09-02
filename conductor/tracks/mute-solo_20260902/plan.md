# Plan — Mute y Solo por Track

Sigue el `workflow.md`: tests antes de implementación, un commit por tarea, git
note por commit y checkpoint verificado al cerrar cada fase.

**El orden va de dentro afuera.** La nota de la desviación primero, porque el
Task Workflow §8 lo exige antes de implementar. Después la máscara, que es el
tipo del que todo lo demás depende; luego el gate, que la usa; luego el apagado,
que arregla lo que el gate deja colgando; y solo entonces las dos superficies
—controlador y pantalla— que la accionan. Cada fase deja algo comprobable: al
cerrar la 4 el mute ya funciona de verdad aunque todavía no haya botón para
pulsarlo.

**Ninguna fase mide jitter** (NFR6, suspendido el 2026-09-02).

**`Engine` no se toca en ninguna fase** (NFR2). Si una tarea empuja hacia
`Engine`, es la señal de que se está metiendo mezcla en el material: parar y
revisar el diseño antes de seguir.

## FASE 1: LA DESVIACIÓN QUEDA ESCRITA [checkpoint: e7f0571]

- [x] Task: Anotar mute/solo en la Pre Spec y el sitio del par en el handoff (FR11) [e7f0571]
  - [x] Nota fechada 2026-09-02 en `Pre Spec Torax H-0.md`: mute y solo por
        Track, qué son y —lo que importa— que **viven fuera del material**, por
        encima del Pattern. La Pre Spec no los tenía en absoluto.
  - [x] Nota fechada en `design_handoff/README.md`: el par M/S está en la
        pantalla Track y no en la `5 · Tracks`, que no existe; cuando exista,
        enseñará **este mismo** estado, no otro.
  - [x] Dejar dicho en las dos que el solo es **aditivo** y que el mute manda
        sobre él, que es la regla que un lector daría por supuesta al revés.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 2: LA MÁSCARA Y LA REGLA [checkpoint: a85b0c5]

- [x] Task: `MuteMask` — doce mutes y doce solos en una palabra (FR1) [2d30365]
  - [x] Tests (Red): alternar el mute del Track 0 y del 11 no toca a los demás;
        mute y solo del mismo Track son independientes; los bits por encima de
        `Pattern.trackCount` no se pueden encender; el valor inicial es todo a
        cero.
  - [x] Tests (Red): una sola lectura devuelve los dos juegos —el tipo no expone
        forma de leer el mute sin el solo—, que es lo que impide la mezcla de
        dos instantes.
  - [x] Implementación (Green): `MuteMask` en `Packages/MIDI`, un `UInt64`
        atómico con las primitivas de `Atomics.swift`; bits 0–11 mute, 16–27
        solo.
  - [x] Documentar en el tipo **por qué una palabra y no dos atómicos**: dos
        lecturas podrían caer a ambos lados de un cambio y dar un instante en el
        que todo calla o nada.
- [x] Task: La regla de audibilidad (FR2) [a85b0c5]
  - [x] Tests (Red): sin nada activo suenan los doce; con un mute suenan once;
        con un solo suena uno; con dos solos suenan dos; **soleado y muteado
        calla**; quitar el último solo devuelve los doce.
  - [x] Implementación (Green): la regla como función pura sobre el valor leído,
        en un solo sitio.
  - [x] Comprobar que no asigna: sin `Array`, sin colecciones intermedias — la
        va a llamar el hilo del scheduler.
  - [x] Cobertura `MIDI` ≥80%.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 3: EL GATE EN EL CAMINO DE EMISIÓN [checkpoint: 9becb80]

- [x] Task: El Track inaudible no emite, pero su rejilla avanza (FR3) [9becb80]
  - [x] Tests (Red): con el Track 1 muteado, un recorrido de varias vueltas no
        produce ningún mensaje suyo y sí los del resto.
  - [x] Tests (Red): **la prueba de la fase** — mutear, dejar pasar dos vueltas y
        desmutear devuelve al Track en la posición que le tocaba, no en la
        primera. Es FR3 y el criterio de aceptación 2, y es lo que distingue esto
        de parar el Track.
  - [x] Tests (Red): un solo en el Track 2 silencia a los otros once sin alterar
        sus rejillas.
  - [x] Implementación (Green): una lectura de la máscara por ventana en el hilo
        del scheduler y la comprobación por Track antes de llamar al
        `NoteEmitter`. El `PatternScheduler` no cambia.
  - [x] Verificar el camino de tiempo real: sin asignaciones, sin locks, sin
        `await` (NFR1).
  - [x] Cobertura `MIDI` ≥80%.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 4: APAGAR LO QUE YA SUENA

- [~] Task: Factorizar el barrido de silencio de `Transport.stop()` (FR4)
  - [ ] Tests (Red): el barrido acotado a un Track manda `CC 123` por su canal y
        los note-off de las alturas de sus dieciséis Cycles, y **nada** por los
        canales de los demás.
  - [ ] Tests (Red): `stop()` sigue apagando los doce exactamente como hoy — la
        suite `StopWithEveryTrackTests` no cambia de expectativas.
  - [ ] Implementación (Green): extraer el doble barrido —`CC 123` primero,
        alturas después— a un método que reciba qué Tracks apagar; `stop()` pasa
        a ser el caso "los doce".
  - [ ] Conservar el sellado una ventana por delante y el orden de las dos
        pasadas, con su porqué ya escrito en `Transport`.
- [ ] Task: Volverse inaudible apaga (FR4)
  - [ ] Tests (Red): mutear un Track que suena dispara su barrido; **soltar** un
        solo que excluía a otros dispara el barrido de los que acaban de quedar
        fuera; desmutear no dispara nada.
  - [ ] Tests (Red): un Track que ya era inaudible y recibe otro gesto no vuelve
        a barrerse — el apagado va con la transición, no con el estado.
  - [ ] Implementación (Green): al cambiar la máscara, comparar audibilidad antes
        y después y barrer los que pasaron de audibles a inaudibles.
  - [ ] Verificar que ocurre **fuera** del hilo del scheduler (NFR1), como el de
        `stop()`.
  - [ ] Anotar en el código la limitación de canal compartido: el `CC 123` es por
        canal, así que dos Tracks en el mismo canal se apagan juntos y el otro
        vuelve en su siguiente pulso.
  - [ ] Cobertura `MIDI` ≥80%.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 5: EL GESTO DEL CONTROLADOR

- [ ] Task: Los step buttons 15 y 16 como modificadores (FR7, FR8)
  - [ ] Tests (Red): step 16 mantenido + step 3 alterna el mute del Track 3 y
        **no** cambia la selección; al soltar el 16, el step 3 vuelve a
        seleccionar.
  - [ ] Tests (Red): step 15 mantenido hace lo mismo con el solo; los dos
        mantenidos a la vez, manda mute.
  - [ ] Tests (Red): step 15 o 16 pulsados y soltados solos no cambian nada — ni
        selección, ni máscara.
  - [ ] Tests (Red): reconectar la entrada suelta los modificadores, aunque no
        haya llegado su soltada (FR8).
  - [ ] Implementación (Green): estado de "mantenido" en `ControlInput`, movido
        por el valor del CC —127 al pulsar, 0 al soltar—, **sin temporizador**;
        una salida nueva para los cambios de máscara, que no son del `Track`
        publicado.
  - [ ] `ControlMapping` no cambia: sigue describiendo las dieciséis del
        hardware. Quien acota es el consumidor, como en FR3 de `ui-declutter`.
  - [ ] `preset/` no cambia; comprobar que su README sigue siendo cierto y
        anotar ahí el gesto nuevo si lo describe.
  - [ ] Cobertura `MIDI` ≥80%.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 6: LA PANTALLA

- [ ] Task: Cablear el estado en `TransportModel` (FR9, FR10)
  - [ ] Los dos vectores de doce publicados para la vista, espejados al
        `MuteMask` en un solo sitio — el mismo criterio que ya rige para la
        selección de Track: táctil y controlador entran por la misma puerta.
  - [ ] El gesto del controlador de la fase 5 desemboca aquí, no en la vista.
  - [ ] `stop()` y el cambio de Track, Cycle o Pattern **no** lo tocan (FR10).
  - [ ] Si algo de esto pide un test, va a `MIDI` y no a `App` — la regla del
        `workflow.md`.
- [ ] Task: El par M/S debajo de cada pastilla (FR5)
  - [ ] Segunda fila en `TrackSelectorView`, dos botones por Track alineados con
        su pastilla, con `Brutalist` y `Typography`: sin estilo propio (NFR5).
  - [ ] Los tres estados legibles sin texto: `M` activo relleno, `S` activo
        relleno con su color, reposo con el borde apagado.
  - [ ] La pastilla del Track inaudible **por el solo de otro** se atenúa: sin
        eso, once Tracks apagados no tendrían marca.
  - [ ] Ajustar la altura del escenario en `ContentView`: la fila nueva entra en
        el cálculo que hoy sale de `selectorRowHeight`, para que los anillos no
        se recorten.
  - [ ] Área de pulsación utilizable con el dedo, sin invadir la pastilla.
- [ ] Task: El anillo del Track inaudible se atenúa (FR6)
  - [ ] Tests (Red): si la decisión de atenuar es un cálculo, vive donde se
        testea —`Engine` no, así que `MIDI` o una función pura de la vista— y no
        dentro del `body`.
  - [ ] Implementación (Green): trazo atenuado en `RingView`, **playhead
        intacto**: corre y no suena.
  - [ ] Comprobar que no se añade repintado por fotograma: la atenuación cambia
        con el gesto, no con el reloj.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 7: VERIFICACIÓN EN DISPOSITIVO Y CIERRE

- [ ] Task: Pasada completa en iPad con el BeatStep Pro
  - [ ] Los diez criterios de aceptación de la spec, uno a uno, con el sinte
        externo escuchando.
  - [ ] Atención especial al criterio 1 con **Sustain al 200% y una Division
        larga**: es el caso que motiva FR4, y sin él la nota colgaría segundos.
  - [ ] Atención especial al criterio 2: desmutear tiene que devolver el Track
        **en fase**, no desde el principio. Se oye, no se deduce.
  - [ ] Registrar en `device-verification.md` qué se probó y qué se oyó. **Sin
        medición de jitter** (NFR6).
- [ ] Task: Cierre del track
  - [ ] Repasar que las limitaciones conocidas de la spec siguen siendo las tres
        que dice, y añadir las que la implementación haya descubierto.
  - [ ] Actualizar `conductor/tracks.md` con el resultado.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
