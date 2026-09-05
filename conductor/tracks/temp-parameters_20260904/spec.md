# Spec — Temp: parámetros temporales

## Overview

Temp superpone cambios **momentáneos** sobre el Track seleccionado mientras se
mantiene **[step 13]** (índice 12 del bloque de step buttons, CC 114 con el
bloque por defecto). Con el botón hundido, girar cualquiera de los nueve knobs
de parámetro altera lo que suena sin escribir en el Pattern; al soltar, los
valores anteriores vuelven.

Es la herramienta de interpretación que le faltaba al instrumento: fills,
builds, breakdowns y balance en vivo sin gastar un Cycle ni un Pattern, y sin
destruir el material que costó construir.

El gesto encaja en un sitio que ya está libre y en un patrón que ya existe: los
step buttons 15 y 16 son modificadores de mute y solo desde `mute-solo_20260902`,
y el Pattern bajó a doce Tracks en `ui-declutter_20260902`, así que del 13 al 16
no hay Track detrás. Temp es el tercer modificador, con la misma mecánica de
mensajes: 127 al pulsar, 0 al soltar, sin temporizadores.

## Functional Requirements

**FR1 — El gesto.** Mantener [step 13] activa Temp sobre el **Track
seleccionado**. Soltarlo lo desactiva y restaura. El índice es fijo en
`ControlInput`, junto a `muteModifierIndex` y `soloModifierIndex`; reasignarlo es
MIDI Learn, otra rebanada.

**FR2 — El overlay.** Con Temp activo, un giro de knob se traduce al
`TrackParameter` mapeado y produce un **valor absoluto**, calculado desde el
valor del **Cycle en edición** al iniciarse el hold. Ese valor se escribe **igual
en todos los Cycles activos** del Track. Girar dos veces el mismo knob acumula
sobre el valor superpuesto, no sobre el base.

**FR3 — Solo lo que la mano toca.** Los parámetros no girados quedan intactos en
cada Cycle: el overlay aplana un parámetro, no el Cycle.

**FR4 — La restauración.** Al soltar, cada parámetro tocado vuelve a **su** valor
base **en cada Cycle activo** (los valores base se guardan por Cycle, porque el
overlay los igualó). Quedan intactos: el cursor de reproducción, el cursor de
edición, `activeCount`, el pool, el marco tonal, el canal y `padOctaveShift`.

**FR5 — Nada se escribe en el Pattern.** Tras soltar, el Pattern es
indistinguible del anterior al hold salvo por lo que el cursor de reproducción
avanzó por su cuenta.

**FR6 — Con Temp hundido, Temp manda.** Se ignoran en silencio —mismo criterio
que un CC sin asignar— los step buttons 1–12, los modificadores 15 y 16 y sus
gestos de mezcla, el knob 10 (Cycle en edición) y los dieciséis pads. Solo
responden los knobs de parámetro.

**FR7 — Corriendo y parado.** Temp se comporta igual con el transporte en marcha
o detenido. Un gesto que cambia de significado según el transporte es un gesto
que hay que recordar.

**FR8 — Reconexión.** `releaseModifiers()` suelta también Temp y restaura. Un
cable desenchufado con el botón hundido no puede dejar el overlay pegado, porque
la soltada ya no va a llegar por ningún sitio.

**FR9 — Publicación.** Cada giro que cambie algo publica; soltar publica una vez
el snapshot restaurado. Un giro nulo o contra un extremo no publica, igual que
hoy.

**FR10 — Pantalla.** Mientras dura el hold, la pantalla muestra los **valores
superpuestos** —enseña lo que suena— con un distintivo visible de Temp,
reutilizando el valor grande transitorio de `mvp-ring-feedback`. Al soltar vuelve
sola a los valores base.

**FR11 — Preset.** `preset/torax-h0.beatstep-pro.json` y su README declaran el
step 13 como Temp. De paso se corrige el knob 10 (CC 79), que la tabla sigue
marcando libre desde que `cycles_20260901` lo puso a mover el Cycle en edición.

**FR12 — Genérico.** El overlay se define sobre `TrackParameter`, sin enumerar
los nueve. Accent, Repeats, Time, Voicing y Range quedan cubiertos el día que se
mapeen, sin volver aquí.

