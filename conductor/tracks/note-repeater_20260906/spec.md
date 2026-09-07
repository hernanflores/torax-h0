# Spec — v2 rebanada 5: Note Repeater

## Overview

El Note Repeater añade **triggers extra a partir de cada Pulse**. No es un
secuenciador aparte: es una **capa sobre el ritmo que el Track ya tiene**. Steps,
Pulses y Rotate no cambian; el Pulse original sigue sonando y detrás de él caen
hasta ocho repeticiones, separadas por un valor de nota propio, con su curva de
velocity y su curva de espaciado.

Es lo que convierte un hi-hat en un ratchet, una caja en un roll y un ritmo
disperso en una textura densa **sin reescribir el reparto euclidiano**. Hoy no se
puede: la única forma de meter nueve eventos donde había uno es subir Pulses y
bajar Division, y eso cambia el patrón entero en vez de decorar un golpe.

Cuatro knobs, cuatro parámetros:

| Parámetro | Qué decide | Rango | Default |
|---|---|---|---|
| **Repeats** | Cuántos triggers extra genera cada Pulse | 0–8 | 0 |
| **Time** | Separación entre repeticiones, como valor de nota | 1/8 … 1/128, rectos y tresillos | 1/32 |
| **Ramp** | Curva de velocity a través de las repeticiones | −100 … +100 | 0 |
| **Pace** | Cambio del espaciado a lo largo de la tirada | −100 … +100 | 0 |

**Con Repeats en 0 —el default— no cambia nada de lo entregado.** Es la condición
de no regresión de la rebanada, y lo que permite que Probability pase a decidir
sobre *todas* las notas sin que ningún Pattern existente suene distinto: sin
repeticiones, «todas las notas» y «solo los Pulses» son el mismo conjunto.

**Sale de «Fuera de v1».** `product.md` lista hoy «Note Repeater
(Repeats/Time/Ramp/Pace)» entre lo que queda fuera. Entra ahora por la misma vía
que entraron Cycles y los múltiples Tracks: con una nota fechada que diga qué se
entrega y qué se deja —de la Pre Spec quedan fuera el rango 0–48, el «infinito»
del tope y los modos Choke/Tail—.

## Functional Requirements

**FR1 — El modelo: `NoteRepeater`, dentro del `Cycle`.** Un valor propio con los
cuatro parámetros, guardado en el `Cycle` junto a `Shape`, `Groove` y el pool.
Vive en `Engine` y es trivialmente copiable: `_isPOD(Cycle.self)` sigue siendo la
red que lo vigila (NFR2). Cada Cycle tiene el suyo, así que un desarrollo A/B
puede ratchetear solo en el B.

**FR2 — Familia Shape, sin color nuevo.** Los cuatro se clasifican en
`ParameterFamily.shape` y se pintan con su verde `#9AAB79`. La tabla de Shape de
la Pre Spec ya pone Repeats y Time ahí, y `product-guidelines.md` fija tres
acentos verificados a un metro: añadir un cuarto color exigiría verificar un
cuarto color, y no hay una familia nueva que justificarlo.

**FR3 — Cuatro casos nuevos en `TrackParameter`.** `.repeats`, `.repeatTime`,
`.ramp` y `.pace`, con `description` `"Repeats"`, `"Time"`, `"Ramp"` y `"Pace"`.

> El prefijo de `.repeatTime` es desambiguación de Swift y **no un término
> nuevo**: `Time` a secas colisiona con el vocabulario temporal del motor
> (`MusicalTime`, `MusicalTimeline`). Lo que el usuario lee sigue siendo `Time`,
> que es el término de la Pre Spec (NFR7).

**FR4 — Cuatro knobs propios.** El BeatStep Pro no tiene CTRL —nota del
2026-09-02—, así que Ramp y Pace dejan de ser secundarios de un modificador y
pasan a ser knobs, por la misma razón por la que «cuántos Cycles activos» pasó a
ser táctil: el gesto de CTRL agrupaba cosas porque el hardware de la Pre Spec lo
hacía barato, no porque sean la misma cosa. `product-guidelines.md` marca como
antipatrón que un parámetro generativo solo exista en pantalla.

| Knob | CC | Parámetro |
|---|---|---|
| 10 | 79 | Repeats |
| 11 | 80 | Time |
| 12 | 81 | Ramp |
| 13 | 82 | *(Cycle en edición, ya asignado)* |
| 14 | 83 | Pace |

El CC 79 quedó libre a propósito en `ctrl-all_20260905`; 80, 81 y 83 no pisan
nada con significado asignado en la especificación MIDI.

**FR5 — Repeats: 0–8, se detiene en los extremos.** No envuelve, como Steps y
Division: envolver convertiría un giro de más en pasar de ocho repeticiones a
ninguna.

