# Plan — Rediseño de las cuatro pantallas (track, scale, midi, banks)

**Track ID:** `screens-redesign_20260906`
**Spec:** [spec.md](./spec.md)

## Cómo se ejecuta este plan

**El TDD de `workflow.md` sigue vigente, y aquí casi nunca se dispara.** La
regla del proyecto es que `App` no se mide y que *si algo en `App` merece un
test, está en el sitio equivocado*. Este track es capa de presentación, así que
la mayoría de sus tareas no llevan fase roja: llevan una captura.

Lo que sí la lleva: **cualquier tarea que necesite lógica nueva**. Si al
implementar una pantalla aparece una decisión que no es dibujo —clasificar el
estado de un pattern, resolver qué octava mostrar, decidir si un pad entra al
pool—, esa lógica **baja a `Engine` y llega con test antes que con implementación**.
Cada fase lleva una tarea explícita para vigilarlo, porque el fallo típico de un
track de UI es dejar reglas sueltas dentro de una `View`.

**Verificación de fase:** `xcodebuild` verde, captura del simulador en landscape
comparada con el PNG de la pantalla, y confirmación explícita del usuario. Es el
protocolo de *Phase Completion Verification* de `workflow.md`, con la captura
ocupando el sitio de la cobertura que `App` no tiene.

**Integración:** rama propia, un commit por tarea, PR contra `main`. Sin push
directo.

---

## Fase 1 — Desviaciones, tokens y chrome compartido [checkpoint: b45c965]

Nada se dibuja hasta que el sistema de tokens esté cerrado. Es el orden que evita
que cuatro pantallas fijen cada una su propia interpretación del brief y luego
haya que perseguirlas.

- [x] Task: Documentar las dos desviaciones antes de tocar código `c4bdb08`
    - [x] Añadir nota fechada 2026-09-06 en `product-guidelines.md`: el fondo pasa de `#211823` a `#111211`, y **los tres acentos y el tratamiento neo-brutalista siguen siendo los cerrados el 2026-09-02**
    - [x] Añadir nota fechada 2026-09-06 en `product-guidelines.md`: la interfaz escribe en minúsculas; **cambia la caja, no el término** — `Steps` sigue siendo `Steps` en código, tests y documentación
    - [x] Verificar que ninguna de las dos notas contradice el «un solo término por concepto» de la guía
    - [x] Es el paso 8 del *Task Workflow*: se para, se anota, y solo entonces se implementa

- [x] Task: Cerrar el sistema de tokens (FR1, FR2) `502f2b8`
    - [x] `Palette`: fondo a `#111211` y rederivar los neutros —toolbar, inset, border, borderBright, step, muted, mutedBright— sobre el neutro, ya no sobre el violeta oscuro
    - [x] Comprobar el contraste de los tres acentos contra el fondo nuevo; el mauve de groove y el violeta de tonal son los que más riesgo tienen de acercarse
    - [x] `Brutalist`: confirmar trazos 2/3 pt, radios 3–8 y sombra dura sin blur; añadir lo que el brief pida y no exista
    - [x] `Typography`: revisar la escala para el chrome nuevo; **los tamaños viven aquí, no en las vistas**
    - [x] Dejar escrito en el propio tipo por qué el fondo cambió, con la fecha

- [x] Task: Bloquear landscape (FR30) `39b7e3f`
    - [x] `Config/Info-Debug.plist` y la configuración de Release: solo las dos orientaciones horizontales
    - [x] `xcodebuild clean` — el plist generado queda cacheado, según `tech-stack.md`
    - [x] Verificar que el `Info.plist` de Release sigue sin `UIBackgroundModes`

- [x] Task: `appChrome` — la barra superior (FR4, FR5, FR6) `3b95ec5`
    - [x] `torax h-0`, módulo activo centrado, punto de conexión, entrada MIDI, fuente de clock, tempo y transporte
    - [x] El `bpm` es tocable y edita el tempo interno; con reloj externo es lectura, no escritura
    - [x] `no midi device` aparece en la barra solo cuando no hay destino
    - [x] Todo el texto en minúsculas
    - [x] La barra no crece: el estado cede primero ante un nombre largo de endpoint

- [x] Task: `moduleNavigation` — la navegación persistente (FR7, FR8) `b1129d7`
    - [x] Cuatro entradas, subrayado off-white de 3 pt en la activa
    - [x] Retirar los prefijos numéricos y el borde discontinuo: las cuatro pantallas existen
    - [x] Verificar que cambiar de pantalla no reinicia el transporte ni el playhead

- [x] Task: Reducir `ContentView` a contenedor (FR31) `95a754d`
    - [x] Sacar el panel de jitter de la interfaz; **conservar `JitterMeasurementModel`** y su acceso por argumento de lanzamiento
    - [x] Retirar los tabs de familia y la regla «el giro cambia el tab»; su sustituto llega en la Fase 2
    - [x] `ContentView` queda como chrome más conmutador de pantalla, sin layout propio

