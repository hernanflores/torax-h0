# Plan — Flake `clientCreationFailed(-50)` en MIDITests

**Track ID:** `midi-test-flake_20260826`

Sigue la metodología definida en [`workflow.md`](../../workflow.md). El trabajo va en rama y se integra por Pull Request.

> **Bloqueado.** No arranca hasta que el cierre explícito de `scheduler-lifecycle_20260826` esté en `main`. La Fase 1 es la que decide si el track sigue vivo o se reduce a verificar.

## Phase 1: Re-medir y decidir

- [ ] Task: Verificar que el bloqueo se levantó
  - [ ] Confirmar que el cierre explícito de CoreMIDI está en `main`
- [ ] Task: Re-medir la tasa de `-50`
  - [ ] 12+ pasadas consecutivas de `swift test --package-path Packages/MIDI`, contando fallos
  - [ ] Comparar contra la referencia de partida (~1 de cada 12 sobre `main` del 2026-08-26)
  - [ ] Registrar el número en la git note de la tarea
- [ ] Task: Decidir la forma del track
  - [ ] Si el flake desapareció: saltar a la Fase 3
  - [ ] Si persiste: continuar por la Fase 2
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 2: Diagnóstico y arreglo *(solo si el flake persiste)*

- [ ] Task: Reproducir fuera de XCTest
  - [ ] Programa aislado que replique la secuencia del arnés hasta provocar el `-50`
  - [ ] Sin el runner de tests de por medio: si no se reproduce, eso ya es un dato
- [ ] Task: Identificar el recurso que se agota o se corrompe
  - [ ] Instrumentar creación y destrucción de clientes, puertos y endpoints
  - [ ] Contrastar contra lo ya descartado: no es un límite de clientes (200 se crean sin fallo)
- [ ] Task: Corregir
  - [ ] Tests (Red): un test que exponga el fallo de forma determinista, si el diagnóstico lo permite
  - [ ] Implementación (Green): la forma la decide el diagnóstico
  - [ ] No ocultar el síntoma: reintentar, silenciar o saltar el test no es un arreglo
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 3: Verificación y cierre

- [ ] Task: 20+ pasadas consecutivas sin un solo `-50`
  - [ ] Registrar el número de pasadas y el resultado en la git note
- [ ] Task: Documentar la causa raíz
  - [ ] En el track; y en `tech-stack.md` si afecta a una decisión de arquitectura
  - [ ] «Desapareció» no es una causa: si el cierre explícito lo resolvió, explicar por qué
- [ ] Task: Verificar cobertura de `MIDI` ≥80%
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Notas de riesgo

- **Un flake de tasa baja se mide mal.** 20 pasadas limpias no descartan uno mucho más raro. El criterio acota el riesgo; no lo elimina.
- **La tentación es poner la CI en verde.** `NFR1` existe por eso: sin causa raíz, cualquier arreglo es una conjetura con buena pinta.
