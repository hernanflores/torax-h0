# Plan — v2 rebanada 5: Note Repeater

Sigue el `workflow.md`: tests antes de implementación, un commit por tarea, git
note por commit y checkpoint verificado al cerrar cada fase.

**El orden va de dentro afuera.** Primero la nota de la desviación, que el Task
Workflow §8 exige *antes* de implementar porque la Pre Spec promete un Note
Repeater distinto del que se entrega. Después el valor puro en `Engine` —toda la
matemática de Ramp, Pace, hueco y corte, que se prueba sin relojes—; luego la
emisión, que aprende a recibir una velocity y un gate que no son los del Track;
luego la tirada en el `TrackScheduler`, que es donde suena por primera vez; y por
último la entrada, el preset y la pantalla.

**La Fase 4 es la que tiene el riesgo**, no la 2. La matemática se prueba con
números; lo que no se prueba con números es que el corte, el consumo de
aleatoriedad y el desplazamiento de Groove se compongan bien dentro del bucle de
ventana, que es código que ya funciona y que esta rebanada abre.

**Todas las fases cargan con FR16.** Con Repeats en 0 la salida tiene que ser
idéntica a la de antes de la rebanada —instantes, velocities, gates y consumo de
aleatoriedad—. No es una comprobación del final: cada fase que toque el camino de
emisión deja su test de no regresión dentro.

**Ninguna fase mide jitter** (NFR6, suspendido el 2026-09-02), aunque esta
rebanada cree instantes nuevos entre los Steps. Queda anotado en la Fase 1 que es
el segundo cambio desde la suspensión que toca la rejilla temporal y que aquí no
se abre excepción.

> **Enmienda del 2026-09-07 — la persistencia ya existe, y este plan la daba por
> inexistente.** El plan y su `spec.md` se escribieron el 2026-09-06, cuando la
> rebanada 4 de la v2 estaba «por planificar»; el `spec.md` la lista en *Out of
> Scope* con la frase «Persistencia. No existe». Entró a `main` el 2026-09-07, y
> `ProjectRecord.swift` deja escrito lo que eso implica: «añadir un parámetro al
> `Cycle` tiene que romper un test», nombrando a esta rebanada.
>
> **Añadir el `NoteRepeater` al `Cycle` sin tocar `CycleRecord` haría que guardar
> un Bank perdiera los cuatro parámetros en silencio**, que es exactamente lo que
> la rebanada 4 existió para impedir. Entra por eso una tarea nueva en la Fase 2,
> decidida con el usuario.
>
> **`schemaVersion` se queda en 1.** `ProjectRecord.validated()` exige igualdad
> exacta, así que subirla sin migrador dejaría ilegibles los ficheros ya escritos
> en el iPad. Las cuatro claves se decodifican con default neutro, y un fichero
> sin ellas se lee como el estado de antes de la rebanada — que es la misma
> promesa que FR16 hace para la salida MIDI, aplicada al disco.

**Nada nuevo cruza al hilo del scheduler que no sea trivialmente copiable.** Si
una tarea empuja hacia un array temporal de eventos o hacia coma flotante dentro
del bucle de ventana, es la señal de que el diseño se está torciendo: parar y
revisar antes de seguir (NFR1).

## FASE 1: LA DESVIACIÓN QUEDA ESCRITA [checkpoint: 31679cf]

- [x] Task: Anotar el Note Repeater en la Pre Spec (FR19, NFR7) — a312a20
  - [x] Nota fechada en `Pre Spec Torax H-0.md`, §4 «Note Repeater (ratchet)»:
        qué se entrega y qué no.
  - [x] **Repeats es 0–8 y no 0–48, y no hay «infinito»**, con el porqué
        delante: el techo de coste en el hilo del scheduler se razona en vez de
        medirse, y 108 eventos por Step con doce Tracks es defendible donde 588
        no lo es.
  - [x] **Ramp y Pace son knobs y no secundarios de CTRL**, por la misma razón
        que «cuántos Cycles activos» pasó a ser táctil: el BeatStep Pro no tiene
        CTRL, y el gesto agrupaba cosas porque el hardware de la Pre Spec lo
        hacía barato.
  - [x] **Choke y Tail quedan fuera**, con la limitación de solape escrita.
  - [x] Fijar el vocabulario: `Repeats`, `Time`, `Ramp`, `Pace`, `Note Repeater`.
        Ni «ratchet» como nombre de parámetro, ni «roll», ni «stutter».