- [x] Task: Auditar que no se escapó lógica a las vistas `794062a`
    - [x] Revisar lo escrito en esta fase: si hay una regla que no sea dibujo, bajarla a `Engine` o `MIDI` con test
    - [x] Ejecutar la suite de `Engine` y `MIDI` y confirmar que sigue verde

- [x] Task: Phase Verification & Checkpoint (ver `workflow.md`) `b45c965`

---

## Fase 2 — Pantalla `track` [checkpoint: ce92e29]

La pantalla principal y la que más restricciones tiene: es feedback, y sus
animaciones derivan del reloj musical.

- [x] Task: `ringPatternView` — los doce anillos (FR9, FR10) `bc7b977`
    - [x] Reparto 68 / 32
    - [x] Doce anillos concéntricos, track 01 fuera y track 12 dentro, sobre `RingStack`
    - [x] Contorno de 3 pt en el track seleccionado
    - [x] Un track silenciado se distingue **sin dejar de girar**: mute suprime salida, nunca cycle ni playhead
    - [x] Reajustar la geometría al chrome nuevo: la reserva vertical se escribe como suma, no como literal

- [ ] Task: Los playheads (FR11, NFR2)
    - [ ] Una aguja por anillo, off-white, cada una con la `Division` de su track
    - [ ] Verificar que **no se mueven con el transporte parado**
    - [ ] Confirmar que la posición se resuelve contra el origen del scheduler y que `TimelineView` solo decide cuándo repintar

- [x] Task: `cycleStrip` y la lectura grande (FR12) `c75a604`
    - [x] Lectura grande con nombre y valor; **persiste tras el giro**, pierde el acento y no el valor
    - [x] Card `cycle`: `03 / 08`, celdas `01`–`08`, activa marcada
    - [x] El icono de encadenamiento es **indicador de estado, no botón** — sin gesto asociado

- [x] Task: `parameterFamilyCard` — shape, groove y tonal (FR12) `96f4eb6`
    - [x] Los tres cards visibles a la vez, sin tabs
    - [x] Girar un knob resalta el card de su familia con su acento
    - [x] El card tonal muestra `scale`, `root` y el pool, **sin mapear alturas a steps**

- [x] Task: `trackPill` — la franja de doce tracks (FR13, FR14) `ad76d73`
    - [x] `01`–`12` con `m` / `s` bajo cada uno; refleja mute y solo vigentes
    - [x] Táctil: seleccionar track, mute, solo
    - [x] **Auditar la pantalla entera:** ningún gesto altera un parámetro generativo

- [x] Task: Estado sin hardware en `track` (FR29) `dc46ea4`
    - [x] Anillos, playheads y cards siguen visibles sin controlador ni destino
    - [x] Ninguna vía táctil suple un knob ausente

- [x] Task: Auditar que no se escapó lógica a las vistas `fd7f565`

- [x] Task: Phase Verification & Checkpoint (ver `workflow.md`) — captura contra `track.png` `ce92e29`

---

## Fase 3 — Pantalla `scale` [checkpoint: 803b1a0]

- [x] Task: Contexto de track, táctil (FR15) `c91c0f0`
    - [x] Muestra el track en edición y permite cambiarlo sin volver a `track`
    - [x] La selección es la misma que la de la franja: un solo estado, no dos

- [x] Task: `scalePicker` y `rootPicker` (FR16, FR17) `c91c0f0`
    - [x] Seis escalas; la elegida en violeta tonal con trazo de 3 pt
    - [x] Doce roots `c`–`b`; el elegido en off-white
    - [x] Cambiar escala o root **reencuadra el pool, no lo vacía** — la regla de `product-guidelines.md`, ya implementada en `PitchPool.reframed(to:)`

- [x] Task: `pitchPoolGrid` — la rejilla espejo del controlador (FR18, FR19, FR20) `c91c0f0`
    - [x] Rejilla 4×4 fiel a `PadSurface`: 14 pads de nota (7 grados × 2 bloques) y 2 pads de octava en las posiciones 8 y 16
    - [x] Los pads de octava **indican la octava vigente** (`PadSurface.octaveShift`); esa información no está en ninguna otra parte de la interfaz
    - [x] Pool en violeta tonal, resto neutro, **pads de octava nunca en violeta**
    - [x] Contador con el número real de notas; la novena no entra y el contador no miente
    - [x] Verificar que la rejilla dice qué alturas hay disponibles y nunca qué altura suena en qué step

- [x] Task: Retirar `TonalView` (FR32) `c91c0f0`
    - [x] Borrar el fichero una vez sus funciones están cubiertas
    - [x] Confirmar que no queda ninguna referencia

- [x] Task: Auditar que no se escapó lógica a las vistas `caf2107`
    - [x] Atención especial aquí: decidir si un pad entra al pool es lógica de `Engine`, no de la vista

- [x] Task: Phase Verification & Checkpoint (ver `workflow.md`) — captura contra `scale.png` `803b1a0`

