# Spec — MVP rebanada 4: Tonal — pool, Scale y Root

**Track ID:** `mvp-tonal_20260828`
**Track type:** Feature

## Overview

El motor por capas de `product.md` es: **Shape** decide *cuándo* ocurren los
eventos → **Tonal** define *de qué material* se eligen las alturas → **Groove**
convierte la secuencia en interpretación. Shape está entregado y verificado. Esta
rebanada es la capa siguiente.

Hoy todo suena en una sola altura: `NoteEmitter` lleva canal, nota y velocity
constantes, y su documentación lo declara *«constante provisional del camino
MIDI, no estado del Track»*. Vive ahí, y no en `Track`, precisamente para que
nada consolidara la idea de una nota fija por paso mientras Tonal no existiera.
Ahora existe.

### Pool, no piano-roll

La Pre Spec es explícita y `product-guidelines.md` lo eleva a antipatrón:
**mostrar una nota fija por paso contradice el modelo**. `PITCH` determina el
*pool* de notas que un Track puede usar; no escribe una melodía. Una nota
activada entra al pool, una desactivada se excluye, y el pool va de una nota
—centro estable— a ocho.

De ahí salen las dos reglas que ordenan esta rebanada:

1. **El anillo y el pool son representaciones paralelas y separadas**: cuándo
   suena algo, y de qué material se elige. No se cruzan en una sola vista.
2. **No se muestra qué nota sonó en cada paso.** Ni en la pantalla ni en el
   modelo: `Track` guarda el pool, no una asignación de altura por posición.

### Las tres deudas que paga

**1. El camino de tiempo real emite una altura fija.** `TrackScheduler` decide
*si* un Step dispara; `NoteEmitter` decide con qué sonar, y hoy es una constante.
Abrirlo es el único cambio de esta rebanada donde una regresión de jitter es
posible, y por eso la verificación en dispositivo vuelve a ser criterio de
cierre.

**2. El snapshot tiene que seguir siendo trivial.** `tech-stack.md` lo dejó
escrito antes de que hiciera falta: *«cuando llegue Tonal, el pool de pitches
tiene que ser almacenamiento inline de 8 huecos, no un array»*. `Track` se copia
en el hilo del scheduler y un `Array` metería `retain`/`release` ahí. El test
`_isPOD(Track.self)` de `TrackHandoffTests` es la red que lo vigila, y esta
rebanada es la primera que puede romperla.

**3. Los pads son entrada nueva.** La Pre Spec: al pulsar PITCH, los 16 Value
Buttons se comportan como teclado cromático. Hoy `ControlInput` solo entiende
Control Change. Recibir notas no es una extensión del mapeo de CC: es otra
superficie.

### Dos decisiones tomadas antes de planificar

**La altura se elige recorriendo el pool en orden.** Cada Pulse toma la
siguiente y vuelve al principio al agotarlo: es el arpegio ascendente que la Pre
Spec describe para Style monofónico, que es el único Style dentro de v1.
Determinista, sin PRNG.

**Pero la convención entra como un tipo, no cableada.** Mismo patrón que
`RelativeEncoding`: hoy un solo caso, y añadir el recorrido aleatorio —o los que
traigan Phrase y Range— será añadir un caso, no reescribir el camino de tiempo
real. El PRNG sembrado que `tech-stack.md` exige llega con Probability, en la
rebanada 5; adelantarlo aquí obligaría a decidir dónde vive su estado y cómo se
reinicia por vuelta sin tener todavía quien lo use.

**La pantalla de Scale y Root entra en la rebanada.** `product-guidelines.md`
las pone del lado táctil, no del knob. Sin la pantalla quedarían como constantes
que nadie puede cambiar, y la regla de destructividad —*«el pool tonal sobrevive
a un cambio de Scale reencuadrándose, no vaciándose»*— no se podría verificar en
la app, solo en tests.

## Functional Requirements

### FR1 — El marco tonal acota las alturas

`Scale` define el conjunto de notas permitido y `Root` su centro tonal. Solo se
ofrecen escalas preset: Minor, Major, Dorian, Phrygian y Pentatonic. Las escalas
de usuario quedan fuera.

Ninguna altura que salga al MIDI cae fuera del marco vigente.

### FR2 — El pool guarda hasta ocho pitches

Un Track lleva de cero a ocho alturas. Cero es un estado válido y silencioso: el
Track dispara sus Pulses pero no tiene material que emitir, y eso se comunica
como estado, no como error.

### FR3 — Cambiar el marco reencuadra el pool, no lo vacía

Al cambiar Scale o Root, las notas del pool que queden fuera del nuevo marco se
**reubican en la nota permitida más cercana**, conservando su número. Nunca se
eliminan.

Es la regla de destructividad de `product-guidelines.md` aplicada literalmente,
y la misma que ya rige a `Pulses` desde la rebanada 2: cambiar un parámetro no
destruye material.

### FR4 — La altura de cada Pulse sale del pool, en orden

Cada Pulse toma la siguiente altura del pool y vuelve al principio al agotarlo.
El recorrido es **determinista**: mismo pool y mismo Pulse, misma altura.

La convención de recorrido entra como un valor, no cableada, para que añadir
otras sea añadir casos.

### FR5 — El camino de tiempo real no engorda

