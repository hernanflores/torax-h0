# Spec — Rediseño de las cuatro pantallas (track, scale, midi, banks)

**Track ID:** `screens-redesign_20260906`
**Tipo:** Feature — capa de presentación
**Fuente:** `torax-h0-ipados-handoff/coding-agent-brief.md` y los cuatro PNG
(`track.png`, `scale.png`, `midi.png`, `banks.png`).

## Overview

La app tiene hoy tres pantallas construidas rebanada a rebanada, con un chrome
que creció por acumulación: una sola fila arriba mezclando pestañas, estado MIDI
y transporte; nombres de pantalla con prefijo numérico; dos pestañas dibujadas
con borde discontinuo porque no existían; y un panel de medición de jitter que
sobrevive a una medición suspendida el 2026-09-02.

Este track sustituye esa capa por el rediseño del handoff: **un chrome
compartido** —barra de estado y navegación persistente— y **cuatro pantallas
completas**: `track`, `scale`, `midi` y `banks`.

**No es un cambio de estilo, es un cambio de sistema.** Lo que se rehace es el
dibujo; el estado, el motor y el camino de tiempo real no se tocan. `Engine` y
`MIDI` **no cambian por razones de dibujo**: si una tarea necesita tocarlos para
que algo se vea distinto, es señal de que se ha salido del alcance.

> **Enmienda del 2026-09-06, escrita al cerrar el track.** La frase de arriba
> decía «`Engine` y `MIDI` quedan intactos», y no se cumplió — ni debía. Las seis
> auditorías del plan existen precisamente para encontrar reglas y textos de
> dominio escritos en vistas, y encontraron nueve: `Tempo.displayDescription`,
> `Scale.name`, `ParameterFamily.name`, `ClockSource.name`,
> `TrackParameter.value(in:)`, `PitchPool.countDescription`, los `label`/`value`
> de `FamilyReadout` y `ParameterChange`, `ClockStatus` y
> `ControlInput.pressPad(at:)`. Los nueve bajaron con tests en rojo primero.
>
> Lo que se mantiene entero es **NFR1**: el camino de tiempo real no aparece en
> el diff, y eso sí se verificó fichero por fichero.

**El principio rector no cambia.** El controlador sigue siendo el instrumento y
la pantalla el espejo. Lo que el brief precisa es dónde el dedo es legítimo:
`track` se lee mientras suena y no se toca; `scale`, `midi` y `banks` se
configuran antes de tocar y ahí el dedo sí opera. La frontera exacta está en
FR14.

## Decisiones cerradas antes de empezar

Acordadas con el usuario el 2026-09-06, antes de redactar. Se listan porque cada
una descarta una lectura alternativa del brief que el código habría tenido que
adivinar.

| # | Ambigüedad | Decisión |
|---|---|---|
| 1 | Alcance | Feature de presentación. Todo en `App/`. |
| 2 | `banks` sin modelo de Bank | Cáscara visual sobre el `Pattern` actual. |
| 3 | Fondo `#111211` vs. lenguaje «cerrado» en `#211823` | Se adopta `#111211` con nota fechada. |
| 4 | Vistas heredadas | Se reemplazan; `JitterMeasurementModel` se conserva sin entrada en UI. |
| 5 | Pool tonal | 7 grados × 2 bloques = 14 pads de nota + 2 pads de octava. |
| 6 | Verificación de fase | `xcodebuild` verde + `Engine` sin fallos + captura de simulador + confirmación del usuario. |
| 7 | Minúsculas | Solo en UI; el vocabulario de la Pre Spec se conserva en código y docs. |
| 8 | Cards de familia | Los tres simultáneos; el giro resalta el suyo. Sin tabs. |
| 9 | Lectura grande | Persiste el último parámetro tocado. |
| 10 | Destino MIDI | Vive en `midi`; la barra lo menciona solo cuando falta. |
| 11 | Tempo interno | Se edita tocando el `124 bpm` de la barra superior. |
| 12 | Playhead | Uno por anillo, con la Division de su track. |
| 13 | Icono del card `cycle` | Indicador de estado, no botón. |
| 14 | Selección de track en `scale` | Táctil. |
| 15 | Orientación | Landscape bloqueado en Debug y Release. |
| 16 | Sin hardware | Misma estructura, estado real en cada hueco. |

