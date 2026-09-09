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

- [x] Task: Identificar el endpoint de red por propiedad, no por nombre (FR12,
      NFR4) — **requiere iPad** `930713e` `dae873c`
  - [x] La instrumentación: `EndpointDiagnostics` lee las candidatas más el
        volcado entero y las imprime al arrancar bajo `#if DEBUG`.
  - [x] **Corrido en el iPad, dos veces**, con el BeatStep Pro y sin él.
  - [x] Registrado en la git note: las dos pasadas enteras, con lo que devuelve
        cada candidata.
  - [x] **Decidido: `kMIDIPropertyDriverOwner`.** La red declara
        `com.apple.AppleMIDINetworkDriver`; los tres controladores,
        `com.apple.AppleMIDIUSBDriver`. `model` y `manufacturer` vienen vacíos en
        la red y distinguirían hoy, pero eso es una ausencia y no una afirmación.
  - [x] **El volcado entero no sirve en iPadOS**: devuelve solo `uniqueID`. Las
        candidatas con nombre eran el camino.
  - [x] **Hallazgo**: el BeatStep publica dos fuentes y ninguna propiedad las
        distingue. Anotado como limitación.
- [x] Task: `MIDIEndpointInfo` lleva el dato de la decisión (NFR2) `dae873c`
  - [x] Tests (Red): construir la información desde valores conocidos, sin
        CoreMIDI de por medio.
  - [x] Implementación (Green): el campo entra por el enumerador, que es quien
        habla con CoreMIDI. Por defecto `false`, que es la respuesta segura.
- [x] Task: Elegible pero nunca por defecto (FR12, FR13, FR14) `dae873c`
  - [x] Tests (Red): con **solo** la sesión de red, `hasEndpoint` es `false` y el
        estado es `No MIDI input`.
  - [x] Tests (Red): con red + controlador, queda elegido el controlador — en
        cualquiera de los dos órdenes.
  - [x] Tests (Red): añadir un controlador al refrescar lo selecciona; quitarlo
        vuelve al estado vacío.
  - [x] Tests (Red): la red sigue en `available` y `selecting(_:)` la acepta.
  - [x] Tests (Red): una elección manual de la red sobrevive al refresco.
  - [x] Tests (Red): el **destino** no cambia de comportamiento.
  - [x] Implementación (Green): `isAutoSelectable`, separado de `isEligible`.
- [x] Task: Lo recordado manda (FR15) `dae873c`
  - [x] Tests (Red): con una fuente recordada y presente, se elige — **incluida
        la de red**.
  - [x] Tests (Red): con lo recordado ausente, se cae a la regla de FR12 y no a
        la red.
  - [x] Implementación (Green): apoyada en el `sourceName` del `Project`, y solo
        en el descubrimiento inicial.
  - [x] **Hallazgo**: nadie escribía `sourceName` ni `destinationName`. Los
        campos existían desde `persistence_20260907` y se guardaba `null` en cada
        guardado, así que FR15 habría sido letra muerta. Cableado en
        `rememberHardware()`, y **solo para lo elegido a mano**.
- [x] Task: Verificación en iPad — **requiere iPad y controlador** `dae873c`
  - [x] La sesión de red **ya no se autoselecciona**, ni como entrada ni como
        salida. Verificado el 2026-09-09.
  - [x] Con el BeatStep Pro conectado responde a los knobs sin tocar el selector.
  - [x] La elección hecha a mano se recuerda entre arranques.
  - [~] **`No MIDI input` no se pudo ver**: hay un OP-Z permanentemente
        conectado. La regla es correcta y sus tests la fijan; para verlo hay que
        desenchufarlo todo. Anotado en `device-verification.md`.
  - [x] Escrito `device-verification.md` con lo que se probó, los tres fallos que
        encontró y lo que no se pudo ver.
