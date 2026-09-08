# Plan — v2 rebanada 6: LFO Modulation

Sigue el `workflow.md`: tests antes de implementación, un commit por tarea, git
note por commit y checkpoint verificado al cerrar cada fase.

**El orden va de dentro afuera.** Primero la nota de la desviación, que el Task
Workflow §8 exige *antes* de implementar porque la Pre Spec promete un Accent
distinto del que se entrega. Después el valor puro en `Engine` —toda la
matemática de las cuatro ondas y del offset, que se prueba sin relojes—; luego
el `Cycle`, que aprende a llevarlo encima sin dejar de ser POD; luego la emisión,
que es donde suena por primera vez; y por último la pantalla, que es lo único
que no se testea.

**El riesgo de esta rebanada no está en la matemática, está en el `Cycle`.** Las
cuatro ondas se prueban con números y se acabó. Lo que hay que vigilar es que
meter un campo más en un valor que cruza al hilo del scheduler dieciséis veces
por Track no rompa `_isPOD` ni engorde el snapshot: por eso la Fase 3 existe
separada de la 2 y no se resuelve de pasada.

**Todas las fases cargan con el criterio 1.** Con `accent = 0` la salida tiene
que ser idéntica a la de antes de la rebanada —instantes, velocities y consumo de
aleatoriedad—. No es una comprobación del final: cada fase que toque el camino de
emisión deja su test de no regresión dentro.

**Ninguna fase mide jitter** (NFR3). Es el caso que la nota del 2026-08-28 de
`workflow.md` excluye explícitamente —cambia el *cuánto*, no el *cuándo*— y
además la medición está suspendida desde el 2026-09-02. Queda anotado en la Fase
1 para que la ausencia sea una decisión leída y no un olvido.

**Nada de coma flotante entra en el hilo del scheduler** (NFR1). Si una tarea
empuja hacia `sin()`, hacia un `Double` de fase o hacia una tabla que haya que
asignar, es la señal de que el diseño se está torciendo: parar y revisar antes de
seguir.

## FASE 1: LA DESVIACIÓN QUEDA ESCRITA [checkpoint: d6ba133]

- [x] Task: Anotar la modulación en la Pre Spec (NFR7) `817c3d5`
  - [x] Nota fechada en `Pre Spec Torax H-0.md`, §4 «Modulación LFO y Random» y
        en la fila `Accent` de §5: qué se entrega y qué no.
  - [x] **La forma se llama `waveform`, no `Groove`.** La Pre Spec usa *Groove*
        para dos cosas —la familia de parámetros y el knob que elige la forma— y
        el motor ya gastó el término en la primera. Escribir el porqué:
        `product-guidelines.md` pide un solo término por concepto.
  - [x] **La longitud no se puede cambiar.** La Pre Spec dice «se puede cambiar
        su longitud»; se entrega fija a un ciclo por vuelta del anillo, y el
        default de 4 compases del brief de producto no se implementa.
  - [x] **Accent no tiene knob.** La §5 lo lista entre los parámetros de Groove,
        que son todos de knob; aquí es táctil. Con el coste delante: Ctrl All,
        Temp y la lectura transitoria grande no lo alcanzan.
  - [x] **Retrigger reiniciaría Accent y Retrigger no existe.** Anotarlo donde la
        Pre Spec lo promete, para que la deuda esté escrita y no se descubra.
  - [x] Fijar el vocabulario: `modulation`, `waveform`, `accent`, `saw`,
        `triangle`, `sine`, `pulse`. Ni «LFO» como nombre de parámetro, ni
        «shape» —que ya es una familia—, ni «amount».
- [x] Task: Sacar el LFO de «Fuera de v1» en `product.md` (NFR7) `d6ba133`
  - [x] Nota fechada en `conductor/product.md`: de «LFO y Random Modulation»
        entra **solo la primera mitad, y solo sobre velocity**, por la misma vía
        que salieron Cycles y los múltiples Tracks.
  - [x] Describirlo en *Interaction Model*: **capa sobre la dinámica, no sobre el
        material**. Steps, Pulses, Rotate y el pool no cambian.
  - [x] Anotar que la app pasa a tener **cinco pantallas**, y de qué lado de la
        frontera del tacto cae `modulation`: se configura antes de tocar, como
        `scale`, `midi` y `banks`.
  - [x] Anotar que **no se mide jitter** y por qué la regla del 2026-08-28 lo
        excluye, para que la ausencia se lea como decisión.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 2: EL VALOR PURO — `Modulation` EN `Engine` [checkpoint: 2a36a7d]

