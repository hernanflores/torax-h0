# Spec — Feedback visual en el controlador

**Tipo:** Feature · **Fecha:** 2026-09-04

## Overview

El controlador es el instrumento y el iPad la pantalla de estado, pero la
comunicación va **en un solo sentido**: la app lee knobs, pads y step buttons, y
no le devuelve nada. Tocando, eso significa mirar el iPad para saber qué grado
está sonando o qué Track estás editando, cuando las dos cosas tienen un sitio
natural debajo de los dedos.

Este track enciende el controlador: los **pads siguen la nota** del Track
seleccionado y los **step buttons dicen qué Track se edita y cuál está muteado o
soleado**.

Tres decisiones lo definen:

1. **Es la primera vez que la app escribe en un dispositivo ajeno.** Hasta ahora
   la salida iba al sintetizador —el destino que el usuario eligió para que
   sonara—; el controlador era solo una fuente. Por eso hay un interruptor:
   escribir en el hardware de alguien es un efecto que tiene que poder
   revertirse.
2. **Un significado por luz.** El pad encendido quiere decir «esta nota está
   sonando», y nada más: ni el pool, ni la velocity en color, ni el patrón de un
   Track muteado. Lo que no se puede representar honestamente se queda apagado.
3. **Qué sabe hacer el hardware es una pregunta abierta, y va primero.** La
   rebanada 7 enseñó a no dar por sabido el controlador. La Fase 1 lo averigua
   con una pantalla de pruebas desechable, y **si resulta que no ilumina por
   MIDI, el track se para ahí** con el hallazgo escrito.

## Functional Requirements

**FR1 — Los pads siguen la nota del Track seleccionado.** Se enciende con el
note-on y se apaga con el note-off, así que **Sustain se ve**: un gate largo deja
el pad encendido lo que dura la nota. Sin temporizador propio — reutiliza el par
de eventos que el scheduler ya sella.

**FR2 — Solo el Track seleccionado.** Con doce sonando a la vez, una luz de otro
Track no se sabe de quién es; y los pads ya editan el pool de ese mismo Track,
así que el pad encendido es el pad que tocarías. Al cambiar de Track seleccionado
**se barren los pads** y empieza el nuevo: sin barrido, el note-off del Track
viejo llegaría a un pad que ya representa otra cosa.

**FR3 — Una nota fuera del registro de los pads no enciende nada.** Los catorce
grados cubren dos octavas; lo que caiga fuera no tiene pad que lo represente, y
encender otro mentiría. Es el mismo criterio con el que los pads 6, 7, 14 y 15 no
hacen nada en Pentatonic.

**FR4 — Un Track muteado no enciende sus pads.** El LED sigue a la nota y con
mute no hay nota. Sale gratis: el gate del mute está antes del emisor.

**FR5 — Las notas encendidas se cuentan por pad.** Con Sustain por encima del
100% una nota sigue sonando cuando el mismo pad vuelve a dispararse; el pad se
apaga con el **último** note-off, no con el primero. Sin esto, el pad se queda
negro mientras aún suena — justo con Sustain alto, que es cuando más se mira.

**FR6 — Las luces se sellan junto a la nota.** Van por el hilo del scheduler, con
el **mismo timestamp** que su note-on y su note-off. Es la única forma de que la
luz caiga con el sonido; el precio son dos mensajes más por nota en el camino de
tiempo real (ver NFR2 y la limitación 1).

**FR7 — Los step buttons 1–12 dicen qué Track se edita y cómo está en la
mezcla.** El reparto exacto —brillo, parpadeo, color— **lo decide la Fase 1** con
el repertorio real del hardware delante. Si el LED solo puede estar encendido o
apagado, **manda el Track seleccionado**: es lo que dice dónde caen los knobs, y
equivocarse ahí hace que edites el Track que no era. Mute y solo ya se ven en
pantalla y se oyen.

**FR8 — Los step buttons 13–16 se quedan apagados.** No hay Track detrás, y
encender el 15 o el 16 sugeriría que su modificador está activo.

**FR9 — Se repinta al cambiar, más una pasada completa al conectar.** Un mensaje
por gesto, y el estado entero al elegir fuente para que el controlador no arranque
mintiendo. Sin tráfico periódico.

**FR10 — Con el transporte parado se ve la selección y la mezcla; los pads,
apagados.** Lo que no depende del reloj se sigue viendo, así que el hardware
refleja el estado también mientras se prepara.

**FR11 — El destino se deriva de la fuente elegida.** El controlador ya se elige
como fuente de entrada; el feedback va al destino del **mismo dispositivo**, sin
lista nueva. Si esa fuente no tiene destino hermano —una sesión de red, por
ejemplo— **no se ilumina y la pantalla MIDI lo dice**, con el criterio de `No MIDI
device`: es un estado, no un error.

