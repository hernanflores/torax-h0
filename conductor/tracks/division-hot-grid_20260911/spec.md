# Spec — La Division no mueve la rejilla mientras suena

## Overview

**Girar el knob de Division con el transporte corriendo no cambia la velocidad
de la línea.** Cambia la duración de la nota, y nada más. En un instrumento
tonal con notas sostenidas eso se oye —y por eso el defecto pasó desapercibido—;
en una pista rítmica de one-shots percusivos la duración del note-on es
irrelevante, así que el knob parece muerto. Fue el caso desde el que se reportó.

**La rejilla de cada Track se congela al pulsar Play.** `PatternScheduler.init`
construye un `MusicalTimeline` por Track leyendo `cycle.shape.division` una sola
vez (`PatternScheduler.swift:102`), y `TrackScheduler` guarda ese timeline dentro
del `LookAheadScheduler` (`TrackScheduler.swift:269`) y su
`stepDurationNanoseconds` como `let` (`:204`, `:271`). El refresco en caliente
—`refresh(with: Track)`, `:309`— sustituye **solo el material**: ni el timeline
ni la duración de Step se recalculan nunca. Nada más en el camino caliente lo
hace.

**El gate, en cambio, sí sigue a la Division.** `Transport.swift:699` reconstruye
por nota `MusicalTimeline(tempo:division: source.shape.division)` con el snapshot
vigente para pasarle el `stepDurationNanoseconds` al `NoteEmitter`. De ahí la
asimetría exacta que se oye: **la longitud de la nota obedece al knob y el
espaciado de los Steps no**. Las dos mitades del mismo valor viven en sitios
distintos y solo una se actualiza.

**No es un defecto de la Division, es un defecto de la rejilla.** Cada Cycle de
un Track tiene su propio `Shape` y por tanto su propia Division, así que el
avance de Cycle en el límite de vuelta —`advanceCycleIfTheTurnClosed`— tiene el
mismo problema por otra puerta: **un Cycle 2 en 1/8 suena hoy sobre la rejilla
del Cycle 1**. Es la misma causa y se arregla de una vez: la rejilla pasa a ser
función del material vigente, no del material que hubiera al pulsar Play.

**Nadie lo probó.** No existe ni un test que cambie la Division a mitad de
reproducción; los cincuenta y pico que la mencionan la fijan en el `init`. El
mecanismo hizo siempre lo que sus tests le pedían.

**Y el anillo tiene que enterarse.** `Playhead.forEachTrack` calcula la posición
como `elapsed mod (stepDuration × steps)` con la Division vigente
(`Playhead.swift:44`), o sea **asumiendo esa rejilla desde el origen de Play**.
Hoy eso es correcto porque la rejilla nunca cambia; en cuanto cambie, el dibujo
mediría desde un origen y el sonido desde otro. El propio archivo tiene escrita
la invariante que eso rompería —«lo que se ve y lo que suena no pueden
discrepar»—, así que el ancla no es solo del scheduler: la interfaz mide con la
misma.

## La pieza que falta: una rejilla con ancla

`MusicalTimeline.nanosecondOffset(forStep:)` multiplica el índice de Step por la
duración de Step, siempre contra el origen de Play. Es lo que garantiza que no
haya deriva —y eso no se toca—, pero **no sabe expresar «de aquí en adelante, los
Steps duran otra cosa»**: cambiarle la Division a una timeline así recalcularía
también todo el pasado, y el Step siguiente saltaría a un instante que no tiene
nada que ver con el que se estaba tocando.

Lo que falta es un **ancla**: un índice de Step y el instante que ese Step tenía
bajo la rejilla anterior. A partir de ahí, la rejilla nueva mide desde el ancla
con la duración nueva. El pasado queda como sonó y el futuro obedece al knob.

## Functional Requirements

### La rejilla sigue al material

