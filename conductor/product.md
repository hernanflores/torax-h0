# Product Definition — Torax H-0

## Vision

Torax H-0 es un **secuenciador MIDI algorítmico para iPad**, operado con un controlador de knobs y pads (BeatStep Pro como referencia). No genera audio: controla instrumentos externos por MIDI.

Su premisa: no se programa cada evento fijo, se definen **reglas** de ritmo, altura, dinámica, tiempo y variación que producen una secuencia reproducible pero viva.

## Problem

Los secuenciadores por piano-roll obligan a escribir cada nota; los generativos suelen ser cajas negras impredecibles. Torax H-0 busca el punto medio: material musical acotado (pool tonal, escala, pulsos euclidianos) sobre el que la variación es controlada y repetible — desarrollo estructurado (Cycles), no caos.

## Target User

Uso personal y músicos que trabajan con hardware MIDI externo, cómodos operando con las manos sobre knobs en lugar de con el ratón. El controlador es el instrumento; el iPad es el cerebro y la pantalla de estado.

## Core Model

```
Project (estado completo + ajustes)
└── 16 Banks (tempo propio)
    └── 16 Patterns por Bank
        └── hasta 16 Tracks polifónicos
            └── hasta 16 Cycles por Track
```

- **Project:** estado completo: 16 Banks, sus Patterns/Tracks y ajustes asociados. **Existe desde el 2026-09-07**, con los dieciséis Banks y sus 256 Patterns en disco.
- **Bank:** contenedor musical de alto nivel (canción, setup o sección de live). 16 Patterns y tempo propio.
- **Pattern:** sección musical que reproduce el estado de sus 16 Tracks en conjunto (groove principal, break, fill, variante). Disparable cuantizado, encadenable, seleccionable por MIDI Program Change.
- **Track:** una voz/carril musical y de control. Donde residen los parámetros generativos.
- **Cycle:** snapshot de parámetros de un Track. Permite que ese Track varíe en pasadas sucesivas del loop sin cambiar de Pattern.

> **Nota del 2026-09-02 — son doce Tracks por Pattern, no dieciséis.** El árbol
> de arriba escribe 16 porque lo escribe la Pre Spec; la app implementa **12**
> desde el track `ui-declutter_20260902`.
>
> **La razón es de lectura.** Los Tracks se dibujan como anillos concéntricos y
> el ancho de cada banda sale de repartir el radio entre `trackCount - 1`. Con
> dieciséis, cada banda queda en unos pocos puntos y el playhead deja de leerse a
> un metro — el requisito de `product-guidelines.md`, que es condición de uso y
> no preferencia estética. Con doce, la misma fórmula da bandas un tercio más
> anchas sin tocar el dibujo.
>
> **El modelo no cambia de forma**: doce es un límite puesto sobre una constante,
> no un concepto nuevo. Si el ancho deja de ser el problema, la constante vuelve
> a subir. La nota larga, con lo que pierden los step buttons 13–16 del
> controlador, está en la Pre Spec.

El motor por capas: **Shape** decide *cuándo* y con qué densidad ocurren eventos → **Tonal** define el pool de notas y su movimiento armónico → **Groove** convierte la secuencia en interpretación (dinámica, probabilidad, duración, desplazamiento) → **Cycles / LFO / Random** aportan desarrollo en el tiempo.

## Interaction Model

- **Controlador MIDI = entrada primaria.** Knobs para parámetros continuos; pads para el pool tonal. **Un pad es un grado de la escala, no una altura fija**: los catorce primeros dan dos octavas alineadas de la escala vigente y dos mueven el registro entero, así que qué suena depende de Scale y Root y no del número que envía el controlador. Detalle en la nota del 2026-08-31 de la Pre Spec.
- **Pantalla = feedback + edición secundaria.** Muestra estado (pasos activos, pool tonal, Cycle en curso) y expone lo que no cabe en knobs: Scale, guardado, mapeos.
- **El Note Repeater es una capa sobre el ritmo, no un ritmo.** Añade triggers
  extra detrás de cada Pulse y **no toca Steps, Pulses ni Rotate**: el reparto
  euclidiano es el mismo y el Pulse original sigue sonando en su instante. Con
  Repeats en 0 —el default— no hay repeticiones y nada cambia. Ver la nota del
  2026-09-07 en *MVP Scope*.
- **La modulación es una capa sobre la dinámica, no sobre el material.** Añade
  movimiento cíclico a la velocity a lo largo de la vuelta del anillo y **no toca
  Steps, Pulses, Rotate ni el pool**: no cambia qué notas suenan ni cuándo, sino
  con cuánta fuerza. Con `accent` en 0 —el default— nada cambia. Se edita en la
  quinta pantalla, `modulation`, con el dedo y no con knobs. Ver la nota del
  2026-09-08 en *MVP Scope*.

