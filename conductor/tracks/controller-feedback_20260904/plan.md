# Plan — Feedback visual en el controlador

Sigue el `workflow.md`: tests antes de implementación, un commit por tarea, git
note por commit y checkpoint verificado al cerrar cada fase.

**La Fase 1 puede cancelar el track, y por eso va primero y sola.** Todo lo demás
depende de que el BeatStep encienda algo por MIDI in, y eso hoy no se sabe.
Averiguarlo cuesta una pantalla desechable y una tarde; descubrirlo después de
construir el camino de salida cuesta el track entero. Es el mismo criterio con el
que la Fase 1 de `cycles` midió el snapshot antes de diseñar encima.

**Después, de dentro afuera.** La decisión de qué encender es pura y va en
`Engine`, donde se testea sin hardware; luego la salida hacia el controlador;
luego los pads, que son el camino de tiempo real y el riesgo; luego los step
buttons, que son estado y no eventos; y la pantalla al final.

**Ninguna fase mide jitter** (NFR4). La limitación 1 de la spec dice lo que eso
cuesta aquí.

## FASE 1: QUÉ SABE HACER EL HARDWARE

- [ ] Task: Pantalla de pruebas desechable
  - [ ] Una vista temporal tras un flag de lanzamiento —`--led-probe`—, que mande
        a la fuente elegida: note-on por cada nota del bloque de pads, con
        velocities distintas; CC del bloque de step buttons con valores 0, 1, 64 y
        127; y los mismos por varios canales.
  - [ ] **No lleva tests**: es instrumentación que se borra al cerrar la fase,
        como el panel del arnés antes de que FR12 lo quitara.
  - [ ] Que se pueda mandar **un** mensaje a la vez y verlo: descubrir esto es
        mirar el controlador, no leer un log.
- [ ] Task: Averiguar y escribir el repertorio real (NFR1)
  - [ ] ¿Se encienden los pads con note-on? ¿Con qué canal? ¿Importa la velocity
        —color, brillo— o es binario?
  - [ ] ¿Se encienden los step buttons con CC? ¿Qué valores? ¿Hay más de dos
        estados?
  - [ ] ¿Hay que poner el BeatStep en algún modo concreto para que escuche?
  - [ ] Escribir lo aprendido en `device-verification.md` del track, **incluido lo
        que no funcione**: es la mitad del valor de esta fase.
  - [ ] **Punto de cancelación.** Si no ilumina nada por MIDI in, se cierra el
        track aquí con el hallazgo escrito y se registra en `tracks.md`. No se
        busca SysEx ni protocolo propietario: eso es otra investigación y otro
        track.
- [ ] Task: Fijar el reparto de los step buttons (FR7)
  - [ ] Con el repertorio delante, decidir cómo conviven selección y mute/solo, y
        escribirlo en el `spec.md` como enmienda fechada.
  - [ ] Si el LED es binario, manda el Track seleccionado — ya está decidido y no
        hay que volver a discutirlo.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 2: QUÉ ENCENDER, COMO FUNCIÓN PURA

- [ ] Task: De altura a índice de pad (FR3)
  - [ ] Tests (Red): una altura del registro devuelve el pad de su grado; una
        fuera devuelve `nil`; con Pentatonic, los grados que no existen no tienen
        pad.
  - [ ] Tests (Red): la correspondencia es la inversa de la que ya usa
        `PadSurface` al pulsar — el pad que enciende una nota es el que la
        produciría.
  - [ ] Implementación (Green): función pura en `Engine`, junto a `PadSurface`.
  - [ ] Cobertura `Engine` ≥90%.
- [ ] Task: La cuenta de notas por pad (FR5)
  - [ ] Tests (Red): dos note-on sobre el mismo pad y un note-off lo dejan
        encendido; el segundo lo apaga; un note-off sin note-on no baja de cero.
  - [ ] Tests (Red): el barrido lo pone todo a cero de una vez (FR2, FR14).
  - [ ] Implementación (Green): dieciséis contadores en almacenamiento inline, no
        una colección (NFR2). Tipo trivial, con `_isPOD` vigilándolo.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 3: LA SALIDA HACIA EL CONTROLADOR

- [ ] Task: Encontrar el destino hermano de una fuente (FR11)
  - [ ] Tests (Red): la lógica de emparejar fuente y destino se testea sobre
        valores, sin CoreMIDI —la enumeración real ya vive en `CoreMIDIInput` y
        `CoreMIDIOutput`—.
  - [ ] Tests (Red): una fuente sin destino hermano da `nil`, que es un estado y
        no un error.
  - [ ] Implementación (Green): por entidad de CoreMIDI,
        `MIDIEndpointGetEntity` y `MIDIEntityGetDestination`.
