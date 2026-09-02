# Plan — v2 rebanada 3: Cycles, el Track varía por vuelta

Sigue el Task Workflow de [`workflow.md`](../../workflow.md): tests antes que
implementación, un commit por tarea con su git note, y checkpoint al cerrar cada
fase.

**El orden empieza por la incógnita, no por el modelo.** La decisión de avanzar
el Cycle en el hilo del scheduler obliga a que los 256 Cycles viajen en el
snapshot, y eso lo multiplica por dieciséis. Si ese coste no cabe en la ventana,
el diseño entero cambia —el avance pasaría al hilo principal, con su retraso— y
más vale saberlo antes de renombrar medio motor. Por eso la Fase 1 mide con un
valor del tamaño real y **decide**, y solo entonces se construye encima.

**Después, el modelo antes que el recorrido.** Primero que el Cycle sea un valor
trivial y que el Track lo contenga, luego que el scheduler avance por vuelta, y
al final la entrada y la pantalla. Al revés se descubriría tarde que el snapshot
no cabe por donde tiene que pasar.

**La medición de jitter es una fase, no una tarea.** Esta rebanada cambia lo que
cruza al hilo de tiempo real y añade una decisión en el límite de vuelta: es
exactamente lo que la nota del 2026-08-28 de `workflow.md` obliga a medir. Una
regresión la bloquea.

---

## Phase 1: El coste, medido antes de construir [checkpoint: 1998ebc]

> `MIDI`. Ninguna línea del modelo se toca todavía. Esta fase existe para
> responder una pregunta con un número: ¿cabe un snapshot de ~36 KB en la ventana
> de 20 ms? Y para quitar de en medio una copia que hoy pasa desapercibida y con
> Cycles no pasaría.

- [x] Task: El snapshot deja de copiarse una vez por evento (NFR3) — `8e2a9b2`
  - [x] Tests (Red): emitir N eventos hace **como mucho una** lectura del handoff por ventana, no una por evento — hoy `Transport.play()` llama a `handoff.load()` dentro del cierre de emisión, para leer el canal y la Division del Track
  - [x] Tests (Red): el canal y la Division con que sale cada nota siguen siendo los del **mismo** snapshot que produjo el evento, que es la razón por la que aquella lectura existía
  - [x] Tests (Red): cambiar el canal mientras suena se sigue oyendo en el evento siguiente
  - [x] Implementación (Green): el snapshot recogido una vez por ventana se pasa al emisor, en vez de releerlo por evento
  - [x] **Es una corrección, no una optimización prematura**: con 2,25 KB era invisible; con 36 KB es una copia por nota

  Rojo medido antes de implementar: **188 lecturas para 168 notas**. Verde:
  **7 lecturas para 168 notas** —una por ventana, más la de Play—. El contador
  vive en `PatternHandoff` y solo se compila en DEBUG.
- [x] Task: Cuánto cuesta un snapshot con los 256 Cycles — `1998ebc`
  - [x] Medir `MemoryLayout` y el tiempo de un `load()` sobre un valor **del tamaño real** —un tipo de prueba, sin renombrar nada todavía—
  - [x] Comparar contra la ventana de 20 ms y contra la medición del 2026-08-31 —2,25 KB en 274 ns—, que es la única referencia que hay
  - [x] Medir también el anillo completo: cuatro ranuras, ~147 KB, reservadas al construir
  - [x] Registrar los números en la git note **y** en la documentación de `PatternHandoff`, que es donde alguien los buscará

  | | tamaño | `load()` | % de la ventana |
  |---|---|---|---|
  | Hoy | 2304 B | ~125 ns | 0,0006% |
  | Con Cycles | **36 992 B** | **~870 ns** | **0,0044%** |

  Anillo de cuatro ranuras: **147 968 B**, reservados al construir. La
  referencia del 2026-08-31 no era comparable —otra máquina, un Track de 112
  bytes—, así que el snapshot de hoy se midió en la misma pasada. Dieciséis
  veces más bytes cuestan **siete** veces más tiempo, no dieciséis: la
  extrapolación lineal de la nota de riesgo 1 era pesimista por un factor de
  cinco.