- [x] Task: Sacar el Note Repeater de «Fuera de v1» en `product.md` (FR19) — 31679cf
  - [x] Nota fechada en `conductor/product.md`: el Note Repeater sale de la lista
        de *Fuera de v1* por la misma vía que salieron Cycles y los múltiples
        Tracks.
  - [x] Describirlo en *Interaction Model*: **capa sobre el ritmo, no ritmo**.
        Steps, Pulses y Rotate no cambian.
  - [x] Anotar en *Success Criteria* que este es el **segundo cambio desde la
        suspensión del 2026-09-02 que toca la rejilla temporal**, que no se abre
        excepción y que se verifica tocando.
  - [x] Anotar que Probability pasa a decidir sobre todas las notas, y por qué
        eso no es una regresión: con Repeats en 0 los dos conjuntos coinciden.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 2: EL VALOR PURO — `NoteRepeater` EN `Engine` [checkpoint: e71bfc0]

- [x] Task: Los cuatro tipos y sus rangos (FR5, FR6, FR7, FR8) — f5c7339
  - [x] Tests (Red): `Repeats` acota 0…8 y **se detiene en los extremos**, no
        envuelve; `Time` recorre las nueve fracciones de más lenta a más rápida y
        se detiene; `Ramp` y `Pace` acotan −100…100; los cuatro defaults son
        0, 1/32, 0 y 0.
  - [x] Tests (Red): una `Time` que no esté en la lista se devuelve intacta al
        avanzar, con el mismo criterio que `Division`.
  - [x] Implementación (Green): los cuatro tipos, con `init?` validador y
        `init(unchecked:)` interno, en el idioma de `Velocity` y `Division`.
  - [x] `Time` envuelve una fracción y **no amplía `Division.ordered`**: la lista
        de Time es suya, y meter tresillos en la de Division cambiaría por dónde
        pasa otro knob.
- [x] Task: La velocity de cada repetición (FR7) — 0050326
  - [x] Tests (Red): con Ramp 0, las `n` repeticiones suenan a la Velocity del
        Track. Con +100 y V=100, la última llega a 127; con −100, **a 1 y no a
        0**. Con |ramp| intermedio, la última se queda a medio camino.
  - [x] Tests (Red): el **Pulse original no participa de la rampa** — siempre a
        la Velocity del Track, en los dos sentidos.
  - [x] Tests (Red): mover la Velocity del Track mueve la rampa entera con ella.
  - [x] Implementación (Green): aritmética entera, acotada a
        `Velocity.validRange`.
- [x] Task: El hueco de cada repetición (FR6, FR8) — 9a6dc7a
  - [x] Tests (Red): con Pace 0 los `n` huecos son iguales y valen Time. Con
        +100 el último dura el doble que el primero; con −100, la mitad; los
        intermedios interpolan linealmente.
  - [x] Tests (Red): `r` es **exactamente recíproco** entre `+p` y `−p` — +50 da
        ×1,5 y −50 da ÷1,5.
  - [x] Tests (Red): con `n = 1` el único hueco vale Time, sea cual sea Pace (la
        interpolación divide por `n − 1`).
  - [x] Tests (Red): el hueco sale de `duraciónDelStep × (Time / Division)`, así
        que un Track en 1/4 y otro en 1/16 con el mismo Time repiten al mismo
        ritmo.
  - [x] Implementación (Green): aritmética entera en nanosegundos, multiplicando
        antes de dividir, como `Sustain.gateNanoseconds`.
- [x] Task: `NoteRepeater` dentro del `Cycle` (FR1, NFR2) — 8508ac1
  - [x] Tests (Red): el `Cycle` por defecto trae el `NoteRepeater` neutro;
        `with(...)` lo conserva al cambiar Shape, Groove o pool.
  - [x] Tests (Red): **`_isPOD(Cycle.self)` sigue pasando**, y el test de coste
        del snapshot se actualiza con el tamaño nuevo — cuatro enteros por Cycle.
  - [x] Tests (Red): cada Cycle tiene el suyo; editar el B no toca al A.
  - [x] Implementación (Green): el campo en `Cycle`, su `with(noteRepeater:)` y
        el default.
