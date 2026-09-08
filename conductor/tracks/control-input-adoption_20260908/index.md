# Track: `ControlInput` no adopta el Pattern del Bank nuevo

**ID:** `control-input-adoption_20260908` · **Type:** Bug · **Status:** complete

Cambiar de Bank suena, pero no se edita. `ControlInput` guarda su propia copia
del Pattern y **solo la escribe en su `init`**: nadie la reseedea. Después de
cambiar de Bank, el primer giro de knob republica **el Pattern anterior entero**
encima del Bank nuevo — Steps, Pulses, Rotate, el pool, el Groove y el marco
tonal.

Encontrado el 2026-09-07 verificando `note-repeater_20260906` en dispositivo,
porque un ratchet sobre un Bank que se creía vacío es inconfundible. El resto
pasaba por «no cambió nada».

**Absorbe el defecto hermano** —«El cambio de Pattern no llega a la pantalla ni
al Project»— porque comparten la pieza que falta. Con el transporte corriendo,
cambiar de Bank o de Pattern **arma**, y el material entra en el límite de
compás dentro del hilo del scheduler: arreglar solo la rama parada dejaría el
mismo fallo esperando en la que suena.

**Faltan dos direcciones, no una.** La de **ida** —el modelo diciéndole a
`ControlInput` que el material cambió— y la de **vuelta** —el hilo del scheduler
diciéndole al modelo que la adopción ocurrió—.

**Lo que suena entra exacto en el compás; lo que la pantalla refleja puede
llegar hasta un cuadro después.** Es el precio de no meter una llamada de vuelta
en el camino de tiempo real, y nadie lo oye.

**Sin medición de jitter**: no mueve ningún instante, cambia quién conoce el
material.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [Rebanada 4 de la v2 — Persistencia](../persistence_20260907/index.md): trajo
    los Banks, los Patterns y el cambio cuantizado al compás, y con ellos los dos
    defectos que este track cierra.
-   [Rebanada 5 de la v2 — Note Repeater](../note-repeater_20260906/index.md):
    donde se encontró, por lo audible que es un ratchet fuera de sitio.
-   [Rebanada 3 de la v2 — Cycles](../cycles_20260901/index.md): de ahí sale
    `CyclePlaybackClock`, que es la forma que copia la vía de vuelta.
