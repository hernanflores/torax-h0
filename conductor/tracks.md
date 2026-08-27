# Tracks Registry

## MVP — v1

La prioridad del proyecto. Sin app no hay nada que arreglar.

---

- [ ] **Track: MVP rebanada 1 — Shape, transporte y primer sonido**
  *Link: [conductor/tracks/mvp-shape-transport_20260827/index.md](./tracks/mvp-shape-transport_20260827/index.md)*

## Defectos conocidos

---

- [~] **Track: Ciclo de vida del scheduler y desmontaje de CoreMIDI** — *priorizado por encima del MVP el 2026-08-27*
  *Link: [conductor/tracks/scheduler-lifecycle_20260826/index.md](./tracks/scheduler-lifecycle_20260826/index.md)*

  Ya no es hipotético. La Fase 3 de la rebanada 1 del MVP introdujo el transporte y la carrera se manifestó, tal como este registro anticipaba: la suite de `MIDI` pasó a fallar ~1 de cada 6 pasadas con `clientCreationFailed(-50)`, contra 0 de 18 en `main`. Eso haría fallar el check del PR sin culpa del cambio revisado, que es justo lo que el gate de Pull Requests se reparó para evitar.

  El MVP queda pausado tras su Fase 3 hasta que esto se cierre. Evidencia en las git notes de `a6e49fb` y `b9557f3`.

---

- [ ] **Track: Flake `clientCreationFailed(-50)` en MIDITests** — *bloqueado por el track anterior*
  *Link: [conductor/tracks/midi-test-flake_20260826/index.md](./tracks/midi-test-flake_20260826/index.md)*

## Archivados

- [x] **Track: Timing Spike — validación del reloj MIDI** — arquitectura validada en iPad (máx 0,149 ms, σ 0,009 ms)
  *Link: [conductor/archive/timing-spike_20260826/index.md](./archive/timing-spike_20260826/index.md)*