**FR12 — Las luces salen por un canal declarado en `ControlMapping`.** El
controlador escucha en el canal que tenga configurado, que no tiene por qué ser el
de ningún Track. Vive junto a los bloques de pads, knobs y step buttons: un solo
sitio, y si el dispositivo lo desmiente se cambia ahí.

**FR13 — Un interruptor en `3 · MIDI`.** Apagarlo **barre el controlador y lo deja
limpio**: dejar de escribir en un dispositivo ajeno incluye no dejarlo pintado.

**FR14 — Se apaga al parar el transporte.** Los pads se barren con Stop; la
selección y la mezcla siguen mostrándose. **No se barre al pasar a segundo plano
ni al cambiar de fuente**, decidido a sabiendas de que el controlador puede quedar
con luces huérfanas.

**FR15 — El preset se documenta.** `preset/README.md` y
`torax-h0.beatstep-pro.json` describen hoy solo la entrada; pasan a decir qué
significa cada luz y qué configuración del BeatStep exige el feedback.

## Non-Functional Requirements

**NFR1 — La Fase 1 puede cancelar el track.** Si el hardware no ilumina por MIDI
in, no hay feature que entregar: se cierra con el hallazgo escrito, como se hizo
con `scheduler-lifecycle`. La pantalla de pruebas es desechable y se borra al
cerrar la fase.

**NFR2 — Sin asignaciones, locks ni `await` en el camino de emisión.** Las luces
se sellan donde se sellan las notas. La cuenta por pad es almacenamiento inline de
dieciséis huecos, no una colección.

**NFR3 — Cobertura:** `Engine` ≥90%, `MIDI` ≥80%. La decisión de qué encender es
lógica pura y va en `Engine`; el envío, en `MIDI`.

**NFR4 — Sin medición de jitter**, suspendida el 2026-09-02 y confirmado para
este track el 2026-09-04. Ver la limitación 1.

**NFR5 — Verificado en dispositivo**, con el BeatStep Pro conectado.

**NFR6 — No generaliza a otro hardware.** El feedback se declara en
`ControlMapping` como el resto del preset, así que otro controlador sería cambiar
datos; verificar que funciona con otro es MIDI Learn, rebanada 8 de la v1.

## Acceptance Criteria

1. Tocando, los pads del Track seleccionado se encienden con la nota y se apagan
   con ella; con Sustain alto se ve la duración.
2. Una nota fuera del registro de los pads no enciende ninguno, y no se enciende
   ninguno «de más».
3. Con Sustain por encima del 100%, un pad redisparado no se apaga hasta que
   termina la última de sus notas.
4. Cambiar de Track seleccionado apaga los pads del anterior y empieza a mostrar
   el nuevo.
5. Mutear el Track seleccionado apaga sus pads; quitar el mute los devuelve.
6. El step button del Track en edición se distingue de los otros once, y el estado
   de mute/solo se lee según lo que la Fase 1 haya decidido.
7. Los step buttons 13–16 están siempre apagados.
8. Al elegir la fuente, el controlador se pinta entero sin tocar nada más.
9. Parar el transporte apaga los pads y deja la selección y la mezcla encendidas.
10. El interruptor de `3 · MIDI` apaga el feedback y deja el controlador limpio;
    volver a encenderlo lo repinta.
11. Con una fuente sin destino hermano, no se ilumina nada y la pantalla lo dice.

## Limitaciones conocidas

1. **Se duplican los mensajes por nota en el camino de tiempo real, y no se
   mide.** Cada nota pasa a llevar su par de mensajes de luz, sellados en el hilo
   del scheduler. La medición sigue suspendida (NFR4), **y la referencia vigente
   viene de empeorar sin causa identificada** —máx 0,525 ms contra 0,158,
   reproducido en dos pasadas del track `external-clock_20260903`—. Si el timing
   se degrada, esta es la primera carga que hay que mirar, y no habrá número con
   el que compararla: se descubrirá tocando.
2. **El reparto de los step buttons no se puede escribir hasta la Fase 1.** La
   spec fija la prioridad si el LED es binario y deja el resto abierto a
   propósito.
3. **El controlador puede quedar con luces huérfanas** al pasar la app a segundo
   plano o al cambiar de fuente (FR14).
4. **Sin verificar con otro hardware** (NFR6).
5. **La selección de Cycle no se ilumina.** Los step buttons ya cargan Track y
   mezcla; y el Cycle en edición tiene su propio defecto abierto —no se puede
   elegir en pantalla—, que este track no toca.

## Out of Scope

- MIDI Learn y la generalización a otro controlador (rebanada 8 de la v1).
- El playhead recorriendo los step buttons.
- Color por velocity, y cualquier segundo significado sobre la misma luz.
- Iluminar el pool tonal con el transporte parado.
- Arreglar el defecto del Cycle en edición, que es un track aparte.
