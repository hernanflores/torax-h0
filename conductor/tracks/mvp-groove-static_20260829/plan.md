# Plan — MVP rebanada 5: Groove estático — Velocity, Sustain, Probability

**Track ID:** `mvp-groove-static_20260829`

Sigue la metodología definida en [`workflow.md`](../../workflow.md): tests fallando primero (Red), implementación mínima (Green), refactor, verificación de cobertura y checkpoint de fase. El trabajo va en la rama `feat/mvp-groove-static` y se integra por Pull Request.

**Orden.** Los valores antes que el aleatorio, porque Probability necesita un rango que exista; el aleatorio antes que la emisión, porque el camino de tiempo real no es sitio para descubrir que el PRNG asigna; la emisión antes que la entrada, porque hay que saber que suena antes de poder girarlo; el renombrado antes que la pantalla, porque la pantalla consume el tipo renombrado; y la verificación en dispositivo cierra, porque los tres parámetros son audibles y ninguna suite los puede escuchar.

**Lo que este orden evita.** Las fases 1 y 2 son `Engine` puro y no tocan CoreMIDI, así que no se cruzan con `midi-test-flake_20260826`. La fase 3 sí toca `MIDI`, pero `TrackScheduler` está diseñado precisamente para probarse sin arrancar el hilo —«dejar el relevo de snapshot en un valor al que se le puede dar el horizonte a mano»— así que tampoco debería necesitar el bucle. Si alguna tarea lo necesitara, ver *Notas de riesgo*.

## Phase 1: Los tres parámetros como valores [checkpoint: c422e17]

> `Engine` puro. Sin CoreMIDI, sin simulador, sin hardware.

- [x] Task: Documentar las dos desviaciones **antes** de implementar (paso 8 del Task Workflow) — `2407da8`
  - [x] Nota fechada en `tech-stack.md`: Probability es unipolar en v1 porque no existen Repeats, y toda nota es un Pulse; la mitad counter-clockwise vuelve con ellos
  - [x] Nota fechada en `tech-stack.md`: «repetible en loop» se precisa a «repetible por arranque» — el PRNG avanza por Pulse, así que la secuencia varía entre vueltas y es la resiembra al pulsar Play la que la hace reproducible
  - [x] Ninguna de las dos se descubre a posteriori: se escriben con la razón, no solo con la regla
- [x] Task: `Velocity`, `Sustain` y `Probability` como tipos validados — `13e0b64`
  - [x] Tests (Red): `Velocity` admite 1–127 y rechaza 0 y 128 — el 0 es note-off en MIDI 1.0, no un nivel dinámico
  - [x] Tests (Red): `Sustain` admite 1–200 y rechaza 0 y 201; su default es 100
  - [x] Tests (Red): `Probability` admite 0–100; **los dos extremos son válidos**, no casos límite a rechazar
  - [x] Tests (Red): los defaults de producto son Velocity 100, Sustain 100%, Probability 100%
  - [x] Implementación (Green): validación en el inicializador y vía `init(unchecked:)` interna, mismo idioma que `Steps` y `Division`
- [x] Task: `Groove` agrupa los tres y entra en `Track` — `632ea4a`
  - [x] Tests (Red): **`_isPOD(Groove.self)` y `_isPOD(Track.self)`** — el test que ya existe en `TrackHandoffTests` no se relaja ni se mueve
  - [x] Tests (Red): `Track` construido sin Groove toma el default de producto, para que ningún llamante existente cambie
  - [x] Tests (Red): el pool y el Shape sobreviven a construir un Track con otro Groove
  - [x] Implementación (Green): `Groove` como valor trivial; `Track` gana el campo y `TrackHandoff` sigue publicándolo sin cambio de protocolo
- [x] Task: Ajuste por delta, con freno en los extremos — `c422e17`
  - [x] Tests (Red): cada uno de los tres se frena en su extremo superior e inferior — no envuelven, como `Steps` y `Division` y a diferencia de `Rotate`
  - [x] Tests (Red): girar contra un extremo devuelve el mismo valor, que es lo que después permite no publicar
  - [x] Implementación (Green): acotado, no envoltura
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 2: El aleatorio sembrado [checkpoint: 76780fc]

> La deuda que `tech-stack.md` dejó escrita desde el primer commit y que la rebanada 4 aplazó explícitamente. Probability es su primer usuario.

