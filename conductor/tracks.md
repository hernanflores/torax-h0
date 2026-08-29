# Tracks Registry

## MVP — v1

La prioridad del proyecto. Sin app no hay nada que arreglar.

---

Lo que queda de v1, en cinco rebanadas. El orden no es de gusto: cada una paga
una deuda que la siguiente necesita.

| # | Rebanada | Estado |
|---|---|---|
| 3 | Anillo, playhead y valor transitorio | cerrada |
| 4 | Tonal: pool, Scale y Root | cerrada |
| 5 | Groove estático: Velocity, Sustain, Probability | cerrada |
| 6 | Groove temporal: Timing y Delay | **siguiente**, por planificar |
| 7 | Preset del BeatStep Pro y MIDI Learn | por planificar |

**Por qué ese orden.** La 3 no toca el motor y salda la última carga de jitter
sin medir que `product.md` dejó anotada —la visual—; además evita desarrollar
las tres rebanadas de motor contra una pantalla de texto. La 4 es la más cara
porque paga tres deudas de golpe: el camino de tiempo real emite una nota fija y
constante, el snapshot tiene que absorber el pool sin dejar de ser trivial, y el
pool de Pitch se edita con pads, que es entrada nueva y no una extensión del
mapeo de CC. *(Corregido el 2026-08-28: se decía que también pagaba el PRNG
sembrado. No lo hace — con recorrido secuencial del pool no hay aleatoriedad que
sembrar, y el PRNG se va entero a la rebanada 5, con Probability.)* La 5 y la 6 están separadas
por el riesgo, no por el tamaño: Velocity, Sustain y Probability cambian **qué**
se envía; Timing y Delay cambian **cuándo**, que es el camino de jitter que
costó validar, y aislarlas evita que una regresión ahí se lleve por delante al
resto. La 7 va última porque hasta entonces la tabla fija de cuatro CC alcanza.

**Cuándo se vuelve bloqueante un defecto.** `network-session-source` en la
rebanada 7, cuando MIDI Learn tenga que escuchar la fuente correcta.

`midi-test-flake` **ya lo es, desde el 2026-08-28**: cualquier test que arranque
el bucle del scheduler lleva `VirtualLoopbackTests` a fallar 3 de 3 pasadas,
contra 0 de 4 en `main`. La rebanada 3 lo esquiva dejando una línea sin test y
verificándola en dispositivo, pero la 6 —Timing y Delay— no va a poder: toca el
camino de tiempo real y necesita tests que lo corran. Se toma antes de esa.

---

*Sin track abierto.* La rebanada 5 cerró el 2026-08-29; la 6 —Groove temporal:
Timing y Delay— está en la cola de arriba, pendiente de planificar.

**Antes de la 6 hay que tomar `midi-test-flake`.** Deja de ser esquivable: la 6
toca el camino de tiempo real y necesita tests que arranquen el bucle del
scheduler. Esta rebanada lo evitó porque `TrackScheduler` se prueba dándole el
horizonte a mano, sin hilo; Timing y Delay no van a tener esa salida.

## Defectos conocidos

Con las rebanadas 1 y 2 del MVP cerradas, son lo único abierto. Dos de los tres
están encadenados: `midi-test-flake` bloquea a `scheduler-lifecycle`, no al
revés. `network-session-source` es independiente de esa cadena y se puede tomar
en cualquier momento.

---

- [ ] **Track: La sesión MIDI de red monopoliza la entrada**
  *Link: [conductor/tracks/network-session-source_20260828/index.md](./tracks/network-session-source_20260828/index.md)*

  Encontrado el 2026-08-28 verificando la rebanada 2 en iPad. iPadOS publica siempre `Red Session 1` como fuente, así que la lista nunca está vacía: la app la autoselecciona, el estado `No MIDI input` de `product-guidelines.md` es **inalcanzable en el dispositivo de destino**, y el controlador real no se elige solo al conectarlo. No bloquea a nadie ni depende de la cadena de CoreMIDI.

---

- [ ] **Track: Ciclo de vida del scheduler y desmontaje de CoreMIDI**
  *Link: [conductor/tracks/scheduler-lifecycle_20260826/index.md](./tracks/scheduler-lifecycle_20260826/index.md)*

  **Investigado el 2026-08-27; parado en su Fase 3.** La carrera es real y está resuelta en la rama `fix/scheduler-lifecycle`, que no se integra: cerrarla empeora la tasa de `clientCreationFailed(-50)` de 0 a 3 ocurrencias por pasada. La hipótesis sobre la que se construyó su plan —que un cierre explícito y ordenado de CoreMIDI estabilizaría el desmontaje— resultó falsa: el join y el desmontaje del arnés rompen la suite **por separado**. Lo que ambos tienen en común es retrasar el desmontaje, lo que apunta a diagnóstico de CoreMIDI: alcance de [`midi-test-flake_20260826`](./tracks/midi-test-flake_20260826/index.md), que pasa a ser el bloqueante.

  Datos completos en `plan.md` del track y en las git notes de la rama.

---

- [ ] **Track: Flake `clientCreationFailed(-50)` en MIDITests** — *ya no está bloqueado: es al revés*
  *Link: [conductor/tracks/midi-test-flake_20260826/index.md](./tracks/midi-test-flake_20260826/index.md)*

  La investigación del 2026-08-27 invirtió la dependencia. El ciclo de vida del scheduler no se puede cerrar sin entender antes por qué retrasar el desmontaje inutiliza la creación de endpoints virtuales de CoreMIDI.

## Archivados

- [x] **Track: MVP rebanada 5 — Groove estático: Velocity, Sustain, Probability** — los tres suenan; verificado en iPad con BeatStep Pro
  *Link: [conductor/archive/mvp-groove-static_20260829/index.md](./archive/mvp-groove-static_20260829/index.md)*

- [x] **Track: MVP rebanada 4 — Tonal: pool, Scale y Root** — el Track arpegia sobre el pool, dentro del marco tonal
  *Link: [conductor/archive/mvp-tonal_20260828/index.md](./archive/mvp-tonal_20260828/index.md)*

- [x] **Track: MVP rebanada 3 — Anillo, playhead y valor transitorio** — jitter con carga visual: máx 0,134 ms · σ 0,020 ms
  *Link: [conductor/archive/mvp-ring-feedback_20260828/index.md](./archive/mvp-ring-feedback_20260828/index.md)*

- [x] **Track: MVP rebanada 2 — Entrada de control** — verificada en iPad Air (4ª gen) con BeatStep Pro
  *Link: [conductor/archive/mvp-control-input_20260827/index.md](./archive/mvp-control-input_20260827/index.md)*

- [x] **Track: MVP rebanada 1 — Shape, transporte y primer sonido** — suena en hardware; jitter con carga máx 0,127 ms · σ 0,015 ms
  *Link: [conductor/archive/mvp-shape-transport_20260827/index.md](./archive/mvp-shape-transport_20260827/index.md)*

- [x] **Track: Timing Spike — validación del reloj MIDI** — arquitectura validada en iPad (máx 0,149 ms, σ 0,009 ms)
  *Link: [conductor/archive/timing-spike_20260826/index.md](./archive/timing-spike_20260826/index.md)*
