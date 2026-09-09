# Plan — MVP rebanada 8: MIDI Learn, con `network-session-source` dentro

Sigue el `workflow.md`: tests antes de implementación, un commit por tarea, git
note por commit y checkpoint verificado al cerrar cada fase.

**El orden lo decide el bloqueo, no el tamaño.** La fuente va primero porque
MIDI Learn tiene que escuchar la correcta: aprender de `Red Session 1` es
aprender de nada, y descubrirlo al final significaría rehacer la verificación en
dispositivo entera. Después el mapeo mutable, que es la costura; después
aprender, que es el núcleo; después que sobreviva; y al final la pantalla, el
dispositivo y el cierre de la v1.

**La Fase 1 son dos decisiones y ningún código**, y las dos se toman antes de
empezar porque las dos pueden cambiar el resto del plan: qué hacer con la
medición final de la v1 (FR19) y cómo entra el mapeo en el fichero de disco
(FR17). Tomarlas al final, con la rama abierta, es cómo se toman mal.

**La Fase 2 lleva un diagnóstico en dispositivo que no se puede saltar.** Qué
propiedad de CoreMIDI distingue la sesión de red se mira en un iPad real y se
anota con los valores observados; el nombre visible está descartado de entrada
(NFR4).

**Cada fase deja el producto mejor que como lo encontró.** Al cerrar la Fase 2 el
defecto de la sesión de red está arreglado y la issue #43 se puede cerrar, aunque
MIDI Learn no llegue a existir. Al cerrar la 5, el mapeo sobrevive a un reinicio.

**La medición de jitter, según FR19**, que se decide en la Fase 1.

## FASE 1: LAS DOS DECISIONES [checkpoint: 4562ea1]

- [x] Task: Decidir qué pasa con la medición final de la v1 (FR19) — **decisión
      del usuario** `9d00512`
  - [x] Presentar las dos salidas con su coste: medir esta pasada levantando la
        suspensión solo para ella, o cerrar la v1 sin su medición.
  - [x] Dejar delante la última referencia válida: rebanada 2 de la v2,
        2026-09-02 — máx 0,158 ms, σ 0,013–0,014 ms, 1000 eventos por tempo.
  - [x] Escribir la decisión en `workflow.md`, con fecha, gane la que gane. Una
        excepción que se deja sin resolver es peor que cualquiera de las dos.
  - [x] **Resuelto: la v1 cierra sin medir.** La excepción de la nota del
        2026-08-28 queda anulada en `workflow.md`, con su coste y su vuelta
        atrás escritos.
- [x] Task: Decidir cómo entra el mapeo en el fichero de disco (FR17) `4562ea1`
  - [x] Las dos salidas: campo opcional sin subir `schemaVersion`, o subir a 2 y
        estrenar el migrador que `persistence_20260907` dejó preparado y vacío.
  - [x] Lo que decide: `ProjectRecord.validated()` exige igualdad exacta, así que
        subir la versión sin migrador **aparta todos los ficheros existentes**.
  - [x] Escribir el porqué en el `spec.md`, no solo el qué.
  - [x] **Resuelto: campo opcional, `schemaVersion` se queda en 1.** Un mapeo
        ausente es «nunca aprendió nada», que es lo que un opcional ya significa
        aquí — el mismo criterio de `destinationName` y `sourceName`.
  - [x] **Hallazgo**: `migrated(_:)` se documenta como enchufado y no lo está.
        Se arregla en la Fase 5.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 2: LA FUENTE CORRECTA — `network-session-source` DENTRO

- [~] Task: Identificar el endpoint de red por propiedad, no por nombre (FR12,
      NFR4) — **requiere iPad** `930713e`
  - [x] La instrumentación: `EndpointDiagnostics` lee las candidatas
        —`kMIDIPropertyDriverOwner`, `kMIDIPropertyModel`, `manufacturer`,
        `uniqueID`, entidad y dispositivo padre— más el volcado entero, y las
        imprime al arrancar bajo `#if DEBUG`. 9 tests sobre el formato.
  - [ ] **Correrlo en el iPad, dos veces**: con el BeatStep Pro conectado y sin
        él. Es la mitad que no se puede hacer sin dispositivo.
  - [ ] Registrar en la git note **lo que devuelve cada candidata**, con el valor
        observado. Es lo que permitirá saber contra qué comparar si iPadOS lo
        cambia.
  - [ ] Decidir la propiedad y documentar **por qué**, no solo cuál.
