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
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 2: La rejilla desplazada [checkpoint: a1dbf55]

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

- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 3: El scheduler entrega el desplazamiento [checkpoint: 4b32fc8]

> **La fase que toca el camino de tiempo real.** Es la primera desde la rebanada 3 que mueve instantes, y la que la medición de la fase 6 tiene que absolver.

- [x] Task: `TrackScheduler` emite el instante desplazado — `221bc90`
  - [x] Tests (Red): con el Groove default, **cada Step se emite en el mismo offset que hoy** — la rejilla recta no se toca
  - [x] Tests (Red): con Timing y con Delay, el offset emitido es el de la rejilla más el desplazamiento de la fase 2
  - [x] Tests (Red): el desplazamiento sale del **mismo snapshot** que la altura y el Groove, recogido una vez por ventana
  - [x] Tests (Red): cada Step se sigue emitiendo **exactamente una vez** — la invariante de `LookAheadScheduler` sobrevive al desplazamiento
  - [x] Tests (Red): el modo `everyStep` del arnés sigue usando el Groove default, que ahora es también la rejilla recta
  - [x] Implementación (Green): el desplazamiento se suma donde ya se calcula el offset; sin asignaciones, sin locks, `/// Realtime:`
- [x] Task: El horizonte de selección se amplía con el presupuesto — `221bc90`
  - [x] Tests (Red): con Delay −100%, un Step se selecciona **antes** que con Delay 0 — lo bastante antes como para que su instante siga siendo futuro
  - [x] Tests (Red): con Delay ≥ 0 el horizonte es **idéntico** al de hoy, y los mismos Steps caen en la misma ventana
  - [x] Tests (Red): ampliar el horizonte no duplica ni salta Steps — la marca de agua sigue siendo monótona
  - [x] Tests (Red): el presupuesto se relee del snapshot una vez por ventana, no se fija al construir
  - [x] Implementación (Green): el horizonte que recibe `LookAheadScheduler` lleva el presupuesto vigente sumado

  > **Las dos comparten SHA.** Separarlas daría un commit con un defecto conocido
  > dentro: emitir el instante desplazado sin ampliar el horizonte hace que un
  > Step con Delay negativo se pida para un instante que ya pasó, en cada vuelta
  > del anillo. Es lo que la fase existe para evitar.

  > **Una corrección de test, no de código.** El test del presupuesto releído
  > esperaba `[1, 2]` y salía `[1]`: el horizonte es exclusivo y la aritmética de
  > la expectativa estaba mal. Se partió en dos para que el contraste sea
  > explícito —sin presupuesto esa ventana no emite **nada**— y así un fallo diga
  > cuál de las dos cosas se rompió.

- [x] Task: El origen de la rejilla es `Play + presupuesto` — `4b32fc8`
  - [x] Tests (Red): con Delay negativo, **ningún offset pedido cae por detrás del instante de arranque** — con Delay −100%, en los extremos de tempo y Division
  - [x] Tests (Red): con Delay ≥ 0 el origen es el instante de Play, sin latencia añadida
  - [x] Tests (Red): el playhead usa **el mismo origen** que sella los timestamps — si fueran dos, el anillo y lo que suena discreparían, que es lo que `SchedulerThread` ya documenta
  - [x] Implementación (Green): el presupuesto se lee al arrancar, como la `MusicalTimeline`, y desplaza el ancla
  - [x] La documentación de `max(0, offset)` en `SchedulerThread` pasa a decir cuál es el **único** caso que puede dispararlo: bajar el Delay a negativo mientras suena (limitación 2 del spec)

  > **El primer test pasaba sin implementar nada, y eso era el hallazgo.** El
  > recorte a cero ya garantizaba «ningún evento antes del arranque», pero no
  > adelantando: **aplastando** contra el instante de Play todos los que debían
  > sonar antes —con Delay −100%, los Steps 0 y 1 se pedían para el mismo
  > instante—. La aserción que distingue es la **separación**: los instantes
  > siguen estrictamente crecientes y a una Division de distancia.

- [x] Task: Verificar cobertura — `Engine` ≥90% (98,11%), `MIDI` ≥80% (**91,57%**)
  - [x] `MIDI` se mide en **un solo proceso** y **filtrando `Engine/Sources`**, según las dos ampliaciones de `workflow.md`
  - [x] El `.profdata` hubo que fusionarlo a mano (`llvm-profdata merge`): SwiftPM no lo fusiona cuando la pasada falla, y en un proceso la pasada falla por el flake
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 4: Los nueve parámetros [checkpoint: 5cc5a60]

