# Plan — v2 rebanada 1: Dieciséis Tracks sobre un reloj

Sigue el Task Workflow de [`workflow.md`](../../workflow.md): tests antes que
implementación, un commit por tarea con su git note, y checkpoint al cerrar cada
fase.

**El orden no es de gusto.** Primero el valor —que dieciséis Tracks sean un dato
trivial—, luego el canal por el que cruza al hilo de tiempo real, luego el
scheduler que los emite, y solo entonces la entrada y la pantalla. Al revés se
descubriría en la última fase que el snapshot no cabe por donde tiene que pasar.

**La medición de jitter es una fase, no una tarea.** Esta rebanada cambia
*cuándo* cae cada evento —dieciséis rejillas donde había una— y eso es
exactamente lo que la nota del 2026-08-28 de `workflow.md` obliga a medir. Una
regresión la bloquea.

---

## Phase 1: Dieciséis Tracks son un valor [checkpoint: 4b92603]

> `Engine` puro. Sin CoreMIDI, sin simulador, sin hardware. Es donde se decide si
> el resto de la rebanada es posible: si el conjunto no es un valor trivial, no
> puede cruzar al hilo del scheduler y hay que rehacer el enfoque.

- [x] Task: `Pattern` — los dieciséis Tracks como un solo valor — `b0d16cd`
  - [x] Tests (Red): un `Pattern` recién construido tiene **dieciséis** Tracks y ninguno es opcional; no hay Tracks que crear ni destruir
  - [x] Tests (Red): **`_isPOD(Pattern.self)` es verdadero.** Es la red que ya vigila a `Track`, extendida al tipo que de verdad cruza al hilo de tiempo real
  - [x] Tests (Red): leer un índice fuera de 0–15 no revienta — mismo criterio que un pad fuera de la superficie
  - [x] Tests (Red): sustituir un Track devuelve un `Pattern` nuevo con **solo ese** cambiado, comprobado sobre los otros quince
  - [x] Implementación (Green): almacenamiento inline de tamaño fijo, por la misma razón que `PitchPool` lo es — un `Array` traería conteo de referencias y rompería la trivialidad
  - [x] **El nombre es `Pattern` y no una palabra nueva** (NFR6): la Pre Spec llama así al conjunto de los dieciséis Tracks. Que todavía no se pueda tener más de uno es una limitación, no otro concepto
- [x] Task: El Track por defecto y el arranque — `1d3c768`
  - [x] Tests (Red): el `Pattern` inicial tiene material **solo en el Track 1**, con el pool de una altura que la app ya usa; los otros quince están vacíos
  - [x] Tests (Red): un Track vacío no dispara nada aunque su Shape tenga Pulses — el comportamiento de hoy, comprobado ahora sobre quince a la vez
  - [x] Implementación (Green)
- [x] Task: El canal MIDI es un dato del Track — `4b92603`
  - [x] Tests (Red): el Track N arranca en el canal N, sobre los dieciséis
  - [x] Tests (Red): cambiar el canal de un Track no toca el de los otros; dos Tracks pueden compartir canal
  - [x] Tests (Red): el canal se mantiene dentro de 1–16 por construcción
  - [x] Tests (Red): `_isPOD` sigue verdadero con el canal dentro
  - [x] Implementación (Green): vive en `Track`, junto a lo que el hilo del scheduler necesita para construir el mensaje
  - [x] **Documentar la desviación** si el tipo de canal de `Engine` duplica al de `MIDI`: el motor no importa nada de plataforma, y la conversión vive en la capa que conoce ambos —igual que `Pitch`—
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 2: El snapshot que cruza al scheduler

> `MIDI`. El `TrackHandoff` ya dice en su documentación que «el protocolo no
> depende del tamaño del snapshot: la ranura simplemente será mayor». Esta fase
> lo cobra.

- [~] Task: `TrackHandoff` publica un `Pattern`
  - [ ] Tests (Red): publicar y leer devuelve los dieciséis Tracks intactos
  - [ ] Tests (Red): los tests de disciplina de ranura que ya existen siguen valiendo **adaptados al valor nuevo, no reescritos**: el lector descarta si el escritor le da alcance, y nunca lee una ranura a medio escribir
  - [ ] Tests (Red): el escritor concurrente y el lector en bucle no producen ningún `Pattern` mezclado —mitad de una publicación y mitad de otra—, que es el fallo que el anillo existe para evitar y que con un valor mayor es más fácil de provocar
  - [ ] Implementación (Green): el tipo de la ranura, sin tocar el protocolo
- [ ] Task: El coste de copiar el snapshot, medido y escrito
  - [ ] Comprobar el tamaño real de `Pattern` con `MemoryLayout` y **registrarlo en la git note**: es lo que el hilo del scheduler copia en cada ventana
  - [ ] Si el tamaño resulta desproporcionado para copiarlo por ventana, **parar y decidirlo explícitamente** en vez de seguir: la alternativa —leer solo lo que cambió— es otro diseño, no un ajuste
  - [ ] Dejar el número escrito en la documentación del handoff, que es donde alguien lo buscará
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 3: Un reloj, dieciséis rejillas