- [ ] Task: `MIDIEndpointInfo` lleva el dato de la decisión (NFR2)
  - [ ] Tests (Red): construir la información desde valores conocidos, sin
        CoreMIDI de por medio.
  - [ ] Implementación (Green): el campo entra por el enumerador, que es quien
        habla con CoreMIDI. La estructura sigue siendo un valor testeable sin
        hardware.
- [ ] Task: Elegible pero nunca por defecto (FR12, FR13, FR14)
  - [ ] Tests (Red): con **solo** la sesión de red, `hasEndpoint` es `false` y el
        estado es `No MIDI input`.
  - [ ] Tests (Red): con red + controlador, queda elegido el controlador.
  - [ ] Tests (Red): añadir un controlador al refrescar lo selecciona; quitarlo
        vuelve al estado vacío.
  - [ ] Tests (Red): la red sigue en `available` y `selecting(_:)` la acepta.
  - [ ] Tests (Red): una elección manual de la red sobrevive al refresco.
  - [ ] Tests (Red): el **destino** no cambia de comportamiento — sus tests
        siguen en verde.
  - [ ] Implementación (Green): la autoselección salta la sesión de red; la
        elegibilidad no cambia.
- [ ] Task: Lo recordado manda (FR15)
  - [ ] Tests (Red): con una fuente recordada y presente, se elige — **incluida
        la de red**, que elegida a mano es una elección explícita.
  - [ ] Tests (Red): con lo recordado ausente, se cae a la regla de FR12 y no a
        la red.
  - [ ] Implementación (Green): apoyada en el `sourceName` que el `Project` ya
        guarda desde `persistence_20260907`.
- [ ] Task: Verificación en iPad — **requiere iPad y controlador**
  - [ ] Sin controlador: se lee `No MIDI input` y el indicador `read-only`.
  - [ ] Conectar el BeatStep Pro: responde a los knobs sin tocar el selector.
  - [ ] Desconectarlo vuelve al estado vacío, sin error ni caída.
  - [ ] La sesión de red se elige a mano, funciona y **sobrevive a reiniciar la
        app**.
