# Spec — Ctrl All: un knob mueve los doce Tracks

## Overview

Ctrl All superpone un **desplazamiento momentáneo** sobre **los doce Tracks a la
vez** mientras se mantiene **[step 14]** (índice 13 del bloque de step buttons,
CC 115 con el bloque por defecto). Con el botón hundido, girar cualquiera de los
nueve knobs de parámetro suma ese giro al mismo parámetro en todos los Tracks;
al soltar, todo vuelve solo a donde estaba.

**La diferencia con Temp es el verbo: Ctrl All *desplaza*, Temp *iguala*.** Temp
existe para que un parámetro suene igual en todos los Cycles del Track
seleccionado. Ctrl All existe para lo contrario: mover el Pattern entero
**conservando** lo que lo hace un Pattern y no doce copias — un Track lento
sigue siendo el lento, el que tenía menos Pulses sigue teniendo menos. Subir el
Velocity de la mezcla entera sin aplanar su balance no se puede hacer hoy de
ninguna otra manera; con dieciséis knobs y doce Tracks haría falta girar ciento
ocho veces, y ninguna de esas vueltas se podría deshacer.

El gesto entra donde ya hay un hueco y un patrón. Los step buttons 13, 15 y 16
son modificadores momentáneos desde `mute-solo_20260902` y `temp-parameters_20260904`,
y el 14 es el único de los cuatro que el preset todavía declara como «Nada: el
Pattern tiene doce Tracks». Ctrl All es el cuarto modificador, con la misma
mecánica de mensajes: 127 al pulsar, 0 al soltar, sin temporizadores.

**El track lleva además un remapeo de tres knobs**, que no tiene que ver con
Ctrl All salvo en que ambos abren el preset. Se hacen juntos para tocar
`torax-h0.beatstep-pro.json`, su README y `PresetMappingTests` una sola vez, y
para que la verificación en iPad pruebe el mapeo definitivo en lugar de uno
intermedio.

## Functional Requirements

**FR1 — El gesto.** Mantener [step 14] activa Ctrl All sobre **el Pattern
entero**. Soltarlo lo desactiva y restaura. El índice es fijo en `ControlInput`
—`ctrlAllModifierIndex = ControlMapping.controlsPerFamily - 3`— junto a los de
Temp, mute y solo; reasignarlo es MIDI Learn, otra rebanada.

**FR2 — El offset.** Con Ctrl All activo, un giro de knob se traduce al
`TrackParameter` mapeado y **acumula un offset entero** para ese parámetro. El
valor de cada Cycle se recalcula siempre como **base + offset**, nunca a partir
del valor ya superpuesto. Las diferencias entre Tracks y entre Cycles
sobreviven al gesto: eso es lo que lo distingue de Temp.

**FR3 — El alcance: los doce, todos sus Cycles activos.** El offset alcanza a
los `activeCount` Cycles de cada uno de los doce Tracks, **incluidos los
muteados y los soleados fuera**. Mute es mezcla y no material: un Track que se
quedara fuera del offset volvería desalineado al desmutearlo, y el gesto
dependería de un estado que no se ve en los knobs. Los Cycles inactivos no se
tocan, con el mismo criterio que Temp: el overlay alcanza a lo que se recorre.

**FR4 — Acotar sin destruir.** Cada Cycle acota **su** resultado contra **sus**
extremos, con la aritmética que ya tiene `Cycle.applying(_:to:)`. Un Track que
topa no arrastra a los demás, y **al desandar el giro retoma su valor exacto**
en cuanto el desplazamiento vuelve a entrar en su rango, porque lo que se guarda
es el offset pedido y no el valor acotado.

> **Corrección del 2026-09-05, encontrada implementando.** Este requisito decía
> que el Track topado «se despega del tope en el mismo clic» en que los otros se
> mueven, y es falso: con base 16 y tres clics arriba, un clic abajo deja el
> offset en +2 y `16 + 2` sigue acotado. Lo que base+offset garantiza no es
> inmediatez sino **exactitud** — y frente a la alternativa de acotar sobre el
> valor ya escrito, que dejaría el Track en 13 tras tres clics arriba y tres
> abajo, evita perder material de forma permanente. Eso es lo que el requisito
> debía decir. Es la regla de `product-guidelines.md` —«cambiar un
parámetro nunca destruye material»— aplicada al gesto global.