> `MIDI`, y el corazón de la rebanada. Aquí es donde el jitter se puede degradar,
> así que aquí es donde hay que ser conservador: nada nuevo en el bucle que no
> sea aritmética sobre valores ya copiados.

- [ ] Task: El scheduler recorre los Tracks con material
  - [ ] Tests (Red): con un solo Track con material, la secuencia emitida es **byte a byte la de hoy** — la regresión que más importa, porque es la que dice que no se rompió lo entregado
  - [ ] Tests (Red): con dos Tracks, se emiten los eventos de los dos, cada uno en sus posiciones
  - [ ] Tests (Red): un Track vacío no programa nada — el coste crece con los Tracks con material, no con dieciséis siempre (NFR3)
  - [ ] Tests (Red): con los dieciséis llenos no se pierde ningún evento dentro de una ventana
  - [ ] Implementación (Green): un solo hilo y un solo `SchedulerThread`; el bucle recorre los Tracks dentro de la ventana ya abierta
  - [ ] **Sin asignaciones, locks ni `await` nuevos en el bucle**, que es la regla que no se negocia (`swift.md`)
- [ ] Task: Cada Track cae en su propia rejilla, en fase
  - [ ] Tests (Red): **dos Tracks con Divisions distintas comparten origen** — el 1/8 cae exactamente sobre uno de cada dos 1/16, y no se desalinean al cabo de muchos ciclos
  - [ ] Tests (Red): dos Tracks con Steps distintos —16 y 12— vuelven a coincidir donde les toca, sin deriva acumulada
  - [ ] Tests (Red): el Timing y el Delay de un Track no desplazan a los otros
  - [ ] Tests (Red): el playhead de cada Track avanza por su propia longitud
  - [ ] Implementación (Green): una `MusicalTimeline` por Track sobre un solo origen, o el equivalente que no duplique el origen — **la deriva se evita compartiendo el origen, no sincronizando después**
- [ ] Task: Dieciséis generadores, uno por Track
  - [ ] Tests (Red): misma semilla, misma secuencia, por Track (NFR4)
  - [ ] Tests (Red): **dos Tracks con la misma Probability no omiten los mismos Pulses** — con un solo generador compartido el aleatorio se oiría como una sola decisión, y este test es lo que lo impide
  - [ ] Tests (Red): el estado del aleatorio **no** entra en el snapshot: sigue siendo del scheduler, que es su único dueño, y `_isPOD(Pattern.self)` lo confirma
  - [ ] Implementación (Green)
- [ ] Task: Cada Track emite por su canal
  - [ ] Tests (Red): los mensajes de un Track llevan su canal; cambiarlo cambia lo que sale
  - [ ] Tests (Red): dos Tracks en el mismo canal conviven sin pisarse los note-off
  - [ ] Implementación (Green)
- [ ] Task: Stop para los dieciséis sin dejar notas colgadas
  - [ ] Tests (Red): con los dieciséis sonando, tras `Stop` no queda ningún note-on sin su note-off
  - [ ] Tests (Red): **el caso con Delay positivo**, que la rebanada 6 dejó anotado como deuda sin reproducir: con dieciséis Tracks es más probable, así que se cubre aquí
  - [ ] Tests (Red): el gate de Sustain de cada Track es independiente del de los demás
  - [ ] Implementación (Green)
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 4: La entrada edita el Track seleccionado

> `MIDI`. Aquí `trackCount` pasa de 1 a 16 y la costura que dejó la rebanada 7 se
> usa por primera vez. El preset no se toca.

- [ ] Task: Los knobs y los pads mueven el Track seleccionado
  - [ ] Tests (Red): girar un knob cambia el parámetro **del seleccionado** y de ninguno más, comprobado sobre los nueve
  - [ ] Tests (Red): un pad edita el pool del seleccionado
  - [ ] Tests (Red): **seleccionar otro Track no cambia nada del que se deja** — parámetros, pool, marco tonal y octava de pads siguen como estaban al volver
  - [ ] Tests (Red): los dieciséis step buttons seleccionan, y ahora ninguno se ignora
  - [ ] Implementación (Green): `trackCount` a 16; el resto del camino ya está escrito
- [ ] Task: El marco tonal deja de ser global
  - [ ] Tests (Red): dos Tracks en escalas distintas conviven; cambiar la Scale de uno no reencuadra el pool del otro
  - [ ] Tests (Red): al seleccionar un Track, **la superficie de pads se recalcula con su marco y con su desplazamiento de octava**
  - [ ] Tests (Red): el reencuadre del pool al cambiar de Scale sigue siendo el de la rebanada 4, ahora por Track
  - [ ] Implementación (Green): el marco viaja en el Track; `ControlInput` deja de tener uno propio
  - [ ] **Documentar la desviación**: `product.md` describe Scale y Root como configuración de la app; pasan a ser del Track, como dice la Pre Spec
