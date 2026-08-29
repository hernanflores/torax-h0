# Plan — MVP rebanada 5: Groove estático — Velocity, Sustain, Probability

**Track ID:** `mvp-groove-static_20260829`

Sigue la metodología definida en [`workflow.md`](../../workflow.md): tests fallando primero (Red), implementación mínima (Green), refactor, verificación de cobertura y checkpoint de fase. El trabajo va en la rama `feat/mvp-groove-static` y se integra por Pull Request.

**Orden.** Los valores antes que el aleatorio, porque Probability necesita un rango que exista; el aleatorio antes que la emisión, porque el camino de tiempo real no es sitio para descubrir que el PRNG asigna; la emisión antes que la entrada, porque hay que saber que suena antes de poder girarlo; el renombrado antes que la pantalla, porque la pantalla consume el tipo renombrado; y la verificación en dispositivo cierra, porque los tres parámetros son audibles y ninguna suite los puede escuchar.

**Lo que este orden evita.** Las fases 1 y 2 son `Engine` puro y no tocan CoreMIDI, así que no se cruzan con `midi-test-flake_20260826`. La fase 3 sí toca `MIDI`, pero `TrackScheduler` está diseñado precisamente para probarse sin arrancar el hilo —«dejar el relevo de snapshot en un valor al que se le puede dar el horizonte a mano»— así que tampoco debería necesitar el bucle. Si alguna tarea lo necesitara, ver *Notas de riesgo*.

## Phase 1: Los tres parámetros como valores

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
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 2: El aleatorio sembrado

> La deuda que `tech-stack.md` dejó escrita desde el primer commit y que la rebanada 4 aplazó explícitamente. Probability es su primer usuario.

- [ ] Task: PRNG explícito y sembrado
  - [ ] Tests (Red): misma semilla, misma secuencia — literal, sobre una secuencia escrita en el test
  - [ ] Tests (Red): semillas distintas divergen
  - [ ] Tests (Red): la distribución no es degenerada sobre una muestra larga — no se cuelga en un valor ni alterna
  - [ ] Tests (Red): el estado cabe en un entero y avanzar no asigna
  - [ ] Implementación (Green): generador de estado entero, **nunca `Int.random()`**
- [ ] Task: La decisión de omisión
  - [ ] Tests (Red): Probability 100% no omite **ningún** Pulse, con cualquier semilla
  - [ ] Tests (Red): Probability 0% omite **todos**, con cualquier semilla
  - [ ] Tests (Red): un valor intermedio se aproxima a su proporción sobre una muestra larga, con tolerancia declarada
  - [ ] Tests (Red): la decisión es determinista dado el estado del generador — mismo estado, misma respuesta
  - [ ] Implementación (Green): comparación entera contra el umbral; sin coma flotante en el camino que después corre en tiempo real
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 3: Que suene — el camino de emisión

> **La fase que toca el camino de tiempo real.** No mueve ningún note-on: la `MusicalTimeline`, el `LookAheadScheduler` y el `SchedulerThread` no se tocan.

- [ ] Task: La Velocity sale del snapshot
  - [ ] Tests (Red): el note-on lleva la Velocity del Track, no una constante
  - [ ] Tests (Red): el note-off sigue con velocity 0 — es la convención de apagado, no un parámetro
  - [ ] Tests (Red): cambiar la Velocity del snapshot se refleja en la ventana siguiente
  - [ ] Implementación (Green): `NoteEmitter` deja de llevar velocity propia; desaparece la constante que su documentación declaraba provisional
- [ ] Task: El gate sale de Sustain y de la Division
  - [ ] Tests (Red): Sustain 100% da un gate de **exactamente una Division**, comparado contra `MusicalTimeline` y no contra un número escrito a mano
  - [ ] Tests (Red): 1% da el extremo percusivo; 200% dura dos Divisions
  - [ ] Tests (Red): el gate se expresa como offset de timestamp y el note-off sigue viajando sellado en la misma entrega que su note-on
  - [ ] Tests (Red): **el test guardián de los 25 ms se retira con su constante**, y se documenta por qué deja de aplicar: el límite era «que quepa en el Step más corto», y con Sustain el solape es una elección del usuario
  - [ ] Implementación (Green): el gate se deriva de la duración del Step vigente
- [ ] Task: Probability decide en el scheduler, con el PRNG dentro
  - [ ] Tests (Red): el PRNG vive en `TrackScheduler` y se siembra al construirlo — dos schedulers recién construidos omiten igual
  - [ ] Tests (Red): dos vueltas consecutivas del anillo **no** omiten los mismos Pulses
  - [ ] Tests (Red): un Pulse omitido no emite **nada** — ni note-on huérfano ni note-off suelto
  - [ ] Tests (Red): **omitir no descoloca el arpegio** — la altura de cada Step es la misma con Probability 100% y con Probability 50%
  - [ ] Tests (Red): el snapshot se sigue recogiendo una vez por ventana, nunca a mitad
  - [ ] Tests (Red): el modo `everyStep` del arnés de medición no pasa por Probability — mide la rejilla, no el material
  - [ ] Implementación (Green): la omisión se decide donde ya se decide si el Step dispara; sin asignaciones, sin locks, con marcador `/// Realtime:`