**FR5 — El offset acumulado se acota al recorrido real de los Tracks
capturados.** Para los ocho parámetros con extremos, el acumulado se frena donde
ningún Track puede ya moverse: cuánto le queda por subir al que más margen tiene
hacia arriba, y cuánto por bajar al que más tiene hacia abajo. Sin ese tope,
cuarenta clics contra el límite dejarían el knob muerto durante cuarenta clics de
vuelta — el mismo síntoma que la nota del 2026-08-28 sobre encoders mal
configurados, y que un usuario leería como que el gesto se rompió.

> **Corrección del 2026-09-05, encontrada implementando.** Este requisito decía
> «el ancho del rango del parámetro», y **no cumple lo que promete**: con Pulses
> 1…12 y el ancho en 15, cuarenta clics abajo dejan el acumulado en −15 y los doce
> Tracks en 1; un clic arriba lo deja en −14 y el Track de base 12 sigue dando −2,
> así que hacen falta cuatro clics para que algo se mueva. El tope tiene que
> salir de las **bases capturadas**, no del parámetro. Lo destapó el test del
> sentido descendente al fallar mientras el ascendente pasaba: la asimetría es del
> reparto de las bases, no del signo.

**FR5b — Topar tiene un precio, y no es la reversibilidad.** Con el acumulado
saturado, una ida y vuelta simétrica **no** devuelve el Pattern a su sitio: la
subida satura y la bajada parte de ahí. Es inherente a cualquier acotado y se
acepta a cambio de que el knob no quede muerto. **La garantía de no perder nada
vive en la restauración**, no en el recorrido: soltar el step 14 devuelve la base
exacta por muchas vueltas que se hayan dado.

**FR6 — Rotate envuelve y por eso no se acota.** Rotate no tiene extremos: gira
módulo el `steps.count` de **cada** Cycle. Su offset acumulado crece libre y el
módulo lo resuelve cada Cycle al aplicarlo, así que con Steps distintos los
Tracks se desfasan entre sí — que es exactamente lo que se le pide a un Rotate
global. Un knob que envuelve nunca queda muerto, así que la razón de FR5 no le
aplica.

**FR7 — Cada parámetro lleva su offset.** Durante un mismo hold se puede subir
Velocity y bajar Sustain: cada parámetro guarda su base y acumula su propio
offset, y al soltar vuelven los dos. Los parámetros no girados quedan intactos.

**FR8 — La restauración.** Al soltar, cada parámetro tocado vuelve a **su** valor
base **en cada Cycle activo de cada Track**. Quedan intactos: los cursores de
reproducción y de edición, `activeCount`, el pool, el marco tonal, el canal,
`padOctaveShift` y el estado de mute/solo.

**FR9 — Nada se escribe en el Pattern.** Tras soltar, el Pattern es
indistinguible del anterior al hold salvo por lo que los cursores de
reproducción avanzaron por su cuenta.

**FR10 — Con Ctrl All hundido, Ctrl All manda.** Se ignoran en silencio —mismo
criterio que un CC sin asignar— los step buttons 1–12, los modificadores 15 y 16
y sus gestos de mezcla, el knob 10 (Cycle en edición) y los dieciséis pads. Solo
responden los knobs de parámetro.

**FR11 — Y también callan las vías táctiles que escriben.** `selectTrack(_:)`,
`setChannel(_:)`, `setChannel(_:forTrack:)`, `setFrame(_:)` y
`setActiveCycleCount(_:)` devuelven `false` mientras dura el hold. Es un
requisito nuevo que Temp no tiene, y la razón es que el gesto promete no
escribir: un cambio de Scale a media superposición reencuadra el pool y **no se
deshace al soltar**, y un `activeCount` que sube deja Cycles sin base guardada
que se quedarían con el offset puesto para siempre. Congelar `activeCount` es
además lo que permite que el conjunto de Cycles con base no cambie bajo los pies
del gesto.

**FR12 — Publica si cambió algún Track.** La regla de Temp —«si el Cycle en
edición no se mueve, no se mueve nadie»— **no se hereda**: existía porque la
igualación aplanaba a los demás, y aquí no hay nada que aplanar. Se publica
comparando el Pattern, como hoy. Un giro nulo no publica. Un giro en el que el
Track seleccionado topa pero otros se mueven **sí** publica: callar ahí
silenciaría un gesto que está sonando.

