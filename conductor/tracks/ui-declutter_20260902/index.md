# Track: Doce Tracks, pantalla MIDI y limpieza del selector

**ID:** `ui-declutter_20260902` · **Type:** Refactor · **Status:** new

Tres ajustes de superficie sobre la pantalla que dejaron las rebanadas 1–3 de la
v2, todos en la misma dirección: **menos ruido para que el protagonista —los
anillos— tenga sitio**.

**El canal se va a la pantalla `3 · MIDI`**, que hoy es un placeholder en
discontinuo y aquí empieza a existir. Es ruteo, no material del Track, y se edita
para los doce a la vez: el ruteo completo se lee de un vistazo y un choque de
canales se ve sin recorrer Track por Track.

**El botón de Track dice dos veces el mismo número** —`index+1` arriba y el canal
debajo, que por defecto coinciden— y pasa a decir uno.

**Doce Tracks en vez de dieciséis.** Es una desviación de la Pre Spec y por eso la
primera fase la escribe antes de tocar código: con dieciséis, cada banda del
anillo queda en un ancho que no se lee a un metro. `RingStack` reparte entre
`trackCount − 1`, así que doce anillos salen un tercio más anchos sin tocar el
dibujo.

**No lleva medición de jitter**, suspendida el 2026-09-02.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [Rebanada 1 de la v2 — Dieciséis Tracks sobre un reloj](../multi-track_20260831/index.md), cuyo `Pattern` es el que aquí baja a doce.
-   [Rebanada 2 de la v2 — La pantalla del handoff](../screen-handoff_20260901/index.md), que dibujó los anillos y la navegación de cinco pantallas que esta abre por la tercera.
-   [Rebanada 3 de la v2 — Cycles](../cycles_20260901/index.md), cuyo `TrackSelectorView` es el que pierde la fila `Channel`.
-   [Rebanada 7 del MVP — Preset del BeatStep Pro](../mvp-beatstep-mapping_20260830/index.md): el preset **no cambia**; los step buttons 13–16 se acotan del lado de la selección.