- [ ] Task: Verificar cobertura — `Engine` ≥90%, `MIDI` ≥80%
  - [ ] `MIDI` se mide en **un solo proceso**, según la nota del 2026-08-28 de `workflow.md`
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 4: Un solo nombre para lo ajustable

> Renombrado con casos nuevos. **El comportamiento existente no cambia**, y los tests de Shape lo demuestran sin reescribirse.

- [ ] Task: `ShapeParameter` → `TrackParameter`
  - [ ] Tests (Red): los siete casos, con los términos de la Pre Spec en inglés y sin traducir
  - [ ] Tests (Red): los tests de Shape existentes siguen pasando contra el tipo nuevo
  - [ ] Implementación (Green): un enum que nombra todo lo ajustable del Track; el ajuste por delta despacha a Shape o a Groove según el caso
- [ ] Task: `ShapeChange` → `ParameterChange`
  - [ ] Tests (Red): compara dos **Tracks**, no dos Shapes — Groove vive en `Track`, así que la comparación sube un nivel
  - [ ] Tests (Red): sigue anunciando solo el primero que difiera, y `nil` cuando no se movió nada
  - [ ] Tests (Red): los tres nuevos producen su descripción legible (`Velocity 100`, `Sustain 100%`, `Probability 75%`)
  - [ ] Tests (Red): los casos de Shape ya cubiertos dan exactamente la misma descripción que antes
  - [ ] Implementación (Green): el orden de comparación se declara, no se hereda del azar
- [ ] Task: El mapeo cubre los siete
  - [ ] Tests (Red): los tres CC nuevos —74, 75, 76— resuelven a su parámetro y no pisan a los cuatro existentes
  - [ ] Tests (Red): un CC sin asignar se sigue ignorando en silencio, que no es un error
  - [ ] Implementación (Green): `ControlMapping` pasa a estar tecleado por `TrackParameter`, con un solo diccionario
- [ ] Task: Los giros de Groove publican
  - [ ] Tests (Red): girar cada uno de los tres publica un Track nuevo
  - [ ] Tests (Red): girar contra un extremo **no** publica — el valor ya estaba ahí
  - [ ] Tests (Red): girar un parámetro de Groove **conserva el Shape y el pool**, y al revés — la regla de destructividad de `product-guidelines.md`
  - [ ] Implementación (Green): `ControlInput` aplica el delta al parámetro que le toca, sea de la familia que sea
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 5: La pantalla

> `App` no se mide (`workflow.md`): si algo aquí merece un test, está en el sitio equivocado. Todo lo que tiene lógica ya quedó en `Engine` en las fases anteriores.

- [ ] Task: El acento cromático de la familia Groove
  - [ ] Se declara junto al de Shape y el de Tonal, no suelto en la vista
  - [ ] El color codifica **qué tipo de parámetro es**, nunca es decorativo (`product-guidelines.md`)
- [ ] Task: Los tres se leen en el estado persistente
  - [ ] Formato preciso y no conversacional, con los términos de la Pre Spec
  - [ ] La descripción vive en `Engine`, como ya vive la de Shape
- [ ] Task: El valor grande transitorio cubre los siete
  - [ ] Girar cualquiera de los tres lo levanta, con el mismo desvanecimiento por inactividad
  - [ ] **El anillo permanece visible debajo y nunca se oculta** — «nunca se sustituye el contexto por el detalle»
- [ ] Task: Verificación en simulador
  - [ ] Captura de pantalla con los tres parámetros presentes y el acento aplicado
  - [ ] Contraste sobre fondo oscuro, legible como el resto — es como se encontró que las posiciones vacías del anillo desaparecían contra el panel
  - [ ] Se registra la limitación: el simulador no tiene MIDI, así que no se ve el transporte ni un giro real
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 6: Verificación en dispositivo

> **Requiere iPad, BeatStep Pro y un sintetizador.** Los tres parámetros son audibles y ninguna suite los puede escuchar.

- [ ] Task: Los encoders en `Relative #2` antes de empezar
  - [ ] Sin eso, un clic se decodifica como ±63 y todo salta a su extremo — nota del 2026-08-28 en `workflow.md`
- [ ] Task: Escuchar los tres
  - [ ] **Velocity:** girar cambia la dinámica de forma audible y proporcional, sin saltos
  - [ ] **Sustain:** el recorrido va de percusivo a ligado; al 100% la nota dura un Step
  - [ ] **Probability:** bajar perfora la línea; **el arpegio conserva su fase**, no se ralentiza
  - [ ] Los tres se oyen dentro del Step siguiente al giro
  - [ ] Volver a pulsar Play reproduce la misma secuencia de omisiones
  - [ ] La limitación 1 se observa a propósito: pool de una nota y Sustain 200%, para ver el corte y confirmar que es el síntoma previsto y no otro
- [ ] Task: Lo entregado sigue en pie
  - [ ] Transporte, anillo, playhead, pool, Scale y Root siguen funcionando
  - [ ] Sin controlador conectado: los tres se leen pero no se editan; Scale y Root sí, que son configuración
- [ ] Task: Cobertura final y Pull Request
  - [ ] `Engine` ≥90% y `MIDI` ≥80%, esta última medida en un solo proceso
  - [ ] Si la CI falla con `clientCreationFailed(-50)`, correr la suite 3–4 veces y comparar contra `main` antes de atribuirlo al cambio
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

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
