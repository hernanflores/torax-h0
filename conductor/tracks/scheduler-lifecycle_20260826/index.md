# Track: Ciclo de vida del scheduler y desmontaje de CoreMIDI

**ID:** `scheduler-lifecycle_20260826` · **Type:** Bug · **Status:** new

`SchedulerThread.stop()` no espera a que el hilo salga, así que un `start()` inmediato puede dejar dos schedulers vivos emitiendo cada Step dos veces. Cerrar la carrera exige antes dar al arnés de jitter un desmontaje explícito y ordenado de CoreMIDI.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