- [x] Task: `Waveform` y `Accent`, con sus rangos (FR2, FR3) `45073c4`
  - [x] Tests (Red): `Accent` acota −100…100 y **se detiene en los extremos**, no
        envuelve, como `Velocity` y `Sustain`; el `init?` devuelve `nil` fuera de
        rango; el default es 0.
  - [x] Tests (Red): `Waveform` recorre sus cuatro casos y su `description` es el
        término en minúscula (`saw`, `triangle`, `sine`, `pulse`).
  - [x] Implementar (Green) en `Packages/Engine/Sources/Engine/Modulation.swift`.
  - [x] Documentar el porqué del bipolar y del 0 dentro del rango: es el valor
        que apaga la modulación, no un extremo.
- [x] Task: La onda muestreada por Step (FR4, FR5) `b0b75e1`
  - [x] Tests (Red): las cuatro ondas valen **0 en el Step 0** —salvo `pulse`,
        que vale +100— para 1, 9 y 16 Steps.
  - [x] Tests (Red): `triangle` sobre 16 Steps da el pico en el cuarto de vuelta,
        vuelve a 0 a media vuelta y es simétrico en la segunda mitad.
  - [x] Tests (Red): `saw` sube hasta el cuarto de vuelta, **salta** a −100 y
        vuelve a subir; el salto cae exactamente donde dice el spec.
  - [x] Tests (Red): `pulse` produce exactamente dos valores y cambia a media
        vuelta; con Steps impares, la mitad se resuelve por la misma regla y
        queda escrita.
  - [x] Tests (Red): `sine` es monótona donde debe serlo y su pico no se desvía
        del de `triangle` — la tabla aproxima la forma, no otra cosa.
  - [x] Tests (Red): con `stepCount` de 1 la fase es siempre 0 y no se divide por
        cero.
  - [x] Implementar (Green): tabla estática de enteros para `sine`, aritmética
        entera para las otras tres. Marca `/// Realtime:` en la función.
- [x] Task: El offset de velocity y su acotado (FR6, FR7) `2a36a7d`
  - [x] Tests (Red): `accent = 0` da offset 0 en los Steps de la vuelta, para las
        cuatro ondas.
  - [x] Tests (Red): `accent = ±100` sobre el pico da ±63 unidades MIDI.
  - [x] Tests (Red): `accent = −n` es el complemento exacto de `accent = +n`
        respecto de la base, salvo donde el acotado muerde.
  - [x] Tests (Red): con `Velocity 127` y accent positivo nada supera 127; con
        `Velocity 1` y accent negativo nada baja de 1 — reutilizando
        `Velocity.advanced(by:)`, no un segundo acotado.
  - [x] Tests (Red): la aritmética es entera y el redondeo está fijado por test
        en los valores que caen a mitad de unidad.
  - [x] Implementar (Green).
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 3: EL `Cycle` LLEVA SU `Modulation` [checkpoint: 0637f44]

- [x] Task: `Modulation` dentro del `Cycle`, sin dejar de ser POD (FR1, NFR2) `309a2ba`
  - [x] Tests (Red): `_isPOD(Cycle.self)` sigue siendo cierto con el campo nuevo.
  - [x] Tests (Red): un `Cycle` recién creado tiene `accent = 0` y
        `waveform = .triangle`.
  - [x] Tests (Red): `Cycle.with(modulation:)` devuelve un valor nuevo y no toca
        nada más; la igualdad distingue dos Cycles que solo difieren en la onda.
  - [x] Tests (Red): los dieciséis Cycles de un `Track` llevan el suyo — cambiar
        el del Cycle en edición no toca a los otros quince.
  - [x] Implementar (Green), con el campo entrando **por default** en el
        inicializador, como entraron Timing y Delay: código que no lo pide sigue
        compilando y sonando igual.
- [x] Task: `Modulation` en disco, o se pierde al guardar (FR1) `1223a21`
  - [x] **Enmienda del 2026-09-08, escrita al implementar.** El plan daba la
        persistencia por inexistente —la spec la lista en *Out of Scope*, y se
        escribió el 2026-09-06— pero entró el 2026-09-07 con
        `persistence_20260907`. Añadir el campo al `Cycle` sin tocar
        `CycleRecord` **perdería `waveform` y `accent` al guardar, en silencio**.
        Es el mismo hueco que la rebanada 5 se encontró, y `ProjectRecord.swift`
        ya lo deja escrito por adelantado.
  - [x] Tests (Red): `RecordRoundTripTests.testTheCycleJSONHasNoOtherKeys` falla
        con el campo nuevo hasta que las claves se declaran. Es la red, y tiene
        que dispararse.
  - [x] Tests (Red): las dos claves nuevas se escriben —también el neutro—, y
        vuelven enteras del round trip.
  - [x] Tests (Red): un fichero **sin** las dos claves se lee como el neutro
        —`triangle` y `accent` 0—, que es el estado que ese fichero describía.
        `schemaVersion` se queda en 1: `validated()` exige igualdad exacta y sin
        migrador subirla dejaría sin abrir los Banks ya escritos.
  - [x] Implementar (Green): `waveform` por **clave estable en minúsculas** y no
        por su posición en el `enum` — el orden de `allCases` lo manda la rejilla
        de la pantalla y reordenarla no puede cambiar lo que suena un Bank
        guardado. Mismo criterio que `scale`.