**FR13 — Notas en vuelo.** Un evento ya programado conserva su note-off. Entrar o
salir del overlay afecta a los eventos siguientes, como cualquier giro de knob
hoy. No se introduce ningún all-notes-off.

## Non-Functional Requirements

**NFR1 — La regla vive en `Engine`.** Un valor puro (base por Cycle y parámetro +
estado del hold) en `Engine`, con umbral ≥90%. `ControlInput` se limita a
traducir el gesto, bajo el ≥80% de `MIDI`. En `App` solo cableado y presentación,
que no se mide.

**NFR2 — El hilo del scheduler no se entera.** Sigue leyendo un `Pattern` normal
por el `PatternHandoff` de siempre. El snapshot vive en el hilo de control: ni
asignaciones, ni locks, ni `await` nuevos en el camino de timing. `Engine` no
importa nada más allá de la stdlib.

**NFR3 — Snapshot acotado.** Se guardan solo los valores base de los parámetros
efectivamente tocados, por Cycle activo — no una copia del Track (~3 KB) ni del
Pattern (~37 KB).

**NFR4 — Restauración inmediata.** Soltar publica y el look-ahead lo recoge en
≤20 ms. Sin cuantización al límite de vuelta.

**NFR5 — Sin medición de jitter.** Timing y Delay desplazan eventos respecto a la
rejilla y la regla del 2026-08-28 los habría marcado como medibles, pero la
medición está **suspendida desde el 2026-09-02**. Se anota aquí para que la
decisión quede con su coste delante.

**NFR6 — Vocabulario.** «Temp» es el término que se ancla en la Pre Spec; no se
inventan sinónimos («momentary», «override», «latch»).

## Acceptance Criteria

1. Mantener [step 13] y girar Pulses cambia lo que suena en el Track
   seleccionado; soltar devuelve el patrón anterior sin haber escrito nada.
2. Con dos o más Cycles activos, el parámetro girado suena igual en todos durante
   el hold, y cada uno recupera **su** valor propio al soltar.
3. Un parámetro no girado conserva su valor distinto por Cycle durante y después
   del hold.
4. Tras un hold completo, el Pattern es igual al de partida salvo el cursor de
   reproducción.
5. Con Temp hundido: pulsar un step button 1–12 no cambia de Track, mute/solo no
   publican gesto, el knob 10 no mueve el Cycle en edición y los pads no tocan el
   pool.
6. `releaseModifiers()` con Temp hundido restaura y publica.
7. Temp se comporta igual con el transporte parado.
8. La pantalla muestra los valores superpuestos y el distintivo mientras dura el
   hold, y vuelve sola al soltar.
9. Cobertura: `Engine` ≥90%, `MIDI` ≥80%. `swift format` limpio y la app compila
   para `generic/platform=iOS`.
10. Verificado en iPad con BeatStep Pro: el fill entra al mantener y se deshace
    al soltar, sin notas colgadas.

## Out of Scope

-   **Vía táctil.** La pantalla no expone el gesto en este track; la API queda
    pública y probada.
-   **Temp sobre pool, Scale, Root, canal o número de Cycles.** Material y
    configuración quedan fuera: el overlay es de parámetros.
-   **Cuantización al límite de vuelta** para entrar o salir del overlay.
-   **Temp sobre varios Tracks a la vez** o sobre el Pattern entero.
-   **MIDI Learn / reasignar el step button.**
-   **Escribir el overlay en un Cycle** («commit temp to pattern»).

## Riesgos

-   **El step button podría ser toggle y no momentary.** Se asume momentary por
    precedente directo: los modificadores 15 y 16 dependen del mismo 127/0 y
    están verificados en iPad. Si el dispositivo desmiente el supuesto, se
    descubre en el checkpoint de fase — no antes, por decisión explícita de no
    meter una fase de sonda.
-   **Deuda abierta:** `midi-test-flake_20260826` sigue produciendo
    `clientCreationFailed(-50)` esporádico en `MIDITests`; es ruido conocido y no
    se atribuye a este cambio.
