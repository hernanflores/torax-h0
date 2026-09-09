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

## FASE 1: DIAGNÓSTICO EN DISPOSITIVO — **requiere iPad y BeatStep Pro**

- [ ] Task: Reproducir los dos síntomas con el controlador delante
  - [ ] Start desde el BeatStep con reloj externo: la secuencia suena y el botón
        sigue en *play*. Anotar qué enseña la barra en ese momento.
  - [ ] Mover el tempo del maestro: la barra no lo sigue. Anotar el valor que
        enseña y el que manda el maestro.
  - [ ] Confirmar que **`Transport` sí se enteró**: `ExternalStartTests` cubre la
        transición, así que el fallo está en el aviso y no en el transporte.
- [ ] Task: Instrumentar y **mirar los números**, no la pantalla (NFR6)
  - [ ] Contar, en un minuto de reloj externo a 120 bpm: ticks recibidos,
        transiciones de transporte y publicaciones de tempo. Los tres números
        van a la git note.
  - [ ] Es lo que decide FR4 y FR5 con datos: cuántas invalidaciones costaría
        avisar por tick, por negra y por transición.
  - [ ] Comprobar con qué frecuencia cambia el tempo **redondeado a un decimal**,
        que es lo que la app compararía (FR4).
  - [ ] Quitar la instrumentación antes de cerrar la fase, o dejarla bajo
        `#if DEBUG` como `handoffLoadCount`, que es el precedente.
- [ ] Task: Confirmar o desmentir la carrera sobre `scheduler`
  - [ ] Leer los dos sitios que la escriben desde el hilo de recepción
        —`startPlaying(atHostTime:)` y `stop()`— y el que la lee al dibujar.
  - [ ] Decidir si el flag de FR2 puede responder `isPlaying` y **quitar** la
        lectura, o si se queda como límite conocido con su ruta escrita (NFR2).
  - [ ] Si el diagnóstico dice que merece track propio, abrirlo aquí y no
        arreglarlo de paso — que es exactamente lo que este defecto enseñó.
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

- [ ] Task: El modelo invalida cuando el hardware cambió algo (FR6, FR7, FR10)
  - [ ] Tests (Red): con el contador movido, el modelo incrementa
        `clockRevision`; sin moverse, no lo toca (FR7).
  - [ ] Tests (Red): el estado que la pantalla lee sale del flag y no de
        `scheduler` (NFR2).
  - [ ] Implementación (Green): la comparación vive en `MIDI`, donde hay tests;
        en `App` queda la llamada (NFR4).
  - [ ] **En el `.task` de 16 ms que ya existe**, junto a
        `applyPendingAdoption()`. Ni un `.task` nuevo, ni un temporizador colgado
        de una vista — es el error del tercer intento (FR6).
- [ ] Task: El tempo externo, por comparación y sin contador (FR4, FR9)
  - [ ] Tests (Red): con el tempo escrito igual al anterior **no** se invalida;
        con uno distinto, sí.
  - [ ] Tests (Red): el valor comparado es el **redondeado a un decimal**, que es
        el que se ve.
  - [ ] Implementación (Green): la comparación en el mismo tick, sin trabajo
        nuevo en el hilo de recepción.
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