---

## Requisitos funcionales

### Sistema de tokens

**FR1 — Un solo sistema, sin excepciones.** Color, tipografía, trazo, radio y
sombra viven en `Palette`, `Typography` y `Brutalist`. **Ninguna vista de este
track declara un color, una fuente, un grosor, un radio ni una sombra propios.**
Es la regla que `product-guidelines.md` ya fija —«una vista que invente su propio
color es un fallo, no una variación»— y este track la extiende a los tamaños:
una vista que escriba un número de puntos tipográficos es el mismo fallo.

**FR2 — Los valores del brief.**

- Fondo `#111211`. Sustituye al `#211823` actual.
- Los tres acentos se conservan: shape `#9AAB79`, groove `#AA6DA8`,
  tonal `#7C5FD9`.
- Trazos de 2 pt; 3 pt en lo seleccionado.
- Radios de 3 a 8 pt. Nunca pastilla completa, nunca 0.
- Rellenos planos. Sombra dura sin blur, **solo en lo seleccionado**.
- Figtree 400 / 600 / 700, ya en el bundle.
- **Prohibido:** gradiente, blur, glassmorphism, piano roll, teclado musical y
  cualquier gráfico ornamental.

**FR3 — Todo texto visible en minúsculas.** `steps`, `pulses`, `dorian`,
`midi: beatstep pro`, `no midi device`. Se aplica en la capa de presentación; el
vocabulario de la Pre Spec sigue capitalizado en código, tests y documentación.

### Chrome compartido

**FR4 — Barra superior.** De izquierda a derecha: `torax h-0`, el nombre del
módulo activo centrado, punto de conexión, la entrada MIDI (`midi: beatstep
pro`), la fuente de clock (`internal` / `external`), el tempo (`124 bpm`) y el
transporte.

**FR5 — El tempo se edita desde la barra.** El `124 bpm` es tocable y abre el
ajuste del tempo interno. Con reloj externo el valor es lectura: lo manda el
maestro y no se puede escribir.

**FR6 — El destino de salida aparece en la barra solo cuando falta.** La
selección de destino vive en el card `midi output` de la pantalla `midi`. Pero
sin destino el transporte no puede sonar, y eso hay que verlo desde cualquier
pantalla: la barra muestra entonces `no midi device`.

**FR7 — Navegación persistente.** Cuatro entradas —`track`, `scale`, `midi`,
`banks`— siempre visibles y siempre alcanzables. El módulo activo lleva un
subrayado off-white de 3 pt. **Ninguna lleva borde discontinuo: las cuatro
existen.**

**FR8 — Navegar no toca el reloj.** El estado del transporte y el modelo son los
mismos al cambiar de pantalla; el playhead sigue donde tiene que estar al volver,
no reiniciado.

### Pantalla `track`

**FR9 — Reparto 68 / 32.** Visualización a la izquierda, lectura a la derecha.

**FR10 — Doce anillos concéntricos**, del exterior (track 01) al interior (track
12), cada uno con sus posiciones de step y sus pulsos activos. El track
seleccionado lleva contorno de 3 pt. Un track silenciado se distingue **sin
dejar de girar**: mute suprime la salida MIDI, nunca su cycle ni su playhead.

**FR11 — Un playhead por anillo.** Off-white, muy visible, **y se mueve solo
cuando el transporte avanza**. Cada aguja deriva de la `Division` de su propio
track: con divisiones distintas, una única aguja global mentiría sobre once de
los doce.

**FR12 — Columna de lectura.** De arriba abajo:

- La lectura grande: nombre del parámetro y su valor (`pulses`, `5 / 16`).
  **Persiste tras el giro**: pierde el acento de «recién cambiado», no el valor.
- Card `cycle`: `03 / 08`, las celdas `01`–`08` con la activa marcada, y el
  indicador de encadenamiento — **indicador, no botón**.
- Cards `shape`, `groove` y `tonal`, **los tres a la vez**. Girar un knob resalta
  el card de su familia con el acento correspondiente.
- El card `tonal` muestra `scale dorian`, `root d` y el pool. **No mapea alturas
  a steps concretos.**

**FR13 — Franja de doce tracks** con `01`–`12` y `m` / `s` bajo cada uno. Marca
el seleccionado y refleja mute y solo vigentes.

**FR14 — La frontera del tacto.** En `track` **no se edita ningún parámetro
generativo con el dedo**: ni steps, ni pulses, ni rotate, ni division, ni nada de
groove o tonal. Lo que sí es táctil aquí: seleccionar track, mute y solo. Un
slider provisional para suplir un knob ausente es el antipatrón que
`product-guidelines.md` nombra, y este track no lo abre.

### Pantalla `scale`

**FR15 — Contexto de track, táctil.** Muestra qué track se está editando y
permite cambiarlo sin volver a `track`. Scale, root y pool son parámetros del
track: editarlos sin poder elegir cuál obligaría a un viaje de ida y vuelta por
cada uno de los doce.

**FR16 — Selector de escala.** Las seis del brief y en su orden —`minor`,
`major`, `dorian`, `mixolydian`, `phrygian`, `lydian`— más `pentatonic` y
`hirajoshi`: **ocho**. La elegida se rellena en violeta tonal con trazo de 3 pt.

> **Enmienda del 2026-09-06, decidida con el usuario al empezar la Fase 3.** El
> brief pide seis y `Engine` tenía cinco: coincidían cuatro, faltaban
> `mixolydian` y `lydian`, y sobraba `pentatonic`. Se añaden las que faltaban y
> **se conserva `pentatonic`**, que funciona, tiene tests y es el único caso que
> ejercita el hueco de pads que la Pre Spec documenta. `hirajoshi` la pidió el
> usuario; se implementa como `0-2-3-7-8`, la forma que catalogan Elektron,
> Ableton y Novation.
>
> El orden pone las seis del brief primero, así que la rejilla coincide con el
> PNG en sus seis primeras tarjetas y las dos pentatónicas cierran en un cuarto
> renglón.

**FR17 — Selector de root:** las doce clases de altura, `c` a `b`. La elegida en
off-white.

**FR18 — `pitch pool` como rejilla 4×4, espejo de los pads del controlador.**

`Engine` ya define la correspondencia: `PadSurface.padCount = 16`,
`degreesPerBlock = 7`, `octaveDownIndex = 7`, `octaveUpIndex = 15`. La rejilla la
respeta posición por posición:

- **14 pads de nota**: 7 grados de la escala × 2 bloques.
- **2 pads de octava** en las posiciones 8 y 16, marcados como tales y
  **mostrando en qué octava se está** (`PadSurface.octaveShift`). Esa información
  no está disponible en ninguna otra parte de la interfaz.
- Los pads del pool en violeta tonal; el resto, neutros. **Los de octava nunca en
  violeta**: no son notas.
- Pie con el contador real de notas activas.

**FR19 — La capacidad del pool no cambia.** `PitchPool.capacity` sigue siendo 8,
que es lo que exige que el snapshot sea trivial. Con 14 candidatos, el noveno pad
simplemente no entra y el contador dice la verdad.

**FR20 — Los pads son grados, no una melodía.** La rejilla dice qué alturas están
disponibles; nunca qué altura suena en qué step.

### Pantalla `midi`

**FR21 — `clock source`:** control segmentado `internal` / `external`, con la
lectura `internal clock · 124 bpm` debajo. El ajuste del tempo está en la barra
(FR5), no aquí.