---

## Fase 4 — Pantalla `midi` [checkpoint: b1ded87]

- [x] Task: Card `clock source` (FR21) `2bd1202`
    - [x] Segmentado `internal` / `external` reflejando la fuente real
    - [x] Lectura `internal clock · 124 bpm`; el ajuste de tempo está en la barra, **no se duplica aquí**

- [x] Task: Cards `midi input` y `midi output` (FR22, FR23) `2bd1202`
    - [x] Entrada: dispositivos disponibles con su estado; lo conectado marcado `connected`
    - [x] Lo que existe y no se puede usar: **borde discontinuo y `unavailable`**
    - [x] Salida: selección del destino externo y la nota `channel routing active`
    - [x] Comprobar que el `no midi device` de la barra y este card no se contradicen

- [x] Task: `midiChannelRow` — el routing de doce tracks (FR24) `2bd1202`
    - [x] Filas `track 01`–`track 12` con `ch 01`–`ch 12`
    - [x] Track seleccionado resaltado; recuento de tracks enrutados

- [x] Task: Retirar `ChannelMapView` (FR32) `2bd1202`
    - [x] Borrar el fichero y confirmar que no queda ninguna referencia
    - [x] Verificar que el ajuste de tempo no se pierde al borrarla: vive ahora en la barra

- [x] Task: Estado sin hardware en `midi` (FR29) `2bd1202`
    - [x] Lista de entrada vacía, salida en gris, estructura intacta

- [x] Task: Auditar que no se escapó lógica a las vistas `9b6d058`

- [x] Task: Phase Verification & Checkpoint (ver `workflow.md`) — captura contra `midi.png` `b1ded87`

---

## Fase 5 — Pantalla `banks` [checkpoint: 646eef4]

Cáscara visual, y declarada como tal. La tarea de honestidad no es opcional: es
lo que separa esta pantalla de una maqueta que miente.

- [x] Task: `bankGrid` — la columna de bancos (FR26) `4c77f6e`
    - [x] `bank 01` y rejilla 4×4 de `01`–`16`, banco 01 seleccionado
    - [x] Pie con tempo y número de patterns

- [x] Task: `patternGrid` — la rejilla de patterns (FR27) `4c77f6e`
    - [x] 4×4 de `01`–`16`; el que suena en olivo de shape y etiquetado `playing`
    - [x] Los demás, `ready` o `empty` según tengan material
    - [x] Clasificar el estado de un pattern es lógica: si no es una lectura directa del `Pattern`, baja a `Engine` con test

- [x] Task: `track assignments` — la columna derecha (FR28) `4c77f6e`
    - [x] Doce filas de track a pattern, con la fila del track seleccionado enfatizada

- [x] Task: Declarar el alcance en la pantalla y en el código (FR25) `4c77f6e`
    - [x] La selección se mueve y **no altera lo que suena**
    - [x] Dejar escrito en el propio fichero que es cáscara sobre el `Pattern` actual y qué haría falta para levantarla
    - [x] Verificar que ningún gesto de esta pantalla llega al scheduler

- [x] Task: Auditar que no se escapó lógica a las vistas `1c1d3ff`

- [x] Task: Phase Verification & Checkpoint (ver `workflow.md`) — captura contra `banks.png` `646eef4`

---

## Fase 6 — Cierre

- [ ] Task: Auditoría del sistema de tokens (FR1, criterio 3)
    - [ ] `grep` en `App/` buscando literales de color, `Font.custom`, grosores, radios y sombras fuera de `Palette`, `Typography` y `Brutalist`
    - [ ] Corregir cada hallazgo llevándolo al token que corresponda; si no existe, crearlo ahí
    - [ ] Repetir la búsqueda hasta que salga vacía

- [ ] Task: Auditoría de minúsculas (FR3, criterio 2)
    - [ ] Revisar cada cadena visible de las cuatro pantallas y del chrome
    - [ ] Confirmar que el vocabulario capitalizado sigue intacto en código, tests y documentación

- [ ] Task: Auditoría de alcance (NFR1)
    - [ ] `git diff main --name-only` y confirmar que `Engine` y `MIDI` solo cambian por lógica que bajó con sus tests
    - [ ] Confirmar que el camino de tiempo real no aparece en el diff
    - [ ] Ejecutar la suite completa; el flake de CoreMIDI en `MIDITests` es ruido conocido y no se atribuye a este track

- [ ] Task: Repaso de los trece criterios de aceptación del spec
    - [ ] Recorrerlos uno a uno contra la app corriendo
    - [ ] Registrar cualquiera que no se cumpla como tarea, no como nota al pie

- [ ] Task: Abrir el Pull Request
    - [ ] Rama propia contra `main`, sin push directo
    - [ ] Descripción con las dos desviaciones documentadas y las dos limitaciones conocidas

- [ ] Task: Phase Verification & Checkpoint (ver `workflow.md`)
