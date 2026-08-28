# Plan — MVP rebanada 4: Tonal — pool, Scale y Root

**Track ID:** `mvp-tonal_20260828`

Sigue la metodología definida en [`workflow.md`](../../workflow.md): tests fallando primero (Red), implementación mínima (Green), refactor, verificación de cobertura y checkpoint de fase. El trabajo va en rama y se integra por Pull Request.

**Orden:** el marco tonal antes que el pool, porque el pool solo tiene sentido dentro de un marco; el pool antes que la emisión, porque hay que saber qué se guarda antes de decidir cómo se lee; y la emisión antes que la entrada y la pantalla, que son las dos superficies que lo usan. La verificación en dispositivo cierra, porque esta rebanada vuelve a tocar el camino de tiempo real.

## Phase 1: El marco tonal

> `Engine` puro. Sin CoreMIDI, sin simulador, sin hardware.

- [ ] Task: `Scale` y `Root`
  - [ ] Tests (Red): cada preset —Minor, Major, Dorian, Phrygian, Pentatonic— produce su conjunto de intervalos, escritos literalmente en el test
  - [ ] Tests (Red): `Root` transpone el conjunto entero sin cambiar su forma
  - [ ] Tests (Red): recorrer las escalas hacia arriba y hacia abajo se detiene en los extremos, como ya hace `Division`
  - [ ] Implementación (Green): conjuntos preset, no escalas de usuario
- [ ] Task: Qué alturas permite el marco
  - [ ] Tests (Red): una altura está o no en el marco, para toda combinación de Scale y Root
  - [ ] Tests (Red): la nota permitida **más cercana** a una dada; con dos a la misma distancia, la regla de desempate es fija y está escrita
  - [ ] Implementación (Green): el marco responde sin asignar — lo va a consultar el hilo del scheduler
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 2: El pool, sin romper la trivialidad de `Track`

> **La fase con la restricción dura.** `tech-stack.md` lo dejó escrito antes de
> que hiciera falta: almacenamiento inline de ocho huecos, no un `Array`.

- [ ] Task: Almacenamiento inline de ocho pitches
  - [ ] Tests (Red): **`_isPOD` sobre el pool y sobre `Track`** — el test que ya existe en `TrackHandoffTests` no se relaja ni se mueve
  - [ ] Tests (Red): insertar, quitar y consultar; de cero a ocho notas
  - [ ] Tests (Red): insertar una altura ya presente no la duplica ni crece el pool
  - [ ] Tests (Red): el pool lleno rechaza la novena sin destruir las ocho
  - [ ] Implementación (Green): huecos fijos, sin `Array` ni nada con conteo de referencias
- [ ] Task: El pool vive en `Track`
  - [ ] Tests (Red): `_isPOD(Track.self)` sigue en verde con el pool dentro
  - [ ] Tests (Red): un pool vacío es un estado válido, no un `nil` ni un error
  - [ ] Implementación (Green): `Track` gana el pool y `TrackHandoff` sigue publicándolo sin cambios de protocolo
- [ ] Task: Reencuadre no destructivo
  - [ ] Tests (Red): cambiar Scale reubica las notas fuera de marco en la más cercana y **conserva el tamaño del pool**
  - [ ] Tests (Red): cambiar Root hace lo mismo
  - [ ] Tests (Red): invariante — tras cualquier cambio de marco, ninguna nota del pool queda fuera y ninguna desapareció
  - [ ] Tests (Red): si dos notas del pool caen en la misma tras reencuadrar, el pool encoge en vez de duplicar
  - [ ] Implementación (Green): es la regla de destructividad de `product-guidelines.md`, la misma que rige a `Pulses` desde la rebanada 2
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 3: Del pool a la nota que suena

> Aquí se toca el camino de tiempo real. Es el único sitio de la rebanada donde
> una regresión de jitter es posible.

- [ ] Task: El recorrido del pool, como valor
  - [ ] Tests (Red): cada Pulse toma la siguiente altura y vuelve al principio al agotar el pool
  - [ ] Tests (Red): determinismo — mismo pool y mismo Pulse, misma altura
  - [ ] Tests (Red): un pool de una nota da un centro estable; uno vacío no da ninguna
  - [ ] Implementación (Green): la convención entra como tipo de un solo caso, igual que `RelativeEncoding` — añadir el aleatorio será añadir un caso
- [ ] Task: `NoteEmitter` deja de llevar una altura fija
  - [ ] Tests (Red): emitir con la altura que le pasan, en note-on y en su note-off
  - [ ] Tests (Red): sin altura no se emite nada — ni note-on huérfano ni note-off suelto
  - [ ] Implementación (Green): la altura entra por parámetro; canal y velocity siguen siendo la constante provisional hasta Groove
  - [ ] **Revisión explícita registrada:** elegir y emitir no asigna, no toma locks, no espera (`NFR1`)
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 4: Los pads editan el pool

- [ ] Task: Recepción de notas
  - [ ] Tests (Red): un note-on alterna la pertenencia de esa altura al pool
  - [ ] Tests (Red): el mismo pad dos veces la mete y la saca
  - [ ] Tests (Red): una altura fuera del marco tonal se ignora en silencio, no es error
  - [ ] Tests (Red): los note-off no alternan nada — alternar dos veces por pulsación sería no alternar
  - [ ] Implementación (Green): `ControlInput` entiende notas además de Control Change
  - [ ] Revisión: decodificar y publicar siguen en el hilo de control, nunca en el del scheduler
- [ ] Task: El pool publicado se recoge en caliente
  - [ ] Tests (Red): editar el pool publica un `Track` nuevo, recogido en la ventana siguiente
  - [ ] Implementación (Green): por `TrackHandoff`, el mismo camino que ya usa Shape
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 5: El pool y el marco en pantalla

- [ ] Task: Acento de la familia Tonal
  - [ ] Implementación: se puebla el token que la rebanada 3 dejó preparado, en el mismo sitio
- [ ] Task: El pool, sin sugerir una nota por paso
  - [ ] Implementación: las notas de la Scale y cuáles están en el pool
  - [ ] **No se conecta con el anillo ni se muestra qué sonó en cada Step** — es el antipatrón declarado
  - [ ] Revisión: es una representación paralela y separada, no una capa sobre el anillo
- [ ] Task: Elegir Scale y Root
  - [ ] Implementación: pantalla 2 del handoff — rejilla de escalas y barras por nota, con el Root destacado
  - [ ] El cambio se ve en el pool al instante, reencuadrado y no vaciado
  - [ ] Se puede cambiar con el transporte corriendo, sin modal que bloquee (`product-guidelines.md`)
  - [ ] Sigue siendo táctil sin controlador conectado: es configuración, no material generativo
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

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
