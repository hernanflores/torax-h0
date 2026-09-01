# Spec — v2 rebanada 2: La pantalla del handoff

**Track ID:** `screen-handoff_20260901`
**Track type:** Feature

## Overview

La rebanada 1 construyó dieciséis Tracks sobre un reloj y les dio la pantalla
**mínima para operar**: una lista de selección, el estado del Track elegido y su
canal. Funciona y no es la pantalla del producto. El handoff de diseño lleva
cerrado desde antes —cinco pantallas, estructura y flujo decididos, colores y
tipografía finales, lenguaje neo-brutalista aplicado— y su pantalla 1 es
exactamente la vista de lo que la rebanada 1 construyó: **dieciséis Tracks como
anillos concéntricos**, uno de ellos en detalle.

Esta rebanada la implementa. No inventa modelo: todo lo que dibuja ya existe en
`Engine` y en `MIDI`.

**El núcleo es que la pantalla pasa de una columna de texto a un mapa.** Hoy hay
que leer para saber qué Track está seleccionado y qué tiene dentro; con los
anillos se ve de un vistazo cuáles tienen material, cuál suena y por dónde va el
tiempo. Es la diferencia entre un panel de estado y un instrumento, y es lo que
`product-guidelines.md` pide desde el principio: lo expresivo es el material
musical y todo lo demás es soporte.

**Y que el lenguaje visual se cierra.** Hasta hoy `ShapeTheme` dice de sí mismo
que sus colores son ilustrativos y que están en un solo sitio «para poder
cambiarlos cuando el lenguaje visual se cierre». Se cierra aquí: trazos de 2px,
radios de 3 a 8px, sombras duras sin blur, bloques de acento planos, borde
discontinuo como signo de «todavía no», y Figtree.

### Qué se implementa de las cinco pantallas

| # | Pantalla | En esta rebanada |
|---|---|---|
| 1 | Track / anillos | **Sí**, entera |
| 2 | Scale & Root | **Sí**, reconstruida con el lenguaje visual |
| 3 | MIDI / Learn | No — es la rebanada 8 de la v1 |
| 4 | Banks | No — necesita persistencia, que no existe |
| 5 | Track × Pattern | No — necesita Patterns, que no existen |

Las tres que no entran **se ven igualmente**, como pestañas deshabilitadas con
borde discontinuo. No es un adorno: el borde discontinuo es el signo que el
propio handoff define para «no disponible todavía», y enseñar la forma completa
de la app es más honesto que fingir que tiene dos pantallas.

### Lo que esta rebanada no es

**No es modelo nuevo.** Ni mute/solo, ni nombres de Track, ni Banks, ni
Patterns, ni tempo editable. Todo lo que la pantalla muestra sale de lo que ya
hay. La única excepción es `ParameterFamily.tonal` (FR4), que es una
clasificación, no un parámetro.

**No es la pantalla de Cycles.** El Cycle en curso llega con
[`cycles_20260901`](../cycles_20260901/index.md), que depende de ésta.

## Functional Requirements

### FR1 — Dieciséis Tracks son dieciséis anillos concéntricos

Del exterior al interior, Track 1 a 16. Cada anillo dibuja **su propio** reparto
—sus Steps y sus Pulses— así que la forma de cada Track se ve sin seleccionarlo.
El Track seleccionado se dibuja en su acento; los quince restantes, en gris
tenue con el mismo patrón de arcos. Los dieciséis se dibujan siempre, tengan
material o no: un anillo que aparece y desaparece movería a los demás de sitio, y
eso es movimiento no derivado del reloj musical, que la guía prohíbe.

### FR2 — El playhead se ve, y a un metro

Dónde está el tiempo es una de las dos cosas que `product-guidelines.md` exige
leer a un metro. Con dieciséis bandas finas eso no está garantizado por el
diseño, y es el riesgo declarado de la rebanada: se resuelve dibujando, se juzga
en dispositivo y **si no se lee, la solución es dibujar el anillo del Track
seleccionado aparte y grande**, no reducir el número de anillos.

### FR3 — La lectura grande vive en el panel lateral

En reposo muestra el estado de la familia del tab activo. Al girar un knob se
convierte en el valor transitorio, con el acento de la familia del parámetro que
se movió, y se desvanece tras la inactividad como hoy.

**Con esto los anillos no se tapan nunca.** Hoy el valor grande se dibuja encima
del anillo y la guía obliga a que el patrón permanezca visible bajo él; en el
panel lateral la regla se cumple sin excepción. Es una mejora respecto a hoy, no
una desviación del handoff: es lo que el handoff dibuja.

### FR4 — Tres tabs: SHAPE, GROOVE y TONAL

Verde, mauve y violeta. El tab activo decide qué muestra el panel en reposo y se
elige con el dedo — es navegación, no edición.

**TONAL no tiene parámetros de knob detrás**, así que su lectura en reposo es el
marco tonal y el pool: Scale, Root y cuántas alturas hay. `ParameterFamily` gana
un caso `.tonal` en `Engine` para que el acento salga por la misma vía que los
otros dos y no por un condicional en la vista.