- [x] Task: Los cuatro `TrackParameter` (FR2, FR3, FR17) — fe7f169
  - [x] Tests (Red): `.repeats`, `.repeatTime`, `.ramp` y `.pace` existen, caen
        en `ParameterFamily.shape` y describen `"Repeats"`, `"Time"`, `"Ramp"` y
        `"Pace"`.
  - [x] Tests (Red): `applying(_:to:)` mueve cada uno **sin tocar Shape, Groove
        ni el pool**, que es la regla de destructividad de
        `product-guidelines.md`.
  - [x] Tests (Red): `value(in:)` escribe `3`, `1/32`, `+40%` y `−20%` — Ramp y
        Pace **con signo**, por la misma razón que Delay: adelantar y frenar no
        se distinguen por el contexto.
  - [x] Tests (Red): `displacementRange` devuelve el rango de los cuatro
        (ninguno envuelve), y `CtrlAllOffset` los topa como a los demás.
  - [x] Implementación (Green): los cuatro casos y sus ramas.
  - [x] Documentar por qué el caso se llama `.repeatTime` y el usuario lee
        `Time`: desambiguación de Swift frente a `MusicalTime`, no un término
        nuevo (NFR7).
- [x] Task: El `NoteRepeater` sobrevive al disco (enmienda del 2026-09-07) — 8c0008d
  - [x] Tests (Red): `CycleRecord` gana cuatro claves —`repeats`, `repeatTime`,
        `ramp` y `pace`— y el test que enumera las claves esperadas las exige.
  - [x] Tests (Red): round-trip completo — un Cycle con los cuatro movidos vuelve
        del JSON idéntico, con los literales escritos a mano que usa
        `RecordRoundTripTests`.
  - [x] Tests (Red): **un fichero sin las claves nuevas se lee como el estado de
        antes de la rebanada** — Repeats 0, Time 1/32, Ramp 0, Pace 0—, y
        `schemaVersion` **sigue siendo 1**.
  - [x] Tests (Red): un valor fuera de rango cae en su default en vez de
        reventar, como el resto de las claves.
  - [x] Implementación (Green): las cuatro claves, con decodificación tolerante.

- [x] Task: El texto de la familia Shape, en dos líneas (FR15) — e71bfc0
  - [x] Tests (Red): `FamilyReadout` de Shape devuelve **dos líneas** — los
        cuatro de siempre y los cuatro nuevos — y el test que compara lo que
        anuncia un giro con lo que dice el card sigue pasando para los trece.
  - [x] Implementación (Green): la segunda línea, mismo acento.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 3: LA EMISIÓN APRENDE VELOCITY Y GATE PROPIOS

- [x] Task: `NoteEmitter` recibe la velocity y el gate del evento (FR7, FR12) — b74ac73
  - [x] Tests (Red): emitir con una velocity distinta de la del Groove produce
        ese note-on; el note-off sigue con velocity 0, que es la convención de
        MIDI 1.0.
  - [x] Tests (Red): emitir con un gate explícito sella el note-off a esa
        distancia, sin volver a mirar el Step.
  - [x] Tests (Red, FR16): **la vía de hoy no cambia** — un Pulse sin
        repeticiones emite exactamente el mismo par de mensajes, con la Velocity
        del Groove y el gate de Sustain sobre el Step.
  - [x] Implementación (Green): la velocity y el gate pasan a ser argumentos del
        evento, no cosas que el emisor deduce del `Groove`.
  - [x] Documentar el porqué: el Pulse y sus repeticiones tienen que viajar por
        **el mismo camino**. Un camino aparte para las repeticiones duplicaría la
        regla del note-off, que es la que evita notas colgadas.
- [~] Task: El gate de una repetición se mide sobre su hueco (FR12)
  - [ ] Tests (Red): con Sustain 100% y Repeats 3, cada repetición dura
        exactamente su hueco; con Pace ≠ 0, cada una dura **el suyo** y no el
        primero.
  - [ ] Tests (Red, FR16): **el Pulse sigue midiendo su gate sobre el Step**, con
        Repeats en 0 y con Repeats en 3.
  - [ ] Implementación (Green): reutiliza `Sustain.gateNanoseconds(forStep:)`
        pasándole el hueco — es un porcentaje sobre una duración, y el nombre del
        argumento se generaliza.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 4: LA TIRADA — EL `TrackScheduler` REPITE

- [ ] Task: El límite de la tirada (FR9)
  - [ ] Tests (Red): dado un Cycle y un Step que dispara, el límite es el
        **instante de emisión** del Pulse siguiente de la vuelta, con su Timing y
        su Delay dentro — no la rejilla recta.
  - [ ] Tests (Red): sin más Pulses por delante, el límite es **el cierre de la
        vuelta**, y la vuelta se mide desde `turnStartStep` para que cada Cycle
        cierre con su propia longitud.
  - [ ] Tests (Red): las repeticiones **cruzan Steps vacíos** del reparto
        euclidiano; solo las corta un Pulse.
  - [ ] Tests (Red): el límite **nunca mira dentro del Cycle siguiente**, porque
        cuál es lo decide este hilo al cerrar la vuelta.
  - [ ] Implementación (Green): la búsqueda del Pulse siguiente sobre el Shape
        vigente, con aritmética entera y sin recorrer más de una vuelta.
