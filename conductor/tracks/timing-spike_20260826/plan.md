# Plan — Timing Spike: validación del reloj MIDI

**Track ID:** `timing-spike_20260826`

Sigue la metodología definida en [`workflow.md`](../../workflow.md): tests fallando primero (Red), implementación mínima (Green), refactor, verificación de cobertura y checkpoint de fase.

## Phase 1: Scaffold y fronteras [checkpoint: e05c019]

- [x] Task: Crear el proyecto Xcode y los paquetes SPM (df1ad4c)
  - [x] Proyecto Xcode con target `App`, iPadOS 17+ mínimo
  - [x] Paquete SPM `Engine` (solo stdlib) y paquete `MIDI`
  - [x] Targets de test para ambos paquetes
  - [x] Verificar que `swift test --package-path Packages/Engine` corre sin simulador
- [x] Task: Imponer la frontera de dependencias de `Engine` (5555c17)
  - [x] Escribir un test que falle si `Engine` gana dependencias de plataforma
  - [x] Confirmar que el test pasa con el `Package.swift` actual
- [x] Task: Actualizar comandos de desarrollo en `workflow.md` (e513aa7)
  - [x] Sustituir los comandos indicativos por los reales del proyecto ya creado
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md) (e05c019)

## Phase 2: Reloj y salida MIDI

- [x] Task: Modelo de tiempo musical (4aac307)
  - [x] Tests (Red): conversión tempo→intervalo de step a 60/120/174 BPM
  - [x] Tests (Red): división 1/16
  - [x] Tests (Red): acumulación sin deriva sobre 1000 steps
  - [x] Implementación (Green): tipos de tiempo musical y conversión a tiempo de host
  - [x] Refactor y verificar cobertura ≥80%
- [x] Task: Scheduler look-ahead (0d5f7dc)
  - [x] Tests (Red): dada una ventana y un instante, produce el conjunto correcto de eventos
  - [x] Tests (Red): sin duplicar ni omitir eventos en el solape entre ventanas
  - [x] Implementación (Green): cálculo de ventana sin asignaciones — devuelve `Range<Int>`, con lo que el buffer preasignado que preveía el plan resulta innecesario
  - [x] Marcar las funciones de tiempo real con `/// Realtime:`
  - [x] Refactor y verificar cobertura
- [x] Task: Cliente CoreMIDI de salida (d24f8e5)
  - [x] Tests (Red): construcción de paquetes note-on/note-off y asignación de timestamps
  - [x] Implementación (Green): cliente, enumeración de destinos, envío con `MIDISendEventList`
  - [x] Manejar la desconexión de dispositivo como estado esperado, no como error — vía `onSetupChanged`; el resultado del envío no la detecta (CoreMIDI acepta endpoints inválidos con `noErr`)
- [~] Task: Hilo del scheduler y publicación de snapshot
  - [ ] Implementación: hilo dedicado de alta prioridad
  - [ ] Implementación: lectura de snapshot inmutable, sin locks
  - [ ] Revisión explícita: sin asignaciones, locks, `await`, logging ni SwiftUI en el camino
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 3: Instrumentación de medición

- [ ] Task: Documentar la desviación de `tech-stack.md` (antes de implementar FR4)
  - [ ] Añadir nota fechada: endpoints virtuales admitidos como instrumentación, no como producto
  - [ ] Commit separado con scope `docs`
- [ ] Task: Endpoints virtuales de loopback
  - [ ] Implementación: fuente y destino virtuales
  - [ ] Implementación: recepción con timestamp de CoreMIDI
  - [ ] Excluidos del build de producción
- [ ] Task: Arnés de medición de jitter
  - [ ] Tests (Red): cálculo de máximo, media y desviación típica sobre series conocidas
  - [ ] Implementación (Green): captura de desviaciones y agregación por tempo
  - [ ] Tamaño de muestra configurable, 200 eventos por defecto
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 4: UI mínima y veredicto

- [ ] Task: UI mínima de control
  - [ ] Play/stop, selección de tempo, presentación de resultados por tempo
  - [ ] Sin lenguaje visual del producto — es instrumentación
- [ ] Task: Ejecutar la medición en el iPad objetivo
  - [ ] Barrido a 60, 120 y 174 BPM, 200 eventos por tempo
  - [ ] Registrar máximo, media y desviación típica de cada tempo
- [ ] Task: Pasada larga de confirmación
  - [ ] Repetir con ~1000 eventos por tempo para cubrir la limitación de muestra corta
- [ ] Task: Veredicto sobre el criterio de aceptación
  - [ ] Contrastar contra el umbral: máx < 2 ms, desviación típica < 0.5 ms
  - [ ] Registrar los números en la git note del commit
  - [ ] Si no se cumple: parar y reportar con datos. No iterar arquitecturas dentro de este track
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Notas de riesgo

- **La Fase 2 concentra el riesgo**, pero no es medible hasta la Fase 4, cuando el instrumento existe. Es inherente a un spike.
- **La última tarea puede terminar en "no".** Está escrita como veredicto, no como éxito garantizado.