> **Desviación de la Pre Spec, que dice «0–48; máximo clockwise = infinito».**
> Se acota a 8 por el techo de coste en el hilo del scheduler: con doce Tracks,
> ocho repeticiones son 108 eventos por Step como peor caso, contra los 588 de
> 48. La medición de jitter está suspendida desde el 2026-09-02 (NFR6), así que
> el techo se razona y no se mide, y razonar sobre 108 es defendible donde sobre
> 588 no lo es. Ampliarlo después es cambiar una constante y volver a mirar el
> techo. «Infinito» queda fuera del todo: exige decidir qué lo corta y añade un
> caso propio a la regla de corte de FR9.

**FR6 — Time: valor de nota absoluto, no fracción del Step.** Nueve posiciones,
rectos y sus tresillos, de más lenta a más rápida:

`1/8 · 1/12 · 1/16 · 1/24 · 1/32 · 1/48 · 1/64 · 1/96 · 1/128`

Default 1/32. Se detiene en los extremos. Es independiente de la Division del
Track: un Track en 1/4 y otro en 1/16 con el mismo Time repiten al mismo ritmo,
que es lo que «expressed as a note value» significa.

**El hueco se calcula como múltiplo de la duración del Step**, no volviendo al
tempo: `hueco = duraciónDelStep × (fracciónDeTime / fracciónDeDivision)`, con
aritmética entera. La duración del Step ya está precalculada en el
`TrackScheduler`, y hacerlo así hereda —sin inventar una vía nueva— la
limitación conocida de que la rejilla la fija la `MusicalTimeline` al pulsar Play.

**FR7 — Ramp: el Pulse en su Velocity, las repeticiones interpolan.** El Pulse
original suena **siempre** a la Velocity del Track; la rampa recorre solo las
repeticiones. Con `n` repeticiones y la repetición `k` de 1 a `n`:

```
objetivo = ramp > 0 ? 127 : 1
v(k) = V + (objetivo − V) × (|ramp| / 100) × (k / n)
```

acotado a `Velocity.validRange` (1…127). Con Ramp 0 todas suenan a `V`. Con
+100 la última llega a 127; con −100 llega a **1 y no a 0**, porque velocity 0 es
note-off en MIDI 1.0 y una rampa no debe poder emitir un apagado disfrazado de
nota.

Es «relativo a la Velocity general del Track» de la Pre Spec: mover el knob de
VELOCITY mueve la rampa entera con él.

**FR8 — Pace: el último hueco es ×2 o ÷2 del primero.** El factor sale de Pace y
los huecos intermedios se interpolan linealmente:

```
r = pace ≥ 0 ? (100 + pace) / 100 : 100 / (100 − pace)
hueco(i) = Time × (1 + (r − 1) × (i − 1) / (n − 1))     con n > 1
hueco(1) = Time                                          con n = 1
```

`r` es exactamente recíproco entre `+p` y `−p` —+50 da ×1,5 y −50 da ÷1,5— y es
aritmética racional, sin exponenciales en el camino de tiempo real. Con Pace 0
todos los huecos valen Time y la tirada es recta.

**Pace cambia cuánto dura la tirada**, y por eso interactúa con FR9: un Pace
positivo alto entrega menos repeticiones de las pedidas, porque el corte llega
antes. Es visible y deliberado.

**FR9 — El corte: el Pulse siguiente, y en su defecto el fin de la vuelta.** Una
repetición se emite si su instante cae **estrictamente antes** del instante de
emisión del Pulse siguiente de la vuelta en curso. Si no queda ningún Pulse por
delante en la vuelta, el límite es el cierre de la vuelta.

- El límite se mide contra el **instante de emisión** del Pulse siguiente, con su
  desplazamiento de Timing y Delay dentro, no contra la rejilla recta: con swing,
  medir contra la rejilla cortaría de más o de menos según el paso.
- **El límite no cruza la vuelta.** Qué Cycle viene después lo decide el hilo del
  scheduler al cerrar, y mirar dentro de él rompería que el Cycle nuevo entre
  limpio en su primer Step (FR5 de `cycles_20260901`).
- Las repeticiones **sí** cruzan Steps vacíos del reparto euclidiano: eso es lo
  que hace que un roll largo funcione sobre un ritmo disperso.

**FR10 — Las repeticiones se cuentan desde el Pulse ya desplazado.** El Pulse cae
donde Timing y Delay lo pongan y la tirada se espacia desde ahí. Ninguna
repetición recibe un desplazamiento propio: el swing opera sobre la rejilla de
Steps y no sobre la de repeticiones. La tirada viaja con el Pulse.