> **Nota del 2026-08-31 — Scale y Root son de cada Track, no de la app.** Esta
> página y `product-guidelines.md` los describían como configuración táctil sin
> decir de qué, y con un solo Track daba igual. Con dieciséis no: la Pre Spec
> pone los parámetros generativos en el Track —«una voz/carril musical y de
> control»— y eso incluye el marco tonal. **Dónde se editan no cambia**: siguen
> siendo táctiles, del lado de la pantalla; lo que cambia es a quién afectan, que
> es el Track seleccionado.
>
> Lo hace posible un bajo en menor bajo un arpegio en mayor, que con un marco
> global no se podía expresar. Entra con la rebanada 1 de la v2
> (`multi-track_20260831`).
> **Nota del 2026-09-02 — mute y solo por Track.** Un par **M / S** bajo cada
> pastilla de la fila de Tracks, y en el controlador con los step buttons 15 y 16
> mantenidos como modificador.
>
> **Es la primera capacidad de la app que no es del material.** Todo lo demás
> —Shape, Groove, Tonal, Cycles— vive en el Track y viaja con el Pattern; esto es
> **mezcla**: qué se escucha ahora mismo de ese material. Por eso no aparece en
> el Core Model de arriba, no entra en el snapshot que lee el scheduler y no se
> guardará con el Project salvo que la persistencia decida lo contrario.
>
> **Mute no para el Track: le quita la salida.** La rejilla avanza y los Cycles
> rotan, así que quitarlo lo devuelve **en fase** con el resto — es un mute de
> mixer, no un stop. El **solo es aditivo** —varios a la vez suenan todos— y el
> **mute manda sobre el solo**: un Track soleado y muteado calla.
>
> Track `mute-solo_20260902`.

> **Nota del 2026-09-04 — Temp: interpretar sin escribir.** Mantener el **step
> button 13** y girar un knob cambia lo que suena en el Track seleccionado **sin
> escribirlo en el Pattern**; al soltar, los valores anteriores vuelven solos. Es
> lo que permite un fill, un build o un breakdown sin gastar un Cycle ni un
> Pattern.
>
> **Es lo que le faltaba al instrumento para tocarse y no solo programarse.**
> Hasta aquí, girar un knob escribía siempre: la única forma de volver atrás era
> deshacer a mano lo que se acababa de tocar, y no hay deshacer.
>
> **A diferencia de mute y solo, sí es del material** —son los nueve parámetros
> del Track— pero **no se guarda**: existe mientras el dedo está encima. Por eso
> tampoco aparece en el Core Model.
>
> **El overlay iguala, no aplana.** El parámetro girado toma el mismo valor en
> todos los Cycles activos, para que el fill se oiga aunque el cursor cruce de
> Cycle a media vuelta; al soltar, cada uno recupera **el suyo**.
>
> **Con Temp hundido, Temp manda:** callan la selección de Track, los
> modificadores de mezcla, el knob del Cycle en edición y los pads. Un roce no
> puede deshacer el fill.
>
> Track `temp-parameters_20260904`.

> **Nota del 2026-09-05 — Ctrl All: un knob mueve los doce Tracks.** Mantener el
> **step button 14** y girar un knob desplaza ese parámetro en **los doce Tracks
> a la vez**, sin escribirlo en el Pattern; al soltar, todo vuelve solo.
>
> **Es la operación de mezcla que faltaba sobre el material.** Subir el Velocity
> del conjunto, abrir el Sustain de todo o desfasar el Pattern con Rotate pedía
> hasta ciento ocho vueltas de knob —nueve parámetros por doce Tracks—, y ninguna
> se podía deshacer.
>
> **Ctrl All desplaza; Temp iguala.** Es la diferencia entera entre los dos
> gestos, y se lee al revés con facilidad. Temp hace que un parámetro suene igual
> en todos los Cycles del Track seleccionado; Ctrl All mueve el Pattern entero
> **conservando** lo que lo hace un Pattern y no doce copias — el Track lento
> sigue siendo el lento.
>
> **Alcanza a los doce, muteados incluidos**, porque mute es mezcla y la rejilla
> del Track muteado sigue avanzando: dejarlo fuera lo devolvería desalineado al
> desmutearlo.
>
> **Con Ctrl All hundido, Ctrl All manda** — y a diferencia de Temp, callan
> también las vías táctiles que escriben: un cambio de Scale a media
> superposición reencuadra el pool y no se deshace al soltar. Con [13] y [14]
> hundidos a la vez gana Temp.
>
> **Tampoco se guarda:** existe mientras el dedo está encima, y por eso no
> aparece en el Core Model.
>
> Track `ctrl-all_20260905`.

- **Mapeo:** preset listo para BeatStep Pro + **MIDI Learn** para reasignar a otro hardware.

## MVP Scope — v1

**Dentro:**

