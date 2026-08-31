# Plan — MVP rebanada 7: Preset del BeatStep Pro — knobs, pads y step buttons

**Track ID:** `mvp-beatstep-mapping_20260830`

Sigue la metodología definida en [`workflow.md`](../../workflow.md): tests
fallando primero (Red), implementación mínima (Green), refactor, verificación de
cobertura y checkpoint de fase. El trabajo va en la rama
`feat/mvp-beatstep-mapping` y se integra por Pull Request.

**Orden.** La escala antes que el pad, porque «grado 7» no existe hasta que
alguien pueda enumerarlos; la superficie antes que el mensaje, porque qué nota da
un pad es dominio musical y se resuelve en `Engine`, donde hay tests y no hay
CoreMIDI; el mensaje antes que el preset completo, porque los pads son el cambio
de modelo y los knobs y los step buttons son tabla; la pantalla después, porque
consume lo que ya funciona; y el artefacto y el dispositivo cierran, porque **un
preset no está terminado hasta verse llegar en el iPad**.

**Lo que este orden evita.** Las fases 1 y 2 son `Engine` puro. La fase 3 toca
`MIDI` pero **no arranca el bucle del scheduler**: la entrada de control se
prueba con mensajes construidos a mano y un cierre de publicación, como ya hacen
`ControlMappingTests` y `PadPoolInputTests`. Eso deja a `midi-test-flake` fuera
del camino de esta rebanada — a diferencia de la 6, que sí tuvo que arrancarlo.
Si aun así aparece, la firma es la conocida y se descarta comparando pasadas.

**Sin medición de jitter.** No se toca `MusicalTimeline`, `LookAheadScheduler`
ni `SchedulerThread`, y no se añade carga visual al ritmo del reloj: es el caso
que la nota del 2026-08-28 de `workflow.md` exime. La medición final de v1 va con
la rebanada 8.

## Phase 1: Los grados y la superficie de pads [checkpoint: 7ad404a]

> `Engine` puro. Sin CoreMIDI, sin simulador, sin hardware. Es donde vive la
> corrección musical del track.

- [x] Task: Documentar las dos desviaciones **antes** de implementar (paso 8 del Task Workflow) — `96d24ee`
  - [x] Nota fechada en `Pre Spec Torax H-0.md`: los 16 Value Buttons dejan de ser un teclado cromático filtrado por Scale y pasan a ser grados de escala en dos octavas, con los pads 8 y 16 desplazando el registro
  - [x] La misma nota lleva la razón, no solo la regla: sobre dieciséis pads que envían dieciséis semitonos contiguos, el filtro cromático deja la mayoría muertos y acota el registro alcanzable a un octavo del rango MIDI — la superficie nueva cumple la intención de la Pre Spec («sólo las notas permitidas por la Scale») mejor que el mecanismo que proponía
  - [x] Nota fechada en `product.md`: el alcance de v1 lista «Mapeo del controlador + MIDI Learn» como una línea y se parte en dos rebanadas; la 7 entrega el preset, la 8 entrega MIDI Learn junto con `network-session-source`
  - [x] **No va en `tech-stack.md`:** las dos son decisiones de dominio, no de stack. Nada de la arquitectura cambia
- [x] Task: Una escala se puede enumerar por grados — `b9b76fc`
  - [x] Tests (Red): `minor`, `major`, `dorian` y `phrygian` tienen **7 grados**; `pentatonic` tiene **5** — los números salen de la máscara que ya existe, no de una tabla nueva
  - [x] Tests (Red): los grados son los semitonos de la máscara en orden ascendente desde 0: `major` da `[0,2,4,5,7,9,11]` y `pentatonic` da `[0,3,5,7,10]`, que es el registro canónico de `TonalFrameTests`
  - [x] Tests (Red): el grado 1 es siempre el 0 — el Root por definición, que es lo que hace que el pad 1 sea el Root seleccionado
  - [x] Tests (Red): enumerar no contradice a `allows(_:)`: toda altura construida desde un grado es admitida por el marco, sobre las cinco escalas y los doce Roots
  - [x] Implementación (Green): derivado de `pitchClassMask`, sin duplicar los intervalos en un segundo sitio donde puedan divergir