**FR11 — La altura es la del Pulse.** Las repeticiones repiten la altura que le
tocó al Pulse que las generó. `pitch(atStep:)` sigue siendo función de la
posición en el anillo, así que el recorrido del pool no se altera: los Pulses
siguen avanzando el pool de uno en uno y un ratchet no lo acelera.

> Que cada repetición avance el pool —el arpegio rápido— queda anotado como
> ampliación para cuando entren Range y Phrase. Exigiría que la altura dejara de
> ser función de la posición, que es lo que hoy evita un contador mutable en el
> camino de tiempo real.

**FR12 — Sustain se aplica sobre el hueco de la repetición.** El gate de una
repetición es su porcentaje de Sustain sobre **su propio hueco**, no sobre el
Step: con Sustain 100% cada repetición llega justo a la siguiente, que es la
misma regla que ya rige entre Steps, aplicada a la rejilla que la repetición
habita. **El Pulse conserva su gate sobre el Step**, así que con Repeats en 0
nada cambia (FR16).

**FR13 — Probability decide sobre todas las notas.** Cada evento —el Pulse y cada
repetición— consume **una tirada** del generador sembrado, en orden: primero el
Pulse, después las repeticiones.

- **Un Pulse callado no se lleva sus repeticiones.** Son eventos independientes;
  bajar Probability con Repeats altos perfora la textura en vez de borrar tiradas
  enteras.
- **Una repetición que el corte descarta no consume tirada.** El corte se decide
  antes que la tirada, con el mismo criterio que hoy separa «primero dispara,
  después decide si suena»: así girar Time o Pace no desplaza las omisiones de un
  patrón que nadie tocó.
- **Con Repeats en 0 el consumo de aleatoriedad es idéntico al de hoy**, que es
  lo que hace que este cambio no sea una regresión (FR16).

**FR14 — El arnés no repite.** `SchedulerMaterial.everyStep` devuelve un
`NoteRepeater` neutro, por la misma razón por la que usa el `Groove` por defecto:
mide la rejilla temporal, no el material musical.

**FR15 — La pantalla: dos líneas en el card de Shape.** `Steps · Pulses · Rotate
· Division` en la primera y `Repeats · Time · Ramp · Pace` en la segunda, mismo
acento verde. La separación dice lo que el modelo dice: una capa sobre el ritmo,
no el ritmo. Los cuatro aparecen además como **valor grande transitorio** al
girar su knob, como los otros nueve, con su unidad: `3`, `1/32`, `+40%`, `−20%`.

El anillo **no cambia**: dibuja los Pulses y no las repeticiones. Son sub-Step y
a un metro no se distinguen —el requisito de legibilidad de
`product-guidelines.md`—.

**FR16 — No regresión con Repeats en 0.** Con el default, la salida MIDI es
**idéntica** a la de antes de la rebanada: los mismos instantes, las mismas
velocities, los mismos gates y el mismo consumo de aleatoriedad. Es un requisito
con tests propios, no una expectativa.

**FR17 — Temp y Ctrl All alcanzan a los cuatro.** Los dos gestos operan sobre
`TrackParameter`, así que los cuatro entran solos; lo único que hay que declarar
es su `displacementRange` para el tope de Ctrl All (`nil` para ninguno: los
cuatro se acotan, ninguno envuelve). Un fill que sube Repeats en los doce Tracks
y se deshace al soltar es exactamente lo que Ctrl All existe para hacer.

**FR18 — El preset se reescribe.** `preset/torax-h0.beatstep-pro.json` y
`preset/README.md` declaran los cuatro knobs nuevos, y `PresetMappingTests`
compara JSON, README y `ControlMapping` para que ninguno de los tres se quede
atrás.

**FR19 — La desviación queda escrita antes de implementar.** Task Workflow §8:
nota fechada en `Pre Spec Torax H-0.md` —qué se entrega del Note Repeater y qué
no— y nota fechada en `conductor/product.md`, que **saca el Note Repeater de
«Fuera de v1»** y lo describe en *Interaction Model* junto a Cycles.

## Non-Functional Requirements

**NFR1 — Sin asignaciones, locks ni `await` en el camino del scheduler.** Las
repeticiones se calculan con aritmética entera dentro del bucle que ya recorre la
ventana. Nada de arrays temporales de eventos.

**NFR2 — El snapshot sigue siendo trivial.** `NoteRepeater` son cuatro enteros:
con 12 Tracks × 16 Cycles son ~768 bytes sobre los ~37 KB medidos, un 2%.
`_isPOD(Cycle.self)` y los tests de coste del snapshot siguen vigentes y se
actualizan con el tamaño nuevo.

**NFR3 — El coste crece con lo que suena.** Un Cycle con Repeats en 0 no ejecuta
nada del camino nuevo, igual que un Cycle con el pool vacío no se programa.