- [x] Task: La decisión, tomada con el dato delante — `c5728c9`
  - [x] Presupuesto: un `load()` **por debajo del 1% de la ventana**. Por encima, se para y se decide explícitamente
  - [x] Si no cabe, la alternativa está escrita y es otro diseño, no un ajuste: el avance pasa al hilo principal (FR5 cambia) o se publica por Track en vez de entero. **Se elige aquí, no a mitad de la Fase 3**
  - [x] La decisión y su porqué van al `spec.md` como enmienda fechada, con el número

  **Cabe, y por tres órdenes de magnitud: 0,0044% contra un presupuesto del 1%.**
  El diseño se queda como estaba —FR5 intacto, se publica el Pattern entero— y
  las dos alternativas quedan descartadas por escrito, para no reabrirlas a
  mitad de la Fase 3. Enmienda fechada en el NFR2 del `spec.md`.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 2: El Cycle es el valor, el Track lo contiene [checkpoint: 9fb8bbb]

> `Engine` puro. Sin CoreMIDI, sin simulador, sin hardware. Es el renombrado y el
> nivel nuevo: mecánico en volumen, delicado en la frontera de tiempo real.

- [x] Task: `Track` pasa a llamarse `Cycle` — `c45ba2b`
  - [x] Tests (Red): los tests que hoy miden el `Track` —Shape, pool, marco tonal, Groove, canal— siguen midiendo lo mismo sobre `Cycle`, sin cambiar una sola aserción
  - [x] Tests (Red): `_isPOD(Cycle.self)` sigue siendo verdadero
  - [x] Implementación (Green): renombrado mecánico en `Engine` y en `MIDI`
  - [x] **Es el vocabulario de la Pre Spec** (NFR7): «Cycle: snapshot de parámetros de un Track». Mantener `Track` para esto sería inventarle un sinónimo al concepto que ya tiene nombre
  - [x] Un commit propio y solo con el renombrado: mezclado con lógica no habría forma de revisarlo

  **Lo que conserva el nombre, y por qué:** `Pattern.track(at:)`,
  `Pattern.trackCount`, `Transport.track`, `ControlInput.track`,
  `TrackScheduler` y `TrackParameter`. Los dos últimos siguen siendo lo que
  dicen ser; los otros devuelven hoy el único Cycle de ese Track, y así la
  tarea siguiente solo cambia el tipo y no todas las llamadas. Nota fechada en
  `Pattern` para que el estado intermedio no se lea como un descuido.
- [x] Task: El `Track` nuevo: dieciséis Cycles, cuántos activos y por cuál va — `253b2e9`
  - [x] Tests (Red): un Track recién construido tiene dieciséis Cycles, **uno activo** y el cursor en el primero — que es el comportamiento de hoy (FR10)
  - [x] Tests (Red): `_isPOD(Track.self)` y `_isPOD(Pattern.self)` siguen siendo verdaderos con el nivel nuevo dentro
  - [x] Tests (Red): sustituir un Cycle devuelve un Track nuevo con **solo ese** cambiado, comprobado sobre los otros quince
  - [x] Tests (Red): leer un índice de Cycle fuera de 0–15 no revienta — mismo criterio que un pad fuera de la superficie
  - [x] Implementación (Green): almacenamiento inline de tamaño fijo, por la misma razón que `PitchPool` y `Pattern` lo son

  **Hallazgo no previsto: la pila del hilo.** El test de concurrencia del
  handoff empezó a reventar con SIGBUS. Construir un Pattern deja varios
  temporales de 37 KB vivos en el mismo marco y la pila por defecto de un
  `Thread` secundario son 512 KB — medido: desborda con 512 KB y pasa con 1 MB.
  **Importa fuera del test:** el hilo del scheduler es un `Thread` con esa misma
  pila por defecto y copia el snapshot cada ventana, así que su margen se había
  reducido dieciséis veces sin que nadie lo mirara. Ahora reserva 1 MB, con el
  porqué escrito en `start()`.

  Y el detector de tamaño del snapshot saltó, que es para lo que estaba puesto:
  la cota pasa de 4 KB a 64 KB, con la decisión de la Fase 1 escrita al lado.
- [x] Task: Cuántos Cycles activos, y qué pasa al moverlo — `5b9ca53`
  - [x] Tests (Red): el rango es 1–16 y se frena en los extremos, como Steps y Division
  - [x] Tests (Red): **subir el número copia el Cycle en edición** al que empieza a existir (FR3), y el copiado suena igual hasta que se edita
  - [x] Tests (Red): bajar el número descarta por el final, y el Cycle en edición se acota de inmediato si queda fuera (FR9)
  - [x] Tests (Red): bajar el número **no toca el cursor de reproducción** — de eso se encarga el scheduler al cerrar la vuelta
  - [x] Implementación (Green)

  Entra con esta tarea el **segundo cursor**, el de edición (FR7): lo pedían la
  regla de FR3 —se copia el Cycle en edición, no el primero ni el que suena— y
  la de FR9. El tercer contador deja el Pattern en 37 248 bytes contra los
  36 992 del tipo de prueba de la Fase 1: un 0,7%, que no mueve la decisión.
