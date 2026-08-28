# Tracks Registry

## MVP — v1

La prioridad del proyecto. Sin app no hay nada que arreglar.

---

*Sin tracks abiertos.* La rebanada 1 está cerrada y archivada: Torax H-0 suena.
El siguiente paso natural es la **entrada de control** —knobs relativos,
controlador virtual de desarrollo, preset del BeatStep Pro, MIDI Learn—, que es
lo que convierte la app de solo lectura en instrumento. El relevo de snapshot en
caliente ya está hecho y probado, así que girar un knob será publicar un `Track`
nuevo por un camino que ya existe.

## Defectos conocidos

Con la rebanada 1 del MVP cerrada, son lo siguiente en la cola junto con la
entrada de control. La cadena tiene un orden forzado: `midi-test-flake` bloquea
a `scheduler-lifecycle`, no al revés.

---

- [ ] **Track: Ciclo de vida del scheduler y desmontaje de CoreMIDI**
  *Link: [conductor/tracks/scheduler-lifecycle_20260826/index.md](./tracks/scheduler-lifecycle_20260826/index.md)*

  **Investigado el 2026-08-27; parado en su Fase 3.** La carrera es real y está resuelta en la rama `fix/scheduler-lifecycle`, que no se integra: cerrarla empeora la tasa de `clientCreationFailed(-50)` de 0 a 3 ocurrencias por pasada. La hipótesis sobre la que se construyó su plan —que un cierre explícito y ordenado de CoreMIDI estabilizaría el desmontaje— resultó falsa: el join y el desmontaje del arnés rompen la suite **por separado**. Lo que ambos tienen en común es retrasar el desmontaje, lo que apunta a diagnóstico de CoreMIDI: alcance de [`midi-test-flake_20260826`](./tracks/midi-test-flake_20260826/index.md), que pasa a ser el bloqueante.

  Datos completos en `plan.md` del track y en las git notes de la rama.

---

- [ ] **Track: Flake `clientCreationFailed(-50)` en MIDITests** — *ya no está bloqueado: es al revés*
  *Link: [conductor/tracks/midi-test-flake_20260826/index.md](./tracks/midi-test-flake_20260826/index.md)*

  La investigación del 2026-08-27 invirtió la dependencia. El ciclo de vida del scheduler no se puede cerrar sin entender antes por qué retrasar el desmontaje inutiliza la creación de endpoints virtuales de CoreMIDI.

## Archivados

- [x] **Track: MVP rebanada 1 — Shape, transporte y primer sonido** — suena en hardware; jitter con carga máx 0,127 ms · σ 0,015 ms
  *Link: [conductor/archive/mvp-shape-transport_20260827/index.md](./archive/mvp-shape-transport_20260827/index.md)*

- [x] **Track: Timing Spike — validación del reloj MIDI** — arquitectura validada en iPad (máx 0,149 ms, σ 0,009 ms)
  *Link: [conductor/archive/timing-spike_20260826/index.md](./archive/timing-spike_20260826/index.md)*