- Un **Track generativo completo**:
  - Shape: Steps (1–16), Pulses euclidianos, Rotate, Division (1/1–1/32). **Entregado** (rebanadas 1–2; 1/32 en la 5).
  - Tonal: pool de hasta 8 pitches, Scale + Root. **Entregado** (rebanada 4).
  - Groove: Velocity, Sustain, Probability. **Entregado** (rebanada 5).
  - Groove: Timing (swing) y Delay. **Entregado** (rebanada 6).
- Transporte (play/stop) y reloj interno.
- Salida MIDI por CoreMIDI a dispositivo externo.
- Mapeo del controlador + MIDI Learn. **Se parte en dos rebanadas** (ver la nota
  de abajo): el preset del BeatStep Pro, **entregado** (rebanada 7); MIDI Learn,
  en la 8.
- Pantalla de estado del Track.

> **Nota del 2026-09-06 — la app tiene cuatro pantallas, no una.** La línea de
> arriba se escribió cuando la interfaz era el anillo y poco más. El rediseño del
> handoff de iPadOS (`screens-redesign_20260906`) entrega `track`, `scale`, `midi`
> y `banks` sobre un chrome compartido —barra de estado y navegación
> persistente—.
>
> **Tres son estado real y una es cáscara.** `banks` dibuja dieciséis huecos de
> banco y dieciséis de pattern de los que solo el primero existe: no hay modelo de
> `Bank` ni persistencia, así que mover la selección no cambia lo que suena. Se
> entrega igualmente porque enseñar la forma completa y decir qué está vacío es
> más honesto que una pestaña que no lleva a ninguna parte; deja de ser cáscara
> con la rebanada 4 de la v2, sin cambiar de forma.
>
> **Dejó de serlo el 2026-09-07**, y la promesa se cumplió al pie de la letra:
> los tres cards siguen donde estaban. Lo que cambia es que detrás hay dieciséis
> Banks de dieciséis Patterns que existen, se eligen y se guardan, más un cuarto
> estado de hueco —`queued`— con la cuenta atrás hasta el compás en que entra.
> **Las cuatro pantallas son estado real.**
>
> **Y la frontera del tacto queda dicha**, que es lo que el principio rector
> implicaba sin concretar: `track` se lee mientras suena y ahí **no se edita
> ningún parámetro generativo con el dedo**; `scale`, `midi` y `banks` se
> configuran antes de tocar y ahí el dedo opera. La regla está auditada en el
> código, no solo escrita: la pantalla `track` tiene exactamente cinco
> escrituras táctiles —seleccionar Track, mute, solo, cuál es el Cycle en
> edición y cuántos Cycles están activos— y ninguna toca Steps, Pulses, Rotate,
> Division ni Groove.
>
> **Enmienda del 2026-09-09 — la quinta escritura, y por qué no rompe la
> regla.** Eran cuatro hasta hoy. `cycle-edit-cursor_20260908` parte el toque
> sobre la celda de Cycle en dos: pulsar elige **cuál** se edita y mantener
> cambia **cuántos** se recorren. Elegir a quién apuntan los knobs no es editar
> con el dedo, igual que la pastilla de Track no lo era: lo que se escribe es un
> cursor, no material. Sin ella, el cursor solo se movía con el knob 13 y sin
> controlador todo giro caía en el Cycle 1.
>
> **Enmienda del 2026-09-07 — `banks` deja de ser cáscara, y la frontera se
> mueve un poco.** La rebanada 4 de la v2 le pone detrás lo que le faltaba: el
> modelo de `Bank`, los 256 Patterns y el disco. **La forma no cambia**, que es
> lo que esta nota prometió: los tres cards siguen donde están y lo que aparece
> es un cuarto estado —`queued`— con la cuenta atrás hasta el compás en que entra
> el Pattern.
>
> **Lo que sí cambia es la frase de arriba.** «`scale`, `midi` y `banks` se
> configuran antes de tocar» deja de ser exacta: elegir un Pattern es un gesto
> que se usa **tocando**, en mitad de la pasada, y por eso está cuantizado. La
> frontera real no era «antes o durante», era **qué se edita con el dedo**:
> `track` sigue sin editar un solo parámetro generativo al tacto, y las cuatro
> escrituras auditadas siguen siendo cuatro. Lo que `banks` añade no es edición
> de material: es elegir cuál suena.

> **Enmienda del 2026-09-08 — son cinco.** La rebanada 6 de la v2
> (`modulation_20260906`) añade `modulation`, y el chrome no cambia de forma: la
> navegación persistente reparte cinco donde repartía cuatro y nada más se toca.
>
> **Cae del lado táctil, y por el criterio de esta misma nota.** `accent` y
> `waveform` se editan con el dedo porque se configuran antes de tocar, como
> `scale` y `midi` — no hay knob que los mueva. **La regla auditada de `track`
> sigue intacta**: sus cuatro escrituras táctiles siguen siendo cuatro, y ninguna
> de las dos nuevas vive ahí.

