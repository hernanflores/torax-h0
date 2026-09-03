# Spec — Mute y Solo por Track

**Tipo:** Feature · **Fecha:** 2026-09-02

## Overview

Los doce Tracks suenan a la vez y no hay forma de callar a uno. Trabajar sobre un
Pattern vivo —oír la caja sola, quitar el bajo para escuchar el arpegio— obliga
hoy a vaciarle el pool a un Track, que **destruye material** para conseguir un
silencio temporal.

Esta rebanada añade el gesto que hace eso un mixer: un par **M / S** debajo de
cada pastilla de Track, y el mismo gesto en el controlador.

Tres decisiones lo definen:

1. **Mute no para el Track: le quita la salida.** La rejilla avanza, el playhead
   gira y los Cycles rotan; lo único que se suprime es la emisión. Al quitarlo,
   el Track reaparece **en fase** con el resto, que es lo que un mixer promete y
   lo que un "stop del Track" rompería.
2. **El estado vive por encima del Pattern.** No es material: es mezcla. Cambiar
   de Pattern no lo mueve, y por eso no entra en el snapshot ni en `Engine`.
3. **Solo es aditivo.** Varios Tracks pueden estar en solo a la vez y suenan
   todos ellos. Aislar bombo + caja es la operación normal; el solo exclusivo la
   prohíbe.

Es la primera capacidad de la app que **no es del material**. Por eso no toca
`Engine`: `Pattern`, `Track` y `Cycle` quedan exactamente como están.

## Functional Requirements

**FR1 — Doce mutes y doce solos, en una sola palabra atómica.** Un tipo nuevo en
`MIDI` —`MuteMask`— guarda los dos juegos de doce bits en **un** `UInt64` (bits
0–11 mute, 16–27 solo) con las mismas primitivas de `Atomics.swift`.

Una sola palabra y no dos porque el hilo del scheduler decide con las dos a la
vez: leerlas por separado permitiría ver el mute de antes y el solo de después
—un instante en el que todo calla, o nada—. Un `load` acquire da las dos
consistentes, sin asignar, sin lock y sin `await`.

**FR2 — La regla de audibilidad, en un solo sitio.** Un Track suena si

```
audible(i) = !mute(i) && (soloMask == 0 || solo(i))
```

El mute manda sobre el solo: un Track soleado **y** muteado calla. Es lo que hace
un mixer y lo que evita el estado imposible de "está en solo pero no suena y no
se ve por qué".

**FR3 — El gate está en el camino de emisión, no en el de la rejilla.** El
`PatternScheduler` sigue avanzando los doce Tracks; lo que se salta es la llamada
al `NoteEmitter`. Es el mismo criterio que ya rige para un Track sin material
(NFR3 de `multi-track`): *la rejilla avanza para no perder la fase, y no se
emite*.

**FR4 — Al dejar de ser audible, el Track se apaga.** Cuando un gesto vuelve
inaudible a un Track —mutearlo, o soltar un solo que lo excluye— se apaga lo que
tuviera sonando por su canal: `CC 123` (All Notes Off) más el barrido de alturas
de sus dieciséis Cycles, exactamente el procedimiento que ya usa
`Transport.stop()`. Se factoriza ese barrido a un método que acepte qué Tracks
apagar; `stop()` pasa a ser el caso "los doce".

Sin esto, un Sustain al 200% sobre una Division larga deja la nota colgada en el
sinte durante segundos después de pulsar M, que es el modo de fallo caro del
cambio.

**FR5 — El par M / S, debajo de cada pastilla.** En `TrackSelectorView`, bajo la
fila de los doce números, una segunda fila con dos botones por Track alineados a
su pastilla.

Dos botones y no uno que cicle: los dos estados son **independientes** —un Track
puede estar muteado y soleado— y un botón de tres posiciones no puede
representarlos, además de obligar a pasar por mute para llegar a solo.

Los estados se leen sin texto, con el vocabulario de color que ya existe:
`M` activo y `S` activo van rellenos, cada uno con su color; en reposo, el borde
apagado de los controles vacíos. El Track que calla **por el solo de otro** —ni
muteado ni soleado, pero inaudible— se distingue del que suena: su pastilla se
atenúa. Sin eso, once Tracks apagados no tendrían ninguna marca y el silencio
parecería un fallo.

**FR6 — El anillo del Track inaudible se atenúa, y su playhead sigue.** Es FR3
puesto donde se ve: corre y no suena. Un anillo que desapareciera diría que el
Track se paró, que es justo lo que no ocurre.

**FR7 — Mantener step 16 + step N mutea el Track N.** Con el step button 15, lo
solea. Los dos están libres desde que el Pattern bajó a doce (FR3 de
`ui-declutter`), y el controlador ya envía la soltada con valor 0, así que el
"mantener" es estado de mensajes y **no lleva temporizador**: nada se difiere ni
se adivina, y el gesto entero se prueba con mensajes.

- Step N (N ≤ 12) sin modificador: selecciona el Track, como hoy.
- Step N con el modificador de mute mantenido: alterna su mute y **no** cambia la
  selección.
- Step 15 o 16 pulsados solos: no hacen nada al soltarse. No se convierten en un
  toggle "al vuelo" — un modificador que además actúa es un modificador que se
  dispara sin querer.
- Los dos modificadores a la vez: manda el de mute, para que el gesto tenga
  siempre un resultado definido.

**FR8 — Los modificadores se sueltan solos.** El estado de "mantenido" se limpia
al reconectar la entrada: un cable desenchufado con el botón hundido dejaría el
modificador pegado para siempre, y desde la app no hay forma de soltarlo.

