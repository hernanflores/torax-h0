# Track: La sesión MIDI de red monopoliza la entrada

**ID:** `network-session-source_20260828` · **Type:** Bug · **Status:** new

iPadOS publica siempre la sesión MIDI de red como fuente, así que la lista de entradas nunca está vacía. La app la autoselecciona: el estado `No MIDI input` que `product-guidelines.md` especifica es inalcanzable en el dispositivo de destino, y el controlador real no se elige solo al conectarlo.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
