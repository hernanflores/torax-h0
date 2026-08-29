# Spec — MVP rebanada 5: Groove estático — Velocity, Sustain, Probability

**Track ID:** `mvp-groove-static_20260829`
**Track type:** Feature

## Overview

El motor por capas de `product.md` es: **Shape** decide *cuándo* ocurren los
eventos → **Tonal** define *de qué material* se eligen las alturas → **Groove**
convierte la secuencia en interpretación. Shape y Tonal están entregados y
verificados en dispositivo. Esta rebanada abre la tercera capa.

Groove entra partido en dos, y el corte no es por tamaño sino por riesgo.
**Velocity, Sustain y Probability cambian *qué* se envía**; Timing y Delay
cambian *cuándo*, que es el camino de jitter que costó validar. Aislarlos evita
que una regresión de rejilla se lleve por delante a los tres parámetros que no
la tocan. Esta rebanada es la primera mitad.

### Las tres deudas que paga

**1. `NoteEmitter` sigue llevando velocity constante.** Su documentación lo
declara: *«Canal y velocity siguen siendo constantes hasta que llegue Groove».*
Llegó.

**2. El gate es una constante provisional de 25 ms.** Está escrito en el propio
tipo: *«Es una constante provisional, no un valor musical. Sustain es un
parámetro de Groove y está fuera de esta rebanada; cuando llegue, sustituye a
esto y su default es una Division completa (Pre Spec).»* El valor de hoy sale de
una restricción —que quepa en el Step más corto— y no de un criterio musical.

**3. El PRNG sembrado no existe.** `tech-stack.md` lo exige desde el primer
commit —*«El aleatorio es pseudoaleatorio con semilla … PRNG explícito y
sembrado, nunca `Int.random()`»*— y hasta ahora nada lo necesitaba. La rebanada 4
lo dejó anotado explícitamente: *«El PRNG sembrado que `tech-stack.md` exige
llega con Probability, en la rebanada 5.»* Probability es su primer usuario, y
es quien decide dónde vive su estado.

### Once decisiones tomadas antes de planificar

**Sobre los parámetros:**

1. **Velocity vive en 1–127, la unidad MIDI**, default 100. Es lo que viaja por
   el cable: convertir desde un porcentaje metería una pérdida —128 valores no
   caben en 101— y dos escalas para el mismo dato. El 0 se excluye porque en
   MIDI 1.0 equivale a note-off.
2. **Sustain se expresa como % de la Division**: 1–200%, default 100%, que es la
   *«Division completa»* de la Pre Spec. El 1% da el extremo percusivo; el 200%
   liga sobre el Step siguiente sin alcanzar el tercero, lo que acota el solape a
   un solo vecino.
3. **Probability es unipolar 0–100%**, default 100%. La Pre Spec la define
   bipolar —*«clockwise afecta todas las notas; counter-clockwise sólo los
   Pulses»*— pero en v1 no existen Repeats, así que **toda nota es un Pulse** y
   las dos mitades del knob serían indistinguibles. Es una desviación, y se
   documenta fechada en `tech-stack.md`: la mitad counter-clockwise vuelve cuando
   existan Repeats.
4. **El orden es Probability → Velocity y Sustain.** Probability decide si el
   Pulse suena; si suena, los otros dos lo interpretan.

**Sobre el aleatorio:**

5. **El PRNG tiene estado y avanza por Pulse.** La secuencia varía de una vuelta
   del anillo a la siguiente, que es lo que la hace sonar viva en vez de a un
   patrón fijo con huecos fijos.
6. **Repetible significa repetible por arranque, no por vuelta.** Semilla fija:
   cada Play reproduce exactamente la misma secuencia de omisiones. Es una
   precisión de la regla de `tech-stack.md` —que dice *«repetible en loop»*— y se
   documenta fechada, porque con estado mutable por Pulse la repetición por
   vuelta no se cumple y decir lo contrario sería falso.
7. **El estado vive en `TrackScheduler`.** No puede entrar en `Track` sin romper
   `_isPOD(Track.self)`. `TrackScheduler` ya es un valor que solo el hilo del
   scheduler muta, ya recoge el snapshot una vez por ventana y ya decide qué
   Steps se emiten: el PRNG es un `UInt64` más ahí dentro, sin dueño compartido,
   sin lock y sin asignación. La resiembra la dispara el arranque del transporte.
8. **Omitir un Pulse no descoloca el arpegio.** La altura sigue siendo función de
   la posición en el anillo (`pulseOrdinal(atStep:)`, que ya existe y es puro):
   bajar Probability perfora la línea, no la ralentiza. Además no añade ningún
   contador mutable más al camino de tiempo real.

**Sobre la forma del código y de la pantalla:**

9. **Sustain se sella y no se vigila el solape.** Si una altura vuelve a
   dispararse antes de que termine su gate, los dos note-off llegan cuando les
   toca y el primero apaga la nota del segundo. Es una limitación conocida y
   acotada —ver *Known Limitations 1*—, no un defecto a descubrir en
   producción.