- [x] Task: `PadSurface` — qué altura tiene cada pad — `ee95f45`
  - [x] Tests (Red): con `major` y Root en Do, los pads 1–7 son las notas 48, 50, 52, 53, 55, 57, 59 — el grado 1 en la octava de C2, que es la que empieza en la nota MIDI 48
  - [x] Tests (Red): **el pad 9 es exactamente el pad 1 más doce semitonos**, sobre las cinco escalas y los doce Roots. Es la invariante de la que dependen los pads 8 y 16
  - [x] Tests (Red): los pads 9–15 son los mismos grados que los 1–7, una octava por encima, en el mismo orden
  - [x] Tests (Red): con Root en Re el pad 1 es la nota 50 — la base es la **octava**, no una nota fija; el grado 1 se mueve con el Root
  - [x] Tests (Red): con `pentatonic`, los pads **6, 7, 14 y 15 no tienen altura**, y los 1–5 y 9–13 sí. Es la desviación consciente de la decisión 3 del spec, fijada como comportamiento querido y no como efecto
  - [x] Tests (Red): los pads 8 y 16 nunca tienen altura — son desplazamiento, no nota, en todas las escalas
  - [x] Tests (Red): un índice fuera de 0–15 no tiene altura y no revienta
  - [x] Implementación (Green): función pura del índice, el `TonalFrame` y el desplazamiento vigente
- [x] Task: El desplazamiento de octava y su tope — `7ad404a`
  - [x] Tests (Red): **el ejemplo literal del requisito.** Pad 1 en C2 y pad 9 en C3; tras el pad 8 quedan en C1 y C2; desde el estado inicial, tras el pad 16 quedan en C3 y C4
  - [x] Tests (Red): subir y bajar mueve **todas** las alturas asignadas doce semitonos, no solo un bloque
  - [x] Tests (Red): el desplazamiento se admite mientras todas las alturas asignadas queden en 0–127; en el extremo el desplazamiento **no se aplica** y el estado queda idéntico
  - [x] Tests (Red): **no envuelve** —del tope agudo no se vuelve al grave— y **no recorta** —ninguna altura se queda pegada al borde mientras otra sigue subiendo—, que son las dos formas de romper el alineamiento por octava
  - [x] Tests (Red): el tope depende de la escala y del Root, y se comprueba sobre los dos extremos en las cinco escalas
  - [x] Implementación (Green): el desplazamiento es un valor del estado de la superficie; subir o bajar devuelve la superficie nueva o la misma
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 2: El pad es un índice, no una altura

> `MIDI`. Es el cambio de modelo: el número de nota entrante deja de llegar a
> `Pitch`. Sin arrancar el bucle del scheduler.

- [x] Task: El bloque de pads del preset se resuelve a índice — `e9348cf`
  - [x] Tests (Red): un `noteOn` del bloque de pads da su índice 0–15; el primero da 0 y el decimosexto da 15
  - [x] Tests (Red): una nota por debajo o por encima del bloque **no da índice** y no publica nada — mismo criterio que un CC sin asignar
  - [x] Tests (Red): el bloque es un dato del mapeo, no una constante repartida por el código: cambiarlo mueve los dieciséis pads a la vez
  - [x] Tests (Red): **el número de transporte no es la altura musical.** Un test que fije explícitamente que el pad cuyo mensaje es la nota 36 puede producir la nota 48, para que la coincidencia numérica del bloque no se lea nunca como identidad
  - [x] Implementación (Green): resta contra la nota base del bloque, sin tabla
- [x] Task: Pulsar un pad alterna el pool por índice — `6fefe6e`
  - [x] Tests (Red): los casos de `PadPoolInputTests` que siguen valiendo, **adaptados al índice y no reescritos**: un pad mete la altura, el mismo pad la saca, varios pads construyen un pool, el noveno se rechaza sin publicar, el note-off no alterna, el note-on de velocity cero no alterna
  - [x] Tests (Red): **un pad sin altura asignada no publica nada** — el 6 con `pentatonic`, y los 8 y 16 en cuanto a pool
  - [x] Tests (Red): el caso que desaparece: ya no existe «una altura fuera del marco tonal», porque toda altura de la superficie sale de la escala. El test viejo se sustituye por el que fija que **toda nota que un pad puede meter es admitida por el marco**, sobre las cinco escalas
  - [x] Tests (Red): girar un knob no borra el pool y pulsar un pad no borra el Shape — los dos tests de convivencia que ya existen siguen verdes
  - [x] Implementación (Green): `ControlInput` consulta la superficie y alterna; el resto del camino no cambia
