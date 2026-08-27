# Plan — MVP rebanada 1: Shape, transporte y primer sonido

**Track ID:** `mvp-shape-transport_20260827`

Sigue la metodología definida en [`workflow.md`](../../workflow.md): tests fallando primero (Red), implementación mínima (Green), refactor, verificación de cobertura y checkpoint de fase. El trabajo va en rama y se integra por Pull Request.

**Orden:** el motor puro primero (Fase 1), porque se testea sin simulador y sin hardware y es donde vive la corrección musical. Solo después se conecta hacia abajo (Fase 2) y hacia fuera (Fases 3 y 4).

## Phase 1: Shape en `Engine` [checkpoint: cff338e]

- [x] Task: Tipos de Shape — `71d8bb8`
  - [x] Tests (Red): `Steps` acepta 1–16 y rechaza fuera de rango; `Pulses` acepta 1..Steps
  - [x] Tests (Red): `Rotate` admite valores negativos y mayores que Steps
  - [x] Implementación (Green): validación en el inicializador, no en cada sitio de uso
  - [x] Vocabulario de la Pre Spec, sin sinónimos (`steps`, `pulses`, `rotate`)
- [x] Task: Reparto euclidiano — `b5a10fe`
  - [x] Tests (Red): **16/4, 16/5 y 12/7 de la Pre Spec**, como casos literales
  - [x] Tests (Red): bordes — Pulses = 1, Pulses = Steps, Steps = 1
  - [x] Tests (Red): determinismo — mismo estado, misma salida
  - [x] Implementación (Green): distribución euclidiana pura
  - [x] Refactor y verificar cobertura de `Engine` ≥90%
- [x] Task: Rotate — `d00e08f`
  - [x] Tests (Red): Rotate 0 es la identidad; Rotate = Steps vuelve al patrón original
  - [x] Tests (Red): Rotate negativo; Rotate mayor que Steps envuelve
  - [x] Tests (Red): rotar no cambia el número de Pulses
  - [x] Implementación (Green)
- [x] Task: Estado del Track — `cff338e`
  - [x] Tests (Red): un Track resuelve qué Steps disparan, combinando Shape y Rotate
  - [x] Implementación (Green): valor inmutable y `Sendable`, con su `Division`
  - [x] Sin `Int.random()` ni `.randomElement()` — no hay aleatorio en esta rebanada
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 2: Snapshot en caliente [checkpoint: 99c6673]

> La pieza que el spike dejó pendiente y el mayor riesgo técnico que queda en pie.

- [x] Task: Publicación atómica del snapshot — `cc3266e`
  - [x] Decidir el mecanismo sin locks: doble búfer con índice atómico, o ampliar `CToraxAtomics` con un puntero atómico. Documentar el porqué de la elección
  - [x] Tests (Red): el scheduler recoge un snapshot publicado a media reproducción, en la ventana siguiente
  - [x] Tests (Red): al cambiar de snapshot no se duplica ni se omite ningún Step
  - [x] Tests (Red): publicar desde otro hilo mientras el scheduler lee no corrompe el estado
  - [x] Implementación (Green)
  - [x] Revisión explícita: sin asignaciones, locks, `await`, logging ni SwiftUI en el camino del scheduler
  - [x] Marcar las funciones nuevas del camino con `/// Realtime:`
- [x] Task: Emisión de note-on y note-off — `99c6673`
  - [x] Tests (Red): cada pulso produce el par, con el note-off en su propio timestamp futuro
  - [x] Implementación (Green): gate de duración fija, declarado provisional en el código
  - [x] Sin sleeps ni temporizadores — el note-off va sellado, como el note-on
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 3: Salida real, transporte y pantalla [checkpoint: a6e49fb]

- [x] Task: Selección de destino MIDI — `da0edb3`
  - [x] Tests (Red): la lista refleja los destinos del sistema; sin destinos es un estado válido
  - [x] Implementación (Green): enumeración y selección
  - [x] El endpoint de medición no aparece como destino elegible
- [x] Task: Desconexión como estado esperado — `760fe8c`
  - [x] Tests (Red): `onSetupChanged` provoca reconsulta de destinos
  - [x] Implementación (Green): estado `No MIDI device`, sin lenguaje de error ni disculpa