- **FR1.** La rejilla de un Track es función de la Division del **material
  vigente** —`material.cycle?.shape.division`—, no de la que hubiera al
  construir el scheduler.
- **FR2.** Un cambio de Division se aplica **de forma inmediata**, en la
  siguiente ventana del scheduler, como el resto de los knobs
  (`product-guidelines.md`: «siempre un cambio inmediato y proporcional»). No se
  cuantiza a límite de vuelta ni de compás.
- **FR3.** El cambio llega por las dos vías, con el mismo mecanismo:
  - **El knob**, que entra por `refresh(with: Track)` una vez por ventana.
  - **El avance de Cycle**, cuando el Cycle entrante declara otra Division.
- **FR4.** Los eventos **ya sellados** en la ventana en curso no se reescriben.
  El cambio es audible en la ventana siguiente, hasta 20 ms después del gesto —
  el mismo retardo que ya tiene cualquier otro knob, y por debajo del umbral de
  la Pre Spec.

### Qué se conserva al cambiar

- **FR5.** **Se conserva la posición en el anillo.** El Track sigue en el mismo
  índice de Step; `turnStartStep`, el cursor de Cycles y la marca de agua del
  `LookAheadScheduler` no se reinician. Girar el knob no devuelve el desarrollo
  al principio.
- **FR6.** **Se conserva la continuidad temporal en el corte.** El Step que abre
  la rejilla nueva cae exactamente en el instante que le tocaba bajo la rejilla
  anterior; a partir de ahí se mide con la duración nueva. El Step en curso acaba
  cuando le tocaba: ninguno se acorta a la fuerza, se duplica ni se salta.
- **FR7.** **Se preserva el invariante del `LookAheadScheduler`**: sobre llamadas
  sucesivas, cada Step se emite exactamente una vez y los rangos nunca
  retroceden. Reanclar no es excusa para repetir una nota ni para perderla, y el
  cambio de rejilla no puede producir un offset anterior al horizonte ya
  entregado.
- **FR8.** Dos Tracks que giran el knob en momentos distintos **pueden quedar
  desfasados entre sí**, y es la consecuencia aceptada de FR6. La promesa de
  `PatternScheduler.init` —«el origen es el mismo para los dieciséis, y por eso
  dos Divisions distintas caen en fase»— sigue valiendo en Play y deja de valer
  para un Track reanclado. Ver *Known Limitations*.

### Lo que se ve

- **FR9.** **El anillo mide con el mismo ancla que el sonido.** El playhead de
  un Track reanclado se dibuja contra su ancla —índice de Step e instante— y no
  contra el origen de Play, de modo que la invariante que `Playhead.swift` tiene
  escrita sigue siendo cierta: lo que se ve y lo que suena no discrepan.
- **FR10.** El ancla vigente de cada Track se publica **desde el hilo del
  scheduler sin locks**, con la forma que ya usa `CyclePlaybackClock` para el
  cursor de Cycles. No se relee el snapshot ni se calcula nada en el hilo de
  tiempo real que no estuviera ya calculado.
- **FR11.** Un Track que no ha cambiado de rejilla se dibuja exactamente como
  hoy: su ancla es el origen de Play y el cálculo es el de siempre.

### El overlay: Temp y Ctrl All

- **FR12.** **Division se superpone como cualquier otro parámetro.** Temp iguala
  el valor absoluto en todos los Cycles activos y lo restaura al soltar; Ctrl All
  lo aplica a los dieciséis Tracks. Con la rejilla siguiendo al material, un fill
  de Division por Temp **suena** —que es el uso en directo que este arreglo
  desbloquea— y soltar devuelve la rejilla anterior.
- **FR13.** Un gesto de Temp son **dos reanclajes**, el de la pulsación y el de
  la soltada, y los dos cumplen FR6 y FR7: ni al entrar ni al volver se pierde,
  se duplica ni se adelanta un Step. Ctrl All son hasta dieciséis reanclajes en
  la misma ventana, y también.