**FR13 — Prioridad frente a Temp.** Con [step 13] y [step 14] hundidos a la vez
**gana Temp**, por el corte que `receive(_:)` ya aplica: con Temp puesto, el
único step button vivo es el 13. **Al soltar el 13 con el 14 aún hundido, Temp
restaura y publica, y Ctrl All arranca ahí**, tomando su base del Pattern ya
restaurado. Cada modificador entra y sale por su propio botón; ninguno hereda el
estado del otro ni queda muerto esperando una pulsación nueva.

**FR14 — Corriendo y parado.** Ctrl All se comporta igual con el transporte en
marcha o detenido, por la misma razón que Temp: un gesto que cambia de
significado según el transporte es un gesto que hay que recordar.

**FR15 — Reconexión.** `releaseModifiers()` suelta también Ctrl All y restaura.
Un cable desenchufado con el botón hundido no puede dejar el offset pegado sobre
los doce Tracks, porque la soltada ya no va a llegar por ningún sitio.

**FR16 — Pantalla.** Mientras dura el hold, la pantalla muestra el **valor
superpuesto del Track seleccionado** con un **distintivo propio de Ctrl All**,
distinguible del de Temp, reutilizando el valor grande transitorio de
`mvp-ring-feedback`. Los doce anillos ya se redibujan con el Pattern publicado,
así que el alcance global se ve sin trabajo extra. Al soltar vuelve sola a los
valores base.

**FR17 — Preset.** `preset/torax-h0.beatstep-pro.json` y su README declaran el
step 14 (CC 115) como Ctrl All, en lugar del «Nada: el Pattern tiene doce
Tracks» que la tabla dice hoy.

**FR18 — Genérico.** El offset se define sobre `TrackParameter`, sin enumerar los
nueve. Accent, Repeats, Time, Voicing y Range quedan cubiertos el día que se
mapeen, sin volver aquí.

**FR19 — Notas en vuelo.** Un evento ya programado conserva su note-off. Entrar o
salir del offset afecta a los eventos siguientes, como cualquier giro de knob
hoy. No se introduce ningún all-notes-off.

**FR20 — Remapeo de knobs.** Tres knobs cambian de CC: **Delay al 76**,
**Probability al 78** —un intercambio entre ellos— y el **Cycle en edición al
82**, que lo mueve del knob 10 al **13**. El **CC 79 queda libre**, declarado a
propósito como los otros cinco.

**El Cycle deja de ser un CC derivado.** `editingCycleController` se calcula hoy
como `knobBlock.number + 9`; con el knob 13 pasa a ser un dato del mapeo, como
`padBlock` o `knobBlock`, en vez de un desplazamiento fijo escondido en una
propiedad calculada. Un desplazamiento así es lo que hacía que mover un knob
fuera un cambio de aritmética en lugar de un cambio de tabla.

**La justificación del rango se reescribe, no se excepciona.** `ControlMapping` y
el README dicen que los números viven en 70–79 «para no pisar controladores con
significado asignado». La regla real siempre fue la segunda mitad de esa frase:
80–85 también están sin significado fijo en la especificación MIDI. Se corrige el
texto en los dos sitios, con nota fechada que diga por qué decía 70–79.

## Non-Functional Requirements

**NFR1 — La regla vive en `Engine`.** Un valor puro —base por Track, Cycle y
parámetro, más el offset acumulado por parámetro— en `Engine`, con umbral ≥90%.
`ControlInput` se limita a traducir el gesto, bajo el ≥80% de `MIDI`. En `App`
solo cableado y presentación, que no se mide.

**NFR2 — El hilo del scheduler no se entera.** Sigue leyendo un `Pattern` normal
por el `PatternHandoff` de siempre. El offset vive en el hilo de control: ni
asignaciones, ni locks, ni `await` nuevos en el camino de timing. `Engine` no
importa nada más allá de la stdlib.

**NFR3 — Snapshot acotado.** Se guardan solo los valores base de los parámetros
efectivamente tocados, por Track y Cycle activo — no una copia del Pattern
(~37 KB), que además rebobinaría los cursores. El peor caso real es un parámetro
× 12 Tracks × `activeCount` Cycles.

**NFR4 — El coste no se mide con un número.** Un clic reescribe hasta doce
Tracks contra el único de Temp, y esto queda anotado sin test de coste: el hilo
de control ya reescribe el Pattern entero en cada giro y el camino de timing no
cambia. Se escribe aquí para que la decisión quede con su coste delante, igual
que se hizo con la medición de jitter.

**NFR5 — Restauración inmediata.** Soltar publica y el look-ahead lo recoge en
≤20 ms. Sin cuantización al límite de vuelta.