**FR9 — La app publica el estado, la pantalla lo refleja.** `TransportModel`
mantiene el par de vectores de doce, los espeja al `MuteMask` y los publica para
la vista. El gesto táctil y el del controlador entran por el mismo sitio, con el
mismo criterio que ya rige para la selección de Track: si no, la pantalla mentiría
sobre lo que el hardware acaba de hacer.

**FR10 — Stop no lo limpia.** Parar y volver a arrancar conserva mutes y solos:
es mezcla, no transporte. Tampoco lo limpia cambiar de Track, de Cycle ni de
Pattern.

**FR11 — La desviación queda escrita** (Task Workflow §8), antes de tocar código:

- La Pre Spec **no tiene** mute ni solo. Se añade nota fechada: qué son, que
  viven fuera del material y por qué.
- `design_handoff/README.md` pone el par M/S en la pantalla `5 · Tracks`, que no
  existe. Nota fechada: el par vive en la pantalla Track, donde ya está la fila
  de los doce; cuando la pantalla 5 exista, enseñará **este mismo** estado.

## Non-Functional Requirements

- **NFR1 — El camino de tiempo real no se ensancha.** El gate es un `load`
  atómico por ventana y una comparación de bits por Track: sin asignaciones, sin
  locks, sin `await`. El apagado de FR4 ocurre **fuera** del hilo del scheduler,
  como el de `stop()`.
- **NFR2 — `Engine` no se toca.** `Pattern`, `Track` y `Cycle` quedan idénticos y
  `_isPOD` sigue siendo cierto. Si esta feature obligara a tocar `Engine`, es que
  se estaría metiendo mezcla en el material.
- **NFR3 — Cobertura:** `Engine` ≥90%, `MIDI` ≥80%. `App` no se mide.
- **NFR4 — Vocabulario:** *mute*, *solo* y *audible*, sin sinónimos nuevos.
- **NFR5 — Estilo:** los tres ficheros de `App` que poseen color, tipografía y
  borde siguen siendo los únicos. El par M/S no inventa estilo propio.
- **NFR6 — Sin medición de jitter**, suspendida el 2026-09-02. El cambio no mueve
  ningún instante: decide *si* se emite, no *cuándo*.

## Acceptance Criteria

1. Con el transporte corriendo, pulsar `M` en un Track lo calla **antes de su
   siguiente pulso** y lo que estuviera sonando por su canal se apaga; el resto
   sigue sin alterarse.
2. Quitar el mute lo devuelve **en fase**: entra en la posición del anillo que le
   tocaba, no desde el principio.
3. Pulsar `S` en un Track deja sonando solo a ese; pulsar `S` en un segundo deja
   sonando a los dos. Soltar los dos devuelve los doce.
4. Un Track soleado **y** muteado calla.
5. Mantener el step button 16 y pulsar el 3 mutea el Track 3 **sin** cambiar de
   Track seleccionado; el par M/S de la pantalla lo refleja al instante.
6. Mantener el 15 y pulsar el 3 lo solea, con el mismo criterio.
7. El anillo de un Track inaudible se ve atenuado y su playhead **sigue
   girando**.
8. Parar y arrancar el transporte conserva mutes y solos.
9. `Engine` no tiene un solo cambio; `_isPOD(Pattern.self)` sigue pasando.
10. Cobertura de `MIDI` ≥80% con la lógica nueva cubierta: máscara, regla de
    audibilidad, gate y modificadores.

## Limitaciones conocidas

Se documentan porque son consecuencia del diseño elegido, no descuidos:

- **Hasta una ventana de retraso.** Un note-on ya entregado a CoreMIDI con
  timestamp futuro suena aunque el mute llegue después: el look-ahead son 20 ms,
  por debajo de lo perceptible en este gesto. Cancelarlo exigiría poder retirar
  eventos ya sellados, que es justo lo que la arquitectura de look-ahead cambia
  por su precisión.
- **Dos Tracks en el mismo canal se apagan juntos.** El `CC 123` de FR4 es por
  canal, así que mutear uno corta las notas del otro. El otro vuelve en su
  siguiente pulso —no queda mudo—, y la pantalla MIDI existe precisamente para
  ver un choque de canales antes de que ocurra.
- **El estado no persiste** entre arranques. No hay persistencia de proyecto
  todavía; cuando la haya, decidirá si la mezcla se guarda con él.

> **Repaso al cerrar, 2026-09-02.** Las tres siguen siendo exactamente las tres:
> la implementación no descubrió ninguna nueva. Lo que sí apareció, y no es una
> limitación sino una decisión que conviene tener escrita:
>
> - **La máscara no lleva compare-and-swap**, porque hoy solo escribe el actor
>   principal —el gesto táctil nace ahí y el del controlador salta al principal
>   antes de aplicarse—. Si algún día escribiera otro hilo, deja de ser correcto.
>   La condición está escrita en `MuteMask`, no solo sabida.
> - **`Transport.mutes` es interna a propósito.** Se hizo pública en la Fase 3 y
>   se cerró en la Fase 4 al ver que dejaba dos caminos para cambiar la mezcla, y
>   uno de ellos se saltaba el apagado — que es justo la nota colgada que FR4
>   existe para evitar. Fuera se lee por `mix` y se escribe por los dos toggles.

## Out of Scope

- Persistencia del estado de mute/solo.
- La pantalla `5 · Tracks` y su vista de conjunto con M/S por fila.
- Mute o solo de Patterns y de Banks.
- Volumen, fade o cualquier control continuo: esto es binario.
- MIDI Learn del gesto — los step buttons 15 y 16 son fijos, como el resto del
  preset, hasta que llegue el track de MIDI Learn.
- Medición de jitter (NFR6).