- **FR14.** Soltar el Temp **no devuelve la fase al origen de Play**. La rejilla
  vuelve a la Division anterior anclada al instante de la soltada, que es lo
  coherente con FR6: el gesto no rebobina el desarrollo.

### Lo que se arregla de paso, porque es la misma causa

- **FR15.** **La ventana de corte de las repeticiones deja de ser incoherente.**
  Hoy `TrackScheduler.swift:538` calcula el hueco hasta el Pulse siguiente con el
  `stepDurationNanoseconds` congelado mientras `:540` calcula el hueco base con
  la Division viva: con la rejilla siguiendo al material, los dos lados leen el
  mismo valor. Un Repeats que cabía deja de recortarse —o de desbordarse— por un
  desajuste que el usuario no pidió.
- **FR16.** **El gate y la rejilla dejan de divergir.** El `stepDuration` que
  `Transport.swift:699` recalcula por nota y el que mide la rejilla pasan a ser
  el mismo valor para el mismo Step. Se fija con tests en Sustain 100% —el
  note-off cae justo donde empieza el note-on siguiente— y Sustain 200%, que es
  el solape que el usuario pide a propósito.
- **FR17.** *(Enmendado el 2026-09-11, ver la nota de abajo.)* El `advanceBudgetNanoseconds` de Delay se calcula sobre el
  `stepDuration`, así que cambia de valor al cambiar la rejilla. Este track
  **no** rediseña el origen adelantado de `SchedulerThread`; se limita a no
  romperlo: con Delay ≥ 0 el presupuesto sigue siendo cero, y con Delay negativo
  se comprueba que no se pida ningún evento para un instante ya pasado. La
  revisión de fondo queda fuera de alcance y anotada.

> **Enmienda de FR17, 2026-09-11, con `DelayBudgetDivisionTests` delante.**
> Comprobarlo no bastó: **se rompía**. Con Delay negativo, una Division más
> lenta hace crecer el presupuesto de adelanto. El ancla conservaba el
> instante de **rejilla** del Step del corte, así que su instante de
> **emisión** se adelantaba lo que crecía el presupuesto y caía antes del
> presente: hasta 110 ms con Delay −100% y 1/16 → 1/8. Era un evento por
> cambio, por las dos puertas. Lo decidió el usuario: se arregla aquí.
>
> **El arreglo:** cuando un reanclaje hace crecer el presupuesto respecto al
> que decidió la ventana, el ancla se retrasa lo que crece. El Step del corte
> conserva el instante en que **suena**, que es lo que FR6 protege, y no el
> de rejilla. Con Delay ≥ 0 el presupuesto no crece y el ancla es la de
> siempre. Solo se retrasa la rejilla del Track reanclado, y ese desfase ya
> lo acepta FR8.
>
> **Sigue fuera de alcance** el caso sin reanclaje: girar Delay a negativo
> mientras suena, que es la limitación 2 de la rebanada 6, y el origen
> adelantado de `SchedulerThread`.

### Lo que no cambia

- **FR18.** La vía del arnés —`PatternScheduler(timeline:material:)`, una sola
  rejilla fija— sigue existiendo y sigue midiendo lo mismo: mide la rejilla, no
  el material, y un material sin Cycle no tiene Division que seguir.
- **FR19.** El tempo sigue resolviéndose donde se resuelve hoy, escalando de
  tiempo de rejilla a tiempo de reloj contra el tempo de referencia
  (`clockHandoff.reading.wallNanoseconds(forGridNanoseconds:…)`). Este track no
  toca el seguimiento de un maestro externo.
- **FR20.** El recorrido del knob no cambia: `Division.ordered`, de 1/1 a 1/32,
  frenando en los extremos.

## Non-Functional Requirements