**NFR4 — Cobertura.** `Engine` ≥90%, `MIDI` ≥80% (medida en un proceso y
excluyendo `Engine/Sources`, como dice `workflow.md`). Toda la matemática de
Ramp, Pace, hueco y corte vive en `Engine`, donde se testea sin relojes.

**NFR5 — Los cuatro cambian en caliente.** Girar cualquiera de los cuatro se oye
en el Step siguiente: viajan en el snapshot y se releen por ventana, como
Velocity o Probability. Ninguno se congela al pulsar Play.

**NFR6 — Sin medición de jitter.** La suspensión del 2026-09-02 manda. Queda
anotado que **este es el segundo cambio desde entonces que toca la rejilla
temporal** —el primero fue `external-clock_20260903`, que se midió como excepción
acotada— y que aquí no se abre excepción: se verifica tocando, en dispositivo. Un
ratchet que se arrastra se oye.

**NFR7 — Vocabulario de la Pre Spec.** `Repeats`, `Time`, `Ramp`, `Pace`,
`Note Repeater`. Ni «ratchet» como nombre de parámetro, ni «roll», ni
«subdivisión», ni «stutter».

## Acceptance Criteria

1. Con Repeats en 3 y Time en 1/32 sobre un Track en 1/16, cada Pulse entrega
   cuatro note-on: el suyo en la rejilla y tres separados por un 1/32.
2. Con Ramp +100 y Velocity 100, las tres repeticiones suben hacia 127; con
   −100 bajan hacia 1, sin llegar nunca a 0. El Pulse suena a 100 en los dos.
3. Con Pace +100, el último hueco dura el doble que el primero; con −100, la
   mitad; con 0, todos iguales.
4. Con Repeats 8, Time 1/8 y un Pulse por Step en 1/16, se emiten solo las
   repeticiones que caben antes del Pulse siguiente, y las demás no consumen
   tirada de Probability.
5. Con el último Pulse de la vuelta y sin más Pulses por delante, las
   repeticiones se cortan en el cierre de la vuelta, no en el Cycle siguiente.
6. Con Timing al 66% y Delay a +20%, la tirada arranca en el instante desplazado
   del Pulse y no en la rejilla recta.
7. Con Sustain 100% y Repeats 3, cada repetición dura exactamente su hueco; el
   Pulse sigue durando un Step.
8. Con Probability al 50% y Repeats 3, unas repeticiones suenan y otras no,
   incluidas las de Pulses callados; con la misma semilla, la misma secuencia.
9. **Con Repeats 0, la salida es byte a byte la de antes de la rebanada**:
   instantes, velocities, gates y consumo de aleatoriedad.
10. Los cuatro knobs mueven su parámetro en el iPad con el BeatStep Pro, con
    valor grande transitorio y cambio audible en el Step siguiente.
11. Temp y Ctrl All mueven los cuatro y los devuelven al soltar.
12. `Engine` ≥90%, `MIDI` ≥80%, y `_isPOD(Cycle.self)` sigue pasando.

## Out of Scope

- **Repeats por encima de 8, y el «infinito» del tope de la Pre Spec.**
- **Modos Choke y Tail.** Cada repetición emite su note-on y su note-off; con
  Sustain alto se solapan y el note-off de una apaga a la siguiente. Ver *Known
  Limitations*.
- **Que cada repetición avance el pool tonal** (FR11).
- **Swing dentro de la tirada** (FR10).
- **Dibujar las repeticiones en el anillo** (FR15).
- **Un selector Probability «Pulses / All notes».** Se entrega «all notes» fijo,
  que con Repeats en 0 es indistinguible de lo de hoy.
- **Random Modulation sobre Repeats y Time** («Random Rate» en la tabla de la Pre
  Spec): no hay Random Modulation en el producto todavía.
- **Persistencia.** No existe (rebanada 4 de la v2, por planificar).
- **Medición de jitter** (NFR6).

## Known Limitations

- **El solape no se vigila, y ahora hay más sitios donde ocurre.** Es la
  limitación aceptada de `NoteEmitter` —rastrear notas pendientes exigiría estado
  mutable en tiempo real— ampliada a las repeticiones. Con Sustain por encima del
  100% y Repeats altos, una repetición apaga a la siguiente. FR12 la acota: con
  Sustain ≤100% no ocurre entre repeticiones.
- **La rejilla la sigue fijando la `MusicalTimeline` de Play.** Time se calcula
  contra la duración del Step, así que hereda la limitación conocida de Division:
  dos Cycles con Divisions distintas suenan sobre la rejilla del que estuviera
  vigente al pulsar Play, y con ella cambia el hueco de Time.
- **Un Pace positivo alto entrega menos repeticiones de las pedidas** (FR8/FR9).
  Es visible en el sonido y no hay aviso en pantalla.