> Dos casos más en tipos que la rebanada 5 dejó preparados exactamente para esto. **El comportamiento de los siete anteriores no cambia**, y sus tests lo demuestran sin reescribirse.

- [x] Task: `TrackParameter` y `ParameterChange` cubren los nueve — `5cc5a60`
  - [x] Tests (Red): `.timing` y `.delay` existen, están en la familia `groove` y se leen `Timing` y `Delay` — términos de la Pre Spec, sin traducir y sin sinónimos
  - [x] Tests (Red): los dos producen su descripción legible (`Timing 67%`, `Delay -25%`), con el signo visible en el negativo
  - [x] Tests (Red): los siete casos anteriores dan **exactamente la misma descripción que antes**
  - [x] Tests (Red): el orden de comparación sigue declarado — Shape, después Groove
  - [x] Implementación (Green): dos casos más; el despacho por delta ya existe
  - [x] Se retira de `TrackParameter` la frase «Timing y Delay llegan en la rebanada 6»: se cumple aquí, y dejarla diría algo falso
- [x] Task: El mapeo y los giros cubren los nueve — `5cc5a60`
  - [x] Tests (Red): los dos CC nuevos —77 y 78— resuelven a su parámetro y no pisan a los siete existentes
  - [x] Tests (Red): girar cada uno publica un Track nuevo; girar contra un extremo **no** publica
  - [x] Tests (Red): girar Timing o Delay **conserva el Shape, el pool y el resto del Groove**
  - [x] Implementación (Green): dos entradas más en el mapeo provisional; `ControlInput` no cambia
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

  > **Las dos comparten SHA**, por la razón de la rebanada 5: añadir los casos
  > rompe el mapeo hasta que el mapeo los cubre, y el mapeo sin los giros no
  > mueve nada.

  > **`ControlInput` no cambia**, y eso es el resultado que la fase buscaba: el
  > renombrado de la rebanada 5 dejó la entrada sin saber a qué familia pertenece
  > cada parámetro, así que dos casos nuevos no le llegan.

  > **Un test tocado.** Usaba el CC 77 como ejemplo de «sin asignar» y Timing se
  > lo quedó: falló por un comportamiento que no había cambiado. Ahora busca el
  > primer CC libre en el propio mapeo — la lección que `ControlInputTests` ya
  > había anotado al llegar 1/32.


## Phase 5: La pantalla [checkpoint: f5bc845]

> `App` no se mide (`workflow.md`). Todo lo que tiene lógica quedó en `Engine` en las fases anteriores.

- [x] Task: Los dos se leen en el estado persistente — `f5bc845`
  - [x] Con el acento cromático de la familia Groove, que ya existe desde la rebanada 5
  - [x] Formato preciso y no conversacional; la descripción vive en `Engine`
  - [x] El signo de `Delay` se lee sin ambigüedad: adelantar y atrasar no se distinguen por el contexto
- [x] Task: El valor grande transitorio cubre los nueve — `f5bc845`
  - [x] Girar cualquiera de los dos lo levanta, con el mismo desvanecimiento por inactividad
  - [x] **El anillo permanece visible debajo y nunca se oculta**
- [x] Task: El playhead sigue la rejilla, y se comprueba — `f5bc845`
  - [x] Con Timing al máximo el playhead avanza **regular**: la pantalla es el reloj, el oído es el groove
  - [x] No entra aritmética de Timing ni de Delay en el camino de dibujo — es lo que evita una medición de jitter más por carga visual
- [x] Task: Verificación en simulador — `f5bc845`
  - [x] Captura con los nueve parámetros presentes y el acento aplicado
  - [x] Contraste sobre fondo oscuro, legible como el resto
  - [x] Se registra la limitación conocida: el simulador no tiene MIDI, así que no se ve el transporte ni un giro real
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

  > **La línea de Groove no cabía, y el corte lo decidía el ancho.** Con cinco
  > parámetros, SwiftUI dejaba `Delay 0%` colgando solo detrás de un separador
  > huérfano. `Groove.descriptionLines` corta por donde el dominio ya estaba
  > cortado —qué se envía / cuándo se envía— y las dos líneas llevan el mismo
  > acento: Groove es una familia leída en dos renglones, no dos familias.
  > `description` sigue siendo el `joined` de las dos, así que sus tests pasaron
  > sin tocarse.

  > **Captura:** [`simulator-groove-temporal.png`](./simulator-groove-temporal.png).