- **NFR1.** **Camino de tiempo real.** El cálculo del cambio de rejilla vive en
  el hilo del scheduler: sin asignaciones, sin locks, sin await, sin arrays
  temporales. Detectar el cambio es una comparación de dos enteros por ventana;
  reanclar es aritmética acotada.
- **NFR2.** **Coste acotado por ventana.** La comprobación se hace una vez por
  ventana y por Track, y una vez más solo cuando el avance de Cycle cambia de
  material. No se recalcula la rejilla por Step ni por nota.
- **NFR3.** **Sin deriva.** La rejilla anclada sigue multiplicando índice por
  duración desde el ancla, nunca acumulando (`t += paso`). El error queda acotado
  a un redondeo por ancla, no uno por Step.
- **NFR4.** **Sin medición de jitter**, por la suspensión del 2026-09-02, que es
  posterior a la excepción de `workflow.md` para cambios en `MusicalTimeline`,
  `LookAheadScheduler` y `SchedulerThread` y no deja excepciones escritas. **Se
  anota el riesgo asumido**: este track es exactamente el caso que aquella regla
  existía para cubrir, así que una regresión de timing aquí se descubriría
  tocando y no en CI. La vuelta atrás está escrita en `workflow.md`.
- **NFR5.** Cobertura: `MIDI` ≥80%, `Engine` ≥90%. **La rejilla anclada vive en
  `Engine`**, junto a `MusicalTimeline`, porque es valor puro y se prueba sin
  CoreMIDI ni hilo; `MIDI` solo decide *cuándo* reanclar. Es el mismo criterio
  que bajó `PatternSlotState` y `PatternPasteRefresh` de la vista.
- **NFR5b.** **La publicación del ancla no puede costar una copia.** Lo que cruza
  al hilo de dibujo son enteros, como el cursor de Cycles, y no un snapshot.
- **NFR6.** **No cambia el formato de disco**: la Division ya se persiste
  (`ProjectRecord.swift:145`) y este track no toca ni el esquema ni
  `schemaVersion`.

## Acceptance Criteria

1. Con el transporte corriendo, girar Division de 1/16 a 1/8 **dobla el tiempo
   entre Steps** en los offsets emitidos, y de 1/16 a 1/32 lo divide.
2. Ese cambio no reinicia nada: el Track sigue en el mismo índice de Step, la
   vuelta no vuelve a empezar y el cursor de Cycles no se mueve.
3. El Step que abre la rejilla nueva cae en el instante que tenía bajo la
   anterior: ningún Step emitido dos veces, ninguno perdido, ninguno con offset
   anterior al horizonte ya entregado.
4. Tras N cambios de Division seguidos, los offsets siguen coincidiendo con el
   cálculo directo desde el último ancla: no hay deriva acumulada.
5. Un Track con dos Cycles de Divisions distintas cambia de rejilla al entrar el
   Cycle nuevo, en el límite de vuelta, sin perder ni repetir Steps.
6. Los quince Tracks restantes no se enteran: cambiar la Division del Track 1 no
   mueve ni un offset de los demás.
7. Con Repeats > 0, la ventana de corte de las repeticiones y el hueco base se
   miden contra el mismo Step: ninguna repetición cae encima del Pulse siguiente
   ni se descarta una que cabía (FR15).
8. Con Sustain 100% sobre la Division nueva, el note-off cae exactamente donde
   empieza el note-on siguiente; con 200%, solapa como corresponde (FR16).
9. Con Delay negativo, ningún evento se pide para un instante ya pasado tras un
   cambio de Division (FR17).
10. El anillo del Track reanclado **sigue marcando el Step que suena**: girar
    Division no deja el playhead adelantado ni atrasado respecto a las notas, y
    un Track que no giró se dibuja exactamente como antes (FR9, FR11).
11. Un Temp sobre Division suena mientras se mantiene y devuelve la rejilla
    anterior al soltar, sin perder ni duplicar Steps en ninguno de los dos
    reanclajes; con Ctrl All, lo mismo en los dieciséis Tracks a la vez (FR12,
    FR13).
