# Track: Temp — parámetros temporales

**ID:** `temp-parameters_20260904` · **Type:** Feature · **Status:** new

Girar un knob escribe. Siempre. Para hacer un fill hay que gastar un Cycle o un
Pattern, o deshacer a mano lo que se acaba de tocar — y no hay deshacer. Temp
añade el gesto que falta: **mantener [step 13]** y girar superpone el cambio
sobre el Track seleccionado; **soltar lo devuelve**, y en el Pattern no queda
rastro.

**El overlay iguala, no aplana.** El parámetro girado toma el mismo valor
absoluto en todos los Cycles activos —partiendo del que tenía el Cycle en
edición— para que el fill se oiga aunque el cursor cruce de Cycle a media vuelta.
Los parámetros que la mano no toca conservan su valor distinto en cada Cycle, y
al soltar cada uno recupera **el suyo**: por eso el snapshot guarda la base por
Cycle y no un valor único.

**Es el tercer modificador, y no inventa mecánica.** Los step buttons 15 y 16 ya
son mute y solo desde `mute-solo_20260902`, con el mismo 127 al pulsar y 0 al
soltar; del 13 al 16 no hay Track detrás desde que el Pattern bajó a doce. El
«mantener» es estado de mensajes, así que el gesto entero se prueba con mensajes,
sin temporizadores.

**Con Temp hundido, Temp manda.** Se ignoran en silencio la selección de Track,
los gestos de mezcla, el knob del Cycle en edición y los pads: el hold acota qué
controles están vivos, y un roce de dedo no puede deshacer el fill.

**Lo que más importa que no falle es la reversión.** Restaurar devuelve los
parámetros tocados y **nada más**: el cursor de reproducción avanzó durante el
hold y no puede retroceder, así que un snapshot literal del Track rebobinaría la
música. Y `releaseModifiers()` suelta también Temp — un cable desenchufado con el
botón hundido dejaría el overlay pegado para siempre, porque la soltada que lo
levantaría ya no va a llegar.

**La regla vive en `Engine`**, como valor puro con umbral ≥90%; `ControlInput`
solo traduce el gesto. El hilo del scheduler no se entera: sigue leyendo un
`Pattern` normal, y el snapshot se queda en el hilo de control.

**No lleva medición de jitter**, suspendida el 2026-09-02 — aunque toca Timing y
Delay, que la regla del 2026-08-28 habría marcado como medibles.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [Mute y Solo por Track](../mute-solo_20260902/index.md): de ahí sale la
    mecánica del modificador mantenido, y sus dos índices son los vecinos de este.
-   [Doce Tracks, pantalla MIDI y limpieza del selector](../ui-declutter_20260902/index.md),
    que dejó libres los step buttons 13–16.
-   [Rebanada 3 de la v2 — Cycles](../cycles_20260901/index.md): el overlay
    alcanza a los Cycles activos y respeta sus dos cursores.
-   [Rebanada 7 del MVP — Preset del BeatStep Pro](../mvp-beatstep-mapping_20260830/index.md):
    el preset **sí cambia** aquí — declara el step 13 y corrige el knob 10.