- [x] Task: PRNG explícito y sembrado — `379b936`
  - [x] Tests (Red): misma semilla, misma secuencia — literal, sobre una secuencia escrita en el test
  - [x] Tests (Red): semillas distintas divergen
  - [x] Tests (Red): la distribución no es degenerada sobre una muestra larga — no se cuelga en un valor ni alterna
  - [x] Tests (Red): el estado cabe en un entero y avanzar no asigna
  - [x] Implementación (Green): generador de estado entero, **nunca `Int.random()`**
- [x] Task: La decisión de omisión — `76780fc`
  - [x] Tests (Red): Probability 100% no omite **ningún** Pulse, con cualquier semilla
  - [x] Tests (Red): Probability 0% omite **todos**, con cualquier semilla
  - [x] Tests (Red): un valor intermedio se aproxima a su proporción sobre una muestra larga, con tolerancia declarada
  - [x] Tests (Red): la decisión es determinista dado el estado del generador — mismo estado, misma respuesta
  - [x] Implementación (Green): comparación entera contra el umbral; sin coma flotante en el camino que después corre en tiempo real
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 3: Que suene — el camino de emisión [checkpoint: ebc0946]

> **La fase que toca el camino de tiempo real.** No mueve ningún note-on: la `MusicalTimeline`, el `LookAheadScheduler` y el `SchedulerThread` no se tocan.

- [x] Task: La Velocity sale del snapshot — `f0b6773`
  - [x] Tests (Red): el note-on lleva la Velocity del Track, no una constante
  - [x] Tests (Red): el note-off sigue con velocity 0 — es la convención de apagado, no un parámetro
  - [x] Tests (Red): cambiar la Velocity del snapshot se refleja en la ventana siguiente
  - [x] Implementación (Green): `NoteEmitter` deja de llevar velocity propia; desaparece la constante que su documentación declaraba provisional
- [x] Task: El gate sale de Sustain y de la Division — `9e96548`
  - [x] Tests (Red): Sustain 100% da un gate de **exactamente una Division**, comparado contra `MusicalTimeline` y no contra un número escrito a mano
  - [x] Tests (Red): 1% da el extremo percusivo; 200% dura dos Divisions
  - [x] Tests (Red): el gate se expresa como offset de timestamp y el note-off sigue viajando sellado en la misma entrega que su note-on
  - [x] Tests (Red): **el test guardián de los 25 ms se retira con su constante**, y se documenta por qué deja de aplicar: el límite era «que quepa en el Step más corto», y con Sustain el solape es una elección del usuario
  - [x] Implementación (Green): el gate se deriva de la duración del Step vigente
  - [x] **Añadido en curso:** `stop()` manda All Notes Off además del barrido del pool — el hueco que el propio `Transport` dejó anotado «cuando Sustain permita gates largos» se vuelve audible en esta tarea (24 s con Sustain 200% sobre 1/1 a 20 BPM). Decidido con el usuario el 2026-08-29.

- [x] Task: Probability decide en el scheduler, con el PRNG dentro — `9b3d88e`
  - [x] Tests (Red): el PRNG vive en `TrackScheduler` y se siembra al construirlo — dos schedulers recién construidos omiten igual
  - [x] Tests (Red): dos vueltas consecutivas del anillo **no** omiten los mismos Pulses
  - [x] Tests (Red): un Pulse omitido no emite **nada** — ni note-on huérfano ni note-off suelto
  - [x] Tests (Red): **omitir no descoloca el arpegio** — la altura de cada Step es la misma con Probability 100% y con Probability 50%
  - [x] Tests (Red): el snapshot se sigue recogiendo una vez por ventana, nunca a mitad
  - [x] Tests (Red): el modo `everyStep` del arnés de medición no pasa por Probability — mide la rejilla, no el material
  - [x] Implementación (Green): la omisión se decide donde ya se decide si el Step dispara; sin asignaciones, sin locks, con marcador `/// Realtime:`
- [x] Task: `Division` llega a 1/32 — `ebc0946` — *añadida el 2026-08-29, en el checkpoint de la Fase 1*
  - [x] Tests (Red): `Division.ordered` incluye 1/32 y el knob llega hasta ella desde 1/16
  - [x] Tests (Red): a 300 BPM un Step de 1/32 dura 25 ms, y con Sustain 100% el gate dura exactamente eso — el solape empieza por encima del 100%, no por debajo
  - [x] Implementación (Green): un valor más en la lista; el tipo ya admitía cualquier fracción positiva
  - [x] Se reescribe la nota de `Division.ordered` que explicaba por qué se cortaba en 1/16: **la condición que la ponía —«cuando Sustain sustituya al gate»— se cumple en esta fase**, y dejarla en pie diría algo falso