- [ ] Task: El canal de las luces, en `ControlMapping` (FR12)
  - [ ] Tests (Red): el canal declarado es el que sale en los mensajes; cambiarlo
        mueve todas las luces a la vez y no toca nada del dominio.
  - [ ] Implementación (Green): junto a los bloques de pads, knobs y step buttons,
        con el número que dijo la Fase 1.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 4: LOS PADS SIGUEN LA NOTA

- [ ] Task: Encender y apagar con el evento (FR1, FR6)
  - [ ] Tests (Red): un evento del Track seleccionado produce mensaje de luz **con
        el mismo timestamp** que su note-on, y su apagado con el del note-off.
  - [ ] Tests (Red): un evento de otro Track no produce ninguna luz (FR2).
  - [ ] Tests (Red): una altura fuera del registro no produce ninguna luz (FR3).
  - [ ] Tests (Red): un Track muteado no produce luces, sin ramas nuevas — el gate
        ya está antes (FR4).
  - [ ] Implementación (Green): en el cierre de emisión, junto al `NoteEmitter`.
  - [ ] Verificar la regla de tiempo real: sin asignaciones, sin locks, sin
        `await`, sin logging.
- [ ] Task: El barrido al cambiar de Track (FR2)
  - [ ] Tests (Red): cambiar de Track seleccionado apaga los dieciséis pads y deja
        la cuenta a cero.
  - [ ] Tests (Red): con el transporte parado no se manda nada — no hay nada
        encendido.
  - [ ] Implementación (Green): reutiliza el barrido de la Fase 2, sin duplicarlo.
- [ ] Task: Apagar al parar el transporte (FR14)
  - [ ] Tests (Red): `stop()` apaga los pads y **deja** la selección y la mezcla.
  - [ ] Implementación (Green): junto al barrido de notas que `stop()` ya hace.
  - [ ] Cobertura `MIDI` ≥80%.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 5: LOS STEP BUTTONS DICEN EL ESTADO

- [ ] Task: Selección y mezcla, según lo decidido en la Fase 1 (FR7, FR8)
  - [ ] Tests (Red): el Track en edición se distingue de los otros once; los 13–16
        quedan apagados siempre.
  - [ ] Tests (Red): mutear y solear cambian lo que se manda, con el reparto que
        fijó la Fase 1.
  - [ ] Implementación (Green): la decisión como función pura sobre selección y
        `MuteState`; el envío, aparte.
- [ ] Task: Repintar al cambiar y al conectar (FR9, FR10)
  - [ ] Tests (Red): un gesto manda **un** mensaje, no la pasada entera.
  - [ ] Tests (Red): elegir fuente manda el estado completo.
  - [ ] Tests (Red): con el transporte parado se mandan selección y mezcla, y
        ningún pad.
  - [ ] Implementación (Green): fuera del hilo del scheduler — esto es estado, no
        eventos.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 6: EL INTERRUPTOR Y LO QUE SE DOCUMENTA

- [ ] Task: El interruptor de feedback (FR13)
  - [ ] Tests (Red): apagado no se manda nada; encenderlo repinta el estado
        completo; apagarlo **barre el controlador**.
  - [ ] Implementación (Green): en `3 · MIDI`, junto al reloj. El estado vive donde
        lo lee quien manda las luces, no en la vista.
  - [ ] Sin destino hermano, el interruptor se ve deshabilitado y la pantalla dice
        por qué (FR11).
- [ ] Task: Documentar el preset (FR15)
  - [ ] `preset/README.md`: qué significa cada luz, el canal, y la configuración
        del BeatStep que el feedback exige.
  - [ ] `torax-h0.beatstep-pro.json`: los mismos números, legibles por máquina.
  - [ ] Comprobar que `ControlMapping` y el README siguen diciendo lo mismo — si
        uno de los dos cambia, el otro está mal.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 7: DISPOSITIVO Y CIERRE

- [ ] Task: Verificar los once criterios en iPad (NFR5)
  - [ ] Recorrer los criterios 1 a 11 y anotar cada resultado en
        `device-verification.md`.
  - [ ] Los tres que solo se ven tocando: **Sustain alto** (criterio 3), **cambio
        de Track con notas vivas** (4) y **mute del Track seleccionado** (5).
  - [ ] Borrar la pantalla de pruebas de la Fase 1.
- [ ] Task: Cerrar el track
  - [ ] Suite completa de `Engine` y `MIDI`, con la partición de CI para `MIDI`;
        cobertura contra los umbrales.
  - [ ] Build de la app para iPadOS.
  - [ ] Pull Request contra `main`, con los checks en verde y el cuerpo corto que
        exige `workflow.md`.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