- [x] Task: Los pads 8 y 16 desplazan sin tocar el pool — `ad11f67`
  - [x] Tests (Red): **con notas dentro del pool, desplazar la octava deja el pool byte a byte idéntico.** Es `product-guidelines.md` —cambiar un parámetro nunca destruye material— y es la decisión 4 del spec
  - [x] Tests (Red): bajar, meter dos graves, subir y meter dos agudas deja las cuatro en el pool — el caso de uso que justifica la superficie móvil
  - [x] Tests (Red): en el tope, pulsar el pad no publica nada y no cambia el estado
  - [x] Tests (Red): desplazar publica un snapshot solo si algo cambió; en el tope no se publica
  - [x] Implementación (Green): los dos índices se despachan a la superficie antes de llegar al pool
- [x] Task: Cambiar Scale o Root recalcula la superficie — `7f4d0f2`
  - [x] Tests (Red): `setFrame(_:)` sigue reencuadrando el pool en vez de vaciarlo — el comportamiento de la rebanada 4 no se toca
  - [x] Tests (Red): lo nuevo — **la superficie se recalcula con el marco y el desplazamiento vigente se conserva**: tras dos pulsaciones del pad 16, cambiar de Do a Re deja el pad 1 dos octavas arriba del nuevo grado 1, no en la base
  - [x] Tests (Red): pasar de `major` a `pentatonic` apaga los pads 6, 7, 14 y 15 sin tocar el pool ni el desplazamiento
  - [x] Implementación (Green)
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 3: El preset completo — knobs y step buttons

> `MIDI`. Aquí ya no hay cambio de modelo: es la tabla de números y lo que
> deliberadamente no se asigna.

- [ ] Task: `ControlMapping` pasa a describir el preset entero
  - [ ] Tests (Red): los nueve CC 70–78 siguen moviendo sus nueve parámetros en el orden de `TrackParameter` — **los tests existentes de `ControlMappingTests` pasan sin reescribirse**, que es la comprobación de que el preset conserva lo que ya funcionaba
  - [ ] Tests (Red): los CC de los knobs 10–16 no dan parámetro y no publican nada
  - [ ] Tests (Red): el bloque de pads y el bloque de step buttons son parte del mapeo, y **ningún número se solapa entre las tres familias** — un test que barra los tres bloques y falle si un número aparece dos veces
  - [ ] Implementación (Green): un valor que declara los tres bloques; su documentación deja de decir «fija y provisional» y pasa a decir qué preset describe y qué sigue pendiente (MIDI Learn, rebanada 8)
- [ ] Task: Los step buttons seleccionan Track
  - [ ] Tests (Red): un step button del bloque da su índice 0–15
  - [ ] Tests (Red): **en v1 solo el primero corresponde a un Track existente**; los otros quince no publican nada y no rompen el estado
  - [ ] Tests (Red): la soltada no hace nada — mismo criterio que el note-off de un pad
  - [ ] Tests (Red): pulsar el step button 1 no destruye el Track vigente: seleccionar el único que hay es una operación sin efecto, no un reinicio
  - [ ] Implementación (Green): la semántica final —step button N selecciona el Track N— con un solo Track detrás
- [ ] Task: Todo lo no asignado se ignora en silencio, y está probado
  - [ ] Tests (Red): un barrido de los 128 CC y las 128 notas sobre un `ControlInput` recién construido: **nada fuera de los bloques declarados publica**, y nada revienta
  - [ ] Tests (Red): el canal MIDI no se filtra, y el test lo fija como decisión y no como olvido — el mismo mensaje en dos canales distintos hace lo mismo
  - [ ] Implementación (Green): si el barrido encuentra un camino no declarado, se cierra
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 4: La octava en pantalla

> `App`. Cableado y dibujo. Ninguna lógica nueva aquí: si algo de esta fase
> merece un test, está en el sitio equivocado (`workflow.md`).

- [ ] Task: La octava vigente de los pads se lee junto al pool
  - [ ] Estado persistente, no valor grande transitorio: no lo mueve un knob (FR11)
  - [ ] Con el acento cromático de Tonal, que es la familia a la que pertenece
  - [ ] Legible a un metro, según `product-guidelines.md`
  - [ ] En el tope, la lectura tiene que dejar claro que no se puede seguir — un pad que no responde sin explicación visible es el defecto que esta fase existe para evitar
  - [ ] Verificación en simulador con captura, según las notas de entorno de `workflow.md`
