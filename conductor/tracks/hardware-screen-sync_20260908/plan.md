# Plan — La pantalla no ve lo que cambia el hardware

Sigue el `workflow.md`: tests antes de implementación, un commit por tarea, git
note por commit y checkpoint verificado al cerrar cada fase.

**La Fase 1 es un diagnóstico y puede cambiar el resto del plan.** Tres intentos
anteriores fallaron por empezar a escribir código antes de mirar los números en
el dispositivo. Aquí se mira primero, y lo que se mire se escribe en la git note
aunque confirme lo que ya se creía.

**Después, de dentro afuera y de lo caro a lo barato.** La palabra atómica en
`Transport` es la mitad delicada —toca el hilo de recepción de CoreMIDI— y va
sola en su fase, con sus tests y su comprobación de coste. El cableado en `App`
viene después y es una línea en un `.task` que ya existe.

**Cada fase deja el producto mejor que como lo encontró.** Al cerrar la Fase 2 el
transporte publica su estado aunque nadie lo lea todavía, y eso ya elimina la
necesidad de preguntar por `scheduler`; si la 3 no llegara a existir, no se ha
roto nada.

**Sin medición de jitter** (NFR5): no mueve ningún instante. Lo que sí se
comprueba es el coste por tick, contando eventos y no cronometrando.

> **Enmienda del 2026-09-09, al empezar la Fase 1 — el segundo síntoma ya está
> resuelto y el plan encoge.** El usuario lo comprobó en dispositivo: el tempo
> del maestro sí llega a la barra. La causa está en `spec.md`, en la enmienda de
> la misma fecha — los `TimelineView` a 0,25 s de `AppChrome` y `MidiScreen`
> repreguntan por su cuenta y no necesitan que nadie invalide.
>
> **Queda un solo síntoma**: el botón de transporte, que está fuera de esos
> `TimelineView` y además lee una copia (`TransportModel.isPlaying`) en vez de
> preguntar al transporte.
>
> **Qué se cae del plan:** el trabajo de tempo de la Fase 1 (FR4 ya no se
> decide, se verifica), y la segunda tarea entera de la Fase 3. Lo tachado se
> deja escrito con su porqué, que es como este proyecto registra las
> desviaciones.
>
> **Qué no se cae:** la Fase 2 entera. El contador y el flag siguen siendo el
> arreglo, y siguen siendo la única forma de responder `isPlaying` sin agravar
> la carrera sobre `scheduler`.

## FASE 1: DIAGNÓSTICO EN DISPOSITIVO — **requiere iPad y BeatStep Pro**

- [x] Task: Reproducir los dos síntomas con el controlador delante `521e52b`
  - [x] Start desde el BeatStep con reloj externo: la secuencia suena y el botón
        sigue en *play*. Reproducido el 2026-09-09. Pulsarlo **no para**: llama a
        `play()`, que muere en el `guard !isPlaying` de `Transport.play()`.
  - [x] ~~Mover el tempo del maestro: la barra no lo sigue.~~ **Desmentido el
        2026-09-09**: la barra sí lo sigue. Ver la enmienda de arriba.
  - [x] Confirmar que **`Transport` sí se enteró**: confirmado con números, no
        solo por `ExternalStartTests`. En t=90 s el contador de transiciones sube
        a 2 y `transport.isPlaying` pasa a `false` mientras `model.isPlaying`
        sigue en `true`.

  > **Hallazgo del 2026-09-09 — el defecto es simétrico, y el spec contaba la
  > mitad.** La copia `TransportModel.isPlaying` no se entera de un Start **ni de
  > un Stop**: en t=90 s el maestro paró, el transporte se enteró y la copia se
  > quedó en `true`. Los dos sentidos, no uno.
  >
  > **Y hay un tercer síntoma que nadie había anotado: el anillo.** El playhead
  > se dibuja con `TimelineView(.animation(paused: !model.isPlaying))`
  > (`ContentView.swift:369`), colgado de la misma copia — así que con un Start
  > del maestro **el playhead no se mueve aunque la secuencia suene**. Lo arregla
  > el mismo cambio; queda escrito para poder verificarlo en la Fase 4.
- [x] Task: Instrumentar y **mirar los números**, no la pantalla (NFR6) `521e52b`
  - [x] Contar, en dispositivo con reloj externo: ticks recibidos y transiciones
        de transporte. Medido el 2026-09-09, en 220 s a 124 bpm.
  - [x] Es lo que decide FR5 con datos: **~11.000 invalidaciones** si se avisara
        por tick, **4** si se avisa por transición. Tres órdenes de magnitud.
  - [x] ~~Comprobar con qué frecuencia cambia el tempo redondeado a un
        decimal.~~ **Se cae el 2026-09-09**: FR4 no se implementa, así que no
        hay comparación cuya cadencia haya que dimensionar.
  - [x] Instrumentación **bajo `#if DEBUG`**, como `handoffLoadCount`. Se
        conserva hasta la Fase 4 —el criterio 6 exige contar otra vez con el
        arreglo puesto— y se quita en la tarea de cierre.

  > **Los números, para que no haya que releer la consola.** Tramo estable,
  > t=100 s → t=210 s: 5544 ticks en 110 s → **50,4 ticks/s**. Corregido por la
  > deriva del `Task.sleep(1 s)` —cada «segundo» del contador es algo más largo
  > que uno real— quedan ~49,6/s, que es exactamente 124 bpm × 24 PPQN / 60. **El
  > estimador de tempo dice la verdad**: la diferencia aparente no era del reloj
  > sino del cronómetro, y no hay nada que perseguir ahí.
  >
  > Transiciones en los 220 s: **4** — dos arranques y dos paradas del maestro.
