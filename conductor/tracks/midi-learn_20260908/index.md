# Track: MVP rebanada 8 — MIDI Learn, con `network-session-source` dentro

**ID:** `midi-learn_20260908` · **Type:** Feature · **Status:** new

**Cierra la v1.** `product.md` promete MIDI Learn desde el principio y la app
todavía no lo hace: `ControlMapping` es fija, declarada en código y con el preset
del BeatStep Pro dentro. Esta rebanada entrega la reasignación a otro hardware.

**Se lleva dentro `network-session-source`**, que aquí sí bloquea. iPadOS publica
siempre `Red Session 1` como fuente, la app la autoselecciona y el controlador
real no se elige solo al conectarlo. MIDI Learn tiene que escuchar la fuente
correcta: aprender de la sesión de red es aprender de nada. El seguimiento del
defecto vive en la [issue #43](https://github.com/hernanflores/torax-h0/issues/43)
desde el 2026-09-08; **el arreglo entra aquí**.

**Y la persistencia cambió la respuesta.** El plan de `network-session-source`
decía que «cuando haya persistencia, recordar la última elección lo resuelve
mejor que cualquier heurística». La hay desde el 2026-09-07 y el `Project` ya
guarda `sourceName`. Así que este track no repite aquella heurística entera: la
elección recordada manda, y la regla de no autoseleccionar la red es lo que
queda para el primer arranque.

**Lleva también la medición final de jitter de la v1**, que la rebanada 7 no hizo
por no mover ningún instante. **Está suspendida** desde el 2026-09-02 y esta era
una de las dos excepciones escritas — la decisión de si se levanta para cerrar la
v1 es del usuario y se toma antes de empezar, no al llegar al final.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [Rebanada 7 del MVP — Preset del BeatStep Pro](../mvp-beatstep-mapping_20260830/index.md):
    entregó `ControlMapping` y el preset de `preset/`. Esta rebanada es la otra
    mitad de la línea «Mapeo del controlador + MIDI Learn» que la nota del
    2026-08-31 partió en dos.
-   [La sesión MIDI de red monopoliza la entrada](../network-session-source_20260828/index.md):
    el defecto que entra aquí, con su diagnóstico y su NFR4 —no identificar por
    nombre visible—. Cerrado en conductor y trasladado a la
    [issue #43](https://github.com/hernanflores/torax-h0/issues/43).
-   [Rebanada 4 de la v2 — Persistencia](../persistence_20260907/index.md): trajo
    el `Project`, `sourceName` en disco y `ProjectRecord.currentSchemaVersion`,
    que es lo que un mapeo guardado tiene que atravesar.
-   [Ctrl All](../ctrl-all_20260905/index.md) y
    [Note Repeater](../note-repeater_20260906/index.md): dejaron la tabla de CC
    como está hoy, con el knob del Cycle en el 82 y los knobs 15 y 16 libres.