`Track` sigue siendo un tipo trivial: el pool es almacenamiento inline de ocho
huecos, sin `Array` ni nada con conteo de referencias. Elegir la altura de un
Pulse no asigna, no toma locks y no espera.

### FR6 — Los pads editan el pool

Un mensaje de nota entrante alterna la pertenencia de esa altura al pool: si no
estaba, entra; si estaba, sale. Las alturas fuera del marco tonal se ignoran en
silencio, como ya se ignora un CC sin mapear — no es un error.

### FR7 — El pool se ve, sin sugerir una nota por paso

La pantalla muestra el pool sobre la Scale: qué notas están disponibles y cuáles
están activas. **No muestra qué nota suena en cada Step**, ni conecta el pool con
las posiciones del anillo.

Tonal tiene su acento cromático, declarado en el mismo sitio que el de Shape.

### FR8 — Scale y Root se eligen en pantalla

Una pantalla permite elegir Scale entre los presets y Root entre las notas. El
cambio se refleja en el pool según FR3, y en el sonido a partir del Step
siguiente.

Es configuración, así que es táctil: la frontera de `product-guidelines.md` entre
knobs y pantalla se respeta sin excepciones.

### FR9 — Lo entregado sigue en pie

Transporte, anillo, playhead, valor transitorio, selección de dispositivo y el
estado de solo lectura siguen funcionando. Sin controlador conectado el pool no
se edita —es material generativo— pero Scale y Root sí, porque son
configuración.

## Non-Functional Requirements

- **NFR1 — Realtime safety.** Elegir la altura corre en el hilo del scheduler:
  sin asignaciones, sin locks, sin `await`, sin logging. Marcador `/// Realtime:`
  en todo lo que corra ahí.
- **NFR2 — `Track` sigue siendo trivial.** `_isPOD(Track.self)` sigue en verde.
  No se relaja el test ni se mueve el pool fuera del snapshot para esquivarlo.
- **NFR3 — Sin regresión de jitter, medida en dispositivo.** Se toca el camino de
  emisión, así que la medición vuelve a ser criterio de cierre. Referencia: máx
  0,134 ms y σ 0,020 ms con el anillo corriendo (rebanada 3).
- **NFR4 — Cobertura:** `Engine` ≥90%, `MIDI` ≥80%.
- **NFR5 — La lógica no vive en `App`.** El marco tonal, el reencuadre y el
  recorrido del pool son `Engine`; la recepción de notas es `MIDI`. `App` cablea
  y dibuja.
- **NFR6 — Vocabulario de la Pre Spec.** `Pitch`, `Scale`, `Root`, `pool`. Sin
  sinónimos: `pool` no es `chord`, y no se introduce `note` donde el dominio dice
  `pitch`.

## Acceptance Criteria

**Criterio principal:**

> Con un pool de varias notas, el Track arpegia sobre ellas en vez de repetir una
> sola altura, y todo lo que suena está dentro de la Scale y el Root elegidos.

Además:

- [ ] Ninguna altura emitida cae fuera del marco tonal, verificado de forma
      exhaustiva sobre los presets.
- [ ] Bajar el pool a una nota da un centro estable; subirlo a ocho no rompe
      nada.
- [ ] Un pool vacío no emite y no es un error.
- [ ] Cambiar Scale o Root **reubica** las notas fuera de marco y **no** las
      elimina: el tamaño del pool se conserva.
- [ ] El recorrido es determinista: mismo pool y mismo Pulse, misma altura.
- [ ] `_isPOD(Track.self)` sigue en verde con el pool dentro.
- [ ] Un pad activa una altura; el mismo pad la desactiva. Una altura fuera de
      marco se ignora en silencio.
- [ ] La pantalla muestra el pool sobre la Scale y **no** una nota por paso.
- [ ] Scale y Root se cambian tocando, con el transporte corriendo y sin
      cortarlo.
- [ ] Jitter medido en iPad con Tonal activo, comparado contra máx 0,134 ms · σ
      0,020 ms de la rebanada 3.
- [ ] `swift test` sobre `Engine` y `MIDI` pasa sin simulador ni hardware.

## Known Limitations

1. **Solo Style monofónico.** Los acordes simultáneos están fuera de v1 por la
   propia Pre Spec. El pool suena una nota por vez.
2. **Recorrido secuencial y nada más.** Sin aleatorio, sin Phrase, sin Range. La
   costura queda puesta para añadirlos.
3. **Escalas preset, sin escalas de usuario.**
4. **Sin Voicing, Style ni Harmony.** El pool se recorre tal cual, sin
   desplazamiento de octavas ni movimiento de voces.
5. **Sin persistencia.** El pool y la Scale se pierden al cerrar la app, como
   todo lo demás hasta que exista Autosave.
6. **El mapeo de los pads es fijo y provisional**, como el de los CC. MIDI Learn
   llega en la rebanada 7.

## Out of Scope

- Groove entero: Velocity, Sustain, Timing, Delay, Probability.
- PRNG sembrado y elección aleatoria de altura.
- Voicing, Style, Harmony, Range, Phrase, Note Repeater.
- Escalas de usuario.
- Preset del BeatStep Pro y MIDI Learn.
- Persistencia, Autosave y Backup Project.
- Múltiples Tracks, Patterns, Banks y Cycles.
