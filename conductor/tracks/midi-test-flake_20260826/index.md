# Track: Flake `clientCreationFailed(-50)` en MIDITests

**ID:** `midi-test-flake_20260826` · **Type:** Bug · **Status:** blocked

La suite de `MIDI` falla de forma intermitente (~1 de cada 12 pasadas) al crear clientes CoreMIDI. Con la CI reparada y todo entrando por PR, pone PRs en rojo sin culpa del cambio bajo revisión.

**Bloqueado por** [`scheduler-lifecycle_20260826`](../scheduler-lifecycle_20260826/index.md): su cierre explícito de CoreMIDI podría resolverlo de rebote. La Fase 1 vuelve a medir y decide la forma del track.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
