# Track: Mute y Solo por Track

**ID:** `mute-solo_20260902` · **Type:** Feature · **Status:** new

Los doce Tracks suenan a la vez y no hay forma de callar a uno: para oír la caja
sola hay que **vaciarle el pool** a los demás, que destruye material para
conseguir un silencio temporal. Esta rebanada añade el gesto que hace eso un
mixer — un par **M / S** debajo de cada pastilla de Track, y el mismo gesto en el
controlador.

**Mute no para el Track: le quita la salida.** La rejilla avanza, el playhead
gira y los Cycles rotan; lo único que se suprime es la emisión. Al quitarlo, el
Track reaparece **en fase** con el resto, que es lo que un mixer promete y lo que
un «stop del Track» rompería.

**El estado vive por encima del Pattern.** No es material: es mezcla. Por eso no
entra en el snapshot y **`Engine` no se toca** — si una tarea empuja hacia
`Engine`, es la señal de que se está metiendo mezcla en el material. Los doce
mutes y los doce solos viven en una sola palabra atómica que el hilo del
scheduler lee de un tirón: dos atómicos permitirían ver el mute de antes y el
solo de después.

**Solo es aditivo**, y el mute manda sobre él: aislar bombo + caja es la
operación normal, y un Track soleado y muteado calla.

**En el controlador, sin temporizadores.** Mantener el step button 16 y pulsar el
N mutea el Track N; con el 15, lo solea. Los dos están libres desde que el
Pattern bajó a doce, y el hardware ya envía la soltada: el «mantener» es estado
de mensajes, así que el gesto entero se prueba con mensajes.

**Lo que más importa que no falle** es el apagado: un Sustain al 200% sobre una
Division larga dejaría la nota colgada en el sinte durante segundos después de
pulsar M. Se reutiliza el barrido de `Transport.stop()` —`CC 123` más las alturas
de los dieciséis Cycles—, acotado al Track que acaba de quedarse inaudible.

**No lleva medición de jitter**, suspendida el 2026-09-02: el cambio decide *si*
se emite, no *cuándo*.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [Doce Tracks, pantalla MIDI y limpieza del selector](../ui-declutter_20260902/index.md), que dejó libres los step buttons 13–16 y cuyo `TrackSelectorView` recibe aquí la fila M/S.
-   [Rebanada 1 de la v2 — Dieciséis Tracks sobre un reloj](../multi-track_20260831/index.md), cuyo `PatternScheduler` y cuyo barrido de `Transport.stop()` son los que este track acota.
-   [Rebanada 3 de la v2 — Cycles](../cycles_20260901/index.md): el barrido de silencio recorre los dieciséis Cycles de cada Track, y aquí se hereda ese criterio.
-   [Rebanada 7 del MVP — Preset del BeatStep Pro](../mvp-beatstep-mapping_20260830/index.md): el preset **no cambia**; el modificador vive en quien consume los mensajes.