> **Nota del 2026-09-03 — el reloj puede ser de otro.** La línea de arriba dice
> «transporte (play/stop) y **reloj interno**», y sigue siendo cierta: el reloj
> interno existe, y ahora además es **editable** —el tempo estaba clavado en 120
> BPM desde la rebanada 1— en lugar de una constante.
>
> Lo que se añade es que la app **puede seguir a un maestro externo**: el Start,
> el Stop y el clock a 24 ppqn del controlador. Encaja con el Interaction Model
> de arriba —el controlador es el instrumento— y hasta ahora el hardware y la app
> no podían compartir pulso.
>
> **Quién manda lo decide el usuario, no el cable**: un selector
> `Internal / External`. Con `Internal`, un Start entrante no interrumpe nada.
>
> ~~**La app no emite clock.** La sincronía va en un solo sentido: nada externo
> puede seguir a Torax H-0. Ser maestro es otra decisión y no está tomada.~~
>
> Track `external-clock_20260903`.

> **Nota del 2026-09-11 — la decisión está tomada: la app es maestro.** La línea
> tachada de arriba dejó abierta la otra mitad de la sincronía, y
> `midi-clock-master_20260911` la cierra. **Play y Stop arrastran a los aparatos
> conectados, y el tempo de Torax pasa a ser el tempo de la cadena.**
>
> **Entran tres mensajes y ninguno más:** el clock a 24 pulsos por negra, el
> Start y el Stop. Salen al mismo destino que las notas, el que ya se elige en la
> pantalla `midi`.
>
> **El pulso se genera, no se reenvía.** Sale del hilo del scheduler sellado
> hacia el futuro, con el mismo origen de rejilla y el mismo mapa de tempo que
> las notas, así que el tick cae donde cae la nota. Es la misma decisión que
> `tech-stack.md` tomó para la entrada, leída al revés.
>
> **Emite también siguiendo a un maestro externo, y eso es una retransmisión.**
> Con `External` la app no reenvía el tick que recibe: regenera el suyo desde el
> tempo que ya estima para sonar. Hay **un solo generador de pulso** para los dos
> modos, en vez de dos caminos que habría que mantener iguales. El coste está
> escrito: un cambio brusco de tempo del maestro tarda hasta una ventana de
> look-ahead más una negra en llegar a los esclavos.
>
> **No hay interruptor.** La app emite siempre que el transporte suena. A
> diferencia de seguir —donde quién manda lo decide el usuario con el selector
> `Internal / External`— emitir no puede interrumpir nada de lo que la app hace:
> lo peor que produce es un aparato que recibe un pulso que no esperaba.
>
> **Lo que se queda fuera.** **Continue** y **Song Position Pointer**, así que un
> esclavo siempre arranca desde cero — coherente con que la app arranque siempre
> en el paso 0. **Program Change** al cambiar de Pattern, que sigue en la línea de
> «Fuera de v1». Un **destino de clock propio**, separado del de las notas. Y
> **filtrar el aparato del que viene el clock**: si el destino elegido es la
> misma máquina que manda el pulso, recibe el suyo de vuelta.
>
> Track `midi-clock-master_20260911`.

> **Nota del 2026-08-31 — «Mapeo del controlador + MIDI Learn» es una línea y
> son dos rebanadas.** Escrito como una sola entrega, el alcance mezcla dos
> problemas que no comparten nada. El **preset** decide *qué significa cada
> control físico* —dominio musical: qué nota da cada pad, qué parámetro mueve
> cada knob— y **MIDI Learn** decide *cómo se reasigna a otro hardware*
> —infraestructura de entrada, que arrastra el defecto
> [`network-session-source`](./tracks/network-session-source_20260828/index.md) y
> con él una investigación de CoreMIDI—. Juntas metían esa investigación dentro
> de una rebanada cuyo núcleo es la escala.
>
> - **Rebanada 7** (`mvp-beatstep-mapping_20260830`): el preset del BeatStep Pro
>   —knobs, pads y step buttons—, versionado en el repositorio y verificado en
>   dispositivo.
> - **Rebanada 8**: MIDI Learn, con `network-session-source` dentro, donde el
>   defecto sí bloquea: MIDI Learn tiene que escuchar la fuente correcta y en
>   iPad la sesión de red se autoselecciona.
>
> **Las dos siguen dentro de la v1**; lo que cambia es que se entregan por
> separado. La 7 cerró el 2026-08-31: el preset vive en
> [`preset/`](../preset/README.md) —tabla de los cuarenta y ocho controles y el
> proyecto exportado desde MIDI Control Center—, verificado con el controlador en
> la mano. ~~Hasta que cierre la 8, esta página promete un MIDI Learn que la app
> todavía no hace.~~
>
> **La 8 cerró el 2026-09-09, y con ella la v1.** MIDI Learn se entrega en la
> pantalla `midi`: se elige un destino, se mueve un control y ese control queda
> asignado; el mapeo se guarda con la sesión y hay vuelta al preset de fábrica.
> Verificado en iPad con un segundo controlador —un OP-Z—, que es lo único que
> demuestra algo: con solo el BeatStep Pro, aprender es reaprender el preset.
> Track `midi-learn_20260908`.
>
> **Se llevó dentro el defecto de la sesión MIDI de red**, tal como estaba
> previsto: la red ya no se autoselecciona —ni de entrada ni de salida—, sigue
> elegible a mano, y la elección hecha a mano se recuerda.
>
> **La v1 cierra sin su medición final de jitter.** La suspensión del 2026-09-02
> manda sobre la excepción que la exigía; el coste y la vuelta atrás están
> escritos en `workflow.md`.

