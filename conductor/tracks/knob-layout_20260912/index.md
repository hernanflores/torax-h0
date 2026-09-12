# Track: Reordenar los knobs del preset del BeatStep Pro

**ID:** `knob-layout_20260912` · **Type:** Chore · **Status:** new

**La pantalla y la mano vuelven a decir lo mismo.** Desde el 2026-09-05 llevan
órdenes distintos a propósito, y la única forma de saber qué knob mueve qué es la
tabla de `preset/README.md`. Con el Note Repeater dentro (2026-09-07) la fila
física además intercala familias —Shape, Groove, Shape— así que recorrer una fila
cruza de card tres veces.

**La regla nueva es una fila de knobs por card.** Arriba, el card Shape entero:
el ritmo y los cuatro del Note Repeater. Abajo, el card Groove en el orden del
dominio, que revierte el intercambio de Delay y Probability.

**El Cycle en edición se va a la esquina**, al knob 16. Es lo que la nota del
2026-09-05 quería —que no parezca el décimo parámetro— y que estando pegado a
ellos sólo conseguía a medias. Un hueco físico de dos knobs lo dice mejor que un
número.

**El archivo del controlador no cambia.** `Torax.beatsteppro` declara dieciséis
encoders contiguos desde el CC 70 en `Relative #2`, y eso sigue siendo cierto.
Qué significa cada uno lo decide la app.

**Los mapeos aprendidos con MIDI Learn no se migran.** Un proyecto guardado con
el orden anterior se restaura tal cual; lo que cambia aquí es el default de
fábrica.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [Rebanada 7 del MVP — Preset del BeatStep Pro](../mvp-beatstep-mapping_20260830/index.md):
    entregó `ControlMapping` y el preset de `preset/`, con el invariante de que
    las tres fuentes dicen lo mismo.
-   [Ctrl All](../ctrl-all_20260905/index.md): movió Delay y Probability y llevó
    el knob del Cycle al 82. Es la decisión que este track revierte.
-   [Note Repeater](../note-repeater_20260906/index.md): metió Repeats, Time,
    Ramp y Pace en los CC 79–83, que es lo que dejó la fila intercalando
    familias.
-   [MIDI Learn](../midi-learn_20260908/index.md): por qué un mapeo guardado gana
    sobre el de fábrica, y por qué aquí no hay migración.