- [x] Task: El recorrido, como función pura — `9fb8bbb`
  - [x] Tests (Red): con N activos, el cursor recorre 0…N−1 y vuelve a 0
  - [x] Tests (Red): con un solo Cycle activo el cursor no se mueve nunca (FR10)
  - [x] Tests (Red): con el cursor fuera del rango —porque el rango bajó— el avance siguiente entra en 0 (FR9)
  - [x] Implementación (Green): aritmética de enteros, sin asignaciones. **Vive en `Engine` y no en el scheduler**: es una regla del modelo y así se testea sin hilos

  FR9 no necesitó caso aparte: si el cursor ya está fuera del rango, sumarle uno
  lo deja igual de fuera y la comparación lo devuelve a 0.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 3: El scheduler avanza en el límite de vuelta [checkpoint: 0802798]

> `MIDI`. La fase que hace que Cycles se oiga. Toca el hilo de tiempo real y el
> instante en que cambia el material: es la que la medición final juzga.

- [x] Task: Cada Track avanza al cerrar su propia vuelta — `4fbdc6e`
  - [x] Tests (Red): un Track de N Steps cambia de Cycle **en el Step 0** de la vuelta siguiente, comprobado sobre el índice de Step y no de oído (FR5)
  - [x] Tests (Red): dos Tracks de longitudes distintas —16 Steps y 12— no cambian de Cycle a la vez (FR4)
  - [x] Tests (Red): con Divisions distintas, cada uno avanza según **su** vuelta, no según el tiempo del otro
  - [x] Tests (Red): el avance recorre muchas vueltas sin deriva —mil ciclos, no dos compases—, que es como se ven los fallos de fase
  - [x] Implementación (Green): el cursor avanza en el hilo del scheduler, sin asignaciones ni locks

  **Dos decisiones que no estaban escritas.** El cursor de reproducción vive en
  el scheduler y no en el snapshot: el que trae un Track publicado es viejo por
  construcción —lo escribe el hilo principal, que no sabe por dónde va el
  sonido— y hacerle caso devolvería el desarrollo al principio en cada giro de
  knob. Y la vuelta se mide desde el Step en que empezó, no con un módulo sobre
  el índice absoluto, para que un Cycle de 12 Steps que entra en el 16 dure doce
  y no ocho.
- [x] Task: El Cycle vigente decide lo que suena, entero — `e5f6fce`
  - [x] Tests (Red): al cambiar de Cycle cambian a la vez Shape, pool, marco tonal, Groove y canal — no la mitad de uno y la mitad de otro
  - [x] Tests (Red): el Cycle nuevo se lee **una sola vez** al cruzar el límite, no por evento
  - [x] Tests (Red): un Cycle con el pool vacío no emite nada y **no rompe el recorrido**: la vuelta se cuenta igual y el siguiente sí suena (NFR3 de la rebanada 1: el coste crece con lo que suena)
  - [x] Implementación (Green)

  **Encontró una regresión de la tarea anterior.** La decisión de emitir se
  tomaba una vez por ventana, de cuando el material no podía cambiar a mitad de
  ventana. Con Cycles sí puede: un Track que arrancaba mudo y dejaba de serlo al
  cambiar de Cycle no sonaba en esa vuelta, y uno que enmudecía seguía llamando
  al emisor con altura `nil`. Las dos reproducidas con test antes de arreglar.
- [x] Task: Lo que cambia de Cycle y lo que no puede cambiar todavía — `a9d9442`
  - [x] Tests (Red): Steps, Pulses, Rotate, pool, marco tonal, Groove y canal cambian con el Cycle
  - [x] **Division es el caso difícil y se decide aquí, con test.** Cambiar la Division reubica todos los Steps futuros respecto a un origen que ya pasó — es la limitación que `TrackScheduler` ya documenta para el snapshot en caliente. En el límite de vuelta el origen sí es reubicable: si no lo es sin romper la fase con los otros quince, **se acota explícitamente** y va a *Known Limitations* del spec
  - [x] Implementación (Green)

  **Se acota: la Division no cambia de Cycle a Cycle.** Resolverlo exige una
  línea de tiempo rebasable por Track, y eso rompe el invariante del que depende
  que los dieciséis suenen en fase sin sincronización posterior —todas las
  rejillas contra el mismo origen—. Es trabajo en el núcleo de timing, con
  jitter obligatorio, para un caso que nadie ha pedido: cambiar de compás a
  mitad de patrón. Queda en *Known Limitations* 8 del `spec.md` y fijado con dos
  tests.