**Fuera de v1:**

- Acordes polifónicos simultáneos (Style *Poly*) — explícitamente fuera de scope en la Pre Spec.
- ~~Patterns, Banks; guardado/Autosave~~; **Backup Project**. *(Múltiples Tracks salieron de aquí el 2026-09-01: la v2 rebanada 1 entregó dieciséis, que el 2026-09-02 pasaron a **doce** por legibilidad de los anillos — ver la nota del Core Model. Patterns, Banks, Autosave y Save/Reload salen el 2026-09-07: los entrega la v2 rebanada 4 — ver la nota de abajo. **Backup Project se queda**: exportar e importar por la app Files es UI de documentos, no modelo.)*
- ~~Note Repeater (Repeats/Time/Ramp/Pace)~~; Harmony; Voicing/Style; Range/Phrase; ~~LFO~~ y Random Modulation. *(Cycles salió de aquí el 2026-09-02: la v2 rebanada 3 lo entrega — hasta dieciséis por Track, recorridos a cada vuelta del anillo. El Note Repeater sale el 2026-09-07: lo entrega la v2 rebanada 5 — ver la nota de abajo. **Del LFO sale la mitad el 2026-09-08**: la v2 rebanada 6 lo entrega sobre velocity, y solo sobre velocity; **Random Modulation se queda** — ver la nota de abajo.)*
- Ableton Link, MIDI Program Change, encadenado de Patterns.

> **Nota del 2026-09-07 — Patterns, Banks y guardado salen de «Fuera de v1».**
> Salen por la misma vía por la que salieron los múltiples Tracks y los Cycles:
> los entrega una rebanada de la v2, la 4 (`persistence_20260907`), y la lista de
> arriba deja de describir lo que la app hace.
>
> **Es el primer track del proyecto que escribe un fichero.** Aparecen los dos
> niveles que la Pre Spec pone encima del Pattern —**16 Banks de 16 Patterns**,
> cada Bank con su tempo— y el disco: **Autosave** para el trabajo en curso y
> **`Save Bank` / `Reload`** como punto de retorno intencional. Cerrar la app deja
> de perderlo todo.
>
> **Cambiar de Pattern con el transporte corriendo entra en el próximo compás.**
> No es un detalle de implementación: es lo que hace del Bank la «sección de
> live» que la Pre Spec promete, en vez de un fichero que solo se abre parando.
>
> **Lo que se queda fuera, y por qué.** *Backup Project* —exportar e importar por
> Files— es UI de documentos y no toca el modelo. *Program Change* y el
> *encadenado de Patterns* siguen en la línea de abajo. Y **no se dispara desde
> el controlador**: no quedan step buttons libres —1–12 seleccionan Track, 13 es
> Temp, 14 Ctrl All, 15 y 16 solo y mute— así que meter Patterns en el hardware
> exige un modificador nuevo, que es una decisión de mapeo y toca el preset
> cerrado en la rebanada 7. Tampoco entran nombres editables ni copiar Banks.

> **Nota del 2026-09-10 — copiar un Pattern son dos gestos, no uno.**
> `pattern-copy_20260910` arregla un botón que no hacía nada y, al hacerlo, añade
> una interacción de directo que la Pre Spec no nombraba: **corriendo, un acorde
> de dos dedos** —mantener el origen, tocar el destino— copia en el acto y sigue
> sonando lo que sonaba. Es el equivalente por Pattern de lo que `reload` hace
> por Banco: dejar una copia antes de experimentar encima.
>
> Parado, `copy` y `paste`, con un portapapeles que guarda el Pattern entero y
> **cruza Banks**. `paste` también funciona corriendo, porque el acorde no puede:
> los dos dedos caen en la misma rejilla.
>
> Sigue fuera: copiar Banks enteros, y deshacer un pegado — la vuelta atrás ya es
> el punto de retorno de `save`/`reload`.

