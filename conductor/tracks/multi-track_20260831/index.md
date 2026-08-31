# Track: v2 rebanada 1 — Dieciséis Tracks sobre un reloj

**ID:** `multi-track_20260831` · **Type:** Feature · **Status:** new

La v1 se redujo a un Track a propósito: validar el motor de punta a punta antes de escalar, porque el mayor riesgo del proyecto es el timing. Está validado en cuatro mediciones. Esta rebanada gasta ese crédito: **de un Track a dieciséis**, que es la estructura que la Pre Spec describe desde su primera línea y la que el preset del BeatStep Pro ya asume —sus dieciséis step buttons seleccionan Track N desde la rebanada 7, y quince no tienen nada detrás—.

**El núcleo es que el snapshot deja de ser un Track y pasa a ser dieciséis.** No es un cambio de interfaz: es el valor que cruza al hilo del scheduler, el que `TrackHandoff` publica sin lock y el que `_isPOD` vigila. Y con él, un reloj pasa a emitir **dieciséis rejillas**: cada Track con su Division, su Timing y su Delay sobre un solo origen.

**Lleva medición de jitter obligatoria**, con los dieciséis sonando: es el riesgo que la v1 existió para acotar, y una regresión bloquea la rebanada.

**No es la UI definitiva** —los anillos concéntricos del handoff son la rebanada siguiente, y son la vista de lo que esta construye— **ni Patterns ni Banks**, que necesitan una persistencia que todavía no existe.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [Rebanada 7 — Preset del BeatStep Pro](./../mvp-beatstep-mapping_20260830/index.md), que dejó los step buttons con su semántica final y la costura `trackCount`
-   [Rebanada 6 — Groove temporal](../../archive/mvp-groove-temporal_20260830/index.md), cuya medición —máx 0,151 ms, σ 0,009–0,013 ms— es la referencia contra la que se compara ésta
-   [Timing Spike](../../archive/timing-spike_20260826/index.md), donde se validó la arquitectura de look-ahead que esta rebanada pone a prueba con dieciséis voces