- [x] Task: Confirmar o desmentir la carrera sobre `scheduler` `521e52b`
  - [x] Leído. La escriben `startPlaying(atHostTime:)` y `stop()`, a las que
        `receive` llama desde el hilo de recepción de CoreMIDI; la lee
        `Transport.isPlaying`, y por ahí el hilo principal al dibujar. **La
        carrera existe y es anterior a este track.**
  - [x] **Decidido: se quita la lectura.** El flag de FR2 puede responder
        `isPlaying`, así que `Transport.isPlaying` pasa a leer el atómico y el
        hilo principal deja de tocar `scheduler` por ese camino (NFR2). No se
        queda como límite conocido: desaparece.
  - [x] **No hace falta track propio.** Lo que queda después es la escritura de
        `scheduler` desde el hilo de recepción sin lector concurrente en el hilo
        principal. Se anota en el `spec.md` al cerrar, con su ruta, y no se
        arregla de paso — que es lo que este defecto enseñó.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 2: EL TRANSPORTE PUBLICA SU ESTADO

- [ ] Task: El contador y el flag de transporte (FR1, FR2, FR3, NFR1)
  - [ ] Tests (Red): el contador arranca en cero y **se mueve exactamente una vez
        por transición**.
  - [ ] Tests (Red): lo mueven las cuatro puertas —`play()`, `stop()`, `.start` y
        `.stop` entrantes— y ninguna otra (FR3).
  - [ ] Tests (Red): un Start sobre un transporte que ya suena reinicia **y**
        deja el contador consistente con lo que el flag dice.
  - [ ] Tests (Red): **2880 `.timingClock` no lo mueven** (FR5). Es el test que
        impide que alguien «arregle» el tempo avisando por tick.
  - [ ] Tests (Red): el flag y el contador se leen desde otro hilo sin romper
        nada — el mismo test de concurrencia que tiene `CyclePlaybackClock`.
  - [ ] Implementación (Green): `AtomicCounter` y `AtomicFlag` en `Transport`,
        escritos en las cuatro puertas. Marcador `/// Realtime:` en lo que toque
        el hilo de recepción.
  - [ ] Comprobar que el camino del tick **no gana ni una escritura** (FR5,
        NFR1).
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 3: LA APP LO LEE, EN EL `.task` QUE YA EXISTE

- [ ] Task: El modelo invalida cuando el hardware cambió algo (FR6, FR7)
  - [ ] Tests (Red): con el contador movido, el modelo incrementa
        `clockRevision`; sin moverse, no lo toca (FR7).
  - [ ] Tests (Red): el estado que la pantalla lee sale del flag y no de
        `scheduler` (NFR2).
  - [ ] Implementación (Green): la comparación vive en `MIDI`, donde hay tests;
        en `App` queda la llamada (NFR4).
  - [ ] **En el `.task` de 16 ms que ya existe**, junto a
        `applyPendingAdoption()`. Ni un `.task` nuevo, ni un temporizador colgado
        de una vista — es el error del tercer intento (FR6).
- [x] ~~Task: El tempo externo, por comparación y sin contador (FR4, FR9)~~
      **Cancelada el 2026-09-09.** El `TimelineView` de `AppChrome.swift:222` ya
      refresca el número cuatro veces por segundo leyendo `currentTempo`, que es
      atómico. Implementar la comparación añadiría una invalidación del modelo
      entero dos veces por segundo para algo que ya funciona con un repintado
      local de una etiqueta. FR4 y FR9 pasan a verificarse en la Fase 4.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 4: DISPOSITIVO Y CIERRE — **requiere iPad y BeatStep Pro**

- [ ] Task: Verificación en iPad con BeatStep Pro (NFR6)
  - [ ] **Los dos síntomas reportados, primero**: Start del BeatStep deja el
        botón en *stop* y pulsarlo **para** (FR8); el tempo del maestro llega a
        la barra (FR9).
  - [ ] Stop del BeatStep, corte de reloj y recuperación: `clockStatus` y la
        marca `EXT`/`INT` los siguen (FR10).
  - [ ] Play y Stop desde la app, con reloj interno y con externo: sin regresión.
  - [ ] **Contar otra vez, con el arreglo puesto** (criterio 6): en un minuto a
        120 bpm el contador se mueve tantas veces como transiciones hubo. El
        número va a la git note.
  - [ ] Comprobar que el hilo principal no se satura: es el fallo del tercer
        intento y se mira con instrumentación, no de oído.
  - [ ] Escribir `device-verification.md` con lo que se probó, los números y lo
        que falló.
- [ ] Task: Cobertura y suite completa
  - [ ] `MIDI` ≥80% medida en un proceso e ignorando `Engine/Sources`, como dice
        `workflow.md`.
- [ ] Task: Pull Request
  - [ ] Rama `fix/hardware-screen-sync`, PR contra `main`. Cuerpo corto, con los
        números del conteo.
- [ ] Task: Cerrar el defecto en el registro
  - [ ] Marcarlo en `tracks.md` con lo que se verificó en dispositivo.
  - [ ] Quitar de `TransportModel.followsExternalClock` la nota que declara este
        límite, o reescribirla con lo que quede.
  - [ ] Anotar en el `spec.md` lo que se haya corregido al implementar, con
        fecha.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
