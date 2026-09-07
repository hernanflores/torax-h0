# Spec — v2 rebanada 6: LFO Modulation

## Overview

La modulación añade **movimiento cíclico a la velocity**, sincronizado con la
vuelta del anillo del Track. No cambia qué notas suenan ni cuándo: cambia **con
cuánta fuerza** se emiten a lo largo del loop.

Es lo que hace que un patrón repetido deje de sonar mecánico sin tocar el
material. Hoy no se puede: Velocity es un número fijo para todos los Steps del
Cycle, así que la única forma de que un golpe suene distinto del anterior es
cambiar de Cycle — que cambia el Track entero, no solo la dinámica.

Dos parámetros, una pantalla:

| Parámetro | Qué decide | Rango | Default |
|---|---|---|---|
| **waveform** | La forma del movimiento | `saw`, `triangle`, `sine`, `pulse` | `triangle` |
| **accent** | Cuánto se desvía la velocity, con signo | −100 … +100 | 0 |

**Con `accent` en 0 —el default— no cambia nada de lo entregado.** Es la
condición de no regresión de la rebanada y la regla de destructividad de
`product-guidelines.md` aplicada al código: un parámetro nuevo no cambia lo que
ya hacía quien no lo pide.

**Sale de «Fuera de v1».** `product.md` lista hoy «LFO y Random Modulation»
entre lo que queda fuera. Entra la mitad —el LFO cíclico, y solo sobre
velocity— por la misma vía que entraron Cycles y los múltiples Tracks: con una
nota fechada que diga qué se entrega y qué se deja.

### Tres decisiones de vocabulario, escritas antes de que se contradigan

1. **La forma se llama `waveform`, no `groove`.** El brief de producto llama
   *Groove* al knob que elige la forma, pero `Groove` ya nombra en el motor a la
   familia de Velocity, Sustain, Probability, Timing y Delay.
   `product-guidelines.md` pide un solo término por concepto, así que la forma
   toma el término con el que el propio handoff la rotula. La función conserva
   su nombre de la Pre Spec —*LFO Modulation*— y de ahí sale el nombre del
   módulo: `modulation`.

2. **El mauve no es un color nuevo.** `Palette.groove` ya es exactamente
   `#AA6DA8`, el «groove mauve» que pide el brief. La pantalla lo usa porque
   **lo que modula es velocity**, que es Groove: el color sigue codificando qué
   tipo de parámetro se está tocando, que es lo que `product-guidelines.md`
   exige de él. No se añade un cuarto acento ni hay que verificar a un metro un
   color que no existe.

3. **No hay `ParameterFamily` nueva.** Ni `waveform` ni `accent` son
   `TrackParameter`: no se mueven con un delta de knob (ver FR9), así que nada
   les tiene que preguntar su linaje. La familia se añadiría el día que `accent`
   tenga knob, no antes.

## Functional Requirements

**FR1 — El modelo: `Modulation`, dentro del `Cycle`.** Un valor propio con
`waveform` y `accent`, guardado en el `Cycle` junto a `Shape`, `Groove` y el
pool. Vive en `Engine` y es trivialmente copiable: `_isPOD(Cycle.self)` sigue
siendo la red que lo vigila (NFR2). Cada Cycle tiene el suyo, así que un
desarrollo A/B puede acentuar solo en el B.

**FR2 — Cuatro formas, y ninguna más.** `Waveform` es un `enum` de cuatro casos
—`saw`, `triangle`, `sine`, `pulse`— tal y como los lista la Pre Spec. Su
lectura en pantalla es el mismo término en minúscula.

**FR3 — `Accent`, bipolar, −100…100.** Valida en el inicializador como
`Velocity` y `Steps`: un `Accent` que existe es siempre aplicable. El 0 está
dentro del rango y es el default, porque es el valor que apaga la modulación.

**FR4 — Un ciclo por vuelta del anillo del Track.** La fase sale del índice de
Step dentro de la vuelta dividido por los Steps del Track: `phase = cycleStep /
stepCount`. No hay reloj de modulación, ni estado que mantener, ni nada que
sincronizar — la sincronía es una consecuencia de cómo se calcula la fase, no
algo que haya que vigilar.