**NFR6 — Sin medición de jitter.** Timing y Delay desplazan eventos respecto a la
rejilla y la regla del 2026-08-28 los habría marcado como medibles, pero la
medición está **suspendida desde el 2026-09-02**. Se anota para que la decisión
quede con su coste delante.

**NFR7 — Vocabulario.** «Ctrl All» es el término, literal, en el código, en la
Pre Spec y en la pantalla — como se ancló «Temp». No se inventan sinónimos
(«global», «all tracks», «macro»).

## Acceptance Criteria

1. Mantener [step 14] y girar Velocity sube el Velocity de los doce Tracks;
   soltar devuelve el balance anterior sin haber escrito nada.
2. Dos Tracks con Pulses 4 y 9 mantienen su diferencia durante todo el gesto:
   Ctrl All desplaza y no iguala.
3. Con dos o más Cycles activos, cada Cycle de cada Track conserva su valor
   propio desplazado, y recupera **el suyo** al soltar.
4. Un Track topado contra su extremo no arrastra a los demás, retoma su valor
   exacto en cuanto el desplazamiento reentra en su rango, y una ida y vuelta
   completa lo devuelve a su base sin pérdida.
5. Cuarenta clics contra el tope y un clic de vuelta mueven algo, **en los dos
   sentidos**: el acumulado está acotado al recorrido real de las bases
   capturadas (FR5). Pasado el tope, una ida y vuelta simétrica no devuelve el
   Pattern, y soltar sí (FR5b).
6. Rotate desplaza los doce envolviendo cada Cycle con su propio Steps, y su
   offset no se acota.
7. Tras un hold completo, el Pattern es igual al de partida salvo los cursores
   de reproducción.
8. Con Ctrl All hundido: pulsar un step button 1–12 no cambia de Track,
   mute/solo no publican gesto, el knob 10 no mueve el Cycle en edición, los pads
   no tocan el pool, y las cinco vías táctiles de FR11 devuelven `false`.
9. Con 13 y 14 hundidos gana Temp; soltar el 13 restaura, publica, y los giros
   siguientes son Ctrl All sobre el Pattern restaurado.
10. `releaseModifiers()` con Ctrl All hundido restaura y publica.
11. Ctrl All se comporta igual con el transporte parado.
12. La pantalla muestra el valor superpuesto y un distintivo propio, distinto del
    de Temp, mientras dura el hold, y vuelve sola al soltar.
13. Cobertura: `Engine` ≥90%, `MIDI` ≥80%. `swift format` limpio y la app compila
    para `generic/platform=iOS`.
14. Verificado en iPad con BeatStep Pro: el gesto global entra al mantener y se
    deshace al soltar, sin notas colgadas.
15. Un giro en CC 76 mueve Delay, en CC 78 mueve Probability y en CC 82 mueve el
    Cycle en edición; CC 79 se ignora en silencio. `PresetMappingTests` confirma
    que JSON, README y `ControlMapping` dicen los mismos números.

## Out of Scope

-   **Vía táctil para accionar Ctrl All.** La pantalla no expone el gesto en este
    track; la API queda pública y probada. (Lo que sí entra es **congelar** las
    vías táctiles que escriben — FR11.)
-   **Ctrl All sobre pool, Scale, Root, canal, `padOctaveShift` o número de
    Cycles.** Material y configuración quedan fuera: el offset es de parámetros.
-   **Ctrl All acotado a una selección de Tracks** («todos menos estos»).
-   **Cuantización al límite de vuelta** para entrar o salir.
-   **Escribir el offset en el Pattern** («commit»).
-   **MIDI Learn / reasignar el step button.**
-   **Test de coste del hilo de control** (NFR4).

## Riesgos

-   **El step 14 podría ser toggle y no momentary.** Riesgo menor que en Temp: ya
    hay tres modificadores del mismo bloque verificados en iPad, incluido el 13,
    contiguo. Si el dispositivo desmiente el supuesto, se descubre en el
    checkpoint de fase.
-   **La restauración global es más grande que la de Temp.** Si un parámetro
    quedara sin base guardada —por un Cycle activado a media superposición, que
    FR11 impide— el fill quedaría escrito. La defensa es FR11 y un test que
    compare el Pattern completo antes y después del hold (AC7).
-   **Deuda abierta:** `midi-test-flake_20260826` sigue produciendo
    `clientCreationFailed(-50)` esporádico en `MIDITests`; es ruido conocido y no
    se atribuye a este cambio.
