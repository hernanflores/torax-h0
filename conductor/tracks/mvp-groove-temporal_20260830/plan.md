# Plan — MVP rebanada 6: Groove temporal — Timing y Delay

**Track ID:** `mvp-groove-temporal_20260830`

Sigue la metodología definida en [`workflow.md`](../../workflow.md): tests fallando primero (Red), implementación mínima (Green), refactor, verificación de cobertura y checkpoint de fase. El trabajo va en la rama `feat/mvp-groove-temporal` y se integra por Pull Request.

**Orden.** Los valores antes que la aritmética, porque desplazar necesita un rango que exista; la aritmética antes que el scheduler, porque el hilo de tiempo real no es sitio para descubrir que una fórmula estaba mal; el presupuesto de adelanto junto al desplazamiento y no después, porque un Delay negativo sin él pide instantes que ya pasaron y eso es un defecto, no una fase pendiente; la entrada y la pantalla después, porque consumen lo que ya funciona; y la medición cierra, porque es la única fase que puede decir que la rebanada no rompió lo que costó validar.

**Lo que este orden evita.** Las fases 1 y 2 son `Engine` puro y no tocan CoreMIDI. La fase 3 sí toca `MIDI`, y a diferencia de la rebanada 5 **va a necesitar arrancar el bucle del scheduler**: el origen de la rejilla lo fija `SchedulerThread`, y eso no se prueba dándole el horizonte a mano. Ver *Notas de riesgo* — es el punto donde `midi-test-flake` se hace visible, y la decisión de convivir con él ya está tomada.

## Phase 1: Los dos parámetros como valores [checkpoint: ab38c72]

> `Engine` puro. Sin CoreMIDI, sin simulador, sin hardware.

- [x] Task: Documentar la desviación **antes** de implementar (paso 8 del Task Workflow) — `7ef9703`
  - [x] Nota fechada en `tech-stack.md`: el horizonte de look-ahead deja de ser constante — con Delay negativo, la selección se amplía en el presupuesto de adelanto, porque un evento adelantado tiene que calcularse antes de su instante
  - [x] La misma nota: el origen de la rejilla deja de ser el instante de Play y pasa a ser `Play + presupuesto`
  - [x] La misma nota acota el coste: el presupuesto es **dinámico**, así que con Delay ≥ 0 —donde vive el default— la ventana y la latencia de knob no cambian
  - [x] Se escribe con la razón, no solo con la regla: la frase que enmienda es «esa latencia acota el tamaño de la ventana», y sigue siendo cierta en la mitad del rango donde no hay adelanto
- [x] Task: `Timing` y `Delay` como tipos validados — `42d2621`
  - [x] Tests (Red): `Timing` admite 50–75 y rechaza 49 y 76; su default es 50 — la rejilla recta
  - [x] Tests (Red): `Delay` admite −100…+100 y rechaza −101 y 101; su default es 0
  - [x] Tests (Red): **el 50% de `Timing` y el 0% de `Delay` son estados válidos y son el punto de partida**, no casos límite
  - [x] Implementación (Green): validación en el inicializador y vía `init(unchecked:)` interna, mismo idioma que `Velocity`, `Sustain` y `Probability`
- [x] Task: Los dos entran en `Groove` sin romper el snapshot — `c743e37`
  - [x] Tests (Red): **`_isPOD(Groove.self)` y `_isPOD(Track.self)`** — el test que ya existe no se relaja ni se mueve
  - [x] Tests (Red): `Groove` construido sin ellos toma los defaults, para que ningún llamante existente cambie
  - [x] Tests (Red): `Groove.default` sigue siendo el que no interpreta nada, ahora también en el tiempo
  - [x] Tests (Red): `Groove.description` los incluye con el formato de la Pre Spec (`Timing 67% · Delay -25%`)
  - [x] Implementación (Green): dos enteros más en un valor que sigue siendo trivial