> **Nota del 2026-09-07 — el Note Repeater sale de «Fuera de v1».** Sale por la
> misma vía por la que salieron los múltiples Tracks, los Cycles y la
> persistencia: lo entrega una rebanada de la v2, la 5
> (`note-repeater_20260906`), y la lista de arriba deja de describir lo que la
> app hace.
>
> **Es una capa sobre el ritmo, no un ritmo nuevo.** Cada Pulse pasa a generar
> hasta ocho triggers extra, y **Steps, Pulses y Rotate no cambian**: el reparto
> euclidiano es el mismo, el anillo dibuja lo mismo y el Pulse original sigue
> sonando en su instante. Las repeticiones son del Track y heredan lo suyo — su
> Velocity, su Sustain, su swing y su Delay. Cuatro knobs: **Repeats** (0–8),
> **Time** (1/8 … 1/128, rectos y tresillos), **Ramp** (curva de velocity, ±100)
> y **Pace** (curva de espaciado, ±100).
>
> **Con Repeats en 0 —el default— no cambia nada de lo entregado.** Instantes,
> velocities, gates y consumo de aleatoriedad son los de antes de la rebanada.
> Es el requisito que sostiene todo lo demás: un Pattern hecho antes suena igual
> después.
>
> **Probability pasa a decidir sobre todas las notas, y no es una regresión.**
> Hasta ahora tiraba una vez por Pulse; ahora tira también por cada repetición.
> Con Repeats en 0 los dos conjuntos son el mismo, así que ningún Pattern
> existente suena distinto — y con repeticiones, que la tirada fuera solo del
> Pulse dejaría el roll entero a todo o nada, que no es lo que Probability
> significa.
>
> **Lo que se queda fuera, y por qué.** Repeats por encima de 8 y el «infinito»
> del tope de la Pre Spec: el techo de coste en el hilo del scheduler se razona
> en vez de medirse, y ampliarlo después es cambiar una constante. Los modos
> **Choke y Tail**, con la limitación de solape escrita en la Pre Spec. Que cada
> repetición avance el pool tonal, el swing dentro de la tirada, y dibujar las
> repeticiones en el anillo.

> **Nota del 2026-09-08 — la mitad del LFO sale de «Fuera de v1».** Sale por la
> misma vía por la que salieron los múltiples Tracks, los Cycles, la persistencia
> y el Note Repeater: lo entrega una rebanada de la v2, la 6
> (`modulation_20260906`), y la lista de arriba deja de describir lo que la app
> hace.
>
> **Entra la mitad, y está dicho cuál.** De la línea «LFO y Random Modulation»
> entra el **LFO cíclico, y solo sobre velocity**. Dos parámetros por Cycle:
> **`waveform`** —`saw`, `triangle`, `sine`, `pulse`— y **`accent`**, bipolar
> −100…100. La forma no se llama *Groove* aunque la Pre Spec así la rotule,
> porque el motor ya gastó ese término en la familia de Velocity, Sustain,
> Probability, Timing y Delay; el porqué está en la nota del 2026-09-08 de la
> Pre Spec.
>
> **Con `accent` en 0 —el default— no cambia nada de lo entregado.** Instantes,
> velocities y consumo de aleatoriedad son los de antes de la rebanada. Es el
> mismo requisito que sostuvo el Note Repeater: un Pattern hecho antes suena
> igual después.
>
> **Un ciclo por vuelta del anillo del propio Track.** La fase sale del índice
> de Step dentro de la vuelta, así que no hay reloj de modulación ni estado que
> mantener: la sincronía es una consecuencia de cómo se calcula la fase. Cada
> Track modula a su velocidad, porque cada uno tiene sus Steps y su Division.
>
> **La app pasa a tener cinco pantallas.** `modulation` es la quinta, junto a
> `track`, `scale`, `midi` y `banks`, y cae **del lado táctil de la frontera**
> del 2026-09-06: se configura antes de tocar, como `scale` y `midi`. La regla
> auditada de la pantalla `track` no se toca — sigue sin editar un solo
> parámetro generativo con el dedo.
>
> **No se mide jitter, y es una decisión, no un olvido.** La modulación cambia
> el *cuánto* y no el *cuándo*: aritmética entera acotada en el camino de
> emisión, sin desplazar la rejilla. Es literalmente el caso que la nota del
> 2026-08-28 de `workflow.md` excluye, y además la medición está suspendida
> desde el 2026-09-02.
>
> **Lo que se queda fuera, y por qué.** **Random Modulation** entera, que es la
> otra mitad de la línea. El destino **Phrase/Range** del LFO, que modula pitch
> y no dinámica. La **longitud ajustable** del ciclo —la Pre Spec la promete y
> el brief pedía cuatro compases—: queda fija a una vuelta del anillo, porque es
> lo que hace que la sincronía no necesite estado. Modular **cualquier cosa que
> no sea velocity**. Y **el knob**: ni `waveform` ni `accent` entran en el
> preset del BeatStep Pro, así que Ctrl All, Temp y la lectura transitoria
> grande no los alcanzan — el coste está escrito en la Pre Spec y se paga el día
> que tengan knob.

