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

- [x] **Track: MVP rebanada 7 — Preset del BeatStep Pro: knobs, pads y step buttons** — los 48 controles verificados en iPad, sin discrepancias
  *Link: [conductor/tracks/mvp-beatstep-mapping_20260830/index.md](./tracks/mvp-beatstep-mapping_20260830/index.md)*

  Abierto el 2026-08-30. Sustituye el mapeo provisional por un preset declarado y
  verificado en dispositivo. **Su núcleo es que un pad deja de ser una altura y
  pasa a ser un índice:** hoy los pads son un teclado cromático filtrado por
  Scale, y sobre dieciséis pads contiguos eso deja la mayoría muertos y acota el
  registro alcanzable a un octavo del rango MIDI. Pasan a ser grados de escala en
  dos octavas alineadas, con los pads 8 y 16 moviendo el registro sin tocar el
  pool.

  No toca el motor y **no lleva medición de jitter** — no mueve ningún instante.

  **Cerrado el 2026-08-31**, PR [#17](https://github.com/hernanflores/torax-h0/pull/17).
  Las cinco fases con checkpoint, `Engine` al 98,36% y `MIDI` al 92,52%, y el
  preset entregado como artefacto: `preset/Torax.beatsteppro` exportado desde
  MIDI Control Center, con su README y la tabla de los 48 controles. La
  verificación en dispositivo no encontró ninguna discrepancia, así que el número
  del bloque de pads —la única suposición del track— resultó correcto.

---

- [ ] **Track: MVP rebanada 8 — MIDI Learn, con `network-session-source` dentro**

  Por planificar. **Cierra la v1.** Entrega la reasignación del mapeo a otro
  hardware —`ControlMapping` es fija hasta entonces, y `product.md` promete MIDI
  Learn desde el principio— y se lleva dentro
  [`network-session-source`](./tracks/network-session-source_20260828/index.md),
  que **ahí sí bloquea**: MIDI Learn tiene que escuchar la fuente correcta y en
  iPad la sesión de red se autoselecciona.

  Lleva también la **medición final de jitter de la v1**, que la 7 no hizo por no
  mover ningún instante.

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

---

## v2

Abierta el 2026-08-31, con la v1 a falta de MIDI Learn. La estructura de la Pre
Spec sigue subiendo —16 Tracks por Pattern, 16 Patterns por Bank— y el primer
escalón es el que se nota.

---

- [x] **Track: v2 rebanada 1 — Dieciséis Tracks sobre un reloj** — los dieciséis suenan por su canal; jitter CUMPLE: máx 0,598 ms · σ 0,083 ms
  *Link: [conductor/tracks/multi-track_20260831/index.md](./tracks/multi-track_20260831/index.md)*

  Abierto el 2026-08-31. El snapshot deja de ser un `Track` y pasa a ser
  dieciséis, y un reloj pasa a emitir dieciséis rejillas. Todo lo generativo
  —Shape, Groove y Tonal completo— es de cada Track, más su canal MIDI; el reloj
  y el transporte se comparten.

  **Lleva medición de jitter con los dieciséis sonando**: es el riesgo que la v1
  existió para acotar, y una regresión bloquea la rebanada.

  No es la UI definitiva del handoff —esa es la rebanada siguiente, y es la vista
  de lo que ésta construye— ni Patterns ni Banks, que necesitan persistencia.

  **Cerrado el 2026-09-01.** Las seis fases con checkpoint, `Engine` al 99,42% y
  `MIDI` al 92,08%, y la verificación en dispositivo sin discrepancias: cada
  Track por su canal, dos Divisions en fase, dos tonalidades sin contaminarse y
  `Stop` con Delay positivo sin nada colgado.

  **La medición pasó, con una cola nueva anotada.** Máx 0,598 ms y σ 0,083 ms
  contra un umbral de 2 ms y 0,5 ms. El exceso está **solo a 174 BPM** —a 60 y
  120 BPM es indistinguible de la referencia— y **la media no se mueve**, que es
  lo que descarta un coste sistemático de copiar dieciséis Tracks por ventana.
  Es la primera cola que se ensancha en seis mediciones: **el sitio por donde
  mirar si la rebanada 2 o la 3 empeoran el número.** Distinguir unos pocos
  outliers de un corrimiento de la distribución pide percentiles en el reporte
  del arnés, que hoy solo persiste n, máximo, media y σ.

---

- [x] **Track: v2 rebanada 2 — La pantalla del handoff** — se lee a un metro; jitter máx 0,158 ms · σ 0,013–0,014 ms
  *Link: [conductor/tracks/screen-handoff_20260901/index.md](./tracks/screen-handoff_20260901/index.md)*

  Planificado el 2026-09-01. La pantalla definitiva de la rebanada 1: **dieciséis
  Tracks como anillos concéntricos**, el seleccionado en su acento, la lectura
  grande en el panel lateral y los tabs SHAPE/GROOVE/TONAL. Más Scale & Root
  reconstruida y la navegación de cinco pestañas, con tres deshabilitadas en
  borde discontinuo.

  **Cierra el lenguaje visual**, que `ShapeTheme` declara ilustrativo hasta que
  esto ocurra: Figtree, el sistema neo-brutalista en un solo sitio, y el acento
  de Groove pasando de ámbar a mauve.

  **No inventa modelo.** Sin mute/solo, sin nombres de Track, sin Banks ni
  Patterns — las tres pantallas que los necesitan quedan fuera.

  **Lleva medición de jitter**, y no por tocar el scheduler: dieciséis anillos
  redibujándose al ritmo del reloj son la «carga visual nueva» que `workflow.md`
  obliga a medir. Referencia: la rebanada 3 del MVP, con **un** anillo.

  Depende de que cierre la rebanada 1. **Desbloquea a la 3.**

  **Cerrado el 2026-09-02.** Las seis fases con checkpoint, `Engine` al 99,26% y
  `MIDI` al 91,59%, y la verificación en dispositivo completa. **Ninguno de los
  dos riesgos declarados se materializó**: el playhead se lee a un metro sobre
  dieciséis anillos —así que el anillo grande aparte que la spec guardaba de
  reserva no hizo falta— y el mauve se separa del violeta de Tonal de reojo y con
  poca luz, que era la pregunta que el ámbar dejó abierta.

  **La medición salió mejor que la referencia.** Máx 0,158 ms y σ 0,013–0,014 ms
  con 1000 eventos por tempo, contra los 0,020 ms de σ de la rebanada 3 —que
  medía **un** anillo—. Dibujar quince anillos más no cuesta timing.

  **Y la cola de la rebanada 1 no se reprodujo**: sus 0,598 ms a 174 BPM aquí son
  0,141 ms, con cinco veces más muestras y más carga. Apunta a un episodio
  puntual de aquella pasada y no a una propiedad de los dieciséis Tracks; no se
  afirma más, porque no se repitió aquella medición en sus condiciones.

  **Tres divergencias del handoff, decididas y escritas** en su README: el anillo
  se lleva la columna ancha —las proporciones del mock eran para cinco anillos—,
  los anillos son arcos y no puntos, y las notas fuera de la escala siguen
  pudiendo ser raíz. Y dos cosas que el handoff no decía: la app se bloquea en
  landscape y no lleva su propio nombre en pantalla.

---

- [x] **Track: v2 rebanada 3 — Cycles: el Track varía por vuelta** — el desarrollo A/B/C suena en dispositivo; **cerrada sin medición de jitter**
  *Link: [conductor/tracks/cycles_20260901/index.md](./tracks/cycles_20260901/index.md)*

  Planificado el 2026-09-01. Un Track deja de repetir un juego de parámetros
  idéntico: hasta dieciséis **Cycles** recorridos a cada vuelta del anillo, que
  es la A/B/C de la Pre Spec y la última de las cuatro capas del motor —Shape,
  Tonal, Groove y **Cycles**—.

  **El núcleo es que el nivel donde viven los parámetros baja uno.** Lo que hoy
  se llama `Track` es lo que la Pre Spec llama Cycle; el Track pasa a contenerlos.
  El avance ocurre en el hilo del scheduler, en el límite de vuelta, así que el
  snapshot pasa de 2304 bytes a unos 36 KB: **la Fase 1 lo mide y decide** antes
  de construir encima, y puede cambiar el diseño.

  **Llevaba medición de jitter obligatoria**, con los dieciséis sonando y
  avanzando. **Retirada el 2026-09-02** — ver el cierre.

  **Desbloqueado el 2026-09-02.** Sus dos dependencias están cerradas: la Fase 6
  de la rebanada 1 dejó la línea base, y la
  [rebanada 2](./tracks/screen-handoff_20260901/index.md) entregó la pantalla
  donde se mostrará el Cycle en curso. Es la rebanada siguiente.

  Lleva de la 2 una referencia de jitter recién medida —máx 0,158 ms, σ 0,013–0,014
  ms con los dieciséis anillos repintándose— y **el procedimiento para medir la
  carga visual, que no era obvio**: el arnés por sí solo deja la pantalla quieta,
  así que hay que medir con el transporte de la app corriendo. Está en el
  `device-verification.md` de la 2.

  **Cerrada el 2026-09-02**, PR [#27](https://github.com/hernanflores/torax-h0/pull/27).
  Seis fases, `Engine` al 99,14% y `MIDI` al 92,19%. El renombrado `Track` →
  `Cycle` tocó 54 ficheros sin cambiar una aserción; el nivel nuevo dejó el
  snapshot en 37 248 bytes.

  **La Fase 1 hizo su trabajo: el tamaño no era el problema.** Un `load()` cuesta
  ~870 ns, el 0,0044% de la ventana contra un presupuesto del 1%, así que FR5 no
  cambió y las dos alternativas de diseño quedaron descartadas por escrito antes
  de construir nada. Y dieciséis veces más bytes cuestan **siete** veces más
  tiempo, no dieciséis.

  **Cuatro fallos encontrados por los tests de la Fase 3** —la decisión de emitir
  tomada una vez por ventana, `restartCycles` mirando el cursor de edición,
  `Stop` barriendo solo el Cycle vigente— y **uno en dispositivo**: la pantalla
  enseñaba el Cycle que suena en vez del que se edita, que se leía como «el Track
  dejó de responder a los knobs».

  **Dos cosas acotadas por escrito.** La Division no cambia de Cycle a Cycle
  —resolverlo exigiría una línea de tiempo rebasable por Track, que rompe el
  invariante que mantiene en fase a los dieciséis—; y la pila del hilo del
  scheduler pasó a 1 MB, porque la de por defecto son 512 KB y el snapshot ya no
  cabía con holgura.

  **Cerrada sin medición de jitter, y es la primera.** La medición era obligatoria
  y bloqueante por su NFR4; se retiró el 2026-09-02 por decisión del usuario,
  después de que la recogida del informe del dispositivo fallara. Queda sin
  comprobar el trabajo que la Fase 3 añadió al hilo del scheduler. El porqué y el
  coste están en `workflow.md`, en *Medición de jitter: suspendida*.

---

- [ ] **Track: v2 rebanada 4 — Persistencia: Patterns y Banks**

  Por planificar. Es el escalón que la Pre Spec pone encima —dieciséis Patterns
  por Bank— y **el primero que necesita disco**: hasta ahora cerrar la app pierde
  todo, y con Cycles dentro eso son dieciséis veces más trabajo que se pierde.

  **No es una rebanada de motor.** Lo que cruza al hilo del scheduler sigue
  siendo un Pattern de 37 KB; lo que cambia es cuántos hay y de dónde salen. Por
  eso el detector de tamaño del snapshot no le aplica: guardar no es copiar en
  tiempo real.

  Arrastra las tres pantallas que la rebanada 2 dejó fuera —Banks, Patterns y la
  lista de Tracks— y la limitación 1 de Cycles, que era «sin persistencia».

---

- [x] **Track: Doce Tracks, pantalla MIDI y limpieza del selector** — doce anillos más anchos, el canal en su pantalla y la pastilla con un solo número; verificado en dispositivo
  *Link: [conductor/tracks/ui-declutter_20260902/index.md](./tracks/ui-declutter_20260902/index.md)*

  Planificado y cerrado el 2026-09-02, en cinco fases. Tres ajustes de superficie
  sobre la pantalla de las rebanadas 1–3, todos en la misma dirección: **menos
  ruido para que el protagonista —los anillos— tenga sitio**. El **canal** se va
  a la pantalla `3 · MIDI`, que aquí empieza a existir, y se edita para los doce a
  la vez; el **botón de Track** deja de decir dos veces el mismo número; y los
  Tracks pasan de dieciséis a **doce**, que es lo que ensancha los anillos.

  **Es una desviación de la Pre Spec** —«hasta 16 Tracks por Pattern»— y la Fase 1
  la escribe, fechada, antes de tocar código. La nota deja la decisión reversible:
  doce es un límite de legibilidad puesto sobre `Pattern.trackCount`, no un
  concepto nuevo. Con ella se sincronizaron `product.md` y, al cerrar,
  `product-guidelines.md`: el canal entra en la tabla del reparto táctil y la nota
  de legibilidad explica por qué doce.

  **Tres cosas salieron por el camino y no estaban en el plan.** `RingStack`
  calculaba el radio acumulando restas y el anillo interior invadía el hueco
  central por un bit —con dieciséis no se veía, con doce sí—; ahora interpola y el
  test exige igualdad exacta. `reservedBelowStage` era un literal que seguía
  reservando la fila de canal y una pastilla de 56 puntos, y el anillo pagaba 108
  puntos: salió de la verificación manual, que el usuario rechazó. Y la rejilla
  del arnés no era cosmética: `min(count, trackCount)` habría medido doce bajo una
  etiqueta que decía dieciséis.

  **Sin medición de jitter**, suspendida el 2026-09-02. La rejilla pasa a
  `12-tracks-cycles` para que el arnés siga listo si se retoma.

  **Deja sin tocar** MIDI Learn —rebanada 8 de la v1, y entra en esta misma
  pantalla— y el preset del BeatStep Pro: los step buttons 13–16 dejan de
  seleccionar, pero la acotación vive en quien selecciona y `ControlMapping` sigue
  describiendo los dieciséis del hardware.

  Integrado por [PR #28](https://github.com/hernanflores/torax-h0/pull/28).

---

- [x] **Track: Mute y Solo por Track** — M/S por Track suenan y se accionan con el dedo y con los step buttons 15/16; verificado en iPad
  *Link: [conductor/tracks/mute-solo_20260902/index.md](./tracks/mute-solo_20260902/index.md)*

  Planificado el 2026-09-02, en siete fases. El par **M / S** debajo de cada
  pastilla de Track, y el mismo gesto en el controlador: hoy, para oír la caja
  sola hay que vaciarle el pool a los demás — destruir material para conseguir un
  silencio temporal.

  **Mute no para el Track: le quita la salida.** La rejilla avanza y los Cycles
  rotan; al quitarlo, el Track vuelve **en fase**. **El estado vive por encima
  del Pattern** —es mezcla, no material— así que `Engine` no se toca: los doce
  mutes y los doce solos van en una sola palabra atómica, porque dos atómicos
  permitirían leer el mute de antes con el solo de después. El **solo es
  aditivo** y el mute manda sobre él.

  **En el controlador, sin temporizadores:** mantener el step button 16 y pulsar
  el N mutea el Track N; con el 15, lo solea. Los dos quedaron libres al bajar a
  doce Tracks, y el hardware ya envía la soltada.

  **El riesgo caro es la nota colgada:** con Sustain al 200% sobre una Division
  larga, mutear sin apagar dejaría el sinte sonando segundos. Se reutiliza el
  barrido de `Transport.stop()`, acotado al Track que se queda inaudible.

  **Sin medición de jitter**, suspendida el 2026-09-02: decide *si* se emite, no
  *cuándo*.

  **Cerrado el 2026-09-02**, en siete fases, con los diez criterios de
  aceptación verificados en iPad. `Engine` no se tocó en ninguna fase, que era
  el NFR2 y también la señal de diseño: si la mezcla hubiera empujado hacia el
  motor, es que se estaría metiendo en el material.

  **Dos cosas salieron por el camino y no estaban en el plan.** `Transport.mutes`
  nació pública en la Fase 3 y se cerró en la Fase 4: dejaba dos caminos para
  cambiar la mezcla y uno se saltaba el apagado, que es la nota colgada que FR4
  existe para evitar. Y la tabla de `preset/README.md` seguía diciendo
  «Seleccionar Track 2–16, sin Track detrás en v1», desactualizada desde la
  bajada a doce; ahora describe los modificadores.

  **Deja sin tocar** la persistencia —cuando llegue, decidirá si la mezcla se
  guarda con el Project—, la pantalla `5 · Tracks` con su vista de conjunto, y
  el mute de Patterns y Banks.

---

- [x] **Track: Sincronía de reloj externo — el BeatStep Pro manda el tempo** — el BeatStep manda tempo y transporte, verificado en iPad; jitter CUMPLE con regresión aceptada
  *Link: [conductor/tracks/external-clock_20260903/index.md](./tracks/external-clock_20260903/index.md)*

  Planificado el 2026-09-03, en seis fases. La app deja de tener un tempo propio
  y constante —hoy es un literal de 120 BPM en `TransportModel`— y pasa a seguir
  el **Start**, el **Stop** y el **reloj a 24 ppqn** del controlador.

  **El look-ahead se conserva, y esa es la decisión.** El jitter del proyecto es
  bueno porque los eventos se sellan hacia el futuro y no dependen de cuándo
  despierta el hilo; seguir a un maestro no cambia eso. El tempo se **estima**
  con los ticks y la **fase se re-ancla una vez por negra** — corregir tick a
  tick metería el jitter del cable en cada evento, que es la alternativa
  descartada por escrito.

  **Quién manda lo decide el usuario, no el cable:** un selector
  `Internal / External` en la pantalla `3 · MIDI`. Con `Internal`, un Start
  entrante no interrumpe nada. Con `External`, Play **arma** y el maestro
  dispara.

  **El corte de clock no para la música:** sigue al último tempo conocido y la
  pantalla lo dice. Eso obliga a que el tempo interno sea editable, así que se
  entrega aquí.

  **Retoma la medición de jitter**, suspendida el 2026-09-02, como excepción
  acotada: es el primer cambio desde entonces que toca la rejilla temporal misma
  y no la carga. Se mide con reloj interno, como regresión contra máx 0,158 ms y
  σ 0,013–0,014 ms. **El modo esclavizado queda sin número** —el arnés no sabe
  medir contra un maestro externo— y se juzga tocando.

  **Deja fuera** Continue y Song Position, la app como maestro de clock, y todo
  el feedback visual, que es el track de abajo.

  **Cerrado el 2026-09-04**, PR [#30](https://github.com/hernanflores/torax-h0/pull/30).
  Seis fases, `Engine` al 98,61% y `MIDI` al 92,05%. El núcleo acabó siendo
  `TempoMap`: el tempo estaba horneado en `TrackScheduler` igual que la Division
  —cambiar la duración del Step reubica los Steps futuros contra un origen que ya
  pasó— así que en vez de rehacer las doce rejillas se estira la línea de tiempo y
  se rebasa en cada cambio. Es legítimo porque el cambio llega a los doce a la
  vez, que es justo lo que impidió hacerlo para la Division en `cycles`.

  **Tres defectos los encontró el dispositivo, no los tests.** `Transport.receive`
  no tenía ningún llamador —la lógica estaba escrita y probada, y nadie la
  conectó al callback de CoreMIDI—; el transporte del maestro no mandaba sobre el
  de la app, que resultó no ser intuitivo con el hardware delante y cambió el FR4;
  y el endpoint del arnés se colaba en la lista de destinos porque el filtro y su
  test compartían el mismo nombre equivocado. Los dos primeros vivían en el
  cableado de `App`, que no tiene target de test.

  **Un test sí encontró uno**, y caro: al volver el clock tras un corte, la
  primera negra se medía a través del hueco —dos segundos dan 22,7 BPM, dentro del
  rango válido, así que el rechazo por rango no lo salvaba—.

  **Cerrado con regresión de jitter dentro, y es la primera vez.** Máx 0,525 ms y
  σ 0,030 ms contra una referencia de 0,158 y 0,013–0,014: CUMPLE el umbral con
  4,3× de margen y triplica la referencia, reproducido en dos pasadas —60 BPM
  limpio, 120 y 174 degradados—. Su NFR4 decía que una regresión bloquea el
  cierre; se cerró igualmente por decisión del 2026-09-04, con el experimento que
  lo habría zanjado —medir `main` el mismo día— propuesto y descartado. **La
  referencia vigente del proyecto pasa a ser este número.**

---

- [ ] **Track: Feedback visual en el controlador**
  *Link: [conductor/tracks/controller-feedback_20260904/index.md](./tracks/controller-feedback_20260904/index.md)*

  **Planificado el 2026-09-04, en siete fases.** Sale de la misma petición que la sincronía —2026-09-03— y se
  separa por el mismo criterio que partió la rebanada 7 del MVP en preset y MIDI
  Learn: **no comparten nada**. La sincronía toca la rejilla temporal y lleva
  medición; esto toca la salida y lleva descubrimiento de hardware.

  Lo decidido, para que planificarlo no vuelva a discutirlo:

  - **Los pads siguen a la nota** del Track **seleccionado** —con doce sonando,
    una luz de otro Track no se sabe de quién es—: se encienden con el note-on y
    se apagan con el note-off, así que Sustain se ve. Sin temporizador propio.
  - **Los step buttons** muestran selección y mute/solo, y **cómo se reparten se
    decide en dispositivo**: qué sabe hacer ese LED —brillo, parpadeo, color—
    está sin verificar, y la rebanada 7 enseñó a no dar por sabido el hardware.
  - **El destino se deriva de la fuente elegida**, sin lista nueva: hoy la salida
    va a un solo destino, el sinte, y hablarle al controlador es una segunda
    salida.
  - **Se apaga al parar el transporte**, y no en segundo plano ni al cambiar de
    fuente — decidido así a sabiendas de que el controlador puede quedar con
    luces huérfanas.
  - **Entrega también `preset/README.md` y el JSON**, que hoy describen solo la
    entrada.

  **No generaliza a otro hardware.** Eso es MIDI Learn, rebanada 8 de la v1.

  **La Fase 1 puede cancelar el track**, y va primero y sola: si el BeatStep no
  ilumina por MIDI in, no hay nada que entregar y se cierra ahí con el hallazgo
  escrito. Averiguarlo cuesta una pantalla desechable; descubrirlo después de
  construir el camino de salida cuesta el track entero.

  **Las luces se sellan junto a la nota**, en el hilo del scheduler y con su mismo
  timestamp: es la única forma de que la luz caiga con el sonido. Eso **duplica
  los mensajes por nota en el camino de tiempo real y no se mide** —la medición
  sigue suspendida—, justo detrás de una regresión sin causa identificada. Si el
  timing se degrada, esta es la primera carga que mirar, y no habrá número con el
  que compararla.

---

- [ ] **Track: En pantalla no se puede elegir qué Cycle se edita**

  Encontrado el 2026-09-03 verificando el reloj externo en iPad. **El cursor de
  edición se queda siempre en el Cycle 1**, así que todo giro de knob cae ahí y
  los otros quince parecen copias que no guardan nada — que es exactamente lo que
  son: nacen iguales y nunca reciben una edición.

  **La causa es un gesto que falta, no el modelo.** `Track` lleva sus dos
  cursores —el de reproducción y el de edición— y `replacingEditing(_:)` escribe
  en el que toca; lo que no existe es la forma táctil de mover el de edición.
  Pulsar un número en la fila de Cycles llama a `onActiveCyclesChange`
  (`App/TrackSelectorView.swift`), que cambia **cuántos** se recorren, no cuál se
  edita. La única vía es el knob 10 del BeatStep, CC 79.

  **El reparto de gestos está decidido** (2026-09-03): **pulsar elige** el Cycle
  en edición y **mantener pulsado cambia cuántos** están activos. El gesto
  frecuente es el simple y el raro pide mantener, que es el mismo criterio con el
  que los step buttons 15 y 16 hacen de modificadores de solo y mute.

  Es de `cycles_20260901`, no del track del reloj externo: se separa por el mismo
  criterio que partió la rebanada 7 del MVP.

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