- [x] Task: El coste del snapshot, medido y no supuesto (NFR2) `0637f44`
  - [x] Tests (Red): extender `CycleSnapshotCostTests` con el tamaño nuevo del
        `Pattern` de doce Tracks × dieciséis Cycles.
  - [x] Anotar la cifra en la git note del commit, junto a la anterior (~37 KB,
        `load()` ~870 ns), para que la serie siga siendo comparable.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 4: EL ACENTO SUENA [checkpoint: e89e0d6]

- [x] Task: El `TrackScheduler` aplica la modulación (FR4, FR8) `4454140`
  - [x] Tests (Red): con `accent = 0` la secuencia emitida es **idéntica** a la
        de antes —instantes, velocities y consumo de aleatoriedad—. Es el
        criterio 1 y se queda dentro de la suite.
  - [x] Tests (Red): con `triangle` y `accent = +100`, las velocities de una
        vuelta siguen la forma; el Step 0 de cada vuelta vuelve a la base.
  - [x] Tests (Red): la fase usa `cycleStep`, no el Step absoluto: dos vueltas
        seguidas emiten la misma serie de velocities.
  - [x] Tests (Red): un Step apagado por Probability **no desplaza la fase** —
        los siguientes valen lo mismo que si hubiera sonado.
  - [x] Tests (Red): un Step que no es pulso euclidiano tampoco la desplaza.
  - [x] Tests (Red): al avanzar de Cycle en el límite de vuelta, la modulación
        que se aplica es la del Cycle nuevo desde su Step 0.
  - [x] Implementar (Green): componer el `Groove` modulado donde el scheduler ya
        tiene `cycleStep` y `stepCount` a mano, sin releer el snapshot.
  - [x] Verificar a mano que no entra ninguna asignación, bloqueo ni coma
        flotante en el bucle de ventana (NFR1, Quality Gates).
- [x] Task: Cada Track modula con su propio anillo (FR4) `654ce21`
  - [x] Tests (Red): dos Tracks con Steps distintos completan su ciclo en vueltas
        distintas, cada uno con la suya.
  - [x] Tests (Red): un Track muteado sigue avanzando su fase — la rejilla del
        muteado avanza, y la modulación va con ella.
  - [x] Implementar (Green) si hace falta; si los tests pasan sin tocar nada, la
        tarea es el test y queda dicho en la git note.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 5: LA QUINTA PESTAÑA Y LAS CUATRO ONDAS [checkpoint: 8743480]

- [x] Task: `Module.modulation` y la navegación de cinco (FR10) `8743480`
  - [x] Añadir el caso a `Module` y comprobar que `ModuleNavigation` reparte los
        cinco sin apretar la fila.
  - [x] Verificar que navegar a `modulation` y volver **no** interrumpe el
        transporte ni mueve el playhead: el modelo lo posee `ContentView`.
- [x] Task: `WaveformPreview` y `WaveformCard` (FR11, FR19, FR20) `8743480`
  - [x] El dibujo de cada onda: trazo geométrico simple, sin relleno, sin
        degradado, dos ciclos como en el handoff.
  - [x] Seleccionado: relleno mauve plano, etiqueta oscura, borde de 3 pt y
        sombra dura sin desenfoque. Los otros tres, oscuros con borde neutro de
        2 pt.
  - [x] Cadenas en minúscula, radios de 3 a 8 pt, Figtree 400/600/700.
- [x] Task: `WaveformSelector` y la etiqueta de contexto (FR11, FR16, FR17) `8743480`
  - [x] Rejilla 2×2, escritura sobre el **Cycle en edición**.
  - [x] La etiqueta dice `track 04 · cycle 02`; el Track lo elige el controlador
        y esta pantalla no lo escribe (FR17).
  - [x] Área táctil suficiente y legible sin zoom (Code Review Process §6).
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 6: EL ACENTO SE VE [checkpoint: 411c1cc]

