# Plan — v2 rebanada 2: La pantalla del handoff

Sigue el Task Workflow de [`workflow.md`](../../workflow.md): tests antes que
implementación, un commit por tarea con su git note, y checkpoint al cerrar cada
fase.

**El orden va del sistema a las vistas.** Primero el lenguaje visual en un sitio
—tokens, tipografía, el estilo neo-brutalista, el acento que falta—, luego los
anillos, luego lo que los rodea, y al final Scale & Root. Al revés, cada vista
inventaría su propio botón y el sistema llegaría tarde a limpiarlo, que es
exactamente lo que FR9 prohíbe.

**La lógica calculable baja a `Engine` antes de dibujarse.** `App` no se mide y
no debe merecer tests (`workflow.md`): qué radio tiene cada anillo, qué arco
ocupa cada Step y qué texto muestra el panel son funciones puras, y ahí es donde
se testean. Lo que queda en `App` es `Canvas` y composición.

**La referencia es el click-through, no las capturas.** `design_handoff/Torax
H-0 Click-through.dc.html` abierto en el navegador: las capturas de
`screenshots/` fijan la composición, pero las interacciones —qué cambia al tocar
un tab, cómo se ve un estado deshabilitado— solo se ven ahí. **No se porta el
HTML**: se reconstruye en SwiftUI, como el README del handoff exige.

**Lleva medición de jitter, y no por tocar el scheduler.** No lo toca. La lleva
porque dieciséis anillos redibujándose al ritmo del reloj son «carga visual nueva
que redibuja al ritmo del reloj», el caso que la nota del 2026-08-28 de
`workflow.md` nombra. Una regresión bloquea la rebanada.

---

## Phase 1: El lenguaje visual, en un sitio [checkpoint: d39dc0c]

> `Engine` para la clasificación, `App` para el sistema. Ninguna pantalla cambia
> todavía: al terminar esta fase la app se ve casi igual, con Groove en mauve y
> con Figtree. Es deliberado — el sistema tiene que existir antes que las vistas
> que lo usan.

- [x] Task: `ParameterFamily` gana Tonal — `847fa40`
  - [x] Tests (Red): las tres familias existen y `CaseIterable` las devuelve; ningún `TrackParameter` de knob cae en `.tonal` — Scale, Root y el pool son táctiles o de pads, no de knob
  - [x] Tests (Red): la clasificación de los nueve parámetros de knob no cambia
  - [x] Implementación (Green): el caso nuevo en `Engine`, y el `switch` de `Palette.accent(for:)` deja de ser exhaustivo con dos casos
  - [x] **Es una clasificación, no un parámetro** (FR4): existe para que el tercer tab tenga su acento por la misma vía que los otros dos y no por un condicional en la vista
- [x] Task: Los colores del handoff, y el ámbar que se va — `e52feb4`
  - [x] `Palette` toma los valores finales del handoff: fondos `#211823` / `#1a1420` / `#0e0a10`, bordes `#3a2c3d` y `#4a3d4d`, texto atenuado `#8a7d8d` y `#a99cab`
  - [x] **Groove pasa de ámbar `#D99A4E` a mauve `#AA6DA8`** (FR11), y Tonal se queda en `#7C5FD9`
  - [x] La documentación de `Palette` deja de decir que los colores son ilustrativos: **el lenguaje visual se cierra aquí**, y se dice de dónde salen
  - [x] La razón del ámbar —separarse por tono y no por luminosidad— **no se borra**: queda escrita como lo que hay que volver a comprobar a un metro en la Fase 6
- [x] Task: Figtree, empaquetada — `5ae0c15`
  - [x] La familia en el bundle y declarada en el `Info.plist`; licencia OFL incluida donde corresponda — **hizo falta un `Info-Release.plist` nuevo**: Release no tenía plist, así que las fuentes se habrían registrado solo en Debug
  - [x] Un solo sitio decide la tipografía: pesos 400/600/700 según el handoff, sin que ninguna vista pida una fuente por su cuenta — las 26 llamadas de las tres vistas pasan por `Typography`
  - [x] Verificado en simulador con captura: si la fuente no carga, iOS cae a la del sistema **en silencio**, y eso hay que verlo, no suponerlo — **y pasó**: `INFOPLIST_KEY_UIAppFonts` compila, mete las caras en el bundle y no las registra. Se vio inspeccionando el `Info.plist` construido. Captura en `simulator-phase1-figtree.png`