10. **`ShapeParameter` y `ShapeChange` se renombran a `TrackParameter` y
    `ParameterChange`**, con los casos de Shape y de Groove dentro. La pantalla y
    el mapeo de CC dejan de saber a qué familia pertenece cada parámetro. Es el
    momento de hacerlo: la rebanada 6 trae dos más y la deuda se pagaría con más
    sitios que tocar.
11. **La pantalla entra entera**: estado persistente de los tres, acento
    cromático de la familia Groove —`product-guidelines.md`: *«Shape, Groove y
    Tonal tienen cada una su acento»*— y valor grande transitorio al girar, que
    hoy solo funciona para Shape.

## Functional Requirements

### FR1 — Velocity fija el nivel dinámico del note-on

Un valor 1–127 por Track, default 100, que sustituye a la constante de
`NoteEmitter`. Todo note-on emitido lleva la Velocity vigente en el snapshot.

La velocity del note-off sigue siendo 0: es la convención de apagado de MIDI 1.0
y no es un parámetro.

### FR2 — Sustain fija la duración de nota

Un porcentaje 1–200% de la Division vigente, default 100%. El gate del note-off
deja de ser la constante de 25 ms y pasa a derivarse de la duración del Step y
del Sustain.

La duración se expresa **como offset de timestamp**, nunca como sleep ni retardo
de hilo (`tech-stack.md`). El note-off sigue viajando sellado en la misma
entrega que su note-on.

### FR3 — Probability omite Pulses

Un porcentaje 0–100%, default 100%. Con 100% suenan todos los Pulses; con 0% no
suena ninguno, y ninguno de los dos extremos es un error. Los valores intermedios
omiten Pulses de forma pseudoaleatoria.

Unipolar en v1, por la ausencia de Repeats. Ver la decisión 3.

### FR4 — El aleatorio es sembrado y repetible por arranque

La secuencia de omisiones sale de un PRNG explícito y sembrado, nunca de
`Int.random()`. Con la misma semilla y el mismo Probability, dos arranques del
transporte producen **exactamente la misma secuencia de omisiones**.

Dentro de una pasada la secuencia avanza por Pulse, así que dos vueltas
consecutivas del anillo no omiten lo mismo.

### FR5 — Omitir no descoloca el material tonal

La altura que le toca a un Step no depende de cuántos Pulses anteriores sonaron.
Bajar Probability deja huecos en la línea; no cambia qué altura ocupa cada
posición.

### FR6 — Los tres se ajustan con knobs

Velocity, Sustain y Probability son parámetros generativos, así que van del lado
del knob: `product-guidelines.md` lo pone por escrito y prohíbe explícitamente
«parámetros generativos que solo existan en pantalla y no sean mapeables a un
knob».

Cada uno se frena en sus extremos, como Steps y Division: son escalas con
principio y fin, y envolver convertiría un ajuste fino en un salto brutal.

### FR7 — Un solo tipo nombra lo ajustable del Track

`TrackParameter` sustituye a `ShapeParameter` y `ParameterChange` a
`ShapeChange`, cubriendo los siete parámetros de hoy. El mapeo de CC y el valor
transitorio dejan de estar acoplados a la familia Shape.

El comportamiento existente no cambia: es un renombrado con casos nuevos, y los
tests de Shape siguen verdes sin reescribirse.

### FR8 — Los tres se ven en pantalla

Se leen en el estado persistente, con el acento cromático de la familia Groove
declarado en el mismo sitio que el de Shape y el de Tonal. Girar cualquiera de
los tres produce el valor grande transitorio, con el anillo siempre visible
debajo.

### FR9 — El camino de tiempo real no engorda

`Track` sigue siendo trivial: Groove es un valor POD dentro del snapshot y
`_isPOD(Track.self)` sigue en verde. Decidir la omisión, aplicar la Velocity y
calcular el gate no asignan, no toman locks y no esperan.

El estado del PRNG vive en `TrackScheduler`, fuera del snapshot, y solo lo toca
el hilo del scheduler.

### FR10 — Lo entregado sigue en pie

Transporte, anillo, playhead, valor transitorio, pool tonal, Scale y Root,
selección de dispositivo y el estado de solo lectura siguen funcionando. Sin
controlador conectado los tres parámetros nuevos no se editan —son material
generativo— pero se leen.

## Non-Functional Requirements

- **NFR1 — Realtime safety.** La decisión de omisión y el cálculo del gate corren
  en el hilo del scheduler: sin asignaciones, sin locks, sin `await`, sin
  logging. Marcador `/// Realtime:` en todo lo que corra ahí.
- **NFR2 — `Track` sigue siendo trivial.** `_isPOD(Track.self)` sigue en verde
  con Groove dentro. No se relaja el test ni se saca Groove del snapshot para
  esquivarlo.
- **NFR3 — Sin medición de jitter, y por qué.** `workflow.md` exige medir cuando
  cambia **cuándo** cae un evento. Esta rebanada no mueve ningún note-on: la
  `MusicalTimeline`, el `LookAheadScheduler` y el `SchedulerThread` no se tocan,
  y Sustain solo alarga el gate de un note-off que ya viajaba sellado. La
  medición toca en la rebanada 6, con Timing y Delay, que sí desplazan eventos
  respecto a la rejilla.