- [ ] Task: Las repeticiones se emiten (FR9, FR10, FR11, NFR1, NFR3)
  - [ ] Tests (Red): con Repeats 3 y Time 1/32 sobre un Track en 1/16, cada Pulse
        entrega **cuatro** note-on, el primero en la rejilla.
  - [ ] Tests (Red): la tirada arranca en el **Pulse ya desplazado** por Timing y
        Delay; ninguna repetición recibe swing propio.
  - [ ] Tests (Red): todas las repeticiones suenan **a la altura del Pulse**, y
        el recorrido del pool no se acelera — dos Pulses seguidos con Repeats
        altos siguen avanzando el pool de uno en uno.
  - [ ] Tests (Red): con Repeats 8 y Time 1/8 en un Track en 1/16, solo se emiten
        las que caben antes del Pulse siguiente.
  - [ ] Tests (Red, NFR3): con Repeats en 0 no se ejecuta nada del camino nuevo.
  - [ ] Implementación (Green): el bucle interior dentro del recorrido de
        ventana, sin arrays temporales ni coma flotante.
  - [ ] Comprobar que **`advanceBudgetNanoseconds` no cambia**: las repeticiones
        van siempre *después* del Pulse, así que no adelantan ningún instante y
        el presupuesto sigue siendo cosa de Delay.
- [ ] Task: Probability decide sobre todas las notas (FR13)
  - [ ] Tests (Red): cada evento consume **una** tirada, en orden — primero el
        Pulse, después las repeticiones.
  - [ ] Tests (Red): **un Pulse callado no se lleva sus repeticiones**.
  - [ ] Tests (Red): una repetición **descartada por el corte no consume
        tirada**, así que girar Time o Pace no desplaza las omisiones.
  - [ ] Tests (Red): misma semilla, misma secuencia de omisiones.
  - [ ] Tests (Red, FR16): **con Repeats en 0 el consumo de aleatoriedad es
        idéntico al de antes de la rebanada** — mismo número de tiradas, mismas
        omisiones, misma semilla.
  - [ ] Implementación (Green): la tirada por evento, después del corte y no
        antes.
- [ ] Task: El arnés no repite (FR14)
  - [ ] Tests (Red): `SchedulerMaterial.everyStep` devuelve el `NoteRepeater`
        neutro y no emite ninguna repetición.
  - [ ] Implementación (Green): la propiedad, junto a la de `groove`.
- [ ] Task: No regresión de punta a punta (FR16)
  - [ ] Tests (Red): un Pattern completo con Repeats en 0 produce **la misma
        secuencia de mensajes y los mismos instantes** que la referencia
        —instantes, velocities, gates y tiradas—, con Groove, Timing, Delay,
        Probability y varios Cycles dentro.
  - [ ] Implementación (Green): si algo falla aquí, es un fallo de las tareas
        anteriores y se arregla ahí, no con un caso especial para Repeats 0.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 5: LOS CUATRO KNOBS Y EL PRESET

- [ ] Task: Los cuatro CC en `ControlMapping` (FR4)
  - [ ] Tests (Red): CC 79 mueve Repeats, 80 Time, 81 Ramp y 83 Pace; el 82
        sigue moviendo el Cycle en edición y ningún otro parámetro cambia de CC.
  - [ ] Tests (Red): con un `knobBlock` distinto del por defecto, los cuatro
        siguen al bloque — ningún número queda clavado.
  - [ ] Tests (Red): las tres familias del preset siguen sin pisarse.
  - [ ] Implementación (Green): las cuatro entradas en `assignments`.
  - [ ] Reescribir el comentario de `defaultKnobBlock`, que hoy dice que los
        knobs 10 a 16 «se declaran y no se asignan; su sitio es de v2, con
        Cycles, Accent, Repeats, Time, Voicing y Range». Quedan libres tres.