- [x] Task: Play reinicia los dieciséis al Cycle 1 — `0802798`
  - [x] Tests (Red): tras `play()`, los dieciséis cursores están en 0 (FR6)
  - [x] Tests (Red): dos pasadas de Play producen la **misma** secuencia de Cycles y las mismas omisiones — la promesa de `tech-stack.md`
  - [x] Tests (Red): cambiar de Cycle **no resiembra** el generador de Probability (NFR5)
  - [x] Tests (Red): `Stop` con Cycles avanzando no deja notas colgadas, incluido con Delay positivo y con canales distintos por Cycle
  - [x] Implementación (Green)

  **Dos fallos encontrados.** `restartCycles()` pedía el Cycle con
  `track.current`, que mira el cursor del snapshot —el de edición—, así que un
  Track dejado editando el Cycle 3 arrancaba sonando el 3. Y `Stop` barría solo
  el Cycle vigente de cada Track y dejaba sonando los otros quince por sus
  canales; ahora barre los dieciséis —no solo los activos, porque FR9 deja el
  cursor fuera del rango a propósito— deduplicando pares canal+altura.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 4: La entrada edita el Cycle en edición

> `MIDI`, en `ControlInput`. Dos cursores conviviendo: el que suena lo mueve el
> scheduler, el que se edita lo mueve el knob 10.

- [~] Task: El knob 10 mueve el Cycle en edición
  - [ ] Tests (Red): el knob 10 del preset mueve el Cycle en edición del **Track seleccionado**, dentro del rango activo y frenando en los extremos
  - [ ] Tests (Red): mover el Cycle en edición **no altera** el cursor de reproducción ni lo que suena (FR7)
  - [ ] Tests (Red): cambiar de Track con un step button deja cada Track con **su** Cycle en edición donde estaba
  - [ ] Implementación (Green): entra en `ControlMapping` como los otros nueve knobs
  - [ ] **Documentar la desviación**: la Pre Spec dice «con CTRL ajusta 1–16 Cycles activos» y el BeatStep Pro no tiene CTRL. Nota fechada en la Pre Spec o en `product.md`, como se hizo con los pads en la rebanada 7
- [ ] Task: Los knobs y los pads editan el Cycle en edición
  - [ ] Tests (Red): un giro de knob mueve el parámetro del Cycle en edición y **no** el de los otros quince Cycles ni el de los otros quince Tracks (FR8)
  - [ ] Tests (Red): un pad mete la altura en el pool de ese Cycle
  - [ ] Tests (Red): editar un Cycle que **no** está sonando no altera lo que suena — construir el B mientras suena el A
  - [ ] Tests (Red): editar el Cycle que **sí** está sonando se oye en el Step siguiente, como hoy
  - [ ] Implementación (Green)
- [ ] Task: Cuántos Cycles activos se ajusta táctilmente
  - [ ] Tests (Red): la vía táctil mueve el número de activos del Track seleccionado y publica, como `setChannel` y `setFrame`
  - [ ] Tests (Red): ningún CC llega hasta ahí — es configuración, no material generativo (`product-guidelines.md`)
  - [ ] Implementación (Green)
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 5: La pantalla muestra el desarrollo

> `App`. No se mide cobertura: si algo aquí merece un test, está en el sitio
> equivocado (`workflow.md`). La lógica ya está en `Engine` y `MIDI`.

- [ ] Task: Cuántos Cycles, cuál suena y cuál se edita
  - [ ] Del Track seleccionado: número de Cycles activos, Cycle en curso y Cycle en edición, distinguibles de un vistazo (FR11)
  - [ ] El Cycle en curso deriva del reloj y se consulta al dibujar, **no se guarda ni se refresca con un temporizador** — la misma regla que el playhead
  - [ ] Legible a un metro, como el resto de la pantalla
- [ ] Task: Ajustar cuántos Cycles hay activos
  - [ ] Control táctil, junto a Scale, Root y el canal, que es donde vive lo configurable
  - [ ] Sin controlador conectado la app sigue siendo de solo lectura y transporte **salvo lo táctil**, como hoy
  - [ ] Verificado en simulador con captura, como la rebanada 1
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 6: La medición y el dispositivo

> La fase que decide si la rebanada vale. El snapshot es dieciséis veces mayor y
> hay una decisión nueva en el límite de vuelta: las dos se cobran aquí.