### FR5 — El selector de Tracks es una fila de pastillas

Dieciséis, con su número y su canal. El seleccionado lleva borde de 2px en el
color de la familia activa; los que tienen material se distinguen de los vacíos.
Seleccionar hace lo mismo que su step button, como hoy.

**Sin nombres de Track.** Los del handoff —KICK, SNARE, CHH— son relleno para que
el mock se lea; el modelo no los tiene y esta rebanada no los inventa.

### FR6 — La barra superior lleva transporte, BPM y estado MIDI

A la derecha, BPM y play/stop. En el sitio que el handoff reserva a
`Bank 1 · Pattern A` va el estado MIDI —destino y fuente—, que es lo que hoy hay
que mirar y lo que la guía manda comunicar como estado y no como disculpa.
Bank y Pattern ocuparán su sitio cuando existan.

### FR7 — Scale & Root, con el lenguaje del handoff

Rejilla de escalas de seis columnas y gráfico de barras por nota: las de la
escala altas e interactivas, las de fuera cortas, oscuras y no interactivas. La
raíz elegida lleva borde de 3px y etiqueta destacada, distinta de «está en la
escala». Debajo, la línea de estado `Scale · <nombre>  Root · <nota>`.

Lo que hace ya lo hace hoy `TonalView`: **cambia la representación, no el
comportamiento.** Cambiar de Scale reencuadra el pool, nunca lo vacía.

### FR8 — Navegación de cinco pestañas, tres deshabilitadas

`1 · Track`, `2 · Scale`, `3 · MIDI`, `4 · Banks`, `5 · Tracks`. Las dos
primeras navegan; las tres restantes se dibujan con borde discontinuo y no
responden. Ningún modal bloquea mientras el transporte corre.

### FR13 — La app es de landscape, y solo de landscape

**Añadido el 2026-09-01, durante la Fase 2.** Ni la spec original ni el plan
decían nada de la orientación, y las seis fases daban por supuesto el layout de
tres columnas del handoff —anillo | panel de lectura | tabs, con el selector de
Tracks abajo— que **es landscape por construcción**. Las cinco capturas del
handoff son 924×540. El supuesto estaba en todas partes y escrito en ninguna.

La app declaraba las cuatro orientaciones, heredadas del andamiaje inicial del
proyecto: nadie lo decidió para esta pantalla. Pasa a declarar solo
`LandscapeLeft` y `LandscapeRight`, en Debug y en Release.

**No hay layout de portrait y no se inventa uno.** Diseñar una segunda
composición sin mock que la respalde sería inventar producto, que es justo lo
que esta rebanada dice no hacer. El iPad se usa apaisado, delante del
controlador.

> **Lo que esto le cuesta a FR2.** En el mock, el anillo ocupa **190px de 924**:
> una columna izquierda estrecha, no la mitad de la pantalla. Dieciséis bandas en
> 190px son unos 6px por banda. El riesgo de legibilidad del playhead a un metro
> es bastante más agudo de lo que sugiere mirar el anillo en grande, y es ahí
> —a su tamaño real, apaisado— donde la Fase 6 tiene que juzgarlo.

### FR9 — El lenguaje neo-brutalista es un sistema, no un estilo por vista

Trazos sólidos de 2px en todo lo interactivo (3px en la raíz elegida), radios de
3 a 8px —nunca pastilla completa, nunca 0—, rellenos de acento planos y
saturados sin degradados, sombras duras `2px 2px 0` sin blur en lo
seleccionado, borde discontinuo para lo no disponible, y peso 700 en lo activo.
Vive en un sitio y las vistas lo usan; una vista que invente su propio botón es
un fallo de esta rebanada.

### FR10 — Figtree

La tipografía del handoff, empaquetada en la app. Es la fuente de todo el texto:
etiquetas, botones, lecturas numéricas y tablas.

### FR11 — El acento de Groove pasa a mauve

`#AA6DA8`, el del handoff, en lugar del ámbar actual. El ámbar se eligió cuando
no había lenguaje visual cerrado y con una razón escrita —separarse por tono y no
por luminosidad—; esa razón se vuelve a comprobar a un metro en dispositivo, y si
mauve y el violeta de Tonal se confunden, se registra y se decide con la app en
la mano.

### FR12 — El arnés de jitter sale de la pantalla

Sigue existiendo y sigue arrancándose por argumento de lanzamiento. Deja de
ocupar sitio en la pantalla de trabajo: es instrumentación, no producto.

## Non-Functional Requirements

- **NFR1 — Nada de esto toca el hilo del scheduler.** Es una rebanada de
  presentación: no cambia *cuándo* cae ningún evento. **Sin medición de jitter
  obligatoria** por la nota del 2026-08-28 de `workflow.md`… con una excepción, y
  es NFR2.