- [x] Task: Ajuste por delta, con freno en los extremos — `ab38c72`
  - [x] Tests (Red): los dos se frenan en sus extremos y no envuelven, como los cinco anteriores
  - [x] Tests (Red): girar contra un extremo devuelve el mismo valor, que es lo que después permite no publicar
  - [x] Tests (Red): `Delay` cruza el cero sin caso especial — es el único parámetro del motor con rango negativo
  - [x] Implementación (Green): acotado, no envoltura; reutiliza el `clamping` que ya existe
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 2: La rejilla desplazada

> Sigue siendo `Engine` puro, y es donde vive la corrección del track. **Aritmética entera, en nanosegundos, sin coma flotante:** esto acaba corriendo en el hilo del scheduler.

- [x] Task: El desplazamiento de un Step — `a1dbf55`
  - [x] Tests (Red): con Timing 50% y Delay 0% el desplazamiento es **exactamente 0** para todos los Steps — la rejilla de hoy, verificada contra `MusicalTimeline` y no contra números escritos a mano
  - [x] Tests (Red): Timing 67% coloca el par en proporción 2:1 **dentro de tolerancia declarada** —el tresillo exacto es 66,67% y el knob va de uno en uno— y Timing 75% deja el Step impar medio Step tarde
  - [x] Tests (Red): **los Steps pares no se mueven nunca por Timing**, en todo el rango
  - [x] Tests (Red): la paridad es la del **índice absoluto**, no la de la posición en el anillo — con Steps impares el swing desfasa de una vuelta a la siguiente, y el test lo fija como comportamiento querido
  - [x] Tests (Red): Delay se aplica por igual a pares e impares, y se suma al de Timing
  - [x] Tests (Red): Delay +100% atrasa un Step entero; −100% lo adelanta
  - [x] Tests (Red): índices negativos y el Step 0 se comportan igual que el resto
  - [x] Implementación (Green): función pura del índice, el Groove y la duración del Step; marcador `/// Realtime:`
- [x] Task: La invariante de orden — `a1dbf55`
  - [x] Tests (Red): **barrido exhaustivo del rango de Timing × Delay**: la secuencia de instantes de emisión es monótona no decreciente sobre una vuelta larga del anillo
  - [x] Tests (Red): el caso extremo —Timing 75%— no invierte el orden, que es la razón declarada del tope
  - [x] Implementación (Green): si el barrido falla, **el tope de Timing está mal elegido y se corrige el rango**, no el test
- [x] Task: El presupuesto de adelanto — `a1dbf55`
  - [x] Tests (Red): con Delay ≥ 0 el presupuesto es **exactamente 0** — es lo que garantiza que la mitad positiva del rango no paga nada
  - [x] Tests (Red): con Delay negativo el presupuesto es su valor absoluto en nanosegundos, contra la Division y el tempo vigentes
  - [x] Tests (Red): **el desplazamiento nunca es más negativo que el presupuesto**, sobre el barrido exhaustivo — es la propiedad de la que dependen las dos piezas de la fase 3
  - [x] Implementación (Green): función pura del Groove y la duración del Step; `/// Realtime:`

  > **Las tres comparten SHA.** No se separan de forma que cada commit se
  > sostenga: la invariante de orden no tiene implementación propia —es una
  > propiedad del desplazamiento— y el presupuesto está definido como función
  > del mismo desplazamiento. El test que los une —el desplazamiento nunca es
  > más negativo que el presupuesto— no podría existir en ninguno por separado,
  > y es la propiedad de la que depende toda la Fase 3.

  > **Una corrección de test, no de código.** El test del tresillo falló en la
  > primera pasada por tolerancia mal calibrada: la separación real al 67% es
  > 0,833 ms y estaba puesta en 0,825 ms. La cota correcta es **medio clic de
  > knob** —cada clic mueve un 2% de la duración del Step, así que el error
  > máximo a cualquier objetivo es un 1%—, que además es general y no un número
  > ajustado a este caso.

- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 3: El scheduler entrega el desplazamiento

> **La fase que toca el camino de tiempo real.** Es la primera desde la rebanada 3 que mueve instantes, y la que la medición de la fase 6 tiene que absolver.

