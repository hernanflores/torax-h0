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

## FASE 3: EL PULSO SALE POR EL HILO DEL SCHEDULER

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
- [~] Task: Emitir el pulso en el bucle de `SchedulerThread`
  - [ ] El generador se lee y avanza **una vez por ventana**, junto al snapshot y
        al `ClockHandoff`.
  - [ ] El instante se convierte con `tempoMap.wallNanoseconds(forGridNanoseconds:)`,
        como los Steps.
  - [ ] Sin asignaciones, sin locks y sin logging (NFR1).
- [ ] Task: Phase Verification & Checkpoint

## FASE 4: START Y STOP

- [ ] Task: Tests de `start` y `stop` en `Transport` (rojo)
  - [ ] `play()` emite `start` sellado en el origen de rejilla, y ningún tick
        lleva timestamp anterior (FR4).
  - [ ] `stop()` emite `stop` con el mismo `silenceHostTime` que el barrido de
        apagado, así que no adelanta a ningún note-on ya programado (FR5).
  - [ ] Parar lo ya parado no emite nada, con el mismo criterio que la guarda de
        `stop()`.
  - [ ] Con el transporte parado no sale ni un tick (FR6).
  - [ ] Con `External`, `start` sale cuando arranca el transporte de verdad
        —disparado por el maestro— y no al recibir el `start` entrante (FR8).
  - [ ] Sin destino seleccionado no se emite nada y nada falla (FR9).
- [ ] Task: Emitir `start` y `stop` en las puertas del transporte
  - [ ] Un solo sitio por mensaje: `startPlaying` y `stop()`, que ya son los
        caminos únicos.
  - [ ] El orden queda escrito en el código: `start` antes de que el hilo
        arranque, `stop` junto al barrido.
- [ ] Task: Phase Verification & Checkpoint

## FASE 5: EL PULSO SIGUE AL MAESTRO, Y AL TEMPO QUE CAMBIA

- [ ] Task: Tests de tempo en vuelo (rojo)
  - [ ] Cambiar el tempo interno con el transporte corriendo cambia la separación
        de los ticks siguientes sin reiniciar el índice ni saltar de fase (FR10).
  - [ ] Cambiar de Bank con el transporte corriendo lleva el tempo del Bank al
        pulso, en el compás y no antes.
  - [ ] Con `External`, las correcciones de fase que `ClockHandoff` acumula
        desplazan también los ticks: en una pasada larga simulada, el pulso
        emitido no se separa del recibido.
- [ ] Task: Cerrar lo que los tests descubran
  - [ ] Un commit por hallazgo, con su caso en rojo primero.
- [ ] Task: Phase Verification & Checkpoint

## FASE 6: COBERTURA, DISPOSITIVO Y CIERRE

- [ ] Task: Cobertura de `MIDI` por encima del umbral
  - [ ] Medir en un proceso, fusionando el `.profdata` a mano y filtrando
        `Engine/Sources`, según `workflow.md`.
  - [ ] Descartar el flake de `VirtualLoopbackTests` comparando 3–4 pasadas
        contra `main`.
- [ ] Task: Verificación en dispositivo (`device-verification.md`)
  - [ ] Los ocho criterios de aceptación con el iPad, el BeatStep Pro y un
        esclavo en sync externo.
  - [ ] **Escucha larga**, que es lo que sustituye al arnés (NFR4): varios
        minutos con el esclavo, comprobando que no se separa.
  - [ ] Monitor MIDI para el criterio 4: con el transporte parado, cero mensajes.
- [ ] Task: Sincronizar documentación y abrir PR
  - [ ] `product.md`, `tracks.md` y el `index.md` del track con lo entregado y lo
        que queda fuera.
  - [ ] Cuerpo de PR corto: qué cambia, cómo se verificó, qué queda pendiente.
- [ ] Task: Phase Verification & Checkpoint