## Success Criteria

**Criterio principal: timing MIDI estable en iPad.** Jitter bajo y consistente contra hardware real; swing (Timing) y Delay que se sientan musicales. Es el mayor riesgo técnico de la plataforma y lo que decide si el proyecto es viable — por eso v1 se reduce a un Track: validar el motor de punta a punta antes de escalar.

> **Estado (2026-08-26): validado.** Medido en iPad Air 4ª generación: σ ≈ 9 µs y máximo 0,149 ms, frente a un umbral de 0,5 ms / 2 ms. La arquitectura de look-ahead scheduling aguanta. Ver [`verdict.md`](./archive/timing-spike_20260826/verdict.md).
>
> **Actualización (2026-08-27): medido con carga.** Con el motor generativo y la interfaz corriendo: máximo 0,127 ms y σ 0,015 ms en el peor tempo. Sin degradación grosera. La σ sube de 8–9 µs a 12–15 µs respecto al spike —4–7 µs, inaudibles— y sube con el tempo. Ver [`measurement-200.txt`](./archive/mvp-shape-transport_20260827/measurement-200.txt).
>
> **Rebanada 6 (2026-08-30): medido con la rejilla desplazada dentro.** La
> primera medición desde la rebanada 3, con 1000 eventos por tempo: máximo
> **0,151 ms** y σ entre **0,009 y 0,013 ms**. La σ **bajó** respecto a la
> referencia de 0,020 ms, así que el intervalo sin medir de las rebanadas 4 y 5
> queda absuelto sin bisecar. El máximo sube porque la muestra es cinco veces
> mayor. Swing y Delay se juzgaron al oído, no con el arnés: ver la enmienda de
> la Fase 6 en el plan de `mvp-groove-temporal_20260830`.
>
> **Cierre (2026-08-28): medido con el anillo.** Era la carga visual que faltaba. Con el anillo circular y el playhead redibujándose: máximo **0,134 ms** y σ hasta **0,020 ms**, contra 0,127 ms y 0,015 ms sin él. El redibujado cuesta unos 5 µs de σ en el peor tempo —mismo orden que el salto anterior, e inaudible—, y la σ queda 25 veces por debajo del umbral de 0,5 ms. **La arquitectura de look-ahead aguanta también la carga de dibujo.** Ver la git note de `9189aec` (track `mvp-ring-feedback_20260828`).
>
> **v2 rebanada 1 (2026-09-01): medido con los dieciséis sonando.** Es la
> medición que la v1 existió para poder hacer. Con 200 eventos por tempo:
> máximo **0,598 ms** y σ hasta **0,083 ms**, contra los 0,151 ms y 0,013 ms de
> la referencia. **CUMPLE**, con el máximo 3,3 veces por debajo del umbral y la
> σ 6 veces. El exceso está **solo a 174 BPM**; a 60 y 120 BPM la medición es
> indistinguible de la referencia. Lo que absuelve al cambio es que **la media
> no se mueve** —entre +0,105 y +0,121 ms en los tres tempos, igual que en las
> cinco mediciones anteriores—: copiar dieciséis Tracks por ventana costaría
> tiempo de forma sistemática, y eso subiría la media y degradaría los tres
> tempos a la vez. Lo que se ensanchó es la cola en el tempo más rápido.
> **La arquitectura de look-ahead aguanta dieciséis voces sobre un hilo.** Ver
> [`device-verification.md`](./tracks/multi-track_20260831/device-verification.md),
> que deja anotado que los estadísticos de resumen no distinguen unos pocos
> outliers de un corrimiento de la distribución, y que hacerlo pide percentiles
> en el reporte del arnés.
>
> **v2 rebanada 2 (2026-09-02): medido con los dieciséis anillos
> repintándose.** La carga visual de la pantalla del handoff, con 1000 eventos
> por tempo: máximo **0,158 ms** y σ **0,013–0,014 ms**. CUMPLE con el máximo
> 12,6 veces por debajo del umbral y la σ 35 veces. **Dibujar dieciséis anillos
> sale más barato que dibujar uno**: la σ de la rebanada 3, con un solo anillo,
> era 0,020 ms. El dibujo va en el hilo principal y el scheduler en el suyo, y
> esta medición existía para comprobar esa separación en vez de suponerla.
>
> Dos cosas que conviene leer junto al número. **La medición es conservadora a
> propósito**: el arnés por sí solo no produce carga visual —no toca el
> transporte de la app, así que los anillos se quedan quietos y SwiftUI no
> repinta lo que no cambia—, de modo que se mide con el transporte corriendo a la
> vez, y eso pone dos schedulers en vuelo, más carga de la que el producto tiene
> nunca. Y **la cola de la rebanada 1 no se reprodujo**: sus 0,598 ms a 174 BPM
> aquí son 0,141 ms, con cinco veces más muestras y más carga. Ver
> [`device-verification.md`](./tracks/screen-handoff_20260901/device-verification.md).