- [ ] Task: `TrackScheduler` emite el instante desplazado
  - [ ] Tests (Red): con el Groove default, **cada Step se emite en el mismo offset que hoy** — la rejilla recta no se toca
  - [ ] Tests (Red): con Timing y con Delay, el offset emitido es el de la rejilla más el desplazamiento de la fase 2
  - [ ] Tests (Red): el desplazamiento sale del **mismo snapshot** que la altura y el Groove, recogido una vez por ventana
  - [ ] Tests (Red): cada Step se sigue emitiendo **exactamente una vez** — la invariante de `LookAheadScheduler` sobrevive al desplazamiento
  - [ ] Tests (Red): el modo `everyStep` del arnés sigue usando el Groove default, que ahora es también la rejilla recta
  - [ ] Implementación (Green): el desplazamiento se suma donde ya se calcula el offset; sin asignaciones, sin locks, `/// Realtime:`
- [ ] Task: El horizonte de selección se amplía con el presupuesto
  - [ ] Tests (Red): con Delay −100%, un Step se selecciona **antes** que con Delay 0 — lo bastante antes como para que su instante siga siendo futuro
  - [ ] Tests (Red): con Delay ≥ 0 el horizonte es **idéntico** al de hoy, y los mismos Steps caen en la misma ventana
  - [ ] Tests (Red): ampliar el horizonte no duplica ni salta Steps — la marca de agua sigue siendo monótona
  - [ ] Tests (Red): el presupuesto se relee del snapshot una vez por ventana, no se fija al construir
  - [ ] Implementación (Green): el horizonte que recibe `LookAheadScheduler` lleva el presupuesto vigente sumado
- [ ] Task: El origen de la rejilla es `Play + presupuesto`
  - [ ] Tests (Red): con Delay negativo, **ningún offset pedido cae por detrás del instante de arranque** — con Delay −100%, en los extremos de tempo y Division
  - [ ] Tests (Red): con Delay ≥ 0 el origen es el instante de Play, sin latencia añadida
  - [ ] Tests (Red): el playhead usa **el mismo origen** que sella los timestamps — si fueran dos, el anillo y lo que suena discreparían, que es lo que `SchedulerThread` ya documenta
  - [ ] Implementación (Green): el presupuesto se lee al arrancar, como la `MusicalTimeline`, y desplaza el ancla
  - [ ] La documentación de `max(0, offset)` en `SchedulerThread` pasa a decir cuál es el **único** caso que puede dispararlo: bajar el Delay a negativo mientras suena (limitación 2 del spec)
- [ ] Task: Verificar cobertura — `Engine` ≥90%, `MIDI` ≥80%
  - [ ] `MIDI` se mide en **un solo proceso** y **filtrando `Engine/Sources`**, según las dos ampliaciones de `workflow.md`
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 4: Los nueve parámetros

> Dos casos más en tipos que la rebanada 5 dejó preparados exactamente para esto. **El comportamiento de los siete anteriores no cambia**, y sus tests lo demuestran sin reescribirse.

- [ ] Task: `TrackParameter` y `ParameterChange` cubren los nueve
  - [ ] Tests (Red): `.timing` y `.delay` existen, están en la familia `groove` y se leen `Timing` y `Delay` — términos de la Pre Spec, sin traducir y sin sinónimos
  - [ ] Tests (Red): los dos producen su descripción legible (`Timing 67%`, `Delay -25%`), con el signo visible en el negativo
  - [ ] Tests (Red): los siete casos anteriores dan **exactamente la misma descripción que antes**
  - [ ] Tests (Red): el orden de comparación sigue declarado — Shape, después Groove
  - [ ] Implementación (Green): dos casos más; el despacho por delta ya existe
  - [ ] Se retira de `TrackParameter` la frase «Timing y Delay llegan en la rebanada 6»: se cumple aquí, y dejarla diría algo falso