## Phase 6: Medición y verificación en dispositivo [checkpoint: a19fb23]

> **Requiere iPad, BeatStep Pro y un sintetizador.** Es la fase que decide si la rebanada entra: `workflow.md` nombra explícitamente a Timing y Delay entre lo que exige medir, y una regresión bloquea la tarea.

> **Guía de ejecución:** [`device-verification.md`](./device-verification.md) — ocho bloques, la configuración previa que explica la mayoría de los síntomas raros, y las tres limitaciones a provocar a propósito.

- [x] Task: El arnés puede correr desplazado — `a19fb23`
  - [x] Tests: `JitterHarness` acepta el Groove con el que medir y conserva el default actual
  - [x] Tests: sin Groove explícito, la medición recorre el modo `everyStep` de siempre — la referencia de regresión no cambia de forma
  - [x] Implementación: un parámetro más en la configuración; el arnés sigue comparando lo pedido contra lo entregado, sin saber que existe el desplazamiento
  - [x] **Añadido en curso:** selector de rejilla en la pantalla de medición —recta, Timing 67%, Delay ±50%— y **un informe por rejilla**: con nombre de fichero fijo, la medición de regresión la habría pisado cualquiera de las otras tres

  > **Aquí el Red no fue previo, y conviene que conste.** La función que eligen
  > los tests —`material(for:)`— se escribió junto a ellos, así que lo único que
  > hubo fue el fallo de compilación por no existir. No cambia lo que cubren,
  > pero no es el ciclo que `workflow.md` pide.
- [x] Task: Los encoders en `Relative #2` antes de empezar
  - [x] Sin eso, un clic se decodifica como ±63 y todo salta a su extremo — nota del 2026-08-28 en `workflow.md`
- [x] Task: **Medición recta** — la regresión y la atribución — **CUMPLE**, medida el 2026-08-30
  - [x] Con el Groove default, a 60, 120 y 174 BPM, 1000 eventos

    | BPM | máx | media | σ |
    |---|---|---|---|
    | 60 | 0,151 ms | +0,094 ms | **0,013 ms** |
    | 120 | 0,138 ms | +0,098 ms | **0,009 ms** |
    | 174 | 0,135 ms | +0,093 ms | **0,011 ms** |

    El 174 BPM llegó transcrito como `0,0135 ms`, imposible por ser menor que la
    media. **Contrastado contra el informe el 2026-08-30: son 0,135 ms.** Fue
    una errata al copiar, no un dato raro.

  - [x] Se compara contra la referencia de la rebanada 3: máx 0,134 ms, σ 0,020 ms
  - [x] **El intervalo sin medir de las rebanadas 4 y 5 queda absuelto.** La σ no subió: **bajó**. La serie era 9 → 15 → 20 µs y esta pasada da 9–13 µs, por debajo de la referencia. No hay nada que bisecar.
  - [x] El máximo sube (0,151 vs 0,134 ms) y es lo esperable con n=1000 frente a n=200: más muestras, más cola. La spec del arnés ya lo advertía.
  - [x] La media de +0,094 ms es **constante en los tres tempos**: es latencia fija del camino de loopback, no jitter. Lo que se juzga es la dispersión alrededor de ella.
  - [x] Margen sobre el umbral: σ **38 veces** por debajo de 0,5 ms; máx 13 veces por debajo de 2 ms.