- [x] Task: El estilo neo-brutalista, como sistema — `d39dc0c`
  - [x] Trazos de 2px, radios de 3–8px, rellenos de acento planos, sombra dura `2px 2px 0` sin blur en lo seleccionado, borde discontinuo para lo no disponible, peso 700 en lo activo (FR9)
  - [x] Se expresa como estilos y modificadores reutilizables, no como parámetros repetidos en cada vista: **una vista que invente su propio botón es un fallo de esta rebanada** — `Brutalist.swift`, cuatro modificadores. Ningún `cornerRadius` ni `lineWidth` suelto queda en `App`
  - [x] Se aplica a lo que ya existe —botones de transporte, selector de Track, `TonalView`— para comprobar que el sistema cubre los casos reales antes de construir los nuevos — **y encontró tres cosas**: el transporte era una pastilla completa (`.borderedProminent`), el panel del anillo tenía radio 12 —fuera de la escala— y dos lecturas de `TonalView` usaban un tinte al 15%, que el handoff no admite

  > **Anotado para la Fase 6.** La sombra dura de 2px negro al 40% es casi
  > invisible sobre el fondo ciruela oscuro. Se implementa como el handoff la
  > especifica; si a un metro no aporta nada, es una decisión a tomar con la app
  > en la mano, no ahora.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 2: Dieciséis anillos concéntricos [checkpoint: 4506bad]

> El corazón de la rebanada. La geometría a `Engine`, el dibujo a `Canvas`.

- [x] Task: La geometría de los anillos, en `Engine` — `9c3863f`
  - [x] Tests (Red): con dieciséis Tracks, el anillo N tiene su radio y el orden es exterior→interior, Track 1 al 16 (FR1)
  - [x] Tests (Red): los radios no dependen del material — un Track vacío ocupa su sitio igual, o los demás se moverían (FR1)
  - [x] Tests (Red): cada anillo reparte sus **propios** Steps: 16/5 y 12/7 en dos anillos distintos dan dos repartos distintos y correctos
  - [x] Tests (Red): la geometría escala con el tamaño disponible sin solaparse ni dejar el centro invadido
  - [x] Implementación (Green): funciones puras. `App` no calcula nada (NFR5)

  > **Las proporciones no son las del handoff, y no pueden serlo.** El
  > click-through dibuja **cinco** anillos con un paso de 16px de radio;
  > dieciséis con ese paso pedirían un lienzo tres veces mayor del que la
  > pantalla reserva. Se conserva lo que el handoff decide —orden, paso
  > constante, hueco central— y se recalcula la escala.
- [x] Task: Los dieciséis, dibujados — `86bac46`
  - [x] Un solo `Canvas` para los dieciséis: sin una vista por posición (NFR4) — dieciséis Tracks de hasta 64 Steps son mil posiciones por fotograma
  - [x] El seleccionado en su acento; los quince restantes en gris tenue con el mismo patrón de arcos, como el handoff especifica
  - [x] Los que tienen material se distinguen de los vacíos sin leer texto
  - [x] Capturas en simulador de varios repartos —16/4, 16/5, 12/7— para comprobar que la simetría euclidiana se sigue viendo, que es lo que la guía pide del anillo — `simulator-phase2-distributions.png`, con 16/4, 16/5, 12/7 y 8/3 a la vez

  > **Arcos, no puntos — y la captura fue lo que lo dijo.** Se dibujó primero con
  > una marca por Step, heredando el anillo único de la v1. Los dieciséis Tracks
  > arrancan con los mismos 16 Steps, así que las marcas se alinean radialmente y
  > la pantalla se lee como dieciséis **radios**, no como dieciséis círculos. El
  > handoff ya lo decía —«a conic-gradient of colored arcs vs dark gaps»— y se
  > había leído como una técnica de CSS en vez de como la decisión de diseño que
  > es.
