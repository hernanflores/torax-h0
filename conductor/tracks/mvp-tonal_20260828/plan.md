# Plan — MVP rebanada 4: Tonal — pool, Scale y Root

**Track ID:** `mvp-tonal_20260828`

Sigue la metodología definida en [`workflow.md`](../../workflow.md): tests fallando primero (Red), implementación mínima (Green), refactor, verificación de cobertura y checkpoint de fase. El trabajo va en rama y se integra por Pull Request.

**Orden:** el marco tonal antes que el pool, porque el pool solo tiene sentido dentro de un marco; el pool antes que la emisión, porque hay que saber qué se guarda antes de decidir cómo se lee; y la emisión antes que la entrada y la pantalla, que son las dos superficies que lo usan. La verificación en dispositivo cierra, porque esta rebanada vuelve a tocar el camino de tiempo real.

## Phase 1: El marco tonal [checkpoint: a666348]

> `Engine` puro. Sin CoreMIDI, sin simulador, sin hardware.

- [x] Task: `Scale` y `Root` — `a666348`
  - [x] Tests (Red): cada preset —Minor, Major, Dorian, Phrygian, Pentatonic— produce su conjunto de intervalos, escritos literalmente en el test
  - [x] Tests (Red): `Root` transpone el conjunto entero sin cambiar su forma
  - [x] Tests (Red): recorrer las escalas hacia arriba y hacia abajo se detiene en los extremos, como ya hace `Division`
  - [x] Implementación (Green): conjuntos preset, no escalas de usuario
- [x] Task: Qué alturas permite el marco — `a666348`
  - [x] Tests (Red): una altura está o no en el marco, para toda combinación de Scale y Root — invariante exhaustiva sobre 5 escalas × 12 Roots × 128 alturas
  - [x] Tests (Red): la nota permitida **más cercana**; el desempate baja, fijado sobre las 60 combinaciones
  - [x] Implementación (Green): máscara de doce bits, sin asignar — como `EuclideanRhythm`

  > Las dos tareas comparten SHA: son un solo fichero y un solo concepto. `Scale`
  > sin saber qué alturas permite no lo puede usar nadie.

  > **Decisión que la Pre Spec deja abierta.** Nombra «Pentatonic» sin decir
  > cuál, y la lista ya trae Major y Minor completas. Se elige la **menor**
  > (0-3-5-7-10). Documentado en el código con nota fechada.

- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 2: El pool, sin romper la trivialidad de `Track` [checkpoint: a773d90]

> **La fase con la restricción dura.** `tech-stack.md` lo dejó escrito antes de
> que hiciera falta: almacenamiento inline de ocho huecos, no un `Array`.

- [x] Task: Almacenamiento inline de ocho pitches — `a773d90`
  - [x] Tests (Red): **`_isPOD` sobre el pool y sobre `Track`** — el test que ya existe en `TrackHandoffTests` no se relajó ni se movió
  - [x] Tests (Red): insertar, quitar y consultar; de cero a ocho notas
  - [x] Tests (Red): insertar una altura ya presente no la duplica ni crece el pool
  - [x] Tests (Red): el pool lleno rechaza la novena sin destruir las ocho
  - [x] Implementación (Green): ocho huecos de ocho bits en un `UInt64`, con `0xFF` como hueco vacío — el rango MIDI son siete bits y sobra el centinela
- [x] Task: El pool vive en `Track` — `a773d90`
  - [x] Tests (Red): `_isPOD(Track.self)` sigue en verde con el pool dentro, en `Engine` y en `MIDI`
  - [x] Tests (Red): un pool vacío es un estado válido, no un `nil` ni un error
  - [x] Implementación (Green): `Track` gana el pool; `TrackHandoff` sigue publicándolo sin cambios de protocolo
- [x] Task: Reencuadre no destructivo — `a773d90`
  - [x] Tests (Red): cambiar Scale reubica las notas fuera de marco y conserva el pool
  - [x] Tests (Red): cambiar Root hace lo mismo
  - [x] Tests (Red): invariante — tras cualquier reencuadre, ninguna nota queda fuera del marco (5 escalas × 12 Roots)
  - [x] Tests (Red): si dos notas caen en la misma tras reencuadrar, el pool encoge en vez de duplicar
  - [x] Implementación (Green): la regla de destructividad de `product-guidelines.md`, la misma que rige a `Pulses`

  > **La restricción dura no obligó a rediseñar nada.** El riesgo anotado en el
  > plan —que el pool inline no cupiera en `Track` sin romper `_isPOD`— no se
  > materializó: ocho alturas de siete bits caben en un `UInt64` con centinela
  > de sobra, y el test pasó a la primera.

  > Las tres tareas comparten SHA: el pool sin reencuadre publicaría un tipo que
  > viola la regla de destructividad en cuanto alguien cambie la Scale.

- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 3: Del pool a la nota que suena [checkpoint: e91688a]

> Aquí se toca el camino de tiempo real. Es el único sitio de la rebanada donde
> una regresión de jitter es posible.

- [x] Task: El recorrido del pool, como valor — `2365241`
  - [x] Tests (Red): cada Pulse toma la siguiente altura y vuelve al principio al agotar el pool
  - [x] Tests (Red): determinismo — mismo pool y mismo Pulse, misma altura
  - [x] Tests (Red): un pool de una nota da un centro estable; uno vacío no da ninguna
  - [x] Implementación (Green): `PoolTraversal`, tipo de un solo caso como `RelativeEncoding`

  > **El ordinal del Pulse se deriva, no se acumula.** `EuclideanRhythm.pulseOrdinal`
  > cuenta bits encendidos por debajo de la posición más las vueltas completas.
  > Es la disciplina de `MusicalTimeline`: un contador que avanzara solo
  > derivaría al descartarse una lectura del snapshot, y esa deriva no se vería
  > hasta oírla. Sigue contando al dar la vuelta, que es lo que hace que un pool
  > de tres sobre un anillo de ocho no repita la misma altura en la misma
  > posición.

- [x] Task: `NoteEmitter` deja de llevar una altura fija — `e91688a`
  - [x] Tests (Red): emitir con la altura que le pasan, en note-on y en su note-off
  - [x] Tests (Red): sin altura no se emite nada — ni note-on huérfano ni note-off suelto
  - [x] Implementación (Green): la altura entra por parámetro; canal y velocity siguen constantes hasta Groove
  - [x] **Revisión explícita registrada:** elegir la altura es aritmética sobre enteros y una consulta a un `UInt64`; emitir no cambió de forma. Sin asignaciones, sin locks, sin `await` (`NFR1`)

  > **Dos cosas que la fase destapó y no estaban en el plan.**
  >
  > **Parar tiene que apagar todo el pool, no una nota.** Con una altura fija
  > bastaba con apagarla; ahora cualquiera del pool pudo ser la última en sonar,
  > y saber cuál exigiría que el scheduler publicara algo por cada pulso —
  > trabajo en el camino de tiempo real para resolver un caso de parada. Se
  > apagan todas. Queda un hueco documentado: una altura quitada del pool
  > mientras sonaba no se apaga. Dura lo que el gate (25 ms), así que es
  > inaudible; **cuando Sustain permita gates largos hay que volver a mirarlo.**
  >
  > **Pool vacío significa silencio, y todos los `Track` se construían sin
  > pool.** La app habría arrancado muda. Se le da un pool de una altura —la
  > misma que sonaba antes—, que la Pre Spec llama «centro estable». Abrir la
  > app en silencio es correcto por el modelo, pero la pantalla todavía no
  > explica que hay que pulsar un pad, así que sería un cambio a peor disfrazado
  > de coherencia.

- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 4: Los pads editan el pool [checkpoint: 5105f2d]

- [x] Task: Recepción de notas — `5105f2d`
  - [x] Tests (Red): un note-on alterna la pertenencia de esa altura al pool
  - [x] Tests (Red): el mismo pad dos veces la mete y la saca
  - [x] Tests (Red): una altura fuera del marco tonal se ignora en silencio, no es error
  - [x] Tests (Red): los note-off no alternan; un note-on con velocity cero tampoco
  - [x] Implementación (Green): `ControlInput` entiende notas además de Control Change
  - [x] Revisión: decodificar y publicar siguen en el hilo de control
- [x] Task: El pool publicado se recoge en caliente — `5105f2d`
  - [x] Tests (Red): editar el pool publica un `Track` nuevo por `TrackHandoff`
  - [x] Tests (Red): cambiar Scale o Root reencuadra el pool y publica; si nada cambió, no publica
  - [x] Implementación (Green): el mismo camino que ya usa Shape

  > **Un defecto que la fase destapó.** `ControlInput` reconstruía
  > `Track(shape:)` al girar un knob, y desde que el pool entró en `Track` eso lo
  > **borraba**: mover Pulses habría vaciado el material tonal. Es la
  > destrucción silenciosa que `product-guidelines.md` prohíbe, introducida en la
  > Fase 2 y no detectada hasta aquí. Cubierto ahora en las dos direcciones:
  > girar conserva el pool, y editar el pool conserva el Shape.

- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 5: El pool y el marco en pantalla [checkpoint: f65dce5]