- [ ] Task: Cerrar la [issue #43](https://github.com/hernanflores/torax-h0/issues/43)
  - [ ] Con lo verificado en dispositivo, y enlazando a este track.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 3: EL MAPEO DEJA DE SER FIJO

- [ ] Task: `ControlInput` adopta un mapeo (FR2, FR3, NFR1)
  - [ ] Tests (Red): adoptar un mapeo cambia a qué controlador responde cada
        destino, **sin tocar el material**: ni una nota, ni un Cycle, ni el Track
        seleccionado.
  - [ ] Tests (Red): adoptar **no publica** material, por la misma razón que
        `adopt(_:)` para el Pattern.
  - [ ] Tests (Red): un control que el mapeo nuevo no asigna deja de hacer nada,
        y eso no es un error (FR5).
  - [ ] Implementación (Green): `mapping` deja de ser un `let` privado; la vía
        pública va junto a `adopt(_:)`.
- [ ] Task: Un destino, un control (FR4, FR5)
  - [ ] Tests (Red): asignar un controlador ya ocupado **desasigna** al destino
        anterior, que se queda sin control.
  - [ ] Tests (Red): un destino sin control no se puede mover y no revienta.
  - [ ] Tests (Red): las tres familias conviven sin pisarse — es lo que
        `declaredNumbers` ya comprueba para el preset, extendido al aprendido.
  - [ ] Implementación (Green): la regla vive en `ControlMapping`, con tests.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 4: APRENDER

- [ ] Task: El estado de aprendizaje (FR6, FR9, FR10, FR11)
  - [ ] Tests (Red): en aprendizaje, un CC **asigna y no mueve el parámetro**.
  - [ ] Tests (Red): salir sin asignar deja el mapeo como estaba.
  - [ ] Tests (Red): fuera de aprendizaje, todo se comporta como hoy — la suite
        entera de `ControlInput` es el test de no regresión.
  - [ ] Implementación (Green): el estado vive en `MIDI`, donde se testea sin
        dedo de por medio.
- [ ] Task: Las tres familias, y un giro es una asignación (FR7, FR8)
  - [ ] Tests (Red): un knob se aprende con el primer CC; los siguientes del
        mismo control **no** reabren la pregunta.
  - [ ] Tests (Red): un pad se aprende con su nota; un step button con su CC de
        conmutación.
  - [ ] Tests (Red): los mensajes que no son del control esperado no asignan.
  - [ ] Implementación (Green).
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 5: QUE SOBREVIVA

- [ ] Task: El mapeo entra en el `Project` (FR16, NFR3)
  - [ ] Tests (Red): round-trip del mapeo por `ProjectRecord`, con el resto de
        ajustes de sesión intactos.
  - [ ] Tests (Red): el mapeo de fábrica y uno aprendido se distinguen en disco.
  - [ ] Implementación (Green): junto a `clockSource`, `destinationName` y
        `sourceName`, que es donde ya vive lo que no es material.
- [ ] Task: Los ficheros existentes abren (FR17)
  - [ ] Tests (Red): un fichero escrito **antes** de este track —sin la clave del
        mapeo— abre, y abre con el preset de fábrica.
  - [ ] Tests (Red): `schemaVersion` **sigue siendo 1**, y un fichero que declare
        2 se sigue apartando. La decisión de la Fase 1 es que esta rebanada no
        estrena la subida de versión.
  - [ ] Implementación (Green): campo opcional en `ProjectRecord`, con el mismo
        criterio que `destinationName` y `sourceName`.
- [ ] Task: Enchufar el migrador que se documenta como enchufado
  - [ ] Tests (Red): el camino de carga pasa por `ProjectRecord.migrated(_:)` y
        no por `validated()` a secas.
  - [ ] Implementación (Green): una línea en `ProjectStore.load()`
        (`ProjectStore.swift:187`).
  - [ ] Hoy no cambia ningún comportamiento —`migrated(_:)` solo valida—, y ese
        es el momento de hacerlo: quien escriba la primera migración de verdad
        confiará en el comentario que ya dice que la llamada está puesta.
- [ ] Task: Vía de vuelta al preset de fábrica (FR18)
  - [ ] Tests (Red): restaurar el preset deja `ControlMapping.beatStepPro` y no
        toca el material.
  - [ ] Implementación (Green).
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 6: LA PANTALLA

- [ ] Task: Aprender desde la pantalla `midi` (FR6, FR11)
  - [ ] Elegir el destino, entrar en aprendizaje, ver qué se está esperando y
        salir. **Sin modal que bloquee con el transporte corriendo**
        (`product-guidelines.md`).
  - [ ] Enseñar qué destinos han quedado **sin control** tras un aprendizaje
        (FR4, FR5): un destino mudo que no se anuncia parece un fallo.
  - [ ] El botón de volver al preset de fábrica (FR18).
  - [ ] Sobre el chrome de `screens-redesign_20260906`, sin inventar un lenguaje
        visual nuevo.
  - [ ] La lógica que merezca un test **no vive aquí** (`workflow.md`): si
        aparece una decisión en `App`, baja a `MIDI`.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 7: DISPOSITIVO, MEDICIÓN Y CIERRE DE LA v1

- [ ] Task: Verificación en iPad — **requiere iPad, BeatStep Pro y un segundo
      controlador**
  - [ ] Aprender un knob, un pad y un step button del **segundo** controlador.
        Sin él no se prueba nada de esta rebanada: con el BeatStep Pro solo se
        reaprendería el preset.
  - [ ] Girar durante el aprendizaje asigna una vez y no mueve el parámetro.
  - [ ] Aprender con la secuencia sonando, sin cortes.
  - [ ] Cerrar y abrir la app: el mapeo sigue puesto. Volver al preset de fábrica
        y comprobar que el BeatStep Pro vuelve a mandar.
  - [ ] Repasar los cuarenta y ocho controles del preset restaurado contra la
        tabla de `preset/README.md`, como hizo la rebanada 7 (NFR6).
  - [ ] Escribir `device-verification.md` con lo que se probó y lo que falló.
- [ ] Task: La medición final de la v1, según la decisión de la Fase 1 (FR19)
  - [ ] **Si se mide**: rejilla `12-tracks-cycles`, en dispositivo, y el número
        entra en `product.md`, en el registro y en la git note.
  - [ ] **Si no**: la nota fechada en `workflow.md` que la Fase 1 escribió, y una
        línea en el registro diciendo que la v1 cerró sin ella.
- [ ] Task: Cobertura y suite completa
  - [ ] `Engine` ≥90%, `MIDI` ≥80% medida en un proceso e ignorando
        `Engine/Sources`, `Persistence` ≥90% si el mapeo bajó ahí.
- [ ] Task: Pull Request
  - [ ] Rama `feat/midi-learn`, PR contra `main`. Cuerpo corto.
- [ ] Task: Cerrar la v1 en la documentación
  - [ ] `product.md`: quitar la promesa pendiente de la nota del 2026-08-31 —«esta
        página promete un MIDI Learn que la app todavía no hace»— y decir qué se
        entregó.
  - [ ] `tracks.md`: cerrar la rebanada 8 y **la v1 entera**, con lo verificado en
        dispositivo.
  - [ ] Anotar en el `spec.md` lo que se haya corregido al implementar, con
        fecha.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
