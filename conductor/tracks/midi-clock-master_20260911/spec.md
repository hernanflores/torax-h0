# Spec — Torax H-0 como maestro de MIDI clock

## Overview

`product.md` dice hoy, en la nota del 2026-09-03: «**La app no emite clock.** La
sincronía va en un solo sentido: nada externo puede seguir a Torax H-0. Ser
maestro es otra decisión y no está tomada». Este track la toma. Play y Stop pasan
a arrastrar a los aparatos conectados, y el tempo de Torax pasa a ser el tempo de
la cadena.

**El pulso se genera, no se reenvía.** Los 24 pulsos por negra salen del hilo del
scheduler, sellados hacia el futuro con `MIDISendEventList`, exactamente como las
notas: misma ventana de look-ahead, mismo `TempoMap`, mismo origen de rejilla. Es
lo que hace que el tick caiga donde cae la nota, y es la misma razón por la que
`tech-stack.md` descartó por escrito el reenvío inmediato para la entrada — un
pulso reenviado al vuelo devuelve el jitter al planificador del sistema
operativo, que es justo lo que la arquitectura existe para evitar.

**Con reloj `External` la app retransmite regenerando.** El `TempoMap` ya sigue
al maestro, así que los esclavos siguen el mismo tempo estimado que la app: un
solo generador de pulso para los dos modos, y no dos caminos que habría que
mantener iguales.

**No añade interfaz, ni modelo, ni fichero.** Sin interruptor, sin destino de
clock propio, sin clave nueva en el esquema. La app emite siempre que el
transporte suena, al mismo destino único que ya eligen las notas en la pantalla
`midi`.

## Dónde encaja en lo que ya existe

Las tres piezas que hacen falta están construidas y probadas:

- **`MIDIMessage` ya tiene los tres mensajes.** `timingClock`, `start` y `stop`
  entraron con `external-clock_20260903` para poder *recibirlos*, con su
  empaquetado a Universal MIDI Packet de tipo `0x1` verificado en la ida y
  vuelta. Lo que cambia es que ahora se emiten.
- **`SchedulerThread` ya sella hacia el futuro.** El bucle convierte instantes de
  rejilla en ticks de host con `tempoMap.wallNanoseconds(forGridNanoseconds:)` y
  se los entrega al emisor. El pulso usa el mismo camino.
- **`LookAheadScheduler` ya resuelve el problema del borde de ventana** para los
  Steps: marca de agua por índice, para que ninguno se pierda ni se repita. El
  generador de pulso repite ese patrón con el índice de tick.

Lo único que no existe es el generador, y es aritmética de enteros sobre un
índice.

## Functional Requirements

**FR1 — La app emite clock mientras suena.** Con el transporte corriendo se
emite `timingClock` (`0xF8`) a 24 pulsos por negra, al destino de salida
seleccionado.

**FR2 — El pulso comparte origen y mapa de tempo con las notas.** El instante del
tick *n* es `origen de rejilla + n × (negra / 24)` en tiempo de rejilla,
convertido a tiempo de reloj con el mismo `TempoMap` que sella las notas, y
entregado con timestamp futuro dentro de la ventana de look-ahead. Con Delay
negativo, el presupuesto de adelanto desplaza el origen igual que a los Steps.

**FR3 — Ningún tick se pierde ni se repite.** El generador lleva marca de agua
por índice, de modo que dos ventanas consecutivas entregan cada tick exactamente
una vez.

**FR4 — Arrancar emite `start`.** `start` (`0xFA`) se sella en el origen de
rejilla y sale antes que el primer tick.

**FR5 — Parar emite `stop`.** `stop` (`0xFC`) se sella en el mismo instante que
el barrido de apagado (`silenceHostTime`, una ventana por delante), para que el
esclavo pare cuando paran las notas y no antes de lo ya programado.

**FR6 — Parado no se emite nada.** No hay clock en vacío: sin transporte no hay
un solo mensaje en el cable.

**FR7 — Con `External`, el pulso emitido sigue al maestro.** El tick se convierte
con el `TempoMap` ya rebasado por `ClockHandoff`, así que un maestro más lento
estira el pulso de salida en la misma proporción en que estira los Steps.

