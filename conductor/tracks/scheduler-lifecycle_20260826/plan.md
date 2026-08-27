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

- [x] Task: Cierre ordenado de `CoreMIDIOutput` — `c8c8ed0`
  - [x] Tests (Red): cerrar es idempotente; enviar tras cerrar es un estado esperado, no un error
  - [x] Implementación (Green): `close()` explícito — puerto y luego cliente
  - [x] `deinit` pasa a ser red de seguridad idempotente, no el mecanismo principal
- [x] Task: Cierre ordenado de `VirtualLoopback` — `cd70b95`
  - [x] Tests (Red): cerrar es idempotente; no llegan callbacks tras cerrar
  - [x] Implementación (Green): `close()` explícito — endpoint y luego cliente
- [x] Task: `JitterHarness` desmonta en orden — `9bfb02a`
  - [x] Implementación: dejar de programar → drenar la ventana entregada → dejar de enviar → destruir endpoints → destruir clientes
  - [x] Sustituir la confianza en el orden de liberación de ARC por el cierre explícito
  - [~] Verificar que la tasa de `-50` no empeora respecto a la medida en la Fase 1 — **NO SE CUMPLE**: 3 ocurrencias contra 0 en `main`. Ver abajo.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 3: Cerrar la carrera

- [x] Task: `stop()` espera al hilo — `964f22f`
  - [x] Implementación (Green): el hilo señala su salida; `stop()` espera con cota superior
  - [x] La espera corre en el hilo de control — el bucle del scheduler sigue sin locks ni asignaciones
  - [x] Agotar la cota se reporta; parar nunca cuelga a quien lo pide
  - [x] El test de la Fase 1 pasa, y sigue fallando si se desactiva la guarda
- [ ] Task: Verificar que la suite no se degrada
  - [ ] 12+ pasadas de `MIDI`, comparadas contra la tasa base de la Fase 1
  - [ ] Cobertura de `MIDI` ≥80%
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Estado: PARADO EN LA FASE 3, el 2026-08-27

**La carrera está cerrada. El track no se puede cerrar.**

FR1 y FR2 se cumplen y están verificados: `stop()` espera al hilo, reiniciar no
solapa bucles, y los tests de regresión pasan con la guarda y fallan 3 de 3 sin
ella. FR3 y FR4 también: `CoreMIDIOutput` y `VirtualLoopback` tienen cierre
explícito, ordenado e idempotente, y `deinit` quedó como red de seguridad.

Lo que no se cumple es el último criterio de aceptación: **la tasa de
`clientCreationFailed(-50)` empeora respecto a `main`.**

Bisección por commits (ocurrencias de `-50`, saltando los tests nuevos de cada
commit para no contarse a sí mismos):

| Punto | `-50` |
|---|---|
| `main` | **0** de 18 pasadas |
| `cc251ec` test de regresión | 0 |
| `c8c8ed0` + `close()` de `CoreMIDIOutput` | 0 |
| `cd70b95` + `close()` de `VirtualLoopback` | 0 |
| `9bfb02a` + desmontaje en orden del arnés | **3** |
| `964f22f` + join en `stop()` | **3** |

**Las dos piezas rompen la suite por separado**: revirtiendo el arnés y dejando
solo el join, siguen saliendo 3. Coincide con los dos intentos que la propia
spec daba por descartados, y demuestra que **el cierre explícito de la Fase 2 no
era la pieza que faltaba** — que es justo la hipótesis sobre la que se construyó
el plan.

Se para aquí porque el plan lo instruye: *«Si el cierre explícito no estabiliza
el desmontaje, la Fase 3 vuelve a chocar con el mismo muro y hay que parar y
reportar con datos, no probar variantes a ciegas.»*

El entorno queda descartado: `main` se remidió tres veces a lo largo de la
sesión —tras 12, ~40 y ~70 pasadas acumuladas— y siempre dio 0.

Lo que falla es siempre la creación de **endpoints virtuales**, y lo que las dos
piezas tienen en común es que **retrasan el desmontaje**. Eso apunta a que el
diagnóstico de la spec es correcto pero su remedio es insuficiente: no basta con
controlar *el orden* del desmontaje, hay que entender por qué retrasarlo lo
rompe. Eso es diagnóstico de CoreMIDI, que esta spec puso explícitamente fuera
de alcance y que pertenece a `midi-test-flake_20260826`.

## Notas de riesgo

- **La Fase 2 es la que decide el track.** Si el cierre explícito no estabiliza el desmontaje, la Fase 3 vuelve a chocar con el mismo muro y hay que parar y reportar con datos, no probar variantes a ciegas.
- **El criterio de la Fase 1 es exigente a propósito.** Un test de esta carrera que no se haya visto fallar no prueba nada: ya ocurrió una vez en la revisión, con un test que pasaba por razones equivocadas.