- [ ] Task: Jitter con los dieciséis sonando y avanzando
  - [ ] iPad real, con el arnés, en la división más rápida y el tempo más alto ya usados — comparable con las mediciones anteriores
  - [ ] **Los dieciséis Tracks con varios Cycles cada uno**, avanzando: es el peor caso realista de esta rebanada
  - [ ] Umbral: **máximo < 2 ms, σ < 0,5 ms**. Se registra el número, no la impresión
  - [ ] Se compara contra la referencia de la rebanada 6 —máx 0,151 ms, σ 0,009–0,013 ms— y contra la que deje la Fase 6 de `multi-track`, y **la diferencia se explica**
  - [ ] Atención al **límite de vuelta**: si hay un pico, mirar si cae en el Step 0 de una vuelta. Ahí es donde esta rebanada añade trabajo
  - [ ] Si hay regresión: **la rebanada se para** y se bisecta con el arnés. No se cierra con una medición mala explicada
  - [ ] El resultado va a `product.md`, junto a las anteriores
- [ ] Task: Verificación en dispositivo
  - [ ] BeatStep Pro y un multitímbrico
  - [ ] Un Track con 3 Cycles distintos: se oye el desarrollo A/B/C y el retorno a A, sin tocar nada
  - [ ] Dos Tracks de longitudes distintas con Cycles: desarrollan a ritmos distintos y **no se desalinean** al cabo de varios minutos
  - [ ] Construir el Cycle B con el knob 10 mientras suena el A, y oírlo entrar en su vuelta
  - [ ] Play dos veces: el desarrollo se repite igual
  - [ ] `Stop` con Cycles avanzando: nada queda colgado
  - [ ] Se registra en un `device-verification.md` del track y en la git note
- [ ] Task: Cerrar la rebanada
  - [ ] Cobertura de `Engine` ≥90% y de `MIDI` ≥80%, medidas como dice `workflow.md`
  - [ ] `product.md` refleja que Cycles deja de estar fuera de alcance, y qué queda de la v2
  - [ ] La Pre Spec queda con su nota fechada sobre el gesto de CTRL
  - [ ] `tracks.md` deja descrita la rebanada siguiente
  - [ ] Pull Request contra `main`, con los checks en verde
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Notas de riesgo

1. **El tamaño del snapshot es la incógnita, y por eso se mide primero.** ~36 KB
   por `load()` extrapolan a ~4,4 µs contra 20 ms, pero es extrapolación: la
   única medida real es la de 2,25 KB. Si no cabe, la Fase 1 cambia el diseño
   —avance en el hilo principal, o publicación por Track— antes de que nadie haya
   renombrado nada.

2. **Division cambiando en el límite de vuelta es el caso difícil.**
   `TrackScheduler` ya documenta que la rejilla la fija la `MusicalTimeline` con
   la que se construye y no se vuelve a leer: cambiar la Division reubica los
   Steps futuros respecto a un origen que ya pasó. En el límite de vuelta puede
   ser tratable, y puede no serlo sin romper la fase con los otros quince. La
   Fase 3 lo decide con un test delante, y si se acota, se escribe.

3. **El renombrado es amplio y hay que revisarlo aparte.** `Track` → `Cycle`
   toca `Engine` y `MIDI` casi enteros. Va en su propio commit, sin lógica
   mezclada: es la única forma de que un revisor pueda mirarlo.

4. **Dos cursores es la parte que se puede operar mal.** Que el Cycle que se edita
   no sea el que suena es deliberado y potente, pero es donde alguien se
   confundirá. La Fase 5 tiene que hacerlo evidente de un vistazo; si en el
   dispositivo no lo es, es un fallo de esta rebanada y no de la siguiente.

5. **`midi-test-flake` estará en el camino.** Esta rebanada arranca el bucle del
   scheduler en los tests, que es la condición que lo dispara. Sigue aplazado: se
   corre `MIDI` con la partición de CI, la firma conocida —las 4 pruebas de
   `VirtualLoopbackTests` con `clientCreationFailed(-50)`— se descarta comparando
   pasadas, y la cobertura se mide con el `.profdata` fusionado a mano.

6. **`scheduler-lifecycle` sigue parado y esta rebanada toca su terreno.** Si
   aparece un Step duplicado al parar y arrancar deprisa, es ese defecto y no
   este cambio.

7. **Las dependencias son reales.** No arranca hasta que `multi-track` cierre su
   Fase 6 —sin esa medición no hay línea base— y hasta que exista la pantalla de
   la rebanada 2, que es donde el Cycle en curso se muestra.