- [ ] Task: Cableado de la superficie
  - [ ] La superficie vive donde ya vive el marco tonal, y se recalcula por el mismo camino
  - [ ] Sin controlador conectado la superficie se ve y no se edita, como el resto de los parámetros generativos
  - [ ] `xcodebuild build -scheme ToraxH0 -destination 'generic/platform=iOS'` en verde
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 5: El artefacto del preset y el dispositivo

> Es la fase que decide si el track vale. **Los números del preset no son
> ciertos hasta verse llegar en el iPad**, y esa es la lección de la nota del
> 2026-08-28 sobre los encoders en `Relative #2`, donde una suposición sobre el
> controlador clavó todos los parámetros en su extremo.

- [ ] Task: El preset del BeatStep Pro, versionado
  - [ ] Archivo cargable por MIDI Control Center en el repositorio
  - [ ] README junto a él con la tabla completa: los dieciséis knobs (nueve con parámetro, siete libres), los dieciséis pads y los dieciséis step buttons, con su número y su significado
  - [ ] El README incluye el modo **`Relative #2`** de los encoders, que ya está documentado en `workflow.md` y sin el cual todos los parámetros saltan a su extremo
  - [ ] El README dice qué hacer con un BeatStep Pro que no tenga el preset cargado: qué se rompe y cómo se reconoce
- [ ] Task: Verificación en dispositivo de los cuarenta y ocho controles
  - [ ] iPad real, BeatStep Pro con el preset cargado, sintetizador o destino MIDI real
  - [ ] Los dieciséis pads, uno a uno: qué nota mete cada uno, contra la tabla
  - [ ] Los pads 8 y 16, con notas ya en el pool: el registro se mueve y el pool no
  - [ ] Los dos extremos del desplazamiento: el pad deja de responder y la pantalla lo dice
  - [ ] Los nueve knobs asignados y los siete libres
  - [ ] Los dieciséis step buttons: el primero sin efecto visible, los otros quince sin efecto y sin romper nada
  - [ ] Con `pentatonic` cargada: los pads 6, 7, 14 y 15 no hacen nada, y es lo esperado
  - [ ] Se registra en un `device-verification.md` del track y en la git note
- [ ] Task: Reconciliar la tabla con lo observado
  - [ ] **Si el dispositivo desmiente algún número, manda el dispositivo**: se corrige la tabla, el preset y el código, en ese orden
  - [ ] Los tests que fijaban el bloque se actualizan con el número real y la razón queda en la git note
  - [ ] Si no hay discrepancia, se registra explícitamente que la tabla se verificó y coincidió — un resultado, no un silencio
- [ ] Task: Cerrar la rebanada
  - [ ] `swift test --package-path Packages/Engine --enable-code-coverage` y lo mismo para `MIDI`, contra los umbrales ≥90% y ≥80%
  - [ ] `ControlMapping` ya no se llama provisional, y lo que queda pendiente —MIDI Learn— está nombrado como rebanada 8
  - [ ] `tracks.md` refleja el corte de la rebanada 7 en dos y deja la 8 descrita
  - [ ] Pull Request contra `main`, con los checks en verde
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Notas de riesgo

1. **El número del bloque de pads es una suposición hasta la fase 5.** Las fases
   2 y 3 escriben tests contra un bloque elegido de antemano. Si el dispositivo
   lo desmiente, lo que cambia es un dato del mapeo y los tests que lo citan — no
   el modelo. Está aislado a propósito: por eso el bloque es un dato del mapeo y
   no una constante repartida (fase 2, tarea 1).

2. **La escala de más de siete grados no existe todavía, y el diseño no la
   cubre.** Las cinco de v1 tienen cinco o siete. Una escala de usuario cromática
   —admitida por la Pre Spec, fuera de v1— no cabe en siete pads. Queda como
   limitación escrita del spec, no como deuda de esta rebanada.

3. **`midi-test-flake` no está en el camino, pero puede aparecer.** Esta rebanada
   no arranca el bucle del scheduler, así que no debería verse. Si aparece, la
   firma es la conocida —las 4 pruebas de `VirtualLoopbackTests` con
   `clientCreationFailed(-50)`, ningún otro test— y se descarta comparando 3–4
   pasadas contra `main`. Sigue aplazado a después de la v2.

4. **`network-session-source` no bloquea, pero estorba.** En el iPad la sesión de
   red se autoselecciona como fuente y el BeatStep Pro hay que elegirlo a mano
   antes de cada verificación de la fase 5. Es fricción, no impedimento; el
   defecto se toma en la rebanada 8, donde sí bloquea.