- [ ] Task: El preset y su tabla (FR18)
  - [ ] Tests (Red): `PresetMappingTests` compara JSON, README y `ControlMapping`
        con los números nuevos, y falla si uno de los tres se queda atrás.
  - [ ] `preset/torax-h0.beatstep-pro.json`: los cuatro knobs, subiendo
        `version` y `updated`.
  - [ ] `preset/README.md`: la tabla de knobs, con los cuatro y los tres que
        siguen libres.
- [ ] Task: Temp y Ctrl All alcanzan a los cuatro (FR17)
  - [ ] Tests (Red): con [13] hundido, girar REPEATS iguala el valor en los
        Cycles activos del Track seleccionado y soltar devuelve el de cada uno.
  - [ ] Tests (Red): con [14] hundido, girar REPEATS desplaza los doce Tracks,
        el tope sale de las bases capturadas y soltar devuelve la base exacta.
  - [ ] Implementación (Green): **debería salir gratis** — los dos gestos operan
        sobre `TrackParameter`. Si hace falta tocar `ControlInput` o
        `ParameterOverlay`, es que hay una lista de parámetros escrita a mano en
        algún sitio: quitarla es parte de la tarea.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 6: LA PANTALLA

- [ ] Task: El card de Shape, en dos líneas (FR15)
  - [ ] Tests (Red): el texto de la familia trae las dos líneas y los ocho
        valores (cubierto en `Engine`, Fase 2; aquí se cablea).
  - [ ] Implementación (Green): la segunda línea en `ParameterFamilyCard`, mismo
        acento `#9AAB79`, sin color ni tipografía nuevos.
  - [ ] **El anillo no se toca**: dibuja Pulses, no repeticiones.
- [ ] Task: El valor grande transitorio de los cuatro (FR15)
  - [ ] Tests (Red): `ParameterOverlay` anuncia `Repeats 3`, `Time 1/32`,
        `Ramp +40%` y `Pace −20%`, y el test que compara el anuncio con el card
        sigue pasando.
  - [ ] Implementación (Green): las cuatro ramas.
- [ ] Task: Compilar la app para iPadOS y revisar en simulador
  - [ ] `xcodebuild build -scheme ToraxH0 -destination 'generic/platform=iOS'`.
  - [ ] Captura en simulador de la pantalla `track` con las dos líneas, y
        comprobar que el card no desborda a un metro con los ocho valores.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 7: DISPOSITIVO Y CIERRE

- [ ] Task: Verificación en iPad con BeatStep Pro (NFR6)
  - [ ] Los cuatro knobs mueven su parámetro, con valor grande transitorio y
        cambio audible **en el Step siguiente**.
  - [ ] Un ratchet de hi-hat: Repeats 3, Time 1/32. Un roll: Repeats 8, Time
        1/64. Ramp arriba y abajo. Pace a los dos lados.
  - [ ] **Al oído, lo que no se puede medir** (NFR6): que la tirada no se
        arrastre ni se adelante, que el swing la lleve entera y que Sustain no
        deje notas colgadas.
  - [ ] Probability al 50% con Repeats altos: textura agujereada, no huecos
        enteros.
  - [ ] Temp y Ctrl All sobre REPEATS: el fill sube, soltar lo devuelve.
  - [ ] Escribir `device-verification.md` con lo que se probó y lo que se oyó,
        **incluido lo que no cumplió**.
- [ ] Task: Cobertura y suite completa
  - [ ] `swift test --package-path Packages/Engine --enable-code-coverage` — ≥90%.
  - [ ] `MIDI` en un proceso, con el `.profdata` fusionado a mano e ignorando
        `Engine/Sources`, como dice `workflow.md` — ≥80%.
  - [ ] Si aparece `clientCreationFailed(-50)` en `VirtualLoopbackTests`, correr
        3–4 pasadas y comparar contra `main` antes de atribuirlo al cambio.
- [ ] Task: Pull Request
  - [ ] Rama `feat/note-repeater`, PR contra `main`. Nada entra en `main` sin PR.
  - [ ] **Cuerpo corto**: qué cambia, cómo se verificó en números, qué queda
        pendiente. Las decisiones se enlazan al `spec.md`, no se copian.
  - [ ] Anotar en el cuerpo que **no lleva medición de jitter** y por qué, que es
        la pregunta que un revisor va a hacer en un track que crea instantes
        nuevos entre los Steps.
- [ ] Task: Actualizar el registro y cerrar el track
  - [ ] `conductor/tracks.md`: marcar la rebanada 5 y su resultado.
  - [ ] Anotar en el `spec.md` cualquier requisito que se haya corregido
        implementando, con fecha, como hicieron `ctrl-all` y `temp-parameters`.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
