# Plan — Torax H-0 como maestro de MIDI clock

Sigue el `workflow.md`: tests en rojo antes de implementar, un commit por tarea,
git note por commit y checkpoint verificado al cerrar cada fase.

**De dentro afuera.** El generador de pulso es aritmética de enteros sobre un
índice, así que se prueba sin hilo, sin CoreMIDI y sin reloj. Va antes de que
nada lo use.

**La Fase 1 no toca código.** `product.md` promete hoy lo contrario de lo que
este track entrega —«La app no emite clock»— y `MIDIMessage.universalPacketWord`
lleva escrito «Nada del producto los emite». Las dos notas se escriben antes,
como manda el paso 8 del *Task Workflow*.

**El riesgo está en la Fase 4, y está localizado.** `start` y `stop` se sellan
desde el hilo de control mientras el hilo del scheduler sella ticks; un orden mal
elegido deja al esclavo corriendo después de Stop. Va sola, con el generador ya
probado.

**Sin medición de jitter** (NFR4), por la suspensión del 2026-09-02. Se sustituye
por la escucha larga de la Fase 6.

## FASE 1: LA DECISIÓN, ESCRITA ANTES DEL CÓDIGO [checkpoint: d8acc52]

- [x] Task: Nota fechada en `product.md` — la app pasa a ser maestro — `679cd45`
  - [x] Enmendar la nota del 2026-09-03: «La app no emite clock» deja de ser
        cierto. Decir qué entra —clock, Start y Stop— y qué no —Continue, Song
        Position y Program Change—.
  - [x] Dejar escrito que emite **también con `External`**, regenerando el pulso,
        y por qué: un solo generador para los dos modos.
- [x] Task: Nota fechada en `tech-stack.md` — el pulso sale por el look-ahead — `d8acc52`
  - [x] El clock de salida se sella hacia el futuro como las notas, con el mismo
        `TempoMap`. La alternativa —reenviar el tick entrante al vuelo— queda
        descartada por escrito, por la misma razón que ya se descartó para la
        entrada.
  - [x] Corregir la frase de `MIDIMessage`: los tres mensajes de System Real-Time
        pasan a emitirse.
- [x] Task: Phase Verification & Checkpoint (Refer to `workflow.md`)

## FASE 2: EL GENERADOR DE PULSO [checkpoint: 931e48e]

- [x] Task: Tests de `ClockPulseScheduler` (rojo) — `e046e4b`
  - [x] A 120 BPM los ticks caen cada 20 833 333 ns, y el índice *n* cae en `n ×`
        esa cantidad desde el origen (FR2).
  - [x] Avanzar dos horizontes consecutivos entrega cada tick **exactamente una
        vez**, sin hueco ni repetición en el borde (FR3).
  - [x] Un horizonte que no avanza no entrega nada.
  - [x] Un horizonte que salta varias negras entrega todos los ticks intermedios,
        en orden.
  - [x] Con el tempo cambiado a mitad, los ticks anteriores conservan su instante
        y los siguientes se separan según el tempo nuevo (FR10).
  - [x] El tipo es trivial y `Sendable`, sin asignaciones en el camino (NFR1).
  - [x] Añadido sobre el plan: 600 negras seguidas sin deriva, que es el fallo
        propio de este generador y no lo cubre ningún test de ventana.
- [x] Task: Implementar `ClockPulseScheduler` en `Packages/MIDI` — `931e48e`
  - [x] Marca de agua por índice de tick, igual que `LookAheadScheduler` con los
        Steps.
  - [x] Trabaja en tiempo de rejilla; la conversión a tiempo de reloj es de quien
        lo llama.
  - [x] `rebase(to: Tempo)` ancla en el tick aún no entregado, con el mismo
        criterio que `LookAheadScheduler.rebase(to:)`.
- [x] Task: Phase Verification & Checkpoint

## FASE 3: EL PULSO SALE POR EL HILO DEL SCHEDULER [checkpoint: b6ddffb]

- [x] Task: Tests de emisión de ticks desde `SchedulerThread` (rojo) — `df7155b`
  - [x] Con un recolector de prueba, el bucle entrega pulsos con timestamps
        crecientes y separación de negra/24 (FR1, FR3).
  - [x] Ningún pulso se sella antes del origen de rejilla (FR2, FR4).
  - [x] Con `ClockHandoff` publicando un maestro más lento, la separación de los
        ticks siguientes crece en la misma proporción que la de los Steps (FR7).
  - [x] La vía del arnés de medición no emite clock: **la condición resultó ser
        el handler, no el `Pattern`**. Sin `clockPulseHandler` no se genera un
        solo pulso, y el arnés no lo pasa; el test fija que los Steps siguen
        saliendo igual por esa vía.
  - [x] Enmienda sobre el plan: **no se escribe test del presupuesto de adelanto
        de Delay**. El pulso usa literalmente la misma expresión que el Step
        —`budgetNanoseconds + offset`, en la misma función— así que un test ahí
        mediría el desplazamiento que `DelayBudgetDivisionTests` ya cubre, no
        nada propio del clock. Lo que sí queda fijado es que ningún pulso se
        selle en el pasado.