- [x] Task: Acento de la familia Tonal — `f65dce5`
  - [x] Se puebla el token que la rebanada 3 dejó preparado, en el mismo sitio. Groove sigue sin poblar: sigue sin parámetros
- [x] Task: El pool, sin sugerir una nota por paso — `f65dce5`
  - [x] Implementación: las alturas del pool con su octava, y el marco vigente
  - [x] **No se conecta con el anillo ni se muestra qué sonó en cada Step** — la vista no sabe que el anillo existe
  - [x] Revisión: es una representación paralela y separada, no una capa sobre el anillo
  - [x] `Pitch.description` vive en `Engine`, con tests: ninguna altura sin nombre, ninguna repetida, y el nombre no puede discrepar de `pitchClass`
- [x] Task: Elegir Scale y Root — `f65dce5`
  - [x] Implementación: rejilla de las cinco escalas y las doce clases de altura
  - [x] El cambio reencuadra el pool y se ve al instante
  - [x] Se puede cambiar con el transporte corriendo, sin modal que bloquee
  - [x] Sigue siendo táctil sin controlador: es configuración, no material generativo
  - [~] Verificación de que el reencuadre se ve al cambiar Scale — **pendiente de dispositivo**: el simulador no permite tocar desde la línea de comandos

  > **Desviación del handoff, deliberada.** Su pantalla 2 vive en una navegación
  > de cinco pestañas que no existe: hay un Track, una familia con knobs y
  > ninguna de las otras cuatro pantallas. Construirla ahora sería chrome sin
  > función. Tonal entra como sección de la pantalla única y se moverá cuando
  > haya dónde moverla.

  > **Un desajuste corregido antes de commitear:** la documentación decía que los
  > Roots fuera de la escala no eran elegibles. Es falso — el Root es la
  > fundamental *que transpone* la Scale, así que es él quien decide dónde se
  > apoya el conjunto, y las doce clases son válidas.

- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 6: Verificación en dispositivo

- [ ] Task: Jitter con Tonal activo — **requiere iPad**
  - [ ] Medir con el anillo corriendo y un pool de varias notas
  - [ ] Comparar contra la referencia de la rebanada 3: máx 0,134 ms · σ 0,020 ms
  - [ ] **Registrar el número, cumpla o no**
  - [ ] Si se degrada, el sospechoso es la elección de altura en el camino de emisión, no el scheduler
- [ ] Task: Verificación de uso — **requiere iPad y controlador**
  - [ ] Con varias notas en el pool, el Track arpegia en vez de repetir una altura
  - [ ] Todo lo que suena está dentro de la Scale y el Root elegidos
  - [ ] Los pads meten y sacan notas del pool, y se ve en pantalla
  - [ ] Cambiar Scale con el transporte corriendo reencuadra el pool sin cortar el sonido
  - [ ] Un pool vacío no suena y se comunica como estado
  - [ ] El anillo, el playhead y el valor transitorio siguen funcionando (`FR9`)
- [ ] Task: Verificar cobertura — `Engine` ≥90%, `MIDI` ≥80%
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Notas de riesgo

- **La Fase 2 puede obligar a rediseñar el snapshot.** Si el pool inline no cabe
  cómodamente en `Track` sin romper `_isPOD`, la salida **no** es relajar el
  test ni sacar el pool del snapshot: es rediseñar el almacenamiento. Ese test
  existe porque el `retain` en el hilo del scheduler no se ve hasta que se mide
  el jitter, y para entonces la causa está enterrada.
- **La Fase 3 toca el camino de emisión.** Es la primera vez desde la rebanada 1
  que cambia la firma de algo que corre en el hilo del scheduler. La medición de
  la Fase 6 es lo que dice si salió bien; hasta entonces, ninguna afirmación
  sobre el timing vale.
- **El reencuadre tiene un caso que destruye material y hay que decidirlo, no
  descubrirlo.** Si dos notas del pool caen en la misma al reencuadrar, el pool
  encoge. Es pérdida real y está aceptada en el plan; lo que no se acepta es que
  ocurra sin un test que lo fije.
- **La tentación de mostrar la nota que suena.** Con el pool y el anillo en la
  misma pantalla, conectarlos parece una mejora obvia y es exactamente el
  antipatrón que `product-guidelines.md` nombra: sugeriría que las alturas están
  fijadas a posiciones, que es el modelo mental que la app rechaza.
- **`midi-test-flake_20260826` sigue abierto.** Esta rebanada no necesita
  arrancar el bucle del scheduler en tests nuevos, así que debería esquivarlo
  como la 3. Si alguna tarea lo necesita, se para y se toma el flake primero: la
  rebanada 6 ya lo tiene como bloqueante.