- [x] Task: El playhead sobre dieciséis anillos — `86bac46`
  - [x] Sigue derivando del reloj: se consulta al dibujar y se resuelve contra el origen del scheduler (NFR3). **Ningún temporizador inventa posición**
  - [x] Tests (Red) en `Engine` de lo calculable: dónde cae el playhead de cada Track sobre su anillo, con Divisions distintas — `Playhead.forEachTrack`, 6 tests
  - [x] **Legibilidad a un metro: se resuelve dibujando y se juzga en la Fase 6** (FR2). Si no se lee, la respuesta es un anillo grande aparte para el Track seleccionado — y eso es superficie que el diseño no reserva, así que se decide con la app en la mano y se anota

  > **La aguja desde el centro se cambió por un arco sobre la banda.** Con un
  > anillo la aguja estaba justificada —se ve por forma, que es lo que sobrevive
  > a la distancia—; con dieciséis cruza todos e informa de uno, y con Divisions
  > distintas serían dieciséis agujas a dieciséis velocidades sobre el mismo
  > centro.
  >
  > **Anotado para la Fase 6:** los doce anillos vacíos llenan el interior y el
  > conjunto pesa. Es consecuencia de FR1, no del dibujo.
- [x] Task: La app se bloquea en landscape — `4506bad`
  - [x] Solo `LandscapeLeft` y `LandscapeRight`, en Debug y en Release (FR13)
  - [x] El requisito queda escrito en `spec.md`, que no lo tenía: el supuesto estaba en las seis fases y en ningún requisito
  - [x] La verificación pasa a hacerse apaisada — durante esta fase se juzgó una composición en portrait que no era la que existe

- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 3: El panel de lectura y los tres tabs [checkpoint: 66aff5d]

> Lo que sustituye al valor grande sobre el anillo. Con esto los anillos dejan de
> taparse nunca, que es lo que `product-guidelines.md` pide y hoy se cumple a
> medias.

- [x] Task: La composición apaisada, en tres columnas — `c3a0728`
  - [x] **Los anillos a la izquierda en columna estrecha, el resto a su derecha** (FR14): panel de lectura en el centro, tabs de familia en la columna del borde, selector de Tracks debajo cruzando el ancho
  - [x] Sustituye a la columna vertical única de la rebanada 1, con el anillo arriba: era lo mínimo para operar, no la pantalla del producto
  - [x] **Es lo que hace posible que el valor grande no tape los anillos** (FR3): dos regiones que no se solapan, en vez de una encima de otra
  - [x] Captura apaisada en simulador contra `design_handoff/screenshots/01-track.png`, que es la referencia de proporciones — `simulator-phase3-columns.png`

  > Las anchuras son **fracciones** de las del mock —190 y 170 sobre 924— con
  > suelo y techo, no puntos fijos: el iPad más grande es medio ancho mayor que
  > el mock, y a puntos fijos el anillo encogería en relativo hasta perderse.
- [x] Task: Qué dice el panel en reposo — `82b3cce`
  - [x] Tests (Red) en `Engine`: el texto y el valor de cada familia salen de una función pura del Track — SHAPE da su reparto, GROOVE sus cinco parámetros, TONAL el marco y el pool (FR4)
  - [x] Tests (Red): con el pool vacío, TONAL lo dice; no se inventa material que no hay
  - [x] Implementación (Green): la vista solo compone

  > **Qué valor encabeza cada familia es una elección, y queda escrita.** Shape
  > lleva Pulses —lo que el propio mock pone—, Groove lleva Velocity —el único
  > de los cinco que se oye en cada nota sin depender de nada más— y Tonal lleva
  > el marco, donde no hay elección porque no tiene knobs detrás.
- [x] Task: El valor transitorio, en el panel — `83b5e1d`
  - [x] Al girar, el panel muestra el valor grande con el acento de la familia del parámetro movido, y se desvanece tras la inactividad como hoy (FR3)
  - [x] **Los anillos no se tapan en ningún momento** — es criterio de aceptación, y es lo que mejora respecto a hoy — **estructural desde FR14**: están en otra columna
  - [x] Girar un knob de una familia que no es la del tab activo: se decide y se escribe qué manda. Por defecto **el giro manda** y el tab sigue al parámetro movido, porque la pantalla es el espejo del controlador
  - [x] Tipografía muy grande, legible a un metro, como hoy — y **la lectura en reposo usa el mismo formato**, así que el panel no cambia de idioma según de dónde venga
- [x] Task: Los tres tabs — `83b5e1d`
  - [x] Verde, mauve y violeta, con el tratamiento del handoff: borde izquierdo acentuado, contorno y sombra dura en el activo
  - [x] Tocar un tab cambia lo que muestra el panel y su color; es navegación, no edición (FR4) — **el toque queda para la verificación manual**: `simctl` no lo simula, y las capturas se hicieron cambiando el estado inicial
  - [x] Sin controlador conectado los tabs siguen funcionando: mirar no es editar
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 4: La barra, el selector y la navegación [checkpoint: 4487682]