**FR22 — `midi input`:** los dispositivos disponibles, con su estado. Lo
conectado se marca `connected`; lo que existe pero no se puede usar lleva **borde
discontinuo y la palabra `unavailable`** — el signo que el lenguaje visual ya
tiene para eso.

**FR23 — `midi output`:** selección del destino externo y la nota `channel
routing active`.

**FR24 — `track channels`:** doce filas `track 01`–`track 12` con su canal
`ch 01`–`ch 12`, el track seleccionado resaltado, y el recuento de tracks
enrutados.

### Pantalla `banks`

**FR25 — Alcance declarado: cáscara visual.** No existe modelo de `Bank` ni
persistencia. La pantalla se dibuja completa y **la selección se puede mover, sin
efecto musical**: solo el pattern vigente tiene material y el resto se muestra
`empty`. Enseñar la forma de la app y decir qué está vacío es más honesto que
fingir un cambio que no ocurre.

**FR26 — Columna izquierda:** `bank 01` y la rejilla 4×4 de bancos `01`–`16`, con
el banco 01 seleccionado. Pie con el tempo y el número de patterns.

**FR27 — Columna central:** rejilla 4×4 de patterns `01`–`16`. El que suena se
marca en olivo de shape y se etiqueta `playing`; los demás, `ready` o `empty`
según tengan material.

**FR28 — Columna derecha:** `track assignments`, doce filas de track a pattern,
con la fila del track seleccionado enfatizada.

### Estado sin hardware

**FR29 — La estructura no cambia sin dispositivo.** Punto apagado y `no midi
device` en la barra; lista de entrada vacía en `midi`; salida en gris. **Los
anillos, los playheads y los cards siguen visibles**, porque son estado y no
edición. Sin controlador la app es de solo lectura y transporte, y no se abre
ninguna vía táctil para suplirlo (FR14).

### Higiene

**FR30 — Landscape bloqueado** en `Config/Info-Debug.plist` y en la
configuración de Release. Los layouts se calculan para landscape; permitir
retrato es prometer una pantalla que nadie ha diseñado.

**FR31 — Lo que se retira.** El panel de medición de jitter sale de la interfaz
—la medición está suspendida desde el 2026-09-02—, junto con los prefijos
numéricos de las pantallas, las pestañas de borde discontinuo y los tabs de
familia. `JitterMeasurementModel` **se conserva** en el repositorio, accesible por
argumento de lanzamiento: si la medición vuelve, no hay que reconstruir el
cableado.

**FR32 — Componentes con los nombres del brief.** `appChrome`,
`moduleNavigation`, `ringPatternView`, `cycleStrip`, `parameterFamilyCard`,
`trackPill`, `scalePicker`, `rootPicker`, `pitchPoolGrid`, `midiChannelRow`,
`bankGrid`, `patternGrid`. `TonalView` y `ChannelMapView` se borran al quedar sus
funciones cubiertas.

---

## Requisitos no funcionales

**NFR1 — El camino de tiempo real no se toca.** Ni el scheduler, ni la ventana de
look-ahead, ni la disciplina de ranura del snapshot. Un diff de este track que
alcance `LookAheadScheduler`, `MusicalTimeline` o `SchedulerThread` es un error de
alcance.

**NFR2 — Las animaciones derivan del reloj musical.** El playhead se dibuja
consultando la posición que el modelo resuelve contra el origen publicado por el
scheduler. **`TimelineView` decide cuándo repintar, nunca dónde está el tiempo.**
Animar con un temporizador algo que debería derivar del reloj musical es el
antipatrón que `product-guidelines.md` nombra por su nombre.

**NFR3 — Legibilidad a un metro y con poca luz.** Es criterio de uso, no
estética.

**NFR4 — `App` no se mide** (`workflow.md`). No se escriben UI tests de bajo
valor para subir un número. Si algo de este track merece un test, es que está en
el sitio equivocado y hay que moverlo a `Engine` o `MIDI`.

