# Track: v2 rebanada 2 — La pantalla del handoff

**ID:** `screen-handoff_20260901` · **Type:** Feature · **Status:** new

La rebanada 1 construyó dieciséis Tracks sobre un reloj y les dio la pantalla **mínima para operar**. El handoff de diseño lleva cerrado desde antes —cinco pantallas, estructura y flujo decididos, colores y tipografía finales, lenguaje neo-brutalista— y su pantalla 1 es exactamente la vista de lo que aquella rebanada construyó: **dieciséis Tracks como anillos concéntricos**, uno de ellos en detalle. Esta la implementa.

**El núcleo es que la pantalla pasa de una columna de texto a un mapa.** Hoy hay que leer para saber qué Track está seleccionado y qué tiene dentro; con los anillos se ve de un vistazo cuáles tienen material, cuál suena y por dónde va el tiempo.

**Y que el lenguaje visual se cierra.** `ShapeTheme` dice hoy de sí mismo que sus colores son ilustrativos «hasta que el lenguaje visual se cierre». Se cierra aquí, con Figtree y el sistema neo-brutalista en un solo sitio.

**No inventa modelo.** Ni mute/solo, ni nombres de Track, ni Banks, ni Patterns. Entran las pantallas 1 y 2; las otras tres se ven deshabilitadas con borde discontinuo, que es el signo que el propio handoff define para «todavía no».

**Lleva medición de jitter**, y no por tocar el scheduler: dieciséis anillos redibujándose al ritmo del reloj son la «carga visual nueva» que la nota del 2026-08-28 de `workflow.md` obliga a medir.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [Handoff de diseño](../../../design_handoff/README.md) — la referencia. El click-through es lo vinculante; las capturas fijan la composición.
-   [Rebanada 1 de la v2 — Dieciséis Tracks sobre un reloj](../multi-track_20260831/index.md), que es lo que esta pantalla muestra.
-   [Rebanada 3 del MVP — Anillo, playhead y valor transitorio](../../archive/mvp-ring-feedback_20260828/index.md), cuya medición con carga visual —máx 0,134 ms, σ 0,020 ms, con **un** anillo— es la referencia de la Fase 6.
-   [Cycles](../cycles_20260901/index.md), que **depende de esta rebanada**: es donde se muestra el Cycle en curso.