> **Cada Track modula a su propia velocidad**, porque cada uno tiene sus Steps y
> su Division. Un Track de 16 Steps a 1/16 y otro de 12 a 1/8 completan su ciclo
> en tiempos distintos, y eso es lo que se quiere: el LFO está atado al material
> del Track, igual que sus Cycles.

**FR5 — La fase 0 cae en el centro, subiendo.** Las cuatro formas valen 0 en el
Step 1 y crecen desde ahí, así que el primer Step suena siempre a la Velocity
base y la desviación es lo que se desarrolla. Con `steps` Steps y `s` el índice
dentro de la vuelta (`0…steps−1`), `p = s / steps`:

| Forma | Definición sobre `p` | En palabras |
|---|---|---|
| `saw` | 0 → +100 en `p=¼`, salto a −100, → 0 en `p=1` | rampa ascendente con un corte |
| `triangle` | 0 → +100 (`¼`) → 0 (`½`) → −100 (`¾`) → 0 | subida y bajada simétricas |
| `sine` | `sin(2πp)`, por tabla entera | la misma forma, redondeada |
| `pulse` | +100 mientras `p < ½`, −100 después | media vuelta arriba, media abajo |

> **`pulse` es la excepción a «empieza en el centro» y no puede no serlo:** una
> onda de dos valores no pasa por el centro. Empieza **arriba**, que es la
> lectura que el handoff dibuja y la que hace la forma útil para lo que sirve —
> acentuar media vuelta entera.

**FR6 — Cuánto mueve: ±63 unidades MIDI en el extremo.** El offset de velocity
de un Step es

```
offset = wave(p) * accent * 63 / 10000      // aritmética entera, wave ∈ −100…100
```

`accent = ±100` sobre el pico de la onda desplaza media excursión del rango MIDI.
Con `Velocity` en el centro del rango, un `accent` al extremo barre
prácticamente 1…127 sin recortar; con la Velocity por defecto (100) recorta
arriba, y ver ese recorte es justo lo que el panel sirve para enseñar (FR12).

**FR7 — La velocity resultante se acota a 1…127.** `Velocity.advanced(by:)` ya
hace exactamente eso y ya está cubierto: la modulación lo reutiliza en vez de
escribir un segundo acotado. El extremo inferior sigue excluyendo el 0 por la
razón de siempre — un note-on con velocity 0 es un note-off, y para no sonar
está Probability.

**FR8 — El LFO corre sobre los Steps, suenen o no.** La fase depende del índice
de Step, nunca de si hubo nota: un Step que Probability apaga, o que no es pulso
euclidiano, consume igualmente su posición del ciclo. Lo contrario ataría la
fase a una tirada aleatoria y «un ciclo por vuelta» dejaría de ser cierto.

**FR9 — Se edita con el dedo, en su pantalla, y no con knobs.** `modulation` cae
del lado táctil de la frontera del 2026-09-06: se configura antes de tocar, como
`scale`, `midi` y `banks`. Ni `waveform` ni `accent` entran en `TrackParameter`,
`ControlMapping` ni el preset del BeatStep Pro.

> **Lo que eso cuesta, dicho aquí para que se pueda revisar:** Ctrl All y Temp
> —los step buttons 13 y 14— no alcanzan a `accent`, porque los dos operan sobre
> `TrackParameter`. Tampoco hay lectura transitoria grande al moverlo, que es la
> vía por la que el resto de parámetros se leen a un metro. Las dos cosas se
> arreglan el día que `accent` tenga knob, y ese día es otro track.

**FR10 — La pantalla `modulation`, quinta del chrome.** `Module` gana su quinto
caso y la navegación persistente pasa a `track`, `scale`, `midi`, `banks`,
`modulation`. Nada más del chrome cambia.

**FR11 — Dos columnas, como el handoff.** Izquierda ~70%, derecha ~30%.

- **Izquierda:** etiqueta de contexto, título `waveform`, rejilla 2×2 de cards
  con el dibujo de cada onda, y debajo el panel `velocity response`.