- [x] Task: El formato de la lectura vive en `Engine` (NFR6) `ab13f2c`
  - [x] Tests (Red): `+34`, `−12` y `0` — el signo se ve en el positivo, como
        `Rotate`, y el 0 va sin signo.
  - [x] Implementar (Green) junto a `Accent`, no en la vista.
- [x] Task: `BipolarAccentSlider` (FR11, FR18, FR19) `411c1cc`
  - [x] Arrastre continuo, `+100` arriba, `0` en el centro exacto, `−100` abajo.
  - [x] Imantado al 0 cerca del centro y toque simple sobre la pista.
  - [x] Pulgar mauve, marcador de centro off-white, etiqueta `bipolar velocity`.
- [x] Task: `VelocityResponseView` (FR12, FR13, FR14, FR15) `411c1cc`
  - [x] Tests (Red, en `Engine`): la serie de velocities finales de una vuelta —
        con base, accent, onda y **recorte**— para 9 y 16 Steps. Es el dato que
        el panel dibuja, y por eso se testea aquí y no mirándolo.
  - [x] Barras: tantas como Steps, altura = velocity final, off-white con
        realces mauve; los Steps que no son pulso, atenuados.
  - [x] La onda seleccionada trazada sobre una línea de centro discreta.
  - [x] Playhead off-white, **un redibujo por Step**, oculto con el transporte
        parado; las barras se quedan.
  - [x] Pie: `1 cycle per pattern`.
- [x] Task: `ModulationSummaryCard` y el montaje de `ModulationView` (FR11, FR19) `411c1cc`
  - [x] Card resumen: `waveform` / la onda, `accent` / el valor con signo.
  - [x] Dos columnas ~70/30, el card alto `accent` a la derecha.
  - [x] Repasar que en `App` no haya quedado lógica que merezca un test
        (`workflow.md`, *Coverage Requirements*).
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 7: SIMULADOR, DISPOSITIVO Y CIERRE

- [x] Task: Verificar la pantalla en simulador (criterio 13) `d96047b`
  - [x] Captura con `simctl` de la pantalla `modulation` con cada una de las
        cuatro ondas seleccionada.
  - [x] Comprobar contra el handoff: rejilla, columnas, mauve, minúsculas,
        bordes y sombra dura.
  - [x] Comprobar el panel con un Track de 9 Steps: nueve barras, no dieciséis.
  - [~] Comprobar el imantado del slider y que la etiqueta de contexto sigue al
        Cycle en edición. **La etiqueta, sí. El imantado, no:** `simctl` no toca
        la pantalla, así que el arrastre no se puede provocar desde aquí y pasa
        a la verificación en dispositivo. Corregido el 2026-09-08 al cerrar la
        tarea — estaba marcado como hecho y no lo estaba.
  - [x] Anotar en la git note lo que el simulador **no** puede verificar: sin
        destinos MIDI no hay transporte, así que ni playhead ni acento audible.
- [x] Task: Verificar en iPad con BeatStep Pro (criterios 3, 5, 13) `d3d0667`
  - [x] Con un sinte externo: `triangle` y `accent` alto **se oye** como una
        respiración a lo largo de la vuelta.
  - [x] `pulse` acentúa media vuelta entera y la otra media suena por debajo.
  - [x] `accent = 0` suena exactamente como antes de la rebanada.
  - [x] Con `Velocity` alta y accent alto, comprobar que el recorte se **ve** en
        el panel y anotar cómo suena.
  - [x] Comprobar que el playhead del panel va con el del anillo, sin retraso
        visible.
  - [x] Legibilidad a un metro del panel y de la lectura grande.
  - [x] **El imantado del slider** (FR18), que viene de la tarea del simulador:
        arrastrar cerca del centro deja `accent` en 0 exacto, y un toque simple
        sobre la pista salta a ese valor. `simctl` no toca la pantalla, así que
        es aquí donde se comprueba (criterio 11). **Cumple, 2026-09-08.**
- [~] Task: Cobertura, estilo y cierre del track
  - [ ] `Engine` ≥90% y `MIDI` ≥80%, esta última medida como dice `workflow.md`:
        un solo proceso, `.profdata` fusionado a mano, `Engine/Sources` fuera del
        informe.
  - [ ] `swift format` sobre `App` y `Packages`.
  - [ ] Repasar los Quality Gates uno a uno, incluido que `Engine` no importe
        nada fuera de la stdlib.
  - [ ] Actualizar `conductor/tracks.md` y abrir el PR contra `main` — cuerpo
        corto, cinco líneas y la tabla de verificación (`workflow.md`).
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