> **Reloj externo (2026-09-04): medido, CUMPLE, y peor que la referencia.** El
> track `external-clock_20260903` retomó la medición como excepción acotada a la
> suspensión de abajo, porque es el primer cambio desde entonces que toca la
> rejilla temporal misma. Dos pasadas con reloj interno y 1000 eventos por tempo:
> máximo **0,525 ms** y σ hasta **0,030 ms**, contra un umbral de 2 ms y 0,5 ms.
>
> **Es una regresión respecto a la referencia** —0,158 ms y 0,013–0,014 ms— que
> **se reproduce**: 60 BPM queda limpio y los dos tempos rápidos no. La media no
> se mueve, que es lo que impide llamarlo un coste sistemático sin más. Se cerró
> con ella dentro por decisión del 2026-09-04, con el experimento que la habría
> zanjado —medir `main` el mismo día en el mismo iPad— propuesto y descartado.
>
> **La referencia vigente pasa a ser esta.** Detalle y sospechosos en
> [`device-verification.md`](./tracks/external-clock_20260903/device-verification.md).

> **Suspendido (2026-09-02).** A partir de aquí **no se hacen más mediciones de
> jitter**, por decisión tomada al cerrar la v2 rebanada 3 después de que la
> recogida del informe del dispositivo fallara. La serie de seis mediciones que
> hay arriba es la última evidencia de que la arquitectura de look-ahead cumple,
> y la de la rebanada 2 —máx 0,158 ms, σ 0,013–0,014 ms— es la referencia
> vigente.
>
> **Lo que eso significa para este criterio:** «timing MIDI estable en iPad»
> sigue siendo el criterio principal, pero deja de comprobarse con un número. Una
> regresión se descubrirá tocando. El arnés y su procedimiento se quedan en el
> repositorio, listos por si se retoma; el porqué y el coste están en
> `workflow.md`, en *Medición de jitter: suspendida*.

> **Persistencia (2026-09-07): el tercer cambio que roza el hilo del scheduler, y
> tampoco se mide.** La rebanada 4 de la v2 hace que **cambiar de Pattern con el
> transporte corriendo entre en el próximo compás**, y esa decisión la toma el
> hilo del scheduler en el límite. Es la tercera vez desde la suspensión que un
> cambio llega ahí —las otras dos son `note-repeater` y `modulation`, todavía sin
> empezar— y aquí **no se abre excepción**, a diferencia de
> `external-clock_20260903`.
>
> **La razón no es el cansancio de medir, es que la regla no aplica.** La nota
> del 2026-08-28 del *Task Workflow* dice que se mide cuando cambia el **cuándo**,
> no el **cuánto**: esta rebanada **no mueve ningún instante**. Cambia qué
> material se emite en un límite que ya existía, el snapshot no crece ni un byte
> y no hay trabajo nuevo por evento. Lo que se añade al hilo de tiempo real es
> una lectura atómica más por ventana y una comparación de enteros. Bajo la regla
> anterior a la suspensión tampoco habría exigido arnés.
>
> **Lo que sí se verifica, y tocando:** que el Pattern entre en el compás y no
> antes ni después —comprobado sobre el índice de Step, no de oído— y que ninguna
> nota quede colgada al cruzar el límite. Track `persistence_20260907`.

> **Note Repeater (2026-09-07): el segundo cambio desde la suspensión que sí
> toca la rejilla temporal, y no se mide.** La rebanada 5 de la v2
> (`note-repeater_20260906`) **crea instantes nuevos entre los Steps**, que es
> justo lo que la nota del 2026-08-28 del *Task Workflow* manda medir: cambia el
> **cuándo**, no solo el **cuánto**. El primero fue `external-clock_20260903`, que
> abrió una excepción acotada y midió. **Aquí no se abre excepción**: manda la
> suspensión.
>
> **Lo que se pierde queda escrito.** Con Repeats en 8 y doce Tracks son hasta
> 108 eventos por Step donde antes había 12, y sin arnés no hay número que diga
> cuánto se ensancha la cola. Es también por qué el tope se quedó en 8 y no en
> los 48 de la Pre Spec: sin medición, el techo de coste se **razona**, y un
> número que se pueda defender con la cabeza vale más que uno grande que nadie ha
> medido.
>
> **Lo que sí se verifica, y tocando:** un ratchet que se arrastra se oye. Se
> comprueba en dispositivo, con el BeatStep Pro, que las repeticiones caen
> parejas a Repeats 8 y Time 1/128, y que con Repeats en 0 el Pattern suena
> exactamente igual que antes de la rebanada.

Secundarios:

- Los knobs responden sin saltos de valor ni latencia perceptible.
- El comportamiento de los parámetros es fiel al modelo de la Pre Spec.

## Source

Basado en `Pre Spec Torax H-0.md` (documento de diseño original).