- [ ] Task: El mapeo y los giros cubren los nueve
  - [ ] Tests (Red): los dos CC nuevos —77 y 78— resuelven a su parámetro y no pisan a los siete existentes
  - [ ] Tests (Red): girar cada uno publica un Track nuevo; girar contra un extremo **no** publica
  - [ ] Tests (Red): girar Timing o Delay **conserva el Shape, el pool y el resto del Groove**
  - [ ] Implementación (Green): dos entradas más en el mapeo provisional; `ControlInput` no cambia
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 5: La pantalla

> `App` no se mide (`workflow.md`). Todo lo que tiene lógica quedó en `Engine` en las fases anteriores.

- [ ] Task: Los dos se leen en el estado persistente
  - [ ] Con el acento cromático de la familia Groove, que ya existe desde la rebanada 5
  - [ ] Formato preciso y no conversacional; la descripción vive en `Engine`
  - [ ] El signo de `Delay` se lee sin ambigüedad: adelantar y atrasar no se distinguen por el contexto
- [ ] Task: El valor grande transitorio cubre los nueve
  - [ ] Girar cualquiera de los dos lo levanta, con el mismo desvanecimiento por inactividad
  - [ ] **El anillo permanece visible debajo y nunca se oculta**
- [ ] Task: El playhead sigue la rejilla, y se comprueba
  - [ ] Con Timing al máximo el playhead avanza **regular**: la pantalla es el reloj, el oído es el groove
  - [ ] No entra aritmética de Timing ni de Delay en el camino de dibujo — es lo que evita una medición de jitter más por carga visual
- [ ] Task: Verificación en simulador
  - [ ] Captura con los nueve parámetros presentes y el acento aplicado
  - [ ] Contraste sobre fondo oscuro, legible como el resto
  - [ ] Se registra la limitación conocida: el simulador no tiene MIDI, así que no se ve el transporte ni un giro real
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 6: Medición y verificación en dispositivo

> **Requiere iPad, BeatStep Pro y un sintetizador.** Es la fase que decide si la rebanada entra: `workflow.md` nombra explícitamente a Timing y Delay entre lo que exige medir, y una regresión bloquea la tarea.

- [ ] Task: El arnés puede correr desplazado
  - [ ] Tests (Red): `JitterHarness` acepta el Groove con el que medir y conserva el default actual
  - [ ] Tests (Red): sin Groove explícito, la medición es idéntica a la de hoy — la referencia de regresión no cambia de forma
  - [ ] Implementación (Green): un parámetro más en la configuración; el arnés sigue comparando lo pedido contra lo entregado, sin saber que existe el desplazamiento
- [ ] Task: Los encoders en `Relative #2` antes de empezar
  - [ ] Sin eso, un clic se decodifica como ±63 y todo salta a su extremo — nota del 2026-08-28 en `workflow.md`
- [ ] Task: **Medición recta** — la regresión y la atribución
  - [ ] Con el Groove default, a 60, 120 y 174 BPM, ~1000 eventos
  - [ ] Se compara contra la referencia de la rebanada 3: máx 0,134 ms, σ 0,020 ms
  - [ ] **Cierra el intervalo sin medir de las rebanadas 4 y 5:** si sale en línea, quedan absueltas sin bisecar; si sale peor, ése es el intervalo a bisecar con el arnés
  - [ ] El número se registra en la git note de la tarea, no en una impresión
- [ ] Task: **Medición desplazada** — lo que esta rebanada tiene que demostrar
  - [ ] Con Timing 66,7%, y con Delay +50% y −50%
  - [ ] El criterio es que la desviación **contra lo pedido** esté en el mismo orden que la recta: un instante desplazado se entrega donde se pidió, no donde caía la rejilla
  - [ ] El caso de Delay negativo verifica en dispositivo lo que la fase 3 verifica en test: ningún evento en el pasado
  - [ ] Los números se registran en la git note