- [x] Task: Emitir el pulso en el bucle de `SchedulerThread` — `b6ddffb`
  - [x] El generador se lee y avanza **una vez por ventana**, junto al snapshot y
        al `ClockHandoff`.
  - [x] El instante se convierte con `tempoMap.wallNanoseconds(forGridNanoseconds:)`,
        como los Steps.
  - [x] Sin asignaciones, sin locks y sin logging (NFR1).
- [x] Task: Phase Verification & Checkpoint

## FASE 4: START Y STOP [checkpoint: 84c6999]

- [x] Task: Tests de `start` y `stop` en `Transport` (rojo) — `55e9517`
  - [x] `play()` emite `start` sellado en el instante de arranque, y ningún tick
        lleva timestamp anterior (FR4).
  - [x] `stop()` emite `stop` con el mismo `silenceHostTime` que el barrido de
        apagado, así que no adelanta a ningún note-on ya programado (FR5).
  - [x] Parar lo ya parado no emite nada, con el mismo criterio que la guarda de
        `stop()`.
  - [x] Con el transporte parado no sale ni un tick (FR6).
  - [x] Con `External`, `start` sale cuando arranca el transporte de verdad
        —disparado por el maestro— y no al recibir el `start` entrante (FR8).
  - [x] FR9 no lleva test propio: el envío se inyecta como cierre, así que «sin
        destino» es el cierre que no hace nada, y eso es literalmente el `send`
        de todos estos tests. Cubrirlo aparte sería probar el inyector.
- [x] Task: Emitir `start` y `stop` en las puertas del transporte — `84c6999`
  - [x] Un solo sitio por mensaje: `startPlaying` y `stop()`, que ya son los
        caminos únicos.
  - [x] El orden queda escrito en el código: `start` antes de que el hilo
        arranque, `stop` junto al barrido.
  - [x] `stop` y el apagado comparten **un solo instante**: `silenceHostTime` se
        recalcula en cada lectura, así que leerlo dos veces los separaría.
  - [x] El `clockPulseHandler` queda cableado: el hilo sella el tick y el
        transporte solo lo envía.
- [x] Task: Phase Verification & Checkpoint

## FASE 5: EL PULSO SIGUE AL MAESTRO, Y AL TEMPO QUE CAMBIA [checkpoint: f9c3f85]

- [x] Task: Tests de tempo en vuelo — `f9c3f85`
  - [x] Cambiar el tempo interno con el transporte corriendo cambia la separación
        de los ticks siguientes sin reiniciar el índice ni saltar de fase (FR10).
  - [x] Cambiar de Bank con el transporte corriendo lleva el tempo del Bank al
        pulso.
  - [x] Con `External`, el tempo del maestro llega al pulso en vuelo (FR7) y las
        correcciones de fase que `ClockHandoff` acumula lo desplazan.
  - [x] Añadido sobre el plan: el pulso **nunca retrocede** al cambiar de tempo,
        que es el fallo que dejaría un tick repetido en el esclavo.
- [x] Task: Cerrar lo que los tests descubran — **sin cambios de producción**
  - [x] Los cinco casos pasaron contra el código de las fases 2–4: el mecanismo
        del tempo ya llegaba al pulso porque los dos usan el mismo `TempoMap`.
  - [x] **El único hallazgo fue del test, y queda escrito porque costó una vuelta
        de diagnóstico**: medía los intervalos con `dropFirst(before)`, y el
        salto de una corrección de fase vive en el hueco entre el último pulso
        sellado con el origen viejo y el primero con el nuevo — justo el que ese
        `dropFirst` se saltaba. Se discriminó publicando a la vez un tempo
        distinto: el espaciado sí cambiaba, así que el hilo leía el handoff y lo
        sospechoso era la medición. Corregido en el mismo commit.
- [x] Task: Phase Verification & Checkpoint

## FASE 6: COBERTURA, DISPOSITIVO Y CIERRE

- [x] Task: Cobertura de `MIDI` por encima del umbral — **92,25% de líneas**
  - [x] Medida en un proceso, fusionando el `.profdata` a mano y filtrando
        `Engine/Sources`, según `workflow.md`.
  - [x] Los ficheros del track: `ClockPulseScheduler.swift` 97,83%,
        `SchedulerThread.swift` 93,97%, `Transport.swift` 90,34%.
  - [x] El flake queda descartado por firma y no por número de pasadas: los
        fallos de la pasada en un proceso son **solo** los cuatro de
        `VirtualLoopbackTests`, que es la firma que `workflow.md` describe.
        Ningún test de clock falla ahí.
- [x] Task: Verificación en dispositivo (`device-verification.md`) — **los ocho bloques OK**
  - [x] Los ocho criterios de aceptación con el iPad, el BeatStep Pro y un
        esclavo en sync externo.
  - [x] **Escucha larga**, que es lo que sustituye al arnés (NFR4): varios
        minutos con el esclavo, sin separarse.
  - [x] Monitor MIDI para el criterio 4: con el transporte parado, cero mensajes.
  - [x] Queda anotado en el guion que **el usuario confirmó en bloque** —«todo
        ok»— así que no hay observaciones por bloque. Se escribe tal cual en vez
        de inventar detalle.
- [~] Task: Sincronizar documentación y abrir PR
  - [ ] `product.md`, `tracks.md` y el `index.md` del track con lo entregado y lo
        que queda fuera.
  - [ ] Cuerpo de PR corto: qué cambia, cómo se verificó, qué queda pendiente.
- [ ] Task: Phase Verification & Checkpoint