- [ ] Task: El canal se edita, y no con un knob
  - [ ] Tests (Red): la edición del canal no pasa por `ControlMapping` — ningún CC lo mueve
  - [ ] Tests (Red): cambiar el canal publica el snapshot, para que el scheduler lo use en el evento siguiente
  - [ ] Implementación (Green)
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 5: La pantalla mínima para operar

> `App`. Cableado y dibujo, sin lógica nueva: si algo de esta fase merece un
> test, está en el sitio equivocado (`workflow.md`). **No es la UI del handoff**
> —los anillos concéntricos son la rebanada siguiente—; es lo justo para que
> dieciséis Tracks se puedan usar y verificar.

- [ ] Task: Qué Track está seleccionado y cuáles tienen material
  - [ ] Los dieciséis, con el seleccionado marcado y los que tienen material distinguidos de los vacíos
  - [ ] Legible a un metro y tocable de pie, según `product-guidelines.md`
  - [ ] Seleccionar desde la pantalla hace lo mismo que el step button — sin controlador conectado hay que poder mirar
- [ ] Task: El estado del Track seleccionado, y su canal
  - [ ] Anillo, parámetros, pool y octava de pads pasan a ser los del seleccionado
  - [ ] El canal se lee y se edita, con el mismo criterio táctil que Scale y Root
  - [ ] Verificación en simulador con captura
  - [ ] `xcodebuild build -scheme ToraxH0 -destination 'generic/platform=iOS'` en verde
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 6: La medición y el dispositivo

> La fase que decide si la rebanada vale. **El riesgo que la v1 existió para
> acotar se cobra aquí**: dieciséis voces sobre un hilo, medidas contra el mismo
> umbral de siempre.

- [ ] Task: Jitter con los dieciséis sonando
  - [ ] iPad real, con el arnés, en la división más rápida y el tempo más alto ya usados —comparable con las cuatro mediciones anteriores—
  - [ ] Umbral: **máximo < 2 ms, σ < 0,5 ms**. Se registra el número, no la impresión
  - [ ] Se compara contra la referencia de la rebanada 6 —máx 0,151 ms, σ 0,009–0,013 ms— y **la diferencia se explica**, tanto si sube como si no
  - [ ] Si hay regresión: **la rebanada se para**, y se bisecta con el arnés antes de seguir. No se cierra con una medición mala explicada
  - [ ] El resultado va a `product.md`, junto a las otras cuatro
- [ ] Task: Verificación en dispositivo
  - [ ] BeatStep Pro y varios instrumentos —o un multitímbrico— en canales distintos
  - [ ] Seleccionar Tracks con los step buttons y darles material: cada uno suena por su canal
  - [ ] Dos Tracks en Divisions distintas: se oye que están en fase
  - [ ] Dos Tracks en tonalidades distintas: la Scale de uno no mueve al otro
  - [ ] `Stop` con los dieciséis sonando y con Delay positivo: nada queda colgado
  - [ ] Se registra en un `device-verification.md` del track y en la git note
- [ ] Task: Cerrar la rebanada
  - [ ] Cobertura de `Engine` ≥90% y de `MIDI` ≥80%, medidas como dice `workflow.md`
  - [ ] `product.md` refleja que múltiples Tracks dejan de estar fuera de alcance, y qué queda de la v2
  - [ ] `tracks.md` deja descrita la rebanada siguiente —la UI del handoff—
  - [ ] Pull Request contra `main`, con los checks en verde
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Notas de riesgo

1. **El tamaño del snapshot es la incógnita real.** Dieciséis Tracks copiados por
   ventana pueden ser un `memcpy` irrelevante o un problema; el número no se sabe
   hasta la fase 2, y por eso se mide ahí y no al final. Si sale desproporcionado,
   la decisión —copiar todo, o publicar por Track— se toma explícitamente en ese
   momento, con el dato delante.

2. **La deriva entre rejillas es un fallo que tarda en verse.** Dos Tracks con
   Divisions distintas pueden sonar bien un minuto y separarse al cabo de mil
   ciclos. Los tests de la fase 3 comprueban muchos ciclos a propósito, y no un
   par de compases.

3. **`midi-test-flake` estará en el camino.** Esta rebanada arranca el bucle del
   scheduler en los tests, que es la condición que dispara el flake. Sigue
   aplazado a después de la v2: se corre `MIDI` con la partición de CI, la firma
   conocida —las 4 pruebas de `VirtualLoopbackTests` con
   `clientCreationFailed(-50)`— se descarta comparando pasadas, y la cobertura se
   mide con el `.profdata` fusionado a mano.

4. **`scheduler-lifecycle` sigue parado y esta rebanada toca su terreno.** La
   carrera de `stop()`/`start()` es real y su arreglo no se integró. Con dieciséis
   Tracks no empeora —el hilo sigue siendo uno— pero conviene no dar por sano lo
   que no lo está: si aparece un Step duplicado en los tests, es ese defecto y no
   este cambio.

5. **La v1 no está cerrada.** MIDI Learn —rebanada 8— sigue pendiente y con él la
   medición final de v1. Esta rebanada la adelanta de hecho: si el jitter con
   dieciséis Tracks está dentro del umbral, el de uno también lo está.