- **NFR2 — Carga visual nueva sí exige medición.** Dieciséis anillos
  redibujándose al ritmo del reloj es exactamente el caso que esa misma nota
  nombra: «carga visual nueva que redibuje al ritmo del reloj». Se mide contra la
  referencia de la rebanada 3 —máx 0,134 ms, σ 0,020 ms, que fue la del anillo
  único— y contra la que deje la Fase 6 de `multi-track`. Una regresión bloquea
  la rebanada.
- **NFR3 — El movimiento deriva del reloj musical.** El playhead se consulta al
  dibujar y se resuelve contra el origen que publicó el scheduler, como hoy.
  Ninguna animación de conveniencia, ningún temporizador que invente posición.
- **NFR4 — Dibujar dieciséis anillos no puede costar dieciséis veces más de lo
  razonable.** Se dibuja en un `Canvas`, sin una vista por posición: dieciséis
  Tracks de hasta 64 Steps son mil posiciones por fotograma.
- **NFR5 — La lógica que merezca test no vive en `App`.** Si algo aquí lo
  merece, está en el sitio equivocado (`workflow.md`): lo que sea calculable
  —qué anillo, qué radio, qué texto— baja a `Engine`, donde se testea.
- **NFR6 — Cobertura:** `Engine` ≥90%, `MIDI` ≥80%. `App` no se mide.
- **NFR7 — Vocabulario de la Pre Spec en pantalla**, en inglés y sin traducir.
- **NFR8 — Verificación en dispositivo y a un metro**, que es el criterio de
  legibilidad de `product-guidelines.md`. El simulador sirve para la composición;
  no sirve para juzgar ni el playhead en movimiento ni el color. **Y se verifica
  apaisado** (FR13): una captura en portrait no enseña la composición que existe,
  y durante la Fase 2 se juzgó una que no era.

## Acceptance Criteria

**Criterio principal:**

> Con dieciséis Tracks sonando, la pantalla del handoff muestra sus dieciséis
> anillos concéntricos con el reparto de cada uno, el seleccionado en su acento y
> el playhead corriendo; girar un knob llena el panel lateral con su valor y su
> color sin tapar nada; y todo ello se lee a un metro en el iPad, sin regresión
> de jitter con la carga visual nueva.

Además:

- [ ] Los dieciséis anillos se dibujan siempre, con el reparto propio de cada
      Track y sin moverse de sitio al cambiar el material.
- [ ] El Track seleccionado se distingue del resto sin leer texto.
- [ ] Los tres tabs cambian lo que muestra el panel y su color; TONAL muestra el
      marco tonal y el pool.
- [ ] El valor transitorio aparece con el acento de la familia del parámetro
      movido y se desvanece, **sin tapar los anillos en ningún momento**.
- [ ] El selector muestra los dieciséis con su canal y distingue los que tienen
      material.
- [ ] Scale & Root hace exactamente lo que hace hoy, con la representación nueva;
      cambiar de Scale reencuadra el pool y no lo vacía.
- [ ] Las tres pestañas no disponibles se ven, llevan borde discontinuo y no
      responden.
- [ ] El sistema visual vive en un sitio: ninguna vista define su propio borde,
      radio o sombra.
- [ ] Figtree se usa en toda la app.
- [ ] La app solo gira a landscape, y todas las capturas de verificación son
      apaisadas.
- [ ] El arnés de jitter no aparece en la pantalla y sigue arrancándose por
      argumento de lanzamiento.
- [ ] **Jitter con los dieciséis anillos redibujándose dentro del umbral**,
      medido en iPad y registrado con su número.
- [ ] Verificado a un metro en dispositivo: playhead, valor grande y distinción
      de los tres acentos.
- [ ] `swift test` sobre `Engine` y `MIDI` pasa sin simulador ni hardware.

## Known Limitations

1. **Tres pantallas de cinco siguen sin existir.** Se ven deshabilitadas, que es
   deliberado, pero la app sigue siendo dos pantallas.
2. **Sin nombres de Track.** Con dieciséis anillos y dieciséis pastillas, el
   número y el canal son toda la identidad que hay.
3. **Sin mute ni solo.** Un Track se sigue callando vaciando su pool o poniendo
   Pulses a cero.
4. **Bank, Pattern y BPM son de solo lectura**, y los dos primeros ni siquiera
   existen: su sitio en la barra lo ocupa el estado MIDI.
5. **La legibilidad del playhead con dieciséis anillos es una apuesta.** Si en
   dispositivo no se lee a un metro, la respuesta es un anillo grande aparte para
   el Track seleccionado — y eso es superficie que hoy el diseño no reserva.
6. **El mauve de Groove puede no separarse del violeta de Tonal** de reojo y con
   poca luz. Es el riesgo que el ámbar evitaba; se comprueba en dispositivo.

## Out of Scope

- Banks, Patterns, persistencia, Autosave y Backup.
- MIDI Learn y la pantalla de mapeo — rebanada 8 de la v1.
- Mute y solo, y la matriz Track × Pattern.
- Nombres de Track.
- Cycles y su lectura en pantalla — es [`cycles_20260901`](../cycles_20260901/index.md).
- Tempo editable y cualquier control táctil de un parámetro generativo, que la
  guía prohíbe.