- **NFR4 — Verificación en dispositivo, sí.** Los tres parámetros son audibles y
  el criterio de cierre es escucharlos con el BeatStep Pro y un sintetizador
  real, no solo verlos en verde.
- **NFR5 — Cobertura:** `Engine` ≥90%, `MIDI` ≥80%.
- **NFR6 — La lógica no vive en `App`.** El rango de cada parámetro, el acotado
  al girar, la decisión de omisión y el cálculo del gate son `Engine`; su
  aplicación al mensaje es `MIDI`. `App` cablea y dibuja.
- **NFR7 — Vocabulario de la Pre Spec.** `Velocity`, `Sustain`, `Probability`,
  `Groove`. Sin sinónimos: no se introduce `gate` ni `length` donde el dominio
  dice `Sustain`, ni `chance` donde dice `Probability`.

## Acceptance Criteria

**Criterio principal:**

> Con el transporte corriendo, girar Velocity cambia la dinámica, girar Sustain
> lleva la línea de percusiva a ligada, y girar Probability la perfora sin
> descolocar el arpegio — los tres audibles en el siguiente Step y sin saltos de
> valor.

Además:

- [ ] Todo note-on emitido lleva la Velocity vigente; el note-off sigue con
      velocity 0.
- [ ] Sustain al 100% da un gate de exactamente una Division, verificado contra
      los valores de `MusicalTimeline`.
- [ ] Los extremos del rango de Sustain se comportan: 1% percusivo, 200% ligado
      sobre el Step siguiente.
- [ ] Probability 100% no omite nada y Probability 0% no emite nada; ninguno de
      los dos es un error.
- [ ] Mismo Probability y misma semilla, dos arranques producen la misma
      secuencia de omisiones.
- [ ] Dos vueltas consecutivas del anillo **no** omiten los mismos Pulses.
- [ ] La altura de un Step no depende de cuántos Pulses anteriores sonaron.
- [ ] `_isPOD(Track.self)` sigue en verde con Groove dentro.
- [ ] Girar cada uno de los tres knobs se frena en sus extremos y publica un
      snapshot; girar contra un extremo no publica nada.
- [ ] `TrackParameter` y `ParameterChange` cubren los siete parámetros, y los
      tests de Shape siguen pasando sin cambio de comportamiento.
- [ ] La pantalla muestra los tres con el acento de Groove, y girar cualquiera
      levanta el valor grande transitorio sin ocultar el anillo.
- [ ] `swift test` sobre `Engine` y `MIDI` pasa sin simulador ni hardware.

## Known Limitations

1. **El solape no se vigila: con pool de una nota y Sustain largo, la línea se
   corta.** El note-off de un pulso llega después del note-on del siguiente y lo
   apaga. Es la consecuencia aceptada de sellar el gate y no rastrear notas
   pendientes; el rango de 200% acota el síntoma a un solo vecino. Si molesta en
   la práctica, el arreglo es adelantar el note-off pendiente justo antes del
   nuevo note-on, y es un cambio local a `NoteEmitter`.
2. **Probability es unipolar.** La mitad counter-clockwise de la Pre Spec vuelve
   cuando existan Repeats y haya notas que no sean Pulses.
3. **Sin los botones 8/16 de desplazamiento de fase** de la secuencia aleatoria
   que la Pre Spec menciona junto a Probability. Necesitan superficie de pads,
   que hoy está ocupada por el pool tonal.
4. **Sin Accent ni forma de Groove.** La variación de velocity alrededor del
   valor base está fuera del MVP por `product.md`, no solo de esta rebanada.
5. **Sin Random Modulation.** El PRNG que entra aquí es de Probability; cablearlo
   a otros destinos es trabajo posterior a v1.
6. **Sin persistencia.** Los tres valores se pierden al cerrar la app, como todo
   lo demás hasta que exista Autosave.
7. **El mapeo de los CC es fijo y provisional**, como el de Shape. MIDI Learn
   llega en la rebanada 7.

## Documented Deviations

Dos notas fechadas en `tech-stack.md`, escritas **antes** de implementar, según
el paso 8 del Task Workflow:

1. **Probability unipolar en v1**, con la razón —no existen Repeats— y la
   condición de vuelta.
2. **«Repetible en loop» se precisa a «repetible por arranque»**, con la razón:
   el PRNG avanza por Pulse, así que la secuencia varía entre vueltas y solo la
   resiembra al pulsar Play la hace reproducible.

## Out of Scope

- Timing y Delay — rebanada 6, y con ellos la medición de jitter.
- Accent y la forma/LFO de la variación de velocity.
- Repeats, Time, Ramp y Pace (Note Repeater).
- La mitad counter-clockwise de Probability y los botones de fase 8/16.
- Random Modulation, LFO y Cycles.
- Recorrido aleatorio del pool — el PRNG queda disponible, pero Style sigue
  fuera de v1.
- Preset del BeatStep Pro y MIDI Learn — rebanada 7.
- Persistencia, Autosave y Backup Project.
- Múltiples Tracks, Patterns y Banks.
