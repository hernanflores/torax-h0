# Spec — v2 rebanada 1: Dieciséis Tracks sobre un reloj

**Track ID:** `multi-track_20260831`
**Track type:** Feature

## Overview

La v1 se redujo a un Track a propósito: validar el motor de punta a punta antes
de escalar, porque el mayor riesgo del proyecto es el timing y no el modelo
musical. Está validado —cuatro mediciones, la última con la rejilla desplazada
dentro: máximo 0,151 ms y σ entre 0,009 y 0,013 ms, contra un umbral de 2 ms y
0,5 ms—. Esta rebanada gasta ese crédito: **de un Track a dieciséis**.

Es la estructura que la Pre Spec describe desde su primera línea —«cada Pattern
tiene 16 Tracks polifónicos»— y la que el preset del BeatStep Pro ya asume: los
dieciséis step buttons seleccionan Track N desde la rebanada 7, y quince de ellos
no tienen nada detrás. Esta rebanada los llena.

**El núcleo es que el snapshot deja de ser un Track y pasa a ser dieciséis.** No
es un cambio de interfaz: es el valor que cruza del hilo de control al hilo del
scheduler, el que `TrackHandoff` publica sin lock y el que `_isPOD` vigila.
Dieciséis Tracks tienen que seguir siendo un valor trivial, copiable con un
`memcpy` desde el hilo de tiempo real, o la arquitectura que aguantó la v1 deja
de aguantar.

**Y que un reloj emite dieciséis rejillas.** Cada Track tiene sus propios Steps,
su Division y su Delay, así que cada uno cae en instantes distintos sobre el
mismo tempo. Hasta hoy había una `MusicalTimeline` y un playhead; ahora hay
dieciséis, con un solo origen.

### Lo que esta rebanada no es

**No es la UI definitiva.** El handoff de diseño tiene cinco pantallas y su
pantalla 1 —los anillos concéntricos, uno por Track— es precisamente la vista de
lo que esta rebanada construye. Se hace después, con esto detrás: al revés sería
dibujar el estado antes de que exista. Aquí la pantalla es la mínima para operar
y ver.

**No es Patterns ni Banks.** La jerarquía de la Pre Spec sigue subiendo —16
Patterns por Bank, 16 Banks por Project— y todo eso queda fuera. Dieciséis Tracks
son el primer escalón y el que se nota; los otros dos necesitan persistencia, que
tampoco existe.

### Las decisiones tomadas antes de planificar

1. **Los dieciséis existen siempre, y están vacíos.** No hay Tracks que se creen
   ni se destruyan: el snapshot es de tamaño fijo. Un Track sin pool ya es hoy un
   estado válido —dispara sus Pulses y no tiene material que emitir—, así que el
   silencio sale del material y no de una bandera de actividad que habría que
   mantener coherente.

   Es también lo que mantiene el snapshot trivial: una colección variable exige
   asignación, y asignar en el camino del scheduler está prohibido.

2. **Al arrancar, solo el Track 1 tiene material.** El pool inicial de una altura
   —«centro estable», dice la Pre Spec— se queda donde está; los otros quince
   arrancan vacíos. **La app suena al arrancar exactamente como suena hoy**, y
   eso es deliberado: una rebanada de motor no debería cambiar lo que se oye
   hasta que alguien la use.

3. **Todo lo generativo es del Track.** Shape, Groove y Tonal completo —pool,
   Scale y Root— viven en cada uno. Es la definición de la Pre Spec: el Track es
   «donde residen los parámetros generativos». Dos Tracks pueden estar en
   tonalidades distintas, y eso es una función, no un accidente.

   **El marco tonal deja de ser global.** Hoy `TonalFrame` vive en
   `ControlInput` y en `TransportModel`, uno solo para toda la app; pasa a ser
   del Track, y la superficie de pads se recalcula al cambiar de Track igual que
   se recalcula al cambiar de escala.

4. **El reloj y el transporte se comparten.** Un tempo, un Play/Stop, un origen
   temporal. Es lo que hace que dieciséis voces suenen juntas en vez de en
   paralelo, y lo que la jerarquía de la Pre Spec confirma: el tempo es del Bank,
   no del Track.