- [ ] Task: Escuchar los dos
  - [ ] **Timing:** subirlo convierte la línea recta en swing; al 66,7% el tresillo es reconocible; al 75% es el extremo y sigue sonando ordenado
  - [ ] **Delay:** adelanta y atrasa la voz entera contra el pulso, de forma audible y proporcional
  - [ ] Los dos se oyen dentro del Step siguiente al giro, con Delay ≥ 0
  - [ ] La limitación 1 se observa a propósito: Delay −100% en una Division lenta, para confirmar que el arranque tarda lo que tiene que tardar y que el síntoma es el previsto
  - [ ] La limitación 3 se observa a propósito: Timing alto con Sustain largo, para confirmar que el corte es el de la rebanada 5 con otro umbral y no un defecto nuevo
- [ ] Task: Lo entregado sigue en pie
  - [ ] Transporte, anillo, playhead, pool, Scale, Root, Velocity, Sustain y Probability siguen funcionando
  - [ ] El playhead avanza regular con Timing al máximo
  - [ ] Sin controlador conectado: los nueve se leen pero no se editan; Scale y Root sí, que son configuración
- [ ] Task: Cobertura final y Pull Request
  - [ ] `Engine` ≥90% y `MIDI` ≥80%, esta última en un solo proceso y filtrando `Engine/Sources`
  - [ ] Si la CI falla con `clientCreationFailed(-50)`, correr la suite 3–4 veces y comparar contra `main` antes de atribuirlo al cambio
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Enmiendas al plan

**2026-08-30, checkpoint de la Fase 1 — el tresillo exacto no es representable.**
`Timing` es un porcentaje entero, así que el knob pasa por 66 y por 67 y no por
el 66,67% del tresillo 2:1. El más cercano se separa un 0,66% de la duración del
Step —0,9 ms a 1/16 y 120 BPM—, por debajo de lo audible; la alternativa era un
décimo de porcentaje, que da exactitud a cambio de diez veces más recorrido de
knob para el mismo tramo. El criterio del test de la Fase 2 pasa de igualdad
exacta a **tolerancia declarada**. Queda documentado en el propio tipo.

## Notas de riesgo

**El flake de CoreMIDI, y por qué esta vez sí se lo va a topar.** La rebanada 5
pudo esquivarlo porque `TrackScheduler` se prueba dándole el horizonte a mano. La
fase 3 de esta rebanada no puede: **el origen de la rejilla lo fija
`SchedulerThread` al arrancar el hilo**, y verificar que `Play + presupuesto` es
el ancla exige arrancar el bucle. La decisión ya está tomada y no se vuelve a
discutir —`midi-test-flake` queda aplazado a después de la v2, por decisión del
2026-08-29—: se escriben los tests, se convive con el ruido, y un fallo `-50` se
descarta comparando 3–4 pasadas contra `main`. La firma es reconocible: las 4
pruebas de `VirtualLoopbackTests` y ningún otro test. En la rebanada 5 apareció
en 2 de 8 pasadas.

**La medición es el riesgo real de la rebanada, y puede salir mal de dos formas
distintas.** Una regresión de la medición **recta** no la habría causado
necesariamente esta rebanada: la σ viene subiendo 9 → 15 → 20 µs y las rebanadas
4 y 5 no midieron, así que el intervalo sospechoso incluye tres rebanadas. Una
regresión de la medición **desplazada** con la recta limpia sí apunta aquí, y
apunta a un sitio concreto: la aritmética del desplazamiento o el presupuesto.
Distinguirlas antes de bisecar ahorra el trabajo de bisecar lo que no es.

**El tope de Timing es una decisión de corrección, no de gusto.** El 75% está
puesto para que el orden de emisión no se invierta, y el barrido exhaustivo de la
fase 2 es quien lo demuestra. Si ese test falla, la respuesta es **bajar el tope**
—o revisar la fórmula—, nunca relajar el test: un evento que adelanta a su
predecesor es una nota fuera de sitio, no un valor extremo.

**El presupuesto dinámico es lo que protege la latencia de knob.** Es tentador
simplificar la fase 3 fijándolo al máximo del rango, y sería un error silencioso:
alargaría el look-ahead un Step entero para todos, incluida la mitad del rango
que no lo necesita, y `product-guidelines.md` exige que un giro se oiga «dentro
del siguiente step». Los tests de FR5 están puestos para que esa simplificación
no pueda entrar sin ponerse en rojo.
