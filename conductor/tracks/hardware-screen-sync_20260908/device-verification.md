# Verificación en dispositivo — La pantalla no ve lo que cambia el hardware

**2026-09-09.** iPad con BeatStep Pro conectado, reloj externo. Encoders en
`Relative #2`.

**Por qué este documento existe y no una captura de pantalla.** Los tres
intentos anteriores de arreglar este defecto se revirtieron, y dos de ellos
dejaron la app sin atender el MIDI entrante sin que nadie lo notara mirando. Los
síntomas viven en el hilo de recepción de CoreMIDI y en el hardware, y el
simulador no tiene ninguno de los dos (NFR6). Lo que hay aquí son números y
observaciones enumeradas, no impresiones.

## Lo que se probó, y qué hizo

### Los dos síntomas reportados (FR8, FR9)

| # | Qué se hizo | Qué pasó |
|---|---|---|
| 1 | Reloj externo elegido en la pantalla `midi` | Correcto |
| 2 | **Start en el BeatStep** | Suena, **el botón pasa a *stop* solo**, y el anillo se mueve |
| 3 | **Pulsar el botón de la app** | **Para.** Es el síntoma reportado, resuelto |
| 4 | **Stop en el BeatStep** | El botón vuelve a *play* solo y el anillo se detiene |
| 5 | **Mover el tempo del maestro** | La barra lo sigue |

El paso 3 es el criterio de aceptación que manda. Antes del arreglo, pulsar el
botón no hacía nada: con la copia en `false` llamaba a `play()`, que moría en el
`guard !isPlaying` de `Transport.play()`.

El paso 4 es **la mitad que el `spec.md` no contaba**. Se encontró en la Fase 1,
midiendo: en t=90 s de aquella pasada el maestro paró, `transport.isPlaying`
pasó a `false` y `model.isPlaying` se quedó en `true`. El defecto era simétrico.

El paso 5 **ya funcionaba antes de este track**, y así se comprobó al empezar la
Fase 1: lo resuelve el `TimelineView(.periodic(by: 0.25))` de
`AppChrome.swift:222`, no nada de aquí. Se prueba como no-regresión.

### El anillo (FR8b, no estaba reportado)

El playhead se dibuja con `TimelineView(.animation(paused: !model.isPlaying))`
(`ContentView.swift:369`), colgado de la misma copia que el botón. Antes del
arreglo, **con un Start del maestro el anillo no avanzaba aunque la secuencia
sonara**. Se descubrió al instrumentar, no estaba en el reporte original, y lo
arregla el mismo cambio. Verificado en los pasos 2 y 4 de arriba.

### El estado del reloj (FR10)

| # | Qué se hizo | Qué pasó |
|---|---|---|
| 6 | **Cortar el cable del maestro** unos segundos y devolverlo | `clockStatus` refleja las dos transiciones |

También cubierto por el `TimelineView` de `MidiScreen.swift:20`, que envuelve la
pantalla entera: como el tempo, se prueba como no-regresión.

### Sin regresión (criterio 5)

| # | Qué se hizo | Qué pasó |
|---|---|---|
| 7 | Play y Stop **desde la app**, reloj interno | Igual que antes |
| 7 | Mute y desmute con la secuencia sonando | Se callan y vuelven, sin nota colgada |
| 7 | Elegir Pattern **sonando** | Queda `queued` y entra en el límite de compás |
| 7 | Elegir Pattern **parado** | Entra al momento |

Importa porque `isPlaying` cambió de fuente en la Fase 2 —de
`scheduler?.isRunning` al flag atómico— y de él cuelgan el botón, el anillo, los
mutes, la selección de Pattern y el armado.

## Los números (criterio 6)

**Contado, no estimado.** Instrumentación bajo `#if DEBUG`: un `AtomicCounter`
por cada `.timingClock` atendido y otro por cada transición efectiva, leídos
desde el `.task` de un segundo que ya existía. **Ni un temporizador nuevo** — es
el error que el tercer intento cometió.

Pasada final, con el arreglo puesto, reloj externo a 125 bpm:

| | |
|---|---|
| Ventana | t=10 s → t=100 s (90 s) |
| Ticks | 272 → 4792 = **4520** |
| Ritmo | **50,2 ticks/s** |
| Esperado a 125 bpm × 24 PPQN | 50,0 ticks/s |
| **Transiciones** | **1, durante los noventa segundos** |

**Cuatro mil quinientos veinte ticks movieron el contador cero veces.** Es FR5
comprobado contando, que es lo que el criterio 6 pide: el contador se mueve
tantas veces como transiciones hubo —la del Start— y ni una más.

La diferencia entre 50,2 y 50,0 es del cronómetro, no del reloj: el `.task` de
un segundo usa `Task.sleep(1 s)` más el trabajo del tick, así que cada «segundo»
del contador es algo más largo que uno real y el ritmo sale sobreestimado en
torno al medio por ciento. Se anota para que nadie lo persiga: el estimador de
tempo dice la verdad.

**Y `transport.isPlaying` y `model.isPlaying` coinciden en las diez líneas.** Esa
discrepancia era el defecto entero, y ya no aparece.

### Medición de la Fase 1, para comparar

La pasada de diagnóstico, **antes** del arreglo, 220 s a 124 bpm: 50,4 ticks/s y
4 transiciones. Sirvió para decidir FR5 con datos — avisar por tick habrían sido
~11.000 invalidaciones donde avisar por transición son 4, tres órdenes de
magnitud.

## El hilo principal

**Es donde el tercer intento se rompió**, así que se mira aparte. Aquel intento
colgó un temporizador de un `.task` en una vista que la propia invalidación
recreaba: se multiplicaban y saturaban el hilo principal, el mismo al que la
entrada de control salta para publicar un giro.

Comprobado en dos frentes:

- **Contando**: `ToraxH0App` sigue teniendo **2 `.task`**, los mismos de antes
  (criterio 7). La lectura del transporte entró como una línea dentro del de
  16 ms que ya existía, junto a `applyPendingAdoption()`.
- **Con los knobs**: moviendo encoders del BeatStep con la secuencia sonando,
  los valores siguen al knob **igual de fluido que antes, sin tirones ni
  retraso**.

## Lo que no se midió

**Jitter.** La suspensión del 2026-09-02 manda, y este cambio no mueve ningún
instante (NFR5). La última referencia válida sigue siendo la de la rebanada 2 de
la v2 — máx 0,158 ms, σ 0,013–0,014 ms.

Lo que **sí** se comprobó es el coste por tick, que es otra cosa: se mide
contando, y está arriba.

## Lo que queda escrito como límite

- **Hasta un cuadro de retraso** entre el gesto del hardware y la pantalla
  (FR11). Es el mismo límite que la adopción declara: lo que suena es exacto, lo
  que se lee no es instantáneo. Nadie lo oye.
- **La escritura de `scheduler` desde el hilo de recepción sigue ahí.** Lo que
  este track elimina es el **lector** del hilo principal: `isPlaying` ya no es
  `scheduler?.isRunning`. Cerrarla del todo exigiría que la referencia viajara
  por un atómico o que el hilo dejara de reasignarse, y eso es un track propio.