- [~] Task: **Medición desplazada** — **no se ejecuta, por decisión del 2026-08-30**
  - [x] Decisión del usuario: la medición recta alcanza. Se sustituye por la escucha.
  - [x] **Por qué se sostiene.** Esta medición no buscaba drift pequeño sino si un instante desplazado *se entrega* donde se pidió, y ese fallo sería grosero —un Step entero, o una ráfaga al arrancar—, no un microdesplazamiento. Los bloques 4–6 de `device-verification.md` lo cazan al oído: el tresillo al 67%, el vaivén del swing y el arranque con Delay negativo. El jitter alrededor de un instante desplazado recorre además el mismo camino de entrega que la recta ya midió.
  - [x] **Qué queda sin verificar en dispositivo.** El presupuesto de adelanto con números. Detrás quedan el barrido exhaustivo de la Fase 2 —el desplazamiento nunca es más negativo que el presupuesto— y los tests de origen y horizonte de la Fase 3, más el bloque 6 de la guía al oído.
  - [x] **Cuándo volver a ella.** Si aparece una regresión de timing, el arnés sigue ahí y ahora sabe correr desplazado (`a19fb23`): es el instrumento para bisecar, no trabajo perdido.
  - [ ] *(No ejecutada: `Timing 67%`, `Delay +50%`, `Delay −50%`.)*
- [x] Task: Escuchar los dos
  - [x] **Timing:** subirlo convierte la línea recta en swing; al 66,7% el tresillo es reconocible; al 75% es el extremo y sigue sonando ordenado
  - [x] **Delay:** adelanta y atrasa la voz entera contra el pulso, de forma audible y proporcional
  - [x] Los dos se oyen dentro del Step siguiente al giro, con Delay ≥ 0
  - [x] La limitación 1 se observa a propósito: Delay −100% en una Division lenta, para confirmar que el arranque tarda lo que tiene que tardar y que el síntoma es el previsto
  - [x] La limitación 3 se observa a propósito: Timing alto con Sustain largo, para confirmar que el corte es el de la rebanada 5 con otro umbral y no un defecto nuevo
- [x] Task: Lo entregado sigue en pie
  - [x] Transporte, anillo, playhead, pool, Scale, Root, Velocity, Sustain y Probability siguen funcionando
  - [x] El playhead avanza regular con Timing al máximo
  - [x] Sin controlador conectado: los nueve se leen pero no se editan; Scale y Root sí, que son configuración
- [x] Task: Cobertura final y Pull Request
  - [x] `Engine` ≥90% y `MIDI` ≥80%, esta última en un solo proceso y filtrando `Engine/Sources`
  - [x] Si la CI falla con `clientCreationFailed(-50)`, correr la suite 3–4 veces y comparar contra `main` antes de atribuirlo al cambio
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

  > **Verificación en dispositivo ejecutada y validada el 2026-08-30**, bloques
  > 4–8 de [`device-verification.md`](./device-verification.md): Timing y Delay
  > al oído, las tres limitaciones provocadas a propósito, el playhead regular
  > con swing al máximo, y lo entregado hasta la rebanada 5 en pie.

  > **La comprobación del hallazgo High no está en la guía** —se propuso aparte,
  > después de la revisión— y no consta reportada: con Delay positivo y Division
  > lenta, si `Stop` deja sonar algo después. Sigue abierta en *Review Fixes*.


## Phase: Review Fixes

> **Revisión del 2026-08-30, con las fases 1–5 cerradas y la 6 pendiente de
> hardware.** Decidido: se anotan y se deciden **después** de la verificación en
> dispositivo. Ninguno está arreglado.

- [ ] Task: **[High]** `Stop` deja sonar notas después de silenciar, con Timing o Delay
  - [ ] `Transport.stop()` sella el All Notes Off y el barrido del pool en `now + lookAhead`, un número elegido para caer **después** de todo lo ya entregado a CoreMIDI
  - [ ] Esa cota la daba el look-ahead, y **esta rebanada la rompe**: un evento se calcula cuando su rejilla entra en el horizonte pero se emite en `rejilla + desplazamiento`, hasta **1,5 Steps** más tarde (Timing 75% + Delay +100%)
  - [ ] Consecuencia: el silencio llega antes que esos note-on y suenan después de parar — a 1/1 y 20 BPM, hasta 18 s después. No quedan notas colgadas (su note-off también va sellado), pero **Stop deja de callar**
  - [ ] Ningún test lo vio: la suite de `Transport` verifica *qué* manda `stop()`, no su instante relativo a lo pendiente
  - [ ] Arreglo propuesto: **descartar lo pendiente en vez de intentar llegar después** — `MIDIFlushOutput` sobre el destino y silencio inmediato; el All Notes Off y el barrido del pool, que ya existen, cubren las notas cuyo note-off se acaba de descartar
  - [ ] **No reproducido en dispositivo el 2026-08-30.** Probado con Delay positivo: `Stop` calla bien. No lo descarta ni lo confirma — a 1/16 el retraso previsto son ~145 ms, fácil de perder entre la cola de la nota anterior. **La condición que lo haría inequívoco es Division 1/1 a 20 BPM con Delay +100%**, donde el retraso sería de segundos. Si alguna vez se toma, empezar por ahí.