**NFR5 — Sin dependencias de terceros.**

**NFR6 — Integración por Pull Request**, sin push directo a `main`.

---

## Criterios de aceptación

1. Las cuatro pantallas son alcanzables desde cualquier otra y el módulo activo
   lleva subrayado de 3 pt.
2. Ningún texto visible tiene mayúsculas.
3. `grep` no encuentra en `App/` ningún literal de color, fuente, grosor, radio ni
   sombra fuera de `Palette`, `Typography` y `Brutalist`.
4. El fondo es `#111211` y los tres acentos son los del brief.
5. En `track`, con el transporte corriendo, los doce playheads avanzan y se
   detienen al parar; ninguno se mueve con el transporte parado.
6. En `track` no hay ningún gesto que altere un parámetro generativo.
7. La lectura grande conserva su último valor tras el giro.
8. En `scale`, la rejilla muestra 14 pads de nota y 2 de octava, éstos indicando
   la octava vigente; el contador refleja el número real de notas del pool y no
   admite una novena.
9. En `midi`, el segmentado refleja la fuente de clock real y las doce filas
   muestran su canal, con el track seleccionado resaltado.
10. En `banks`, la selección de banco y pattern se mueve sin alterar lo que suena,
    y los patterns sin material dicen `empty`.
11. Sin BeatStep y sin destino, las cuatro pantallas conservan su estructura y la
    barra dice `no midi device`.
12. La app solo se presenta en landscape.
13. Cada fase cierra con `xcodebuild` verde, `Engine` sin fallos, captura de
    simulador comparada con su
    PNG, y confirmación explícita del usuario.

## Fuera de alcance

- Modelo de `Bank` en `Engine`, persistencia y cambio real de pattern.
- MIDI Learn.
- Cualquier cambio en `Engine` o `MIDI` que no sea consecuencia forzosa de una
  API que la UI necesite leer.
- Layout en retrato.
- Reanudar la medición de jitter.
- Ampliar `PitchPool` más allá de 8 huecos.

## Desviaciones a documentar

Ambas exigen, por el paso 8 del *Task Workflow*, parar y anotar antes de
implementar.

1. **`product-guidelines.md`, fondo.** El lenguaje visual se declaró cerrado el
   2026-09-02 con `#211823`. El brief lo sustituye por el neutro `#111211`. Se
   añade nota fechada explicando que cambia el fondo, **no los tres acentos ni el
   tratamiento neo-brutalista**, que siguen siendo los cerrados aquel día.
2. **`product-guidelines.md`, caja del vocabulario.** La guía fija el vocabulario
   de la Pre Spec en inglés sin traducir; el brief exige minúsculas en toda la
   interfaz. Se añade nota fechada: **cambia la caja, no el término.** `steps` en
   pantalla sigue siendo `Steps` en código, tests y documentación, y sigue siendo
   un solo término por concepto.

## Limitaciones conocidas que este track introduce

1. **`banks` enseña una selección que no suena.** Mover el banco o el pattern
   cambia lo que la pantalla marca y nada más. Se levanta cuando exista el modelo
   de `Bank`.
2. **La pantalla no ve lo que cambia el hardware.** El botón de transporte no se
   entera de un Start del BeatStep y el tempo de un maestro externo no refresca
   la barra: nadie incrementa `clockRevision` desde el hilo de recepción de
   CoreMIDI. Se intentó arreglar dentro de este track y los tres intentos
   dejaron la app sin atender el MIDI entrante; se revirtieron. Registrado como
   defecto propio en `conductor/tracks.md`.

3. **El pool admite 8 de 14 candidatos.** La rejilla ofrece catorce alturas y el
   pool solo guarda ocho: la novena se rechaza en silencio. El límite es de
   `Engine` y es deliberado —snapshot trivial—, pero el usuario lo descubre al
   chocar con él.