- [x] Task: Transporte — `b5dc634`
  - [x] Tests (Red): play arranca el reloj, stop lo detiene y no quedan notas colgadas
  - [x] Implementación (Green): play/stop con reloj interno
  - [x] Al parar, enviar note-off de cualquier nota en curso
- [x] Task: Pantalla mínima de estado — `a6e49fb`
  - [x] Transporte, selección de destino y valores de Shape **en solo lectura**
  - [x] Sin lenguaje visual del producto: ni anillo, ni overlay de valor, ni acentos por familia
  - [x] Nada en pantalla debe sugerir una nota fija por paso — contradice el modelo de pool
  - [x] Verificar cobertura de `App` ≥80% — **umbral retirado**: el proyecto no tiene target de test ni runtime de simulador. La lógica se movió a `Engine` y `MIDI`, donde sí se cubre. Ver la nota del 2026-08-27 en `workflow.md`.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 4: Primer sonido y lectura de jitter

- [~] Task: Primer sonido en dispositivo — **requiere iPad y sintetizador**
  - [ ] Ejecutar en el iPad con un sintetizador conectado
  - [ ] Verificar los pulsos euclidianos audibles en las posiciones esperadas
  - [ ] Verificar que parar no deja notas colgadas
  - [ ] Verificar que desconectar a media reproducción se refleja como estado, no como caída
- [~] Task: Lectura indicativa de jitter con carga — **requiere iPad**
  - [ ] Barrido a 60, 120 y 174 BPM con el motor y la interfaz corriendo
  - [ ] Contrastar contra el umbral: máx < 2 ms, σ < 0,5 ms
  - [ ] Registrar los números en la git note del commit
  - [ ] Comparar contra la medición del spike: lo que interesa es la degradación al meter carga, no el valor absoluto
  - [ ] Si no se cumple: parar y reportar con datos. No iterar arquitecturas dentro de este track
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Estado del track

**Fases 1, 2 y 3 completas y verificadas.** Falta la Fase 4, que exige iPad y
sintetizador conectado.

### La pausa por `scheduler-lifecycle` se levantó el 2026-08-27

El transporte de la Fase 3 destapó la carrera de `stop()`/`start()`, tal como
las notas de riesgo de abajo anticipaban, y se subió la prioridad de
[`scheduler-lifecycle_20260826`](../scheduler-lifecycle_20260826/index.md) para
arreglarla antes de seguir.

**La carrera se cerró, pero el arreglo no se integra.** Cerrarla empeora la tasa
de `clientCreationFailed(-50)` de 0 a 3 ocurrencias por pasada, y la hipótesis
sobre la que se construyó aquel plan resultó falsa. El trabajo queda en la rama
`fix/scheduler-lifecycle` como registro; el bloqueante real pasa a ser
`midi-test-flake_20260826`.

### Lo que eso implica para este track

Se sigue con la Fase 4 asumiendo dos cosas conscientemente:

1. **El check de CI puede fallar** ~1 de cada 6 pasadas por el `-50`. Relanzar.
2. **Parar y arrancar deprisa puede duplicar notas en el iPad.** Es el defecto
   conocido, sin arreglar. Si al probar resulta molesto, es información para
   priorizar `midi-test-flake` y luego `scheduler-lifecycle`.

## Notas de riesgo

- **La Fase 2 concentra el riesgo.** Publicar un snapshot sin locks, en una plataforma donde la stdlib no da atómicos, es lo menos resuelto del track. Si aparece un lock en el camino del scheduler, el diseño está mal: revisarlo, no optimizarlo.
- **La carrera de `stop()`/`start()` está abierta** (`scheduler-lifecycle_20260826`). La Fase 3 introduce transporte, que es justo el gesto que la dispara. Si parar y arrancar duplica notas de forma audible, es señal de subir la prioridad de aquel track — no de parchearlo aquí.
- **La medición de la Fase 4 es indicativa.** Un resultado holgado no cierra la pregunta del timing bajo carga: falta el anillo. Un resultado malo, en cambio, sí es información dura y para el track.