- [x] Task: Verificar cobertura — `Engine` ≥90% (97,38%), `MIDI` ≥80% (87,21%)
  - [x] `MIDI` se mide en **un solo proceso**, según la nota del 2026-08-28 de `workflow.md`
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 4: Un solo nombre para lo ajustable [checkpoint: d4c4021]

> Renombrado con casos nuevos. **El comportamiento existente no cambia**, y los tests de Shape lo demuestran sin reescribirse.

- [x] Task: `ShapeParameter` → `TrackParameter` — `d4c4021`
  - [x] Tests (Red): los siete casos, con los términos de la Pre Spec en inglés y sin traducir
  - [x] Tests (Red): los tests de Shape existentes siguen pasando contra el tipo nuevo
  - [x] Implementación (Green): un enum que nombra todo lo ajustable del Track; el ajuste por delta despacha a Shape o a Groove según el caso
- [x] Task: `ShapeChange` → `ParameterChange` — `d4c4021`
  - [x] Tests (Red): compara dos **Tracks**, no dos Shapes — Groove vive en `Track`, así que la comparación sube un nivel
  - [x] Tests (Red): sigue anunciando solo el primero que difiera, y `nil` cuando no se movió nada
  - [x] Tests (Red): los tres nuevos producen su descripción legible (`Velocity 100`, `Sustain 100%`, `Probability 75%`)
  - [x] Tests (Red): los casos de Shape ya cubiertos dan exactamente la misma descripción que antes
  - [x] Implementación (Green): el orden de comparación se declara, no se hereda del azar
- [x] Task: El mapeo cubre los siete — `d4c4021`
  - [x] Tests (Red): los tres CC nuevos —74, 75, 76— resuelven a su parámetro y no pisan a los cuatro existentes
  - [x] Tests (Red): un CC sin asignar se sigue ignorando en silencio, que no es un error
  - [x] Implementación (Green): `ControlMapping` pasa a estar tecleado por `TrackParameter`, con un solo diccionario
- [x] Task: Los giros de Groove publican — `d4c4021`
  - [x] Tests (Red): girar cada uno de los tres publica un Track nuevo
  - [x] Tests (Red): girar contra un extremo **no** publica — el valor ya estaba ahí
  - [x] Tests (Red): girar un parámetro de Groove **conserva el Shape y el pool**, y al revés — la regla de destructividad de `product-guidelines.md`
  - [x] Implementación (Green): `ControlInput` aplica el delta al parámetro que le toca, sea de la familia que sea

  > **Las cuatro comparten SHA.** No se pueden separar: renombrar el enum rompe
  > el mapeo, y el mapeo sin los giros no mueve nada. Partirlo daría commits que
  > no compilan.

  > **El criterio de la fase estuvo a punto de romperse.** Llegué a borrar
  > `ShapeParameterTests` y `ShapeChangeTests` dándolos por sustituidos por los
  > nuevos. No lo estaban: se habría perdido el exhaustivo sobre parámetros ×
  > deltas y el de Division como valor musical. Restaurados y adaptados solo en
  > el nombre del tipo y el nivel de comparación; ninguna aserción cambió.

- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 5: La pantalla [checkpoint: ce06a44]

> `App` no se mide (`workflow.md`): si algo aquí merece un test, está en el sitio equivocado. Todo lo que tiene lógica ya quedó en `Engine` en las fases anteriores.

- [x] Task: El acento cromático de la familia Groove — `ce06a44`
  - [x] Se declara junto al de Shape y el de Tonal, no suelto en la vista
  - [x] El color codifica **qué tipo de parámetro es**, nunca es decorativo (`product-guidelines.md`)
- [x] Task: Los tres se leen en el estado persistente — `ce06a44`
  - [x] Formato preciso y no conversacional, con los términos de la Pre Spec
  - [x] La descripción vive en `Engine`, como ya vive la de Shape
- [x] Task: El valor grande transitorio cubre los siete — `ce06a44`
  - [x] Girar cualquiera de los tres lo levanta, con el mismo desvanecimiento por inactividad
  - [x] **El anillo permanece visible debajo y nunca se oculta** — «nunca se sustituye el contexto por el detalle»
- [x] Task: Verificación en simulador — `ce06a44`
  - [x] Captura de pantalla con los tres parámetros presentes y el acento aplicado
  - [x] Contraste sobre fondo oscuro, legible como el resto — es como se encontró que las posiciones vacías del anillo desaparecían contra el panel
  - [x] Se registra la limitación: el simulador no tiene MIDI, así que no se ve el transporte ni un giro real

  > **Las cuatro comparten SHA:** el acento sin quien lo use sería un color
  > suelto, que es lo que `product-guidelines.md` dice que el color no es.

  > **Captura:** [`simulator-groove.png`](./simulator-groove.png). Las tres
  > familias conviven y se distinguen por tono sobre el fondo oscuro.

- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 6: Verificación en dispositivo [checkpoint: PLACEHOLDER]

> **Guía de ejecución:** [`device-verification.md`](./device-verification.md) —
> ocho bloques de comprobación, la configuración previa que explica la mayoría
> de los síntomas raros, y los dos casos a provocar a propósito.

> **Requiere iPad, BeatStep Pro y un sintetizador.** Los tres parámetros son audibles y ninguna suite los puede escuchar.

- [x] Task: Los encoders en `Relative #2` antes de empezar
  - [x] Sin eso, un clic se decodifica como ±63 y todo salta a su extremo — nota del 2026-08-28 en `workflow.md`
- [x] Task: Escuchar los tres
  - [x] **Velocity:** girar cambia la dinámica de forma audible y proporcional, sin saltos
  - [x] **Sustain:** el recorrido va de percusivo a ligado; al 100% la nota dura un Step
  - [x] **Probability:** bajar perfora la línea; **el arpegio conserva su fase**, no se ralentiza
  - [x] Los tres se oyen dentro del Step siguiente al giro
  - [x] Volver a pulsar Play reproduce la misma secuencia de omisiones
  - [x] La limitación 1 se observa a propósito: pool de una nota y Sustain 200%, para ver el corte y confirmar que es el síntoma previsto y no otro
- [x] Task: Lo entregado sigue en pie
  - [x] Transporte, anillo, playhead, pool, Scale y Root siguen funcionando
  - [x] Sin controlador conectado: los tres se leen pero no se editan; Scale y Root sí, que son configuración
- [x] Task: Cobertura final y Pull Request
  > **Cobertura medida el 2026-08-29:** `Engine` **97,97%** y `MIDI` **91,54%**
  > de líneas, esta última filtrando `Engine/Sources` del informe — el binario de
  > test de `MIDI` las compila dentro y aparecen a 0% porque las cubre la otra
  > suite. Ampliación añadida a `workflow.md`.
  - [x] `Engine` ≥90% y `MIDI` ≥80%, esta última medida en un solo proceso
  - [x] Si la CI falla con `clientCreationFailed(-50)`, correr la suite 3–4 veces y comparar contra `main` antes de atribuirlo al cambio
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Enmiendas al plan

**2026-08-29, checkpoint de la Fase 1 — `Division` llega a 1/32.** La
documentación de `Division.ordered` cortaba la lista en 1/16 y declaraba la
condición para extenderla: «los valores más rápidos entran cuando Sustain
sustituya al gate, en Groove». Esa condición se cumple en la Fase 3 de este
track. Se añade la tarea ahí, decidida por el usuario en el checkpoint. Sube el
total de la fase de 4 a 5 tareas.

## Notas de riesgo

**El flake de CoreMIDI, y por qué esta rebanada no debería topárselo.**
`midi-test-flake_20260826` es bloqueante desde el 2026-08-28 para cualquier test
que arranque el bucle del scheduler. Las fases 1, 2 y 4 son `Engine` puro o
lógica de entrada; la 3 toca `MIDI` pero `TrackScheduler` se prueba dándole el
horizonte a mano, sin hilo. **Si alguna tarea de la fase 3 necesitara arrancar el
bucle, se para y se toma el flake antes** — es exactamente lo que la rebanada 6
va a tener que hacer de todos modos.

**El solape es una elección, no un descubrimiento.** El test guardián de los
25 ms se retira a propósito en la fase 3. Que una altura se corte a sí misma con
pool de una nota y Sustain largo está en el spec como limitación 1 y se verifica
en la fase 6 para confirmar que el síntoma observado es ése y no otro.

**El renombrado de la fase 4 toca cuatro sitios y sus tests.** Es mecánico y está
cubierto, pero es la fase donde una regresión silenciosa es más fácil: el criterio
es que los tests de Shape existentes pasen **sin reescribirse**. Si hay que
tocarlos, es que cambió el comportamiento y no solo el nombre.

**Sin medición de jitter, y es una decisión con coste.** `workflow.md` acepta no
medir cuando no se mueve ningún instante, y aquí no se mueve ninguno. El coste es
la atribución: la σ sube de forma monótona —9 → 15 → 20 µs— y si la rebanada 6
mide peor, esta rebanada estará dentro del intervalo sin medir. Se bisecta con el
arnés, que sigue ahí.
