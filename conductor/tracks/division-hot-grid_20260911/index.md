# Track: La Division no mueve la rejilla mientras suena

**ID:** `division-hot-grid_20260911` · **Type:** Bug · **Status:** new

**Girar Division con el transporte corriendo no cambia la velocidad de la
línea.** Cambia la duración de la nota, y nada más. Por eso en un instrumento
tonal con notas sostenidas el knob parece funcionar y en una pista rítmica de
one-shots parece muerto, que es desde donde se reportó.

**La rejilla se congela al pulsar Play.** `PatternScheduler.swift:102` construye
un `MusicalTimeline` por Track leyendo `cycle.shape.division` una sola vez, y
`TrackScheduler` guarda su `stepDurationNanoseconds` como `let`. El refresco en
caliente sustituye **solo el material**. El gate, en cambio, sí obedece: lo
recalcula `Transport.swift:699` por nota contra el snapshot vivo. Las dos mitades
del mismo valor viven en sitios distintos y solo una se actualiza.

**No es un defecto de la Division, es un defecto de la rejilla.** Cada Cycle
tiene su propio Shape, así que el avance de Cycle en el límite de vuelta tiene el
mismo problema por otra puerta: hoy un Cycle 2 en 1/8 suena sobre la rejilla del
Cycle 1. Se arregla de una vez — la rejilla pasa a ser función del material
vigente.

**La pieza que falta es un ancla**: un índice de Step y el instante que ese Step
tenía bajo la rejilla anterior. El pasado queda como sonó y el futuro obedece al
knob. **El anillo mide con la misma ancla**, o lo que se ve y lo que suena
dejarían de coincidir — que es una invariante que `Playhead.swift` tiene escrita.

**El defecto reportado se cierra en la Fase 2.** El riesgo va solo en la Fase 3:
el avance de Cycle ocurre dentro de una ventana ya calculada con la rejilla
vieja, y es lo único aquí que puede perder o duplicar una nota.

**Sin medición de jitter** (suspensión del 2026-09-02), en el track que más la
habría justificado. Se sustituye por una escucha larga en dispositivo, y el
riesgo queda escrito.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [`copy here` de la rejilla de Patterns no hace nada](../pattern-copy_20260910/index.md):
    de ahí viene la lección de método que este track hereda — lo que vive en el
    hardware se verifica en el hardware, y el criterio que parece cumplido puede
    estar mirando el sitio equivocado.
-   [El cursor de edición de Cycles](../cycle-edit-cursor_20260908/index.md):
    el **segundo** motivo por el que un knob puede parecer muerto —se edita un
    Cycle que no suena—, que no se arregla aquí y con el que no hay que
    confundir este defecto.