- **Derecha:** el card alto `accent` —lectura numérica grande con signo, slider
  bipolar vertical y la etiqueta `bipolar velocity`— y el card resumen al pie.

**FR12 — El panel `velocity response` enseña la velocity final, recorte
incluido.** La altura de cada barra es la velocity 1…127 que se va a emitir en
ese Step, no la forma normalizada: dos ajustes que recortan distinto se tienen
que ver distintos. Sobre las barras se dibuja la onda seleccionada y una línea
de centro discreta.

**FR13 — Tantas barras como Steps tenga el Track.** El 16 del handoff es el caso
por defecto, no una constante: con 9 Steps el panel dibuja nueve barras. El
panel es el espejo del anillo, y un panel que dice 16 cuando el anillo dice 9
miente sobre lo que suena. Los Steps que no son pulso se dibujan atenuados
(FR8).

**FR14 — El playhead cae sobre la barra que suena, un redibujo por Step.** Misma
cadencia que el playhead del anillo, que ya existe y ya está medida: sin
temporizador nuevo colgado de la vista. Con el transporte parado el playhead
**desaparece** y las barras se quedan dibujadas — son estado, no animación.

**FR15 — El pie dice `1 cycle per pattern`.** Literal del handoff, en minúscula
como el resto.

**FR16 — La etiqueta de contexto nombra Track y Cycle.** Donde el handoff pone
`track 04`, la pantalla pone `track 04 · cycle 02`: `modulation` escribe sobre el
Cycle **en edición**, que puede no ser el que suena (`Track.editing` frente a
`Track.cursor`). Sin decirlo, editar el B mientras suena el A parece que la
pantalla miente.

**FR17 — El Track se elige con el controlador, no en esta pantalla.** La
pantalla lee `selectedTrackIndex` y no lo escribe: no lleva la franja de doce de
`track`, `scale` y `midi`. El controlador es el instrumento.

**FR18 — El slider bipolar se arrastra, y se imanta en el 0.** El pulgar sigue
al dedo; cerca del centro engancha en 0 exacto, que es el único valor que hay
que poder recuperar sin mirar. Un toque simple sobre la pista salta a ese valor.
El marcador de centro es off-white y el pulgar es mauve.

**FR19 — Siete componentes reutilizables**, tal y como los pide el handoff:
`ModulationView`, `WaveformSelector`, `WaveformCard`, `WaveformPreview`,
`VelocityResponseView`, `BipolarAccentSlider`, `ModulationSummaryCard`.

**FR20 — Lenguaje visual, sin excepciones.** Fondo `#111211`, Figtree 400/600/700,
**todas las cadenas en minúscula**, bordes de 2 pt y de 3 pt en lo seleccionado,
radios de 3 a 8 pt, rellenos planos y sombra dura sin desenfoque solo en lo
seleccionado. Sin degradados, cristal, desenfoque, piano roll, teclado ni
gráficas decorativas. El card de la onda seleccionada va en mauve con la etiqueta
oscura; los otros tres, oscuros con borde neutro.

## Non-Functional Requirements

**NFR1 — Seguridad de tiempo real.** El cálculo del offset ocurre en el hilo del
scheduler: **aritmética entera, sin coma flotante, sin asignaciones, sin
bloqueos, sin `await`**. `sine` se resuelve por tabla estática de enteros, no con
`sin()`. La función lleva su marca `/// Realtime:`.

**NFR2 — `Cycle` sigue siendo POD.** `Modulation` es un `struct` de un `enum` y
un entero acotado. `_isPOD(Cycle.self)` es el test que lo vigila y no se relaja.

**NFR3 — No mueve ningún instante, así que no se mide jitter.** La modulación
cambia el *cuánto*, no el *cuándo*: añade aritmética entera acotada al camino de
emisión sin desplazar la rejilla. Es literalmente el caso que la nota del
2026-08-28 de `workflow.md` excluye, y además la medición está suspendida desde
el 2026-09-02.

**NFR4 — Cobertura.** `Engine` ≥90%, `MIDI` ≥80%, medidas como dice
`workflow.md` — la de `MIDI` en un solo proceso, con el `.profdata` fusionado a
mano y `Engine/Sources` excluido del informe.