5. **Track N emite por el canal MIDI N, y el canal se puede cambiar.** Dieciséis
   Tracks y dieciséis canales es la correspondencia que no hay que explicar, y
   sin ella los dieciséis sonarían al mismo instrumento y no se podría juzgar
   nada. Editable porque dos Tracks al mismo instrumento —dos capas rítmicas
   sobre el mismo sinte— es un caso real.

   **El canal se edita en pantalla, no con un knob.** Es configuración, no
   material generativo, y `product-guidelines.md` pone esa frontera del lado
   táctil, donde ya están Scale y Root.

6. **Un hilo recorre los dieciséis.** Un solo `SchedulerThread` a prioridad
   máxima que en cada ventana de look-ahead programa lo de todos los Tracks.
   Conserva la arquitectura ya medida, y evita dieciséis hilos a prioridad
   máxima, que es exactamente la condición que hoy rompe la creación de endpoints
   de CoreMIDI —el mecanismo descrito en la ampliación del 2026-08-27 de
   `workflow.md`—.

7. **El estado del aleatorio sigue siendo del scheduler, y pasa a haber uno por
   Track.** Probability dice *cuánto* se omite y es dato del Track; el PRNG que
   decide *qué* Pulse concreto se omite tiene estado mutable y vive en el
   scheduler. Con dieciséis Tracks hay dieciséis generadores, sembrados de forma
   reproducible y distinta —dos Tracks con la misma Probability no deben omitir
   los mismos Pulses, o el aleatorio se oiría como una sola decisión—.

8. **Los step buttons ya significan lo correcto.** La rebanada 7 implementó
   `selectTrack(_:)` con `trackCount` como costura: aquí pasa de 1 a 16 y no hay
   que tocar el preset. Los knobs mueven los parámetros **del Track
   seleccionado**.

## Functional Requirements

### FR1 — El snapshot son dieciséis Tracks

Lo que el hilo de control publica y el hilo del scheduler lee deja de ser un
`Track` y pasa a ser el conjunto de los dieciséis, de tamaño fijo. Sigue siendo
un valor trivial: sin `Array`, sin nada con conteo de referencias, y con un test
que lo vigila como hoy vigila a `Track`.

### FR2 — Los dieciséis existen desde el arranque

Ninguno se crea ni se destruye. Al arrancar, el Track 1 lleva el pool de una
altura que ya lleva hoy y los otros quince están vacíos; la app suena igual que
antes de esta rebanada.

### FR3 — Cada Track tiene su Shape, su Groove y su marco tonal

Steps, Pulses, Rotate, Division, Velocity, Sustain, Probability, Timing, Delay,
pool, Scale y Root son de cada Track. Cambiar cualquiera de ellos en un Track no
toca a los otros quince.

### FR4 — Un reloj, dieciséis rejillas

Con un solo tempo y un solo origen, cada Track cae donde digan sus Steps, su
Division, su Timing y su Delay. Dos Tracks con Divisions distintas suenan a la
vez y en fase: el compás no se desalinea por llevar rejillas distintas.

### FR5 — Track N emite por el canal N

Por defecto. El canal es un dato del Track y se puede cambiar desde la pantalla.
Dos Tracks pueden compartir canal.

### FR6 — El step button N selecciona el Track N, y ahora hay Track detrás

Los dieciséis seleccionan. Los knobs mueven los parámetros del Track
seleccionado; los pads editan su pool; Scale y Root son las suyas. Seleccionar
otro Track **no cambia nada del que se deja**.

### FR7 — La superficie de pads sigue al Track seleccionado

Al cambiar de Track, la superficie se recalcula con el marco tonal de ese Track.
El desplazamiento de octava es del Track, no de la app: volver a un Track lo
devuelve donde estaba.

### FR8 — El transporte arranca y para los dieciséis

Play emite todos los Tracks con material; Stop los para a todos, sin notas
colgadas.

### FR9 — La pantalla dice qué Track está seleccionado y qué tiene dentro

Lo mínimo para operar: qué Track está seleccionado, cuáles tienen material y el
estado del seleccionado —lo que ya se muestra hoy: anillo, parámetros, pool,
octava de pads— más su canal, editable.

### FR10 — Lo entregado sigue en pie

Transporte, anillo, playhead, valor transitorio, pool tonal, Scale y Root, los
nueve parámetros, el preset del BeatStep Pro y la selección de dispositivo siguen
funcionando sobre el Track seleccionado. Sin controlador conectado, todo se ve y
no se edita.

## Non-Functional Requirements