- [~] Task: Cerrar la [issue #43](https://github.com/hernanflores/torax-h0/issues/43)
  - [x] Comentada con el diagnóstico, los valores observados y las dos
        limitaciones que destapó.
  - [ ] **Se cierra cuando el PR entre en `main`**, no antes: el arreglo vive en
        `feat/midi-learn` y cerrar una issue cuyo arreglo no está integrado deja
        el registro mintiendo.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 3: EL MAPEO DEJA DE SER FIJO [checkpoint: 5a711f5]

- [x] Task: `ControlInput` adopta un mapeo (FR2, FR3, NFR1) `9a8de64`
  - [x] Tests (Red): adoptar un mapeo cambia a qué controlador responde cada
        destino, **sin tocar el material**: ni una nota, ni un Cycle, ni el Track
        seleccionado.
  - [x] Tests (Red): adoptar **no publica** material, por la misma razón que
        `adopt(_:)` para el Pattern.
  - [x] Tests (Red): un control que el mapeo nuevo no asigna deja de hacer nada,
        y eso no es un error (FR5).
  - [x] Tests (Red): los bloques de pads y de step buttons y el knob del Cycle
        se mueven con el mapeo, porque salen de él.
  - [x] Implementación (Green): `mapping` deja de ser un `let` privado; la vía
        pública va junto a `adopt(_:)`.
  - [x] Documentar que **no cancela los modificadores**, al revés que
        `adopt(_:)`: aquí el material no cambia, así que descartarlos sería el
        remedio de otro problema.
- [x] Task: Un destino, un control (FR4, FR5) `5a711f5`
  - [x] Tests (Red): asignar un controlador ya ocupado **desasigna** al destino
        anterior, que se queda sin control.
  - [x] Tests (Red): y al revés — reasignar un destino suelta el controlador que
        tenía. Las dos mitades, porque una sola deja el mapeo mintiendo.
  - [x] Tests (Red): un destino sin control no se puede mover y no revienta.
  - [x] Tests (Red): asignar **no mueve los tres bloques**, que no son de
        `assignments`.
  - [x] Tests (Red): las tres familias conviven sin pisarse — `hasFamilyOverlap`
        extiende al mapeo aprendido lo que `declaredNumbers` comprobaba solo del
        preset.
  - [x] Implementación (Green): la regla vive en `ControlMapping`, con tests.
  - [x] `parametersWithoutController`, en el orden del dominio: es lo que la
        Fase 6 necesita para nombrar lo que acaba de quedarse mudo.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 4: APRENDER [checkpoint: a404c5f]

- [x] Task: El estado de aprendizaje (FR6, FR9, FR10, FR11) `a404c5f`
  - [x] Tests (Red): en aprendizaje, un CC **asigna y no mueve el parámetro**.
  - [x] Tests (Red): salir sin asignar deja el mapeo como estaba.
  - [x] Tests (Red): elegir otro destino sin haber aprendido es cambiar de idea,
        no un error: manda el último.
  - [x] Tests (Red): fuera de aprendizaje, todo se comporta como hoy — la suite
        entera de `ControlInput` es el test de no regresión.
  - [x] Implementación (Green): el estado vive en `MIDI`, donde se testea sin
        dedo de por medio, y se corta **al principio** de `receive`.
  - [x] **FR11 no entra aquí**: `ControlInput` no conoce al transporte. Que
        aprender no lo interrumpa es una propiedad de la pantalla, y su sitio es
        la Fase 6.
- [x] Task: Las tres familias, y un giro es una asignación (FR7, FR8) `a404c5f`
  - [x] Tests (Red): un knob se aprende con el primer CC; los siguientes del
        mismo control **no** reabren la pregunta **ni editan** el parámetro que
        acaban de asignar.
  - [x] Tests (Red): el silencio del control recién aprendido **se levanta con
        el control siguiente**, no con un plazo.
  - [x] Tests (Red): un pad se aprende con su nota; un step button y el bloque de
        knobs con su CC, y con este último se mueve el knob del Cycle.
  - [x] Tests (Red): los mensajes que no son del control esperado no asignan
        **y no cancelan**: el destino sigue esperando.
  - [x] Implementación (Green): `LearnTarget`, con los cuatro casos y por qué
        tres de ellos son bloques y no controles sueltos.
  - [x] **Las dos tareas entran en un commit**, y está anotado en su git note: el
        estado no se prueba sin decidir qué familias acepta, y las familias no
        existen sin el estado.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 5: QUE SOBREVIVA [checkpoint: 6108c01]

- [x] Task: El mapeo entra en el `Project` (FR16, NFR3) `6108c01`
  - [x] Tests (Red): round-trip del mapeo por `ProjectRecord`, con el resto de
        ajustes de sesión intactos.
  - [x] Tests (Red): el mapeo de fábrica y uno aprendido se distinguen en disco.
  - [x] Tests (Red): **los trece parámetros** tienen clave estable; una clave
        desconocida se descarta y el resto entra.
  - [x] Implementación (Green): junto a `clockSource`, `destinationName` y
        `sourceName`, que es donde ya vive lo que no es material.
  - [x] **`ControlNumbers`**, porque `Engine` no puede ver CoreMIDI: lo que cruza
        la frontera son enteros, y `MIDI` convierte en las dos direcciones. Es el
        mismo reparto que el destino guardado por su nombre.
  - [x] Lo imposible que venga del disco se descarta en vez de impedir la
        apertura: asignación fuera de rango, destino sin control; bloque fuera de
        rango, el de fábrica.
- [x] Task: Los ficheros existentes abren (FR17) `6108c01`
  - [x] Tests (Red): un fichero escrito **antes** de este track —sin la clave del
        mapeo— abre, y abre con el preset de fábrica.
  - [x] Tests (Red): `schemaVersion` **sigue siendo 1**, y un fichero que declare
        2 se sigue apartando.
  - [x] Implementación (Green): campo opcional en `ProjectRecord`, con el mismo
        criterio que `destinationName` y `sourceName`.
- [x] Task: Enchufar el migrador que se documenta como enchufado `6108c01`
  - [x] Tests (Red): el camino de carga pasa por `ProjectRecord.migrated(_:)` y
        no por `validated()` a secas.
  - [x] Implementación (Green): `ProjectStore.loadHeader`.
  - [x] Hoy no cambia ningún comportamiento, y ese es el momento de hacerlo:
        quien escriba la primera migración de verdad confiará en el comentario
        que ya dice que la llamada está puesta.
- [x] Task: Vía de vuelta al preset de fábrica (FR18) `6108c01`
  - [x] Tests (Red): restaurar el preset deja `ControlMapping.beatStepPro` y **no
        toca el material** — deshacer lo aprendido no deshace lo tocado.
  - [x] Implementación (Green): ninguna. Volver al de fábrica es adoptar el de
        fábrica, que es lo que la Fase 3 ya entregó.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 6: LA PANTALLA [checkpoint: a861bb0]

- [x] Task: Aprender desde la pantalla `midi` (FR6, FR11) `cbe8336`
  - [x] Elegir el destino, entrar en aprendizaje, ver qué se está esperando y
        salir. **Sin modal que bloquee con el transporte corriendo**
        (`product-guidelines.md`).
  - [x] Volver a pulsar el destino que espera cancela: la vía corta de FR9.
  - [x] Enseñar qué destinos han quedado **sin control** tras un aprendizaje
        (FR4, FR5), en el orden del dominio y antes que nada.
  - [x] El botón de volver al preset de fábrica (FR18).
  - [x] Sobre el chrome de `screens-redesign_20260906`, sin inventar un lenguaje
        visual nuevo: el mismo `Card`, el mismo `brutalistControl`.
  - [x] La lógica que merezca un test **no vive aquí**: el listado de mudos y la
        regla de asignación están en `ControlMapping`, y en `App` queda el
        cableado.
  - [x] **Un mensaje que aprendió no es una edición**: el corte en `apply(_:)`
        guarda el mapeo y vuelve, en vez de marcar el Pattern como editado y
        anunciar un giro que no ocurrió.
  - [x] El mapeo se restaura en el `init` desde el `Project` y se guarda con los
        ajustes de sesión.
  - [x] **Comprobado en dispositivo el 2026-09-09**, y encontró tres fallos:
        aprender un bloque convertía los knobs en step buttons `83223a1`, el card
        no enseñaba el número `5193de4`, y no repintaba hasta cambiar de pestaña
        `a861bb0`.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 7: DISPOSITIVO, MEDICIÓN Y CIERRE DE LA v1

- [x] Task: Verificación en iPad — **requiere iPad, BeatStep Pro y un segundo
      controlador** `8612d01`
  - [x] Aprender un knob, un pad y un step button del **segundo** controlador —
        el OP-Z. Las tres familias vistas funcionando con hardware.
  - [x] Girar durante el aprendizaje asigna una vez y no mueve el parámetro.
  - [x] Aprender con la secuencia sonando, sin cortes.
  - [x] Cerrar y abrir la app: el mapeo sigue puesto. `factory preset` devuelve
        el del BeatStep Pro.
  - [x] Repasados los cuarenta y ocho controles del preset restaurado contra la
        tabla de `preset/README.md` (NFR6).
  - [x] `device-verification.md` con lo que se probó, **los tres fallos que la
        verificación encontró** y lo que no se pudo ver.
- [x] Task: La medición final de la v1, según la decisión de la Fase 1 (FR19)
  - [x] **No se mide.** La nota fechada del 2026-09-09 está en `workflow.md`, con
        el coste escrito y la vuelta atrás, y la excepción de la lista del
        2026-08-28 queda tachada y anulada.
- [x] Task: Cobertura y suite completa
  - [x] `Engine` 98,67% · `MIDI` 91,30% · `Persistence` 97,60%. Los tres sobre su
        umbral. `MIDI` medida en un proceso e ignorando `Engine/Sources`, como
        dice `workflow.md`.
- [ ] Task: Pull Request
  - [ ] Rama `feat/midi-learn`, PR contra `main`. Cuerpo corto. **Lo abre el
        usuario** (2026-09-09).
  - [ ] Al mergear, cerrar la
        [issue #43](https://github.com/hernanflores/torax-h0/issues/43), que ya
        está comentada con el diagnóstico.
- [x] Task: Cerrar la v1 en la documentación
  - [x] `product.md`: tachada la promesa pendiente de la nota del 2026-08-31 y
        escrito qué se entregó, con el defecto de la red dentro y la medición
        final que no se hizo.
  - [x] `tracks.md`: cerrada la rebanada 8 y **la v1 entera**. De paso, la tabla
        decía «abierta» de la rebanada 7 desde que cerró el 2026-08-31.
  - [x] Anotado en el `spec.md` lo corregido al implementar, con fecha.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
