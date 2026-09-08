# Track: v2 rebanada 6 — LFO Modulation

**ID:** `modulation_20260906` · **Type:** Feature · **Status:** new

Velocity es hoy un número fijo para todos los Steps del Cycle, así que la única
forma de que un golpe suene distinto del anterior es cambiar de Cycle — que
cambia el Track entero, no solo la dinámica. La modulación añade **movimiento
cíclico a la velocity**, sincronizado con la vuelta del anillo del Track.

**No cambia qué notas suenan ni cuándo: cambia con cuánta fuerza.** Es lo que
hace que un patrón repetido deje de sonar mecánico sin tocar el material — Steps,
Pulses, Rotate y el pool se quedan como estaban.

Dos parámetros: **waveform** (`saw`, `triangle`, `sine`, `pulse`) y **accent**
(−100 … +100, bipolar). Y una pantalla propia, la quinta.

**Con `accent` en 0 —el default— no cambia nada de lo entregado.** Es la
condición de no regresión de la rebanada y la regla de destructividad de
`product-guidelines.md` aplicada al código: un parámetro nuevo no cambia lo que
ya hacía quien no lo pide.

**Un ciclo por vuelta del anillo del propio Track.** La fase sale del índice de
Step dentro de la vuelta dividido por los Steps del Track. No hay reloj de
modulación, ni estado que mantener, ni nada que sincronizar: la sincronía es una
consecuencia de cómo se calcula la fase, no algo que haya que vigilar. Cada Track
modula a su velocidad, porque cada uno tiene sus Steps y su Division.

**La forma se llama `waveform` y no `Groove`.** La Pre Spec usa *Groove* para dos
cosas —la familia de Velocity, Sustain, Probability, Timing y Delay, y el knob
que elige la forma— y el motor ya gastó el término en la primera.
`product-guidelines.md` pide un solo término por concepto, así que la forma toma
el nombre con el que el propio handoff la rotula.

**El mauve no es un color nuevo.** `Palette.groove` ya es exactamente `#AA6DA8`,
el «groove mauve» del handoff. La pantalla lo usa porque **lo que modula es
velocity**, que es Groove: el color sigue codificando qué tipo de parámetro se
toca, que es lo que se le exige. No se añade un cuarto acento que habría que
verificar a un metro.

**`accent` se edita con el dedo y no tiene knob**, porque `modulation` cae del
lado táctil de la frontera del 2026-09-06: se configura antes de tocar, como
`scale`, `midi` y `banks`. El coste está escrito y es real — Ctrl All, Temp y la
lectura transitoria grande no lo alcanzan, porque los tres operan sobre
`TrackParameter`. Se arregla el día que tenga knob, y ese día es otro track.

**El panel `velocity response` enseña la velocity final, recorte incluido**, y
dibuja tantas barras como Steps tenga el Track — el 16 del handoff es el caso por
defecto, no una constante. Un panel que dice dieciséis cuando el anillo dice
nueve miente sobre lo que suena.

**Sale de «Fuera de v1»** de `product.md`, que lista «LFO y Random Modulation».
Entra la primera mitad, y solo sobre velocity, por la misma vía que salieron
Cycles y los múltiples Tracks: con una nota fechada que diga qué se deja — la
longitud ajustable, Random, y modular cualquier otra cosa.

**No lleva medición de jitter.** Cambia el *cuánto*, no el *cuándo*: aritmética
entera acotada en el camino de emisión, sin desplazar la rejilla. Es el caso que
la nota del 2026-08-28 de `workflow.md` excluye, y además la medición está
suspendida desde el 2026-09-02.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Verificación en simulador](./simulator-verification.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [Rebanada 3 de la v2 — Cycles](../cycles_20260901/index.md): la `Modulation`
    vive en el `Cycle`, así que un desarrollo A/B puede acentuar solo en el B — y
    de ahí sale la exigencia de que el `Cycle` siga siendo POD.
-   [Rediseño de las cuatro pantallas](../screens-redesign_20260906/index.md): el
    chrome y la navegación persistente que esta rebanada extiende a cinco, y la
    frontera del tacto que decide de qué lado cae `modulation`.
-   [Rebanada 1 de la v2 — Múltiples Tracks](../multi-track_20260831/index.md):
    cada uno de los doce modula con su propio anillo, muteados incluidos.
-   [Note Repeater](../note-repeater_20260906/index.md): rebanada anterior, y el
    otro parámetro que toca la velocity de lo que se emite. Ramp recorre las
    repeticiones de un Pulse; accent recorre la vuelta del anillo.