> Lo que rodea al anillo y hace que la app tenga forma de app.

- [x] Task: La barra superior — `35cd292`, ajustada en `4487682`
  - [x] Derecha: BPM y play/stop, con el tratamiento del handoff (FR6)
  - [x] Izquierda, en el sitio de `Bank 1 · Pattern A`: el estado MIDI —destino y fuente—, comunicado como estado y nunca como disculpa (`product-guidelines.md`)
  - [x] `No MIDI device` y `No MIDI input` siguen siendo los textos exactos de la guía

  > **No es una fila propia, sino la de las pestañas.** El handoff usa dos
  > renglones y esta pantalla tiene uno de más: con los anillos en el ancho
  > grande (FR14), esos ~64 puntos eran los que le faltaban al selector para no
  > cortarse. Corregido con el usuario el 2026-09-01. Los selectores de endpoint
  > se mudaron aquí en vez de perderse: eran la única vía para elegir destino o
  > fuente, y la pantalla de MIDI mapping está fuera de alcance.
- [x] Task: El selector de los dieciséis Tracks — `1fb3d8a`
  - [x] Fila de pastillas con número y canal, sin nombres (FR5)
  - [x] El seleccionado lleva borde de 2px en el color de la familia activa; los que tienen material se distinguen de los vacíos
  - [x] Seleccionar hace lo mismo que su step button — las dos vías llevan al mismo sitio o la pantalla mentiría
  - [x] Dieciséis pastillas tienen que caber y ser tocables: se comprueba en simulador, **apaisado** — que es la única orientación desde FR13

  > Una fila de dieciséis y no dos de ocho: dos filas se leen como dos grupos y
  > los Tracks no están agrupados. Una fila es además el orden de los step
  > buttons del controlador.
- [x] Task: La navegación de cinco pestañas — `4a2ea82`
  - [x] `1 · Track` y `2 · Scale` navegan; `3 · MIDI`, `4 · Banks` y `5 · Tracks` se dibujan con borde discontinuo y no responden (FR8)
  - [x] El estado de navegación no interrumpe el transporte, y **ningún modal bloquea mientras suena**
  - [x] Cambiar de pantalla con el transporte corriendo y volver: el playhead sigue donde tiene que estar, no reiniciado — el modelo no se reconstruye al navegar
- [x] Task: El arnés de jitter sale de la pantalla — `4a2ea82`
  - [x] Deja de dibujarse en la pantalla de trabajo (FR12)
  - [x] **Sigue arrancándose por argumento de lanzamiento, y se comprueba que sigue funcionando**: es la herramienta con la que se mide la Fase 6, así que romperla aquí se descubriría en el peor momento

  > **Quitar el panel se llevaba el selector de rejilla**, que era lo único
  > elegible solo tocando: el arnés habría quedado midiendo siempre la recta. Se
  > añadió `--grid=` **antes** de borrarlo y se comprobó ejecutándolo —
  > `harness-still-works.txt`, con la rejilla `16 Tracks` por argumento.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 5: Scale & Root

> La segunda pantalla. Cambia la representación, no el comportamiento: lo que
> hace ya lo hace hoy `TonalView`.

- [ ] Task: La rejilla de escalas
  - [ ] Seis botones con el tratamiento del handoff: relleno violeta sólido el activo, contorno los demás
  - [ ] `+User` va con borde discontinuo — escala de usuario no está en esta rebanada, y ese es el signo que el handoff define para «todavía no»
  - [ ] Tocar una escala reencuadra el pool y **nunca lo vacía**, como hoy y como manda la guía
- [ ] Task: El gráfico de notas y la raíz
  - [ ] Tests (Red) en `Engine`: qué notas están en la escala y cuál es la raíz salen del marco tonal, no de la vista
  - [ ] Las notas de la escala, altas e interactivas; las de fuera, cortas, oscuras y no interactivas
  - [ ] La raíz elegida con borde de 3px y etiqueta destacada: **distinta de «está en la escala»**, que es la confusión que el handoff se molesta en señalar
  - [ ] Línea de estado `Scale · <nombre>  Root · <nota>`, con la raíz en color