**NFR5 — `Engine` no importa nada fuera de la stdlib.** La tabla del seno se
escribe, no se calcula con Foundation.

**NFR6 — En `App` no vive lógica.** El formato de la lectura (`+34`, `−12`, `0`)
y el muestreo de la onda por Step son `Engine`, con tests. En la pantalla queda
el dibujo.

**NFR7 — Vocabulario.** `waveform`, `accent`, `saw`, `triangle`, `sine`,
`pulse`, `modulation`. Ni un sinónimo nuevo, y `groove` no cambia de significado.

## Acceptance Criteria

1. Un Cycle recién creado tiene `accent = 0` y `waveform = .triangle`, y un
   Pattern existente suena **exactamente igual** que antes de la rebanada.
2. Con `accent = 0`, la velocity emitida es la de `Groove.velocity` en los
   `steps` Steps de la vuelta, para las cuatro formas.
3. Con `triangle` y `accent = +100`, la velocity crece del Step 1 al cuarto de
   vuelta, vuelve a la base a media vuelta y baja simétricamente en la segunda
   mitad.
4. `accent = −100` produce, Step a Step, el complemento exacto de `accent = +100`
   respecto de la Velocity base, salvo donde el acotado a 1…127 muerde.
5. Con `Velocity = 127` y `accent` positivo, ninguna velocity emitida supera 127;
   con `Velocity = 1` y `accent` negativo, ninguna baja de 1.
6. El ciclo se completa en una vuelta del anillo para 1, 9 y 16 Steps: el Step 1
   de cada vuelta vuelve a valer la base.
7. `pulse` produce exactamente dos valores distintos en una vuelta (salvo
   recorte), y el cambio cae a media vuelta.
8. Un Step apagado por Probability no desplaza la fase: los Steps siguientes
   valen lo mismo que si hubiera sonado.
9. La pantalla `modulation` aparece como quinta pestaña y navegar a ella y volver
   no interrumpe el transporte ni mueve el playhead.
10. El panel dibuja tantas barras como Steps tenga el Track, con las alturas de
    la velocity final, y el playhead avanza una barra por Step; parado, no se ve.
11. Arrastrar el slider cerca del centro deja `accent` en 0 exacto.
12. Cambiar de Cycle en edición cambia lo que la pantalla enseña, y la etiqueta
    de contexto lo dice.
13. Verificado en simulador (pantalla) y en iPad con BeatStep Pro y un sinte
    externo (que el acento **se oye**).

## Out of Scope

- **Knob para `accent` y para `waveform`**, y con ellos Ctrl All, Temp y la
  lectura transitoria grande. Ver el coste escrito en FR9.
- **Longitud de Groove ajustable** (1/2/4 compases). Se entrega fijo a un ciclo
  por vuelta del anillo.
- **Random Modulation.** De la línea «LFO y Random Modulation» de `product.md`
  entra solo la primera mitad.
- **Modular cualquier cosa que no sea velocity** — Sustain, Timing, Division,
  el pool.
- **Que la modulación se vea en el anillo de `track`.** El anillo dibuja dónde
  caen los pulsos, no con qué fuerza; dos codificaciones en la misma figura la
  hacen ilegible a un metro.
- **Duty ajustable de `pulse`**, fijo al 50%.
- **Persistencia.** No existe todavía para nada del Pattern.

## Known Limitations

- **`accent` no se puede mover mientras se toca**, porque no tiene knob y la
  pantalla `modulation` no es la que se mira tocando. Es una limitación
  aceptada, no un descuido: la alternativa era gastar dos de los controles del
  BeatStep Pro antes de saber si la forma del parámetro es la definitiva.
- **El recorte es silencioso en el sonido y visible solo en el panel.** Con
  Velocity 100 y accent alto, media onda se aplasta contra 127 y el resultado se
  oye asimétrico. El panel lo enseña (FR12); nada avisa.
- **`sine` es una tabla**, así que su forma es una aproximación entera. A 16
  Steps o menos, indistinguible.
