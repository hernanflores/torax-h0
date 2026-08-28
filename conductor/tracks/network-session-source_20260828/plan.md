# Plan — La sesión MIDI de red monopoliza la entrada

**Track ID:** `network-session-source_20260828`

Sigue la metodología definida en [`workflow.md`](../../workflow.md): tests fallando primero (Red), implementación mínima (Green), refactor, verificación de cobertura y checkpoint de fase. El trabajo va en rama y se integra por Pull Request.

**Orden:** primero identificar el endpoint de red de forma fiable, porque de eso
depende la forma del arreglo. Filtrar por nombre visible está descartado de
entrada (`NFR4`).

## Phase 1: Distinguir la sesión de red

- [ ] Task: Identificar el endpoint de red por propiedad, no por nombre
  - [ ] Diagnóstico: qué propiedades de CoreMIDI lo distinguen en un iPad real (`kMIDIPropertyDriverOwner`, `kMIDIPropertyModel`, entidad y dispositivo padre)
  - [ ] Registrar en la git note lo que devuelve cada candidata, con el valor observado
  - [ ] Decidir la propiedad y documentar por qué, no solo cuál
- [ ] Task: `MIDIEndpointInfo` lleva el dato de la decisión
  - [ ] Tests (Red): construir la información desde valores conocidos, sin CoreMIDI de por medio
  - [ ] Implementación (Green): el campo entra por el enumerador, que es quien habla con CoreMIDI
  - [ ] La estructura sigue siendo un valor testeable sin hardware (`NFR1`)
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 2: Elegible pero nunca por defecto

- [ ] Task: Separar «disponible» de «autoseleccionable»
  - [ ] Tests (Red): con solo la sesión de red, `hasEndpoint` es `false` y el estado es `No MIDI input`
  - [ ] Tests (Red): con red + controlador, queda elegido el controlador
  - [ ] Tests (Red): añadir un controlador al refrescar lo selecciona; quitarlo vuelve al estado vacío
  - [ ] Tests (Red): la red sigue en `available` y `selecting(_:)` la acepta
  - [ ] Tests (Red): una elección manual de la red sobrevive al refresco (`FR4`)
  - [ ] Tests (Red): el destino no cambia — sus tests siguen en verde
  - [ ] Implementación (Green): la autoselección salta la sesión de red; la elegibilidad no cambia
- [ ] Task: Verificación en iPad — **requiere iPad y controlador**
  - [ ] Sin controlador: se lee `No MIDI input` y el indicador `read-only`
  - [ ] Conectar el BeatStep Pro: responde a los knobs sin tocar el selector
  - [ ] Desconectarlo vuelve al estado vacío, sin error ni caída
  - [ ] La sesión de red se puede seleccionar a mano y funciona
- [ ] Task: Verificar cobertura de `MIDI` ≥80%
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Notas de riesgo

- **La regla «nunca por defecto» puede sorprender a quien use MIDI por red.** Si
  alguien trabaja de verdad por red, cada arranque le exigirá elegirla. Es
  aceptable mientras no haya persistencia; cuando la haya, recordar la última
  elección lo resuelve mejor que cualquier heurística.
- **La propiedad que identifica la red puede no ser estable entre versiones de
  iPadOS.** Por eso el diagnóstico de la Fase 1 se registra con los valores
  observados: si cambia, se sabrá contra qué comparar.
