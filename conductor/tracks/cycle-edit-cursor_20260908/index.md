# Track: En pantalla no se puede elegir qué Cycle se edita

**ID:** `cycle-edit-cursor_20260908` · **Type:** Bug · **Status:** new

El cursor de edición se queda siempre en el Cycle 1, así que todo giro de knob
cae ahí y los otros quince parecen copias que no guardan nada — que es
exactamente lo que son: nacen iguales y nunca reciben una edición.

**La causa es un gesto que falta, no el modelo.** `Track` lleva sus dos cursores
—`cursor` para la reproducción y `editing` para la edición— y
`replacingEditing(_:)` escribe en el que toca. Lo que no existe es la forma
táctil de mover el de edición: pulsar una celda del `CycleStrip` llama a
`onActiveCountChange`, que cambia **cuántos** Cycles se recorren, no cuál se
edita. La única vía es el knob 13 del BeatStep Pro, CC 82.

**El reparto de gestos está decidido** (2026-09-03): **pulsar elige** el Cycle en
edición y **mantener pulsado cambia cuántos** están activos. El gesto frecuente
es el simple y el raro pide mantener, que es el mismo criterio con el que los
step buttons 15 y 16 hacen de modificadores de solo y mute.

**El modelo no cambia.** `Track.withEditing(_:)` ya existe, ya acota al rango
activo y ya tiene tests. Lo que falta es una vía pública en `ControlInput` que la
llame sin pasar por un delta de knob, y el gesto en la vista que la invoque.

**Sin medición de jitter**: no mueve ningún instante ni toca el hilo del
scheduler.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [Rebanada 3 de la v2 — Cycles](../cycles_20260901/index.md): de donde salen
    los dos cursores, `withEditing(_:)` y el knob del Cycle. Este track es la
    mitad táctil que allí quedó sin entregar.
-   [Ctrl All](../ctrl-all_20260905/index.md): movió el knob del Cycle del 10 al
    13 (CC 82). El registro decía «knob 10, CC 79» y era el dato de antes de esa
    fecha.
-   [Rediseño de las cuatro pantallas](../screens-redesign_20260906/index.md):
    trajo `CycleStrip` a `App/TrackReadout.swift`. El registro señalaba
    `App/TrackSelectorView.swift`, que es donde vivía la fila antes del rediseño.
-   [Mute y Solo por Track](../mute-solo_20260902/index.md): el precedente del
    criterio «lo frecuente es el gesto simple, lo raro pide mantener».
