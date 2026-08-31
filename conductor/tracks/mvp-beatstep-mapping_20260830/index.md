# Track: MVP rebanada 7 — Preset del BeatStep Pro: knobs, pads y step buttons

**ID:** `mvp-beatstep-mapping_20260830` · **Type:** Feature · **Status:** complete

La rebanada 6 cerró el Track generativo completo. Lo que queda de la v1 no es motor: es **la superficie de control**. Esta rebanada sustituye el mapeo provisional por un preset declarado, verificado en dispositivo y entregado como artefacto cargable.

**El núcleo es que un pad deja de ser una altura y pasa a ser un índice.** Hoy `ControlInput` lee el número de nota entrante como `Pitch` y descarta lo que la Scale no admite — un teclado cromático filtrado. Sobre dieciséis pads que envían dieciséis semitonos contiguos eso deja la mayoría muertos y acota el registro alcanzable a **un octavo del rango MIDI**. La superficie nueva asigna a cada pad un **grado de escala**: pads 1–7 una octava, 9–15 la de encima, y los pads 8 y 16 mueven el registro entero sin tocar el pool.

**El alineamiento por octava es la invariante que lo sostiene:** el pad 9 es siempre el pad 1 más doce semitonos, sea cual sea la escala y el Root. Es lo que permite que los pads 8 y 16 se llamen *octava* sin mentir, y la razón de que una escala de cinco grados deje cuatro pads apagados en vez de rellenarlos.

**La rebanada 7 se parte en dos.** El registro la definía como «preset del BeatStep Pro y MIDI Learn»; por decisión del 2026-08-30 este track entrega solo el preset, y MIDI Learn pasa a la **rebanada 8**, junto con `network-session-source`. Son problemas distintos: uno es dominio musical, el otro infraestructura de entrada.

**Sin medición de jitter** — no toca ningún instante, que es el caso que exime la nota del 2026-08-28 de `workflow.md`. La medición final de v1 va con la rebanada 8.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [Rebanada 4 — Tonal: pool, Scale y Root](../../archive/mvp-tonal_20260828/index.md), que introdujo los pads y el `TonalFrame` que esta rebanada reinterpreta
-   [Rebanada 2 — Entrada de control](../../archive/mvp-control-input_20260827/index.md), donde nació el mapeo provisional de CC y la nota sobre `Relative #2`
-   [Rebanada 6 — Groove temporal](../../archive/mvp-groove-temporal_20260830/index.md), que cerró el Track generativo y dejó los nueve parámetros que el preset tiene que cubrir
