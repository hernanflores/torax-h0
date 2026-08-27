# Plan — Ciclo de vida del scheduler y desmontaje de CoreMIDI

**Track ID:** `scheduler-lifecycle_20260826`

Sigue la metodología definida en [`workflow.md`](../../workflow.md): tests fallando primero (Red), implementación mínima (Green), refactor, verificación de cobertura y checkpoint de fase. El trabajo va en rama y se integra por Pull Request.

**Orden deliberado:** el cierre explícito (Fase 2) va **antes** que el join (Fase 3). Al revés ya se probó y deja la suite en rojo 4 de 4 — la carrera no se puede cerrar hasta que el desmontaje deje de ocurrir en un instante que nadie controla.

## Phase 1: Caracterizar la carrera

- [x] Task: Test de regresión que falle de verdad — `cc251ec`
  - [x] Tests (Red): ciclos rápidos de `stop()`/`start()` detectando Steps duplicados o fuera de orden
  - [x] Línea de tiempo rápida frente a la ventana (p. ej. 300 BPM en 1/256 ≈ 3,1 ms por Step contra una ventana de 20 ms) — con los 125 ms por Step del resto de los tests no hay solape posible
  - [x] **Verificar que el test falla sin la guarda**, no solo que pasa con ella
  - [x] Distinguir el defecto real de «el hilo viejo emite unos ms tras `stop()`», que es esperado mientras `stop()` no espere
- [x] Task: Medir la tasa base de `-50` en `main` — **0 de 18 pasadas**
  - [x] 12+ pasadas de `swift test --package-path Packages/MIDI`, registrar el número de fallos
  - [x] Es la referencia contra la que se comprobará que el arreglo no empeora nada

  Medido el 2026-08-27 en dos tandas (12 + 6) sobre `main` limpio, la segunda
  después de ~40 pasadas de sesión para descartar deriva del entorno: **0 fallos
  en 18 pasadas**. La rama del MVP, en cambio, daba ~1 de cada 6 — ver la git
  note de `a6e49fb`.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 2: Cierre explícito del arnés

- [~] Task: Cierre ordenado de `CoreMIDIOutput`
  - [ ] Tests (Red): cerrar es idempotente; enviar tras cerrar es un estado esperado, no un error
  - [ ] Implementación (Green): `close()` explícito — puerto y luego cliente
  - [ ] `deinit` pasa a ser red de seguridad idempotente, no el mecanismo principal
- [ ] Task: Cierre ordenado de `VirtualLoopback`
  - [ ] Tests (Red): cerrar es idempotente; no llegan callbacks tras cerrar
  - [ ] Implementación (Green): `close()` explícito — endpoint y luego cliente
- [ ] Task: `JitterHarness` desmonta en orden
  - [ ] Implementación: dejar de programar → drenar la ventana entregada → dejar de enviar → destruir endpoints → destruir clientes
  - [ ] Sustituir la confianza en el orden de liberación de ARC por el cierre explícito
  - [ ] Verificar que la tasa de `-50` no empeora respecto a la medida en la Fase 1
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 3: Cerrar la carrera

- [ ] Task: `stop()` espera al hilo
  - [ ] Implementación (Green): el hilo señala su salida; `stop()` espera con cota superior
  - [ ] La espera corre en el hilo de control — el bucle del scheduler sigue sin locks ni asignaciones
  - [ ] Agotar la cota se reporta; parar nunca cuelga a quien lo pide
  - [ ] El test de la Fase 1 pasa, y sigue fallando si se desactiva la guarda
- [ ] Task: Verificar que la suite no se degrada
  - [ ] 12+ pasadas de `MIDI`, comparadas contra la tasa base de la Fase 1
  - [ ] Cobertura de `MIDI` ≥80%
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Notas de riesgo

- **La Fase 2 es la que decide el track.** Si el cierre explícito no estabiliza el desmontaje, la Fase 3 vuelve a chocar con el mismo muro y hay que parar y reportar con datos, no probar variantes a ciegas.
- **El criterio de la Fase 1 es exigente a propósito.** Un test de esta carrera que no se haya visto fallar no prueba nada: ya ocurrió una vez en la revisión, con un test que pasaba por razones equivocadas.
