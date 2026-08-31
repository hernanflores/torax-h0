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
| 6 | Groove temporal: Timing y Delay | cerrada |
| 7 | Preset del BeatStep Pro: knobs, pads y step buttons | **abierta** |
| 8 | MIDI Learn, con `network-session-source` dentro | por planificar |

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

**La 7 se parte en dos, el 2026-08-30.** Estaba definida como «preset del
BeatStep Pro y MIDI Learn» y son dos problemas que no comparten nada: el preset
decide *qué significa cada control físico* —dominio musical, y ahí están las
decisiones difíciles: qué nota da cada pad— y MIDI Learn decide *cómo se reasigna
a otro hardware* —infraestructura de entrada, que arrastra
`network-session-source`—. Juntas metían una investigación de CoreMIDI dentro de
una rebanada cuyo núcleo es la escala. La 7 entrega el preset; la 8, MIDI Learn.

**Cuándo se vuelve bloqueante un defecto.** `network-session-source` en la
**rebanada 8**, cuando MIDI Learn tenga que escuchar la fuente correcta. *(Era
la 7 hasta el 2026-08-30, cuando la 7 se partió en dos.)*

`midi-test-flake` **queda aplazado a después de la v2, por decisión del
2026-08-29.** Lo había marcado como bloqueante de la rebanada 6 y ya no lo es:
la v1 y la v2 se entregan con él dentro.

Lo que eso significa en la práctica, para no volver a discutirlo cada vez:
cuando la 6 necesite tests que arranquen el bucle del scheduler, se escriben y
se convive con el ruido. La firma es reconocible —las 4 pruebas de
`VirtualLoopbackTests` con `clientCreationFailed(-50)`, y ningún otro test— así
que un fallo así se descarta comparando 3–4 pasadas contra `main`, como ya dice
*Branching and Pull Requests* en `workflow.md`. La rebanada 5 lo vio 2 de 8
veces sin que afectara a nada.

---

- [~] **Track: MVP rebanada 7 — Preset del BeatStep Pro: knobs, pads y step buttons**
  *Link: [conductor/tracks/mvp-beatstep-mapping_20260830/index.md](./tracks/mvp-beatstep-mapping_20260830/index.md)*

  Abierto el 2026-08-30. Sustituye el mapeo provisional por un preset declarado y
  verificado en dispositivo. **Su núcleo es que un pad deja de ser una altura y
  pasa a ser un índice:** hoy los pads son un teclado cromático filtrado por
  Scale, y sobre dieciséis pads contiguos eso deja la mayoría muertos y acota el
  registro alcanzable a un octavo del rango MIDI. Pasan a ser grados de escala en
  dos octavas alineadas, con los pads 8 y 16 moviendo el registro sin tocar el
  pool.

  No toca el motor y **no lleva medición de jitter** — no mueve ningún instante.

---

La rebanada 6 cerró el 2026-08-30 y con ella el Track generativo completo del
MVP. Después de la 7 solo queda la 8 —MIDI Learn—, y **ahí se vuelve bloqueante
`network-session-source`**, tal como estaba previsto: MIDI Learn tiene que
escuchar la fuente correcta, y en iPad la sesión de red se autoselecciona. La 7
convive con el defecto: basta con elegir el BeatStep Pro a mano.

**La rebanada 6 cerró con deuda conocida**, y conviene tenerla delante antes de
abrir la 7: cuatro hallazgos de revisión sin arreglar en su fase *Review Fixes*,
uno de ellos que `Stop` podría dejar sonar notas con Delay positivo —analizado,
no reproducido en dispositivo, con la condición para provocarlo escrita—. Y la
medición desplazada no se ejecutó: la recta CUMPLE y el swing se juzgó al oído.

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

- [ ] **Track: Flake `clientCreationFailed(-50)` en MIDITests** — *aplazado a después de la v2 (2026-08-29)*
  *Link: [conductor/tracks/midi-test-flake_20260826/index.md](./tracks/midi-test-flake_20260826/index.md)*

  La investigación del 2026-08-27 invirtió la dependencia. El ciclo de vida del scheduler no se puede cerrar sin entender antes por qué retrasar el desmontaje inutiliza la creación de endpoints virtuales de CoreMIDI.

  **Aplazado a después de la v2 el 2026-08-29.** No bloquea a ninguna rebanada del MVP: se convive con el ruido en CI y se descarta comparando pasadas. Sigue bloqueando a `scheduler-lifecycle`, que también espera.

  Dato acumulado por si sirve al diagnóstico: en la rebanada 5 apareció en 2 de 8 pasadas y **siempre con la misma firma** —las 4 pruebas de `VirtualLoopbackTests`, ningún otro test—. El fallo está localizado en la creación de endpoints virtuales, no es difuso.

## Archivados

- [x] **Track: MVP rebanada 6 — Groove temporal: Timing y Delay** — swing y Delay suenan; jitter recto máx 0,151 ms · σ 0,009–0,013 ms. **Cerrado con deuda: fase *Review Fixes* abierta**
  *Link: [conductor/archive/mvp-groove-temporal_20260830/index.md](./archive/mvp-groove-temporal_20260830/index.md)*

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
