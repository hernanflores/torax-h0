# Track: Ctrl All — un knob mueve los doce Tracks

**ID:** `ctrl-all_20260905` · **Type:** Feature · **Status:** new

Subir el Velocity de la mezcla entera no se puede hacer hoy de ninguna manera.
Con dieciséis knobs y doce Tracks harían falta ciento ocho vueltas, y ninguna se
podría deshacer. Ctrl All añade el gesto: **mantener [step 14]** y girar desplaza
ese parámetro en **los doce Tracks a la vez**; **soltar lo devuelve**, y en el
Pattern no queda rastro.

**La diferencia con Temp es el verbo: Ctrl All *desplaza*, Temp *iguala*.** Temp
existe para que un parámetro suene igual en todos los Cycles del Track
seleccionado. Ctrl All existe para lo contrario: mover el Pattern entero
**conservando** lo que lo hace un Pattern y no doce copias — un Track lento sigue
siendo el lento, el que tenía menos Pulses sigue teniendo menos.

**Guarda base y offset por separado, y esa es la decisión de diseño del track.**
El valor de cada Cycle se recalcula siempre como base + offset, nunca desde el
valor ya escrito. Es lo único que hace exacta la ida y vuelta cuando un Track topa
contra su extremo: el topado no arrastra a los demás y **retoma su valor exacto**
en cuanto el desplazamiento reentra en su rango. El acumulado sí se acota al ancho del recorrido,
porque sin tope cuarenta clics contra el límite dejan el knob muerto durante
cuarenta clics de vuelta — el síntoma que la nota del 2026-08-28 enseñó a
reconocer como avería. Rotate queda fuera de ese tope: envuelve, así que nunca se
muere.

**Es el cuarto modificador, y el 14 era el único hueco que quedaba.** Los step
buttons 13, 15 y 16 son Temp, solo y mute; el 14 es el que el preset todavía
declara como «Nada: el Pattern tiene doce Tracks». Misma mecánica de mensajes:
127 al pulsar, 0 al soltar, sin temporizadores.

**Con 13 y 14 hundidos gana Temp, y ninguno hereda el estado del otro.** Al soltar
el 13 con el 14 aún hundido, Temp restaura y publica, y Ctrl All arranca ahí sobre
el Pattern ya restaurado. Cada modificador entra y sale por su propio botón: un
botón hundido que no hace nada sería peor que cualquiera de las dos respuestas.

**Congela también las vías táctiles que escriben** —`selectTrack`, `setChannel`,
`setChannel(forTrack:)`, `setFrame`, `setActiveCycleCount`—, que es un requisito
que Temp no tiene. La razón es que el gesto promete no escribir: un cambio de
Scale a media superposición reencuadra el pool y **no se deshace al soltar**, y un
`activeCount` que sube deja Cycles sin base guardada que se quedarían con el
offset puesto para siempre.

**Publica si cambió algún Track**, y aquí sí se aparta de Temp. La regla «si el
Cycle en edición no se mueve, no se mueve nadie» existía porque la igualación
aplanaba a los demás; con offset no hay nada que aplanar, y callar porque el Track
que se está mirando topó silenciaría un gesto que está sonando.

**El track lleva además un remapeo de tres knobs** —Delay al 76, Probability al
78, el Cycle en edición al 82, con el CC 79 libre—, que no tiene que ver con Ctrl
All salvo en que ambos abren el preset. Van juntos para tocar el JSON, el README y
`PresetMappingTests` una sola vez, y para que la verificación en iPad pruebe el
mapeo definitivo. De paso, `editingCycleController` deja de ser un desplazamiento
fijo escondido en una propiedad calculada y pasa a ser un dato del mapeo.

**La regla vive en `Engine`**, como valor puro con umbral ≥90%; `ControlInput`
solo traduce el gesto. El hilo del scheduler no se entera: sigue leyendo un
`Pattern` normal, y el snapshot se queda en el hilo de control.

**No lleva medición de jitter** (suspendida el 2026-09-02) **ni test de coste del
hilo de control**, aunque un clic reescriba hasta doce Tracks contra el único de
Temp. Las dos decisiones quedan anotadas con su coste delante.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [Temp — parámetros temporales](../temp-parameters_20260904/index.md): el
    hermano directo. De ahí sale el modificador mantenido con restauración, y con
    él hay que ceder el paso (FR13).
-   [Mute y Solo por Track](../mute-solo_20260902/index.md): la mecánica del
    modificador mantenido, y los Tracks muteados que **sí** reciben el offset.
-   [Doce Tracks, pantalla MIDI y limpieza del selector](../ui-declutter_20260902/index.md),
    que dejó libres los step buttons 13–16.
-   [Rebanada 3 de la v2 — Cycles](../cycles_20260901/index.md): el offset alcanza
    a los Cycles activos y respeta sus dos cursores.
-   [Rebanada 7 del MVP — Preset del BeatStep Pro](../mvp-beatstep-mapping_20260830/index.md):
    el preset cambia aquí dos veces — el step 14 y tres knobs.