12. La vía del arnés sigue construyendo su rejilla fija y midiendo lo mismo.
13. `MIDI` ≥80%, `Engine` ≥90% y la suite entera en verde.
14. **Verificado en iPad con una pista rítmica de one-shots**, que es el caso
    reportado: girar Division mientras suena cambia la velocidad de la línea de
    forma audible e inmediata, sin cortes, sin duplicados y sin que el Track
    salte al principio.

## Out of Scope

- **Revisar el origen adelantado de Delay** (`advanceBudgetNanoseconds` y el
  desplazamiento de origen que `SchedulerThread` calcula una sola vez al
  arrancar) frente a una rejilla que cambia en caliente. Aquí solo se comprueba
  que no se rompe (FR17); el rediseño se anota como pendiente en el registry.
- **Cuantizar el cambio de Division** a límite de vuelta o de compás. Decidido en
  contra: el knob es inmediato como los demás.
- **Medición de jitter** (NFR4).
- **Ampliar `Division.ordered`** con tresillos u otras fracciones. El tipo ya
  admite cualquier fracción positiva; por dónde pasa el knob es otro asunto.
- **Que dos Tracks reanclados vuelvan a ponerse en fase** entre sí, por gesto o
  automáticamente. Ver *Known Limitations*.
- **El tempo y el seguimiento del maestro externo** (FR19).
- **El cursor de edición frente al de reproducción.** Girar un knob edita el
  Cycle **en edición**, que con varios Cycles activos puede no ser el que suena.
  Es de [`cycle-edit-cursor_20260908`](../cycle-edit-cursor_20260908/index.md) y
  no se toca aquí. Ver *Known Limitations*.

## Known Limitations

- **Un Track que cambió de Division queda anclado a su propio corte**, no al
  origen de Play. Dos Tracks en 1/8, si uno llegó ahí girando el knob a mitad de
  compás, pueden no caer en el mismo instante. Es el precio de FR6 —que el cambio
  no salte ni pierda Steps— y se acepta a sabiendas: para volver a alinearlos
  está Play, que reconstruye las dieciséis rejillas contra el mismo origen.
- **El cambio llega hasta 20 ms tarde**, por la ventana de look-ahead (FR4). No
  es específico de este track: es lo que ya ocurre con cualquier knob.
- **Sin medición de jitter** (NFR4), en el track que más la habría justificado.
- **Queda un segundo motivo para que el knob «no haga nada», y este track no lo
  arregla.** Con varios Cycles activos, Division se gira sobre el Cycle en
  edición y el scheduler toca el del cursor de reproducción: si no son el mismo,
  el cambio no se oye hasta que el Cycle editado entre. Se nombra aquí para que
  no se confunda con este defecto al verificar en dispositivo — la prueba del
  criterio 14 se hace **con un solo Cycle activo**. El caso general es de
  `cycle-edit-cursor_20260908`.
- **Con Delay negativo el anillo va por detrás de lo que suena, y más en
  Divisions lentas.** *(Añadido el 2026-09-11, verificando la Fase 5 en el
  iPad.)* No es de este track: es la decisión 9 de la rebanada 6, «el playhead
  sigue la rejilla, no el desplazamiento», y el usuario decidió mantenerla. Con
  Delay −100% el anillo marca el Step anterior al que suena. Como el desfase
  es un Step, girar Division a una más lenta lo alarga en milisegundos: de 125
  a 250 ms al pasar de 1/16 a 1/8 a 120 BPM. Lo que sí era de este track, un
  salto atrás del anillo en el corte, se arregló.
- **Soltar un Temp de Division no rebobina la fase** (FR14): la línea vuelve a su
  velocidad pero no al punto donde habría estado sin el fill. Es coherente con
  FR6 y con cómo se comportan hoy los demás parámetros, que tampoco rebobinan
  nada.
