# Track: Pitch y Harmony — transformar el pool dentro de la Scale

**ID:** `pitch-harmony_20260912` · **Type:** Feature · **Status:** complete

**Los dos controles Tonal que la Pre Spec nombra y la v1 dejó fuera.** Pitch
transpone el pool entero en grados de la escala del Cycle; Harmony mueve un pitch
del pool por clic, en round robin, sin cruces ni choques y con histéresis. Los
dos transforman el pool que suena; los pads siguen editando el pool base.

**Del PRD se toma el algoritmo, no el vocabulario ni el modelo.** Lo que
`conductor/Pitch_Harmony_PRD.docx` propone y el proyecto ya tiene —pool, marco
tonal, Cycle como snapshot, knobs relativos, reencuadre al cambiar Scale— se
queda como está. La tabla de reconciliación está en el spec.

**Reset Harmony queda descartado.** Harmony se limpia al editar el pool o al
cambiar Scale o Root; Pitch se conserva.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)
-   [Verificación en dispositivo](./device-verification.md)

## Project Context

-   [Project Index](../../index.md)
-   [MVP rebanada 4 — Tonal](../../archive/mvp-tonal_20260828/index.md): pool,
    Scale, Root y el reencuadre que este track conserva.
-   [Temp](../temp-parameters_20260904/index.md) y
    [Ctrl All](../ctrl-all_20260905/index.md): las capturas que Harmony obliga a
    ampliar, porque su base no es un entero.
-   [Persistencia](../persistence_20260907/index.md): `CycleRecord` gana campos.
-   [MIDI Learn](../midi-learn_20260908/index.md) y
    [Reordenar los knobs](../knob-layout_20260912/index.md): los CC 75 y 76
    libres, y el orden físico de los encoders.