- **NFR1 — El camino de tiempo real no admite regresión.** Ninguna asignación,
  lock, `await` ni logging nuevos en el hilo del scheduler. El snapshot de
  dieciséis Tracks se copia con `memcpy`, y el test de trivialidad se extiende al
  tipo nuevo.
- **NFR2 — Medición de jitter obligatoria, con los dieciséis sonando.** Es el
  peor caso realista: dieciséis Tracks con material, en la división más rápida y
  el tempo más alto de las mediciones anteriores. Umbral: máximo < 2 ms, σ < 0,5
  ms. **Una regresión bloquea la rebanada** — es el riesgo que la v1 existió para
  acotar.
- **NFR3 — El coste crece de forma acotada.** El trabajo por ventana crece con el
  número de Tracks con material, no con dieciséis siempre: un Track vacío no
  programa nada.
- **NFR4 — El aleatorio sigue siendo reproducible.** Misma semilla, misma
  secuencia, por Track. Dos Tracks con la misma Probability no omiten los mismos
  Pulses.
- **NFR5 — Cobertura:** `Engine` ≥90%, `MIDI` ≥80%.
- **NFR6 — Vocabulario de la Pre Spec.** `Track`, `Pattern`, `pool`, `Scale`,
  `Root`. Sin sinónimos nuevos para lo que ya tiene nombre.
- **NFR7 — Verificación en dispositivo.** Con el BeatStep Pro y varios
  instrumentos o un multitímbrico: se selecciona un Track con un step button, se
  le da material y suena por su canal sin tocar a los demás.

## Acceptance Criteria

**Criterio principal:**

> Dieciséis Tracks con material propio suenan a la vez sobre un solo reloj, cada
> uno por su canal y con su ritmo, su groove y su tonalidad; los step buttons
> cambian cuál se edita sin tocar lo que los otros tienen dentro; y el jitter con
> los dieciséis sonando sigue dentro del umbral, medido en iPad.

Además:

- [ ] El snapshot de dieciséis Tracks es trivial, comprobado con `_isPOD`.
- [ ] Al arrancar, solo el Track 1 tiene material y la app suena como antes.
- [ ] Cambiar un parámetro de un Track no altera ninguno de los otros quince,
      comprobado sobre los nueve parámetros, el pool y el marco tonal.
- [ ] Dos Tracks con Divisions distintas caen en fase sobre el mismo origen.
- [ ] Dos Tracks con la misma Probability y semillas distintas no omiten los
      mismos Pulses.
- [ ] El Track N emite por el canal N; cambiado el canal, emite por el nuevo.
- [ ] Los dieciséis step buttons seleccionan, y volver a un Track lo encuentra
      como se dejó —incluida la octava de los pads—.
- [ ] Stop no deja notas colgadas con dieciséis Tracks sonando, incluido con
      Delay positivo.
- [ ] **Jitter con los dieciséis sonando dentro del umbral**, medido en iPad y
      registrado con su número.
- [ ] `swift test` sobre `Engine` y `MIDI` pasa sin simulador ni hardware.

## Known Limitations

1. **Sin Patterns ni Banks.** Los dieciséis Tracks son un Pattern implícito y no
   hay forma de tener otro, ni de guardarlos: la persistencia sigue sin existir.
2. **Sin mute ni solo.** La pantalla 5 del handoff los lleva; un Track se calla
   vaciando su pool o poniendo Pulses a cero, que no es lo mismo.
3. **La pantalla es de trabajo, no la definitiva.** Los anillos concéntricos y la
   navegación del handoff son la rebanada siguiente.
4. **Sin Cycles.** La variación por pasadas sigue fuera; cada Track tiene un solo
   juego de parámetros.
5. **Dieciséis es el techo, y está escrito.** No hay Tracks dinámicos: el
   snapshot es de tamaño fijo por una razón de tiempo real, no por comodidad.

## Out of Scope

- Patterns, Banks, Project; Autosave, Save Bank y Backup.
- Mute y solo por Track.
- La UI definitiva del handoff: anillos concéntricos, navegación y el explorador
  Track × Pattern.
- Cycles, Note Repeater, Harmony, Voicing/Style, Range/Phrase, LFO y Random
  Modulation.
- MIDI Learn — es la rebanada 8 de la v1 y sigue pendiente.
- Puerto MIDI por Track: se comparte el destino, y solo el canal distingue.
