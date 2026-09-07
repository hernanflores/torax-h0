# Track: v2 rebanada 5 — Note Repeater

**ID:** `note-repeater_20260906` · **Type:** Feature · **Status:** new

Meter nueve eventos donde hoy hay uno exige subir Pulses y bajar Division, y eso
reescribe el patrón entero en vez de decorar un golpe. El Note Repeater añade
**triggers extra a partir de cada Pulse** sin tocar Steps, Pulses ni Rotate: el
Pulse original sigue sonando y detrás de él caen hasta ocho repeticiones.

**No es un secuenciador aparte, es una capa sobre el ritmo que el Track ya
tiene.** Es lo que convierte un hi-hat en un ratchet, una caja en un roll y un
ritmo disperso en una textura densa, y las repeticiones siguen siendo del Track:
heredan su Velocity, su Sustain, su swing y su Delay.

Cuatro knobs: **Repeats** (0–8), **Time** (1/8 … 1/128, rectos y tresillos),
**Ramp** (curva de velocity, ±100) y **Pace** (curva de espaciado, ±100).

**Con Repeats en 0 —el default— no cambia nada de lo entregado**, y ese es el
requisito que sostiene la rebanada (FR16). Es también lo que permite que
Probability pase a decidir sobre *todas* las notas sin que ningún Pattern
existente suene distinto: sin repeticiones, «todas las notas» y «solo los Pulses»
son el mismo conjunto.

**Ramp y Pace son knobs y no secundarios de CTRL.** El BeatStep Pro no tiene
CTRL, y la nota del 2026-09-02 ya resolvió este caso una vez con Cycles: el gesto
de la Pre Spec agrupaba cosas porque el hardware de entonces lo hacía barato, no
porque sean la misma cosa. Van a los knobs 10, 11, 12 y 14 —CC 79, 80, 81 y 83—,
con el 79 que `ctrl-all_20260905` dejó libre a propósito.

**Repeats es 0–8 y no el 0–48 de la Pre Spec, y no hay «infinito».** El techo de
coste en el hilo del scheduler se **razona** en vez de medirse —la medición de
jitter está suspendida desde el 2026-09-02— y con doce Tracks, 108 eventos por
Step es defendible donde 588 no lo es. Ampliarlo después es cambiar una
constante.

**El corte lo pone el Pulse siguiente, no el Step siguiente.** Las repeticiones
cruzan los Steps vacíos del reparto euclidiano, que es lo que hace funcionar un
roll largo sobre un ritmo disperso, y se miden contra el **instante de emisión**
del Pulse siguiente —swing dentro—, no contra la rejilla recta. Lo que no cruzan
es la vuelta: qué Cycle viene después lo decide el hilo del scheduler al cerrar,
y mirar dentro rompería que el Cycle nuevo entre limpio en su primer Step.

**Sustain se aplica sobre el hueco de la repetición, no sobre el Step.** Es la
misma regla que ya rige entre Steps, aplicada a la rejilla que la repetición
habita: con Sustain 100% cada una llega justo a la siguiente. El Pulse conserva
su gate sobre el Step.

**Ramp deja el Pulse en paz.** El Pulse original suena siempre a la Velocity del
Track y la rampa recorre solo las repeticiones; con −100 acota en **1 y no en 0**,
porque velocity 0 es note-off en MIDI 1.0 y una rampa no debe emitir un apagado
disfrazado de nota.

**Sale de «Fuera de v1»** de `product.md`, por la misma vía que salieron Cycles y
los múltiples Tracks: con una nota fechada que diga qué se entrega y qué se deja
—el rango 0–48, el «infinito» del tope y los modos Choke/Tail—.

**No lleva medición de jitter**, y es el segundo cambio desde la suspensión del
2026-09-02 que toca la rejilla temporal. Aquí no se abre excepción: se verifica
tocando, en dispositivo. Un ratchet que se arrastra se oye.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [Rebanada 3 de la v2 — Cycles](../cycles_20260901/index.md): cada Cycle tiene
    su propio Note Repeater, y de ahí sale el límite de vuelta del corte.
-   [Ctrl All](../ctrl-all_20260905/index.md): dejó libre el CC 79, y alcanza a
    los cuatro parámetros nuevos sin tocar nada.
-   [Temp — parámetros temporales](../temp-parameters_20260904/index.md): también
    los alcanza; un fill que sube Repeats y se deshace al soltar.
-   [Rediseño de las cuatro pantallas](../screens-redesign_20260906/index.md): el
    card de Shape pasa a dos líneas, sin color ni tipografía nuevos.
-   [Rebanada 7 del MVP — Preset del BeatStep Pro](../mvp-beatstep-mapping_20260830/index.md):
    el preset gana cuatro knobs.