- [ ] Task: **[Medium]** La limitación 2 describe un síntoma que el código no produce
  - [ ] `spec.md` y el comentario de `SchedulerThread` dicen que bajar Delay a negativo mientras suena «recorta una ventana de eventos» por el `max(0, ...)`. **Ese recorte es inalcanzable**: un Step solo se calcula cuando su rejilla entra en el horizonte ampliado, así que su instante nunca queda por detrás del presente — el límite se toca exactamente, nunca se cruza
  - [ ] Lo que sí ocurre: la voz **salta hacia atrás un Step**, así que hasta una ventana de notas se apelotona en el instante del giro; y al revés, subir el Delay deja un hueco de un Step
  - [ ] El `max(0, ...)` es una guarda defensiva **sin caso conocido**, y su comentario debe decir eso y no otra cosa
  - [ ] **`device-verification.md` hereda el error:** su bloque 6 pide comprobar que «no suene una ráfaga amontonada», que es exactamente lo que sí va a pasar. Corregir antes de ejecutar la guía, o leerlo con esta nota delante
- [ ] Task: **[Low]** `ForEach(id: \.self)` sobre las dos líneas de Groove en `ContentView`
  - [ ] Identificar por contenido asume que las dos cadenas nunca son iguales; hoy no pueden serlo, pero la invariante vive lejos de donde se declara
- [ ] Task: **[Low]** `Int64(timeline.stepDurationNanoseconds)` puede atrapar con una Division extrema
  - [ ] `Division` admite cualquier fracción positiva por su inicializador público, no solo las seis de `ordered`; una muy lenta desborda al **construir** el scheduler
  - [ ] Misma clase de trampa que ya tenía `nanosecondOffset(forStep:)`, un poco más temprana. Inalcanzable desde la interfaz actual — anotado para que conste

## Enmiendas al plan

**2026-08-30, checkpoint de la Fase 1 — el tresillo exacto no es representable.**
`Timing` es un porcentaje entero, así que el knob pasa por 66 y por 67 y no por
el 66,67% del tresillo 2:1. El más cercano se separa un 0,66% de la duración del
Step —0,9 ms a 1/16 y 120 BPM—, por debajo de lo audible; la alternativa era un
décimo de porcentaje, que da exactitud a cambio de diez veces más recorrido de
knob para el mismo tramo. El criterio del test de la Fase 2 pasa de igualdad
exacta a **tolerancia declarada**. Queda documentado en el propio tipo.

**2026-08-30, Fase 6 — la medición desplazada no se ejecuta.** `workflow.md` la
exige —«Swing (Timing), Delay y cualquier parámetro que desplace eventos»— y el
spec la puso como NFR3. **Decidido por el usuario que la recta alcanza.** La
razón que lo sostiene: el modo de fallo que la desplazada buscaba es grosero y
audible, no un drift pequeño, y los bloques 4–6 de la guía lo cubren al oído. Lo
que se pierde es el presupuesto de adelanto medido con números; queda cubierto
por el barrido exhaustivo de la Fase 2 y los tests de la Fase 3. El arnés
desplazado se conserva como instrumento de bisección.

**2026-08-30, checkpoint de la Fase 3 — el flake deja de ser intermitente.** Los
tests del origen arrancan el bucle del scheduler cuatro veces más, y con eso la
suite de `MIDI` **en un solo proceso** pasa a fallar siempre: 4 de 4 pasadas
contra 0 de 2 en `main`, con la firma de siempre —las 4 de
`VirtualLoopbackTests`, ningún otro test—. Con la partición de CI pasa entera.
Decidido con el usuario: **se acepta y se documenta**, por la decisión del
2026-08-29 de aplazar `midi-test-flake_20260826`. Ampliación fechada en
`workflow.md` (`2f0b94c`) con cómo correr `MIDI` en local y el paso extra que la
cobertura necesita —SwiftPM no fusiona el `.profdata` cuando la pasada falla—.

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
