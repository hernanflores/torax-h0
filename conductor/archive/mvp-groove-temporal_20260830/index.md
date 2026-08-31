# Track: MVP rebanada 6 — Groove temporal: Timing y Delay

**ID:** `mvp-groove-temporal_20260830` · **Type:** Feature · **Status:** complete — cerrado el 2026-08-30, con una fase *Review Fixes* abierta

La otra mitad de Groove: la que cambia **cuándo** se envía. Timing desplaza cada segundo Step —swing— y Delay mueve la voz entera contra la rejilla. Con ella se cierra el Track generativo completo del MVP; después solo queda la rebanada 7, que no toca el motor.

**Es la primera rebanada desde la 3 que mueve instantes**, y por tanto la primera que vuelve a tocar el camino de jitter que costó validar. Su núcleo técnico es el *presupuesto de adelanto*: un evento con Delay negativo tiene que calcularse antes de su instante, o se pediría para un momento que ya pasó. La misma cantidad resuelve el arranque —el origen de la rejilla es `Play + presupuesto`— y el régimen —el horizonte de selección se amplía en él—, y es dinámica, así que con Delay ≥ 0 no cuesta nada.

Lleva **dos mediciones de jitter obligatorias**: la recta, que además cierra el intervalo sin medir que dejaron las rebanadas 4 y 5; y la desplazada, que es lo que la rebanada tiene que demostrar.

**Cerrado con deuda conocida.** La revisión dejó cuatro hallazgos sin arreglar
—uno de ellos que `Stop` podría dejar sonar notas con Delay positivo— registrados
en la fase *Review Fixes* del plan por decisión del 2026-08-30. La medición
desplazada tampoco se ejecutó, y su razón está escrita.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md) — incluye la fase *Review Fixes*, **abierta**
-   [Metadata](./metadata.json)
-   [Verificación en dispositivo](./device-verification.md) — bloques 4–8 ejecutados, validados
-   [Captura del simulador](./simulator-groove-temporal.png)

## Project Context

-   [Project Index](../../index.md)
-   [Rebanada 5 — Groove estático](../../archive/mvp-groove-static_20260829/index.md), que dejó preparados `Groove` y `TrackParameter` para estos dos
-   [Rebanada 3 — Anillo, playhead y valor transitorio](../../archive/mvp-ring-feedback_20260828/index.md), cuya medición —máx 0,134 ms · σ 0,020 ms— es la referencia contra la que se compara
