# Track: v2 rebanada 3 — Cycles, el Track varía por vuelta

**ID:** `cycles_20260901` · **Type:** Feature · **Status:** new

Hasta hoy un Track repite un juego de parámetros idéntico hasta que alguien gira un knob. Esta rebanada le da **desarrollo en el tiempo sin intervención**: hasta dieciséis **Cycles** por Track —versiones completas de sus ajustes— recorridos a cada vuelta del anillo. Es la A/B/C de la Pre Spec, y la última de las cuatro capas del motor que `product.md` describe: Shape decide *cuándo*, Tonal *qué alturas*, Groove *cómo se interpreta* y Cycles aporta el desarrollo.

**El núcleo es que el nivel donde viven los parámetros baja uno.** Lo que hoy se llama `Track` es lo que la Pre Spec llama **Cycle**; el `Track` pasa a ser el contenedor: dieciséis Cycles, cuántos están activos y por cuál va. Con él bajan el snapshot que cruza al hilo del scheduler, la entrada de control y la pantalla.

**El avance ocurre en el hilo del scheduler, en el límite de vuelta**, para que el Cycle cambie exactamente cuando el anillo cierra. El precio es que el snapshot pasa de 2304 bytes a unos 36 KB, y **eso se mide antes de construir encima**: es la Fase 1, y puede cambiar el diseño.

**Lleva medición de jitter obligatoria**, con los dieciséis sonando y avanzando. Una regresión bloquea la rebanada.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [Rebanada 1 de la v2 — Dieciséis Tracks sobre un reloj](../multi-track_20260831/index.md), cuyo `Pattern` y cuyo `PatternHandoff` son lo que esta rebanada multiplica por dieciséis. **Su Fase 6 tiene que cerrar antes**: sin esa medición no hay línea base.
-   [Rebanada 7 del MVP — Preset del BeatStep Pro](../mvp-beatstep-mapping_20260830/index.md), que dejó libres los knobs 10–16 y nombró a Cycles como uno de sus destinos.
-   [Rebanada 6 del MVP — Groove temporal](../../archive/mvp-groove-temporal_20260830/index.md), cuya medición —máx 0,151 ms, σ 0,009–0,013 ms— es una de las dos referencias de jitter.