**FR8 — Con `External`, `start` y `stop` salen cuando el transporte arranca y
para de verdad**, disparado por el maestro, y no al recibir los mensajes
entrantes. La app dice lo que hace, no lo que le dicen.

**FR9 — Sin destino seleccionado no se emite nada y nada falla.** Es el mismo
estado que hoy tienen las notas: un MIDI desconectado es un estado esperado, no
un error.

**FR10 — Un cambio de tempo cambia la separación, no la fase.** Girar el tempo
interno o cambiar de Bank con el transporte corriendo cambia la separación de los
ticks siguientes sin reiniciar el índice ni saltar de fase.

## Non-Functional Requirements

**NFR1 — El hilo del scheduler sigue limpio.** El generador es un valor trivial:
sin asignaciones, sin locks, sin `await`, sin logging. A 174 BPM son unos 1,4
ticks por ventana de 20 ms.

**NFR2 — `Engine` no se toca.** Veinticuatro pulsos por negra es una constante
del protocolo MIDI, no del motor generativo. El generador vive en `MIDI`.

**NFR3 — Cobertura de `MIDI` ≥80%**, medida en un solo proceso con el
`.profdata` fusionado a mano y filtrando `Engine/Sources`, según `workflow.md`.

**NFR4 — Sin medición de jitter**, por la suspensión del 2026-09-02. Los ticks no
desplazan ningún instante de nota: añaden eventos acotados al camino de emisión,
que es literalmente el caso que la nota del 2026-08-28 excluye. Se sustituye por
una escucha larga en dispositivo — un esclavo desincronizado se oye.

**NFR5 — Vocabulario en inglés y sin sinónimos.** `start`, `stop` y
`timingClock` ya están declarados en `MIDIMessage`; no se introduce ninguna
palabra nueva para el mismo concepto.

## Acceptance Criteria

1. Play en la app arranca una caja de ritmos externa puesta en sync externo, y
   Stop la para.
2. El tempo del esclavo coincide con el de la app, y girar el tempo lo sigue sin
   salto ni deriva audible en una escucha larga.
3. Con `External` y el BeatStep Pro mandando, app y esclavo comparten pulso: los
   tres aparatos suenan alineados.
4. Con el transporte parado no llega ningún mensaje al esclavo, comprobado con un
   monitor MIDI.
5. Sin destino seleccionado, la app se comporta exactamente como hoy.
6. Cambiar de Bank con el transporte corriendo lleva su tempo al esclavo en el
   compás, sin cortar el pulso.
7. Con Repeats 8 y doce Tracks sonando, el pulso no se arrastra ni se atraganta.
8. La suite de `MIDI` pasa y la cobertura queda por encima del umbral.

## Out of Scope

- **`Continue` (`0xFB`) y Song Position Pointer.** Un esclavo siempre arranca
  desde cero, que es coherente con que la app arranque siempre en el paso 0.
- **Program Change al cambiar de Pattern**, que sigue en «Fuera de v1» de
  `product.md`.
- **Interruptor `send clock`** y **destino de clock propio**: se emite siempre,
  al destino único.
- **Filtrar el endpoint emparejado con la fuente.** Si el destino es el mismo
  aparato que manda el clock, recibe su propio pulso de vuelta. Emparejar
  endpoints de entrada y salida es heurística, y esa clase de heurística ya costó
  el defecto `network-session-source`.
- MIDI Time Code, Ableton Link y clock por Bluetooth.

## Limitaciones conocidas que introduce

1. **Con `External`, el pulso retransmitido va por detrás del maestro.** Un
   cambio brusco de tempo tarda hasta una ventana de look-ahead más una negra en
   llegar a los esclavos, porque se regenera desde la estimación. Es el mismo
   coste que `tech-stack.md` ya acepta por escrito para la entrada, trasladado a
   la salida.
2. **Clock y notas comparten destino.** No se puede mandar pulso a la caja de
   ritmos y notas a otro sintetizador.
3. **Sin Song Position, un esclavo que arranque a mitad no puede alinearse.**
