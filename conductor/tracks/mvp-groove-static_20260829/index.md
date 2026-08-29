# Track: MVP rebanada 5 — Groove estático: Velocity, Sustain, Probability

**ID:** `mvp-groove-static_20260829` · **Type:** Feature · **Status:** new

La tercera capa del motor. Velocity, Sustain y Probability cambian **qué** se envía; Timing y Delay —que cambian **cuándo**— van aparte, en la rebanada 6. El corte es por riesgo, no por tamaño: aísla los tres parámetros que no tocan la rejilla temporal de los dos que sí.

Paga tres deudas que el código ya declaraba: la velocity constante de `NoteEmitter`, el gate provisional de 25 ms, y el PRNG sembrado que `tech-stack.md` exige desde el primer commit y que Probability es el primero en necesitar.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [Rebanada 4 — Tonal](../../archive/mvp-tonal_20260828/index.md), sobre la que se construye