- [ ] Task: El pool, en su sitio
  - [ ] Se sigue mostrando **solo el pool sobre la escala**, nunca una nota por paso: es fidelidad al modelo y un antipatrón declarado de la guía
  - [ ] La superficie de pads y el registro se siguen viendo, como hoy
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 6: La medición y el dispositivo

> La fase que decide si la pantalla vale. Se juzgan dos cosas que solo el iPad
> puede responder: si el jitter aguanta la carga visual nueva, y si esto se lee a
> un metro.

- [ ] Task: Jitter con los dieciséis anillos redibujándose
  - [ ] iPad real, con el arnés, con los dieciséis Tracks sonando y la pantalla nueva delante
  - [ ] Umbral: **máximo < 2 ms, σ < 0,5 ms**. Se registra el número, no la impresión
  - [ ] Se compara contra la rebanada 3 —máx 0,134 ms, σ 0,020 ms, que midió **un** anillo— y contra la que deje la Fase 6 de `multi-track`, y la diferencia se explica
  - [ ] Si hay regresión: **la rebanada se para**. La causa probable sería dibujar de más por fotograma, no el scheduler; se ataca ahí antes de tocar nada de timing
  - [ ] El resultado va a `product.md`, junto a las anteriores
- [ ] Task: Verificación a un metro
  - [ ] **El playhead se lee a un metro sobre dieciséis anillos** (FR2). Si no, se decide ahí el anillo grande aparte y se anota como enmienda del spec
  - [ ] El valor grande del panel se lee a un metro
  - [ ] **Los tres acentos se distinguen de reojo y con poca luz** (FR11). Si mauve y violeta se confunden, se registra y se decide: volver al ámbar es una opción legítima y documentada
  - [ ] Se comprueba con el BeatStep Pro: girar un knob de cada familia y ver que el panel responde con su color en el Step siguiente
  - [ ] Se registra en un `device-verification.md` del track, con fotos si hacen falta, y en la git note
- [ ] Task: Cerrar la rebanada
  - [ ] Cobertura de `Engine` ≥90% y de `MIDI` ≥80%, medidas como dice `workflow.md`
  - [ ] `product-guidelines.md` recoge lo que esta rebanada cierra: el lenguaje visual deja de ser ilustrativo
  - [ ] El handoff queda anotado con lo que se implementó y lo que no, y con cualquier desviación decidida en dispositivo
  - [ ] `tracks.md` deja descrita la rebanada siguiente, y `cycles_20260901` deja de estar bloqueado por ésta
  - [ ] Pull Request contra `main`, con los checks en verde
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Notas de riesgo

1. **La legibilidad del playhead es la apuesta de la rebanada.** Dieciséis
   bandas finas pueden no dejar sitio para leer dónde está el tiempo a un metro,
   que es un requisito de `product-guidelines.md` y no una preferencia. No se
   sabrá hasta el iPad. La salida está escrita —anillo grande aparte para el
   seleccionado— y cuesta superficie que el diseño no reserva.

2. **Mauve y violeta pueden no separarse.** El ámbar de Groove se eligió por una
   razón que sigue siendo válida: de reojo y con poca luz, dos colores que se
   distinguen sobre todo por luminosidad se confunden. El handoff manda, pero la
   comprobación es en dispositivo y volver al ámbar es una opción documentada.

3. **`App` tiende a engordar en una rebanada de pantalla.** El umbral de
   cobertura no la cubre y la regla que lo sustituye es que ahí no viva nada que
   merezca test. Cada fase baja a `Engine` lo calculable **antes** de dibujarlo;
   si algo en `App` empieza a pedir un test, está en el sitio equivocado.

4. **Figtree puede no cargar y fallar en silencio.** iOS cae a la fuente del
   sistema sin avisar. Se comprueba con captura en la Fase 1 y no se da por
   hecho.

5. **Dibujar de más es el riesgo de rendimiento, no el scheduler.** Dieciséis
   anillos por fotograma es trabajo de dibujo, y la medición de la Fase 6 puede
   subir por ahí. Por eso NFR4 fija el enfoque —un `Canvas`, sin una vista por
   posición— desde la Fase 2 y no como reacción a una medida mala.

6. **Esta rebanada desbloquea a `cycles_20260901`.** Aquel track depende de que
   exista esta pantalla para mostrar el Cycle en curso. Cerrar ésta es lo que le
   deja empezar.
