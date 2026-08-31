# Spec — MVP rebanada 6: Groove temporal — Timing y Delay

**Track ID:** `mvp-groove-temporal_20260830`
**Track type:** Feature

## Overview

La rebanada 5 entregó la mitad de Groove que cambia **qué** se envía —Velocity,
Sustain, Probability—. Esta entrega la otra mitad: **Timing y Delay cambian
*cuándo***. El corte entre las dos lo hizo la rebanada 5 por riesgo y no por
tamaño, y esta rebanada es la razón: es la primera desde la 3 que mueve
instantes, y por tanto la primera que vuelve a tocar el camino de jitter que
costó validar.

Con ella se cierra el Track generativo completo del MVP. Lo único que queda
después es la rebanada 7 —preset del BeatStep Pro y MIDI Learn—, que no toca el
motor.

### Las tres deudas que paga

**1. La rejilla es uniforme y no puede dejar de serlo.** `MusicalTimeline`
traduce índice de Step a offset multiplicando, y ese offset es el único instante
que existe. No hay ningún punto donde un Step pueda caer en otro sitio que el que
le toca por aritmética.

**2. `nanosecondOffset(forStep:)` ya declara a quién espera.** Su documentación
dice literalmente: *«Admite índices negativos: los usará Delay, que desplaza un
Track entero hacia atrás respecto a la rejilla.»* La capacidad está; nadie la
usa.

**3. La atribución de la σ.** `workflow.md` aceptó no medir en las rebanadas 4 y
5, y dejó escrito el coste: *«la σ sube de forma monótona —9 → 15 → 20 µs— y sin
medir cada rebanada, cuando algo suene mal no se sabrá cuál lo introdujo»*. Esta
rebanada mide obligatoriamente, y su medición recta es también la que cierra ese
intervalo abierto: si sale en línea con 20 µs, las rebanadas 4 y 5 quedan
absueltas sin bisecar nada.

### Las decisiones tomadas antes de planificar

**Sobre los dos parámetros:**

1. **Timing vive en 50–75%, y el 50% es la rejilla recta.** El porcentaje es la
   posición del segundo Step del par dentro del par, que es la convención del
   hardware y del software que ya existe: 50% recto, 66,7% tresillo exacto, 75%
   el extremo (medio Step de retraso). Default 50%.

   El tope de 75% no es estético: **es lo que garantiza que el orden de emisión
   nunca se invierte.** Con medio Step de retraso máximo, un Step desplazado
   nunca alcanza al siguiente.

2. **Delay vive en −100…+100% de la Division**, default 0%. Escala con el tempo y
   con la Division, como Sustain y por la misma razón: expresado en
   milisegundos dejaría de significar lo mismo en cuanto se moviera cualquiera
   de los dos. «Medio Step antes» sigue siendo medio Step a cualquier velocidad.

3. **«Cada segundo Step» es la paridad del índice absoluto de la rejilla**, no de
   la posición en el anillo. El swing es una propiedad del tiempo musical, no del
   patrón: con un número impar de Steps el anillo y la rejilla del swing entran
   en desfase de una vuelta a la siguiente, y eso es lo correcto —es lo que hace
   una caja de ritmos—. Ligarlo al anillo produciría un swing que cambia de
   sentido al girar el knob de Steps.

4. **Los dos desplazamientos se suman.** Timing desplaza los Steps impares;
   Delay desplaza todos. El rango total del desplazamiento de un Step queda en
   **[−1 Step, +1,5 Steps]**.

**Sobre el camino de tiempo real —el núcleo de la rebanada:**

5. **Un evento adelantado no puede pedirse para un instante que ya pasó**, y hoy
   podría. Hay dos sitios donde ocurre y **los dos se resuelven con la misma
   cantidad**, el *presupuesto de adelanto*:

   ```
   presupuesto = max(0, −Delay en nanosegundos)
   ```

   - **En el arranque:** el origen de la rejilla es `Play + presupuesto`. Sin
     esto, el Step 0 con Delay negativo se pediría antes de que existiera el
     transporte.
   - **En régimen:** el horizonte de selección se amplía en el presupuesto. Sin
     esto, `TrackScheduler` —que selecciona por el instante de **rejilla**—
     calcularía cada Step unos 20 ms antes de su rejilla y pediría su emisión un
     Step antes de eso: en el pasado, en cada vuelta.

6. **El presupuesto es dinámico y se lee del snapshot una vez por ventana**, no
   una constante del rango máximo. La consecuencia es la que importa: **con
   Delay ≥ 0 el presupuesto es 0 y no cambia absolutamente nada** —ni latencia de
   arranque, ni horizonte más largo, ni respuesta de knob más lenta—. El coste
   solo lo paga quien pide Delay negativo, y es exactamente lo que pidió.

   Un presupuesto fijo al máximo del rango habría alargado el look-ahead un Step
   entero para todo el mundo, y `product-guidelines.md` exige que un giro se oiga
   «dentro del siguiente step». Esto lo preserva.

7. **El orden de emisión es monótono, y es una invariante con test.** Con
   Timing ≤ 75% y Delay uniforme sobre todos los Steps, ningún Step desplazado
   alcanza al siguiente. No es una propiedad que se observe: es la razón del tope
   de Timing, y se verifica exhaustivamente sobre el rango.

8. **El desplazamiento se aplica donde ya se calcula el offset**, en
   `TrackScheduler`, y la aritmética es de `Engine`: entera, en nanosegundos, sin
   coma flotante, sin asignaciones y sin locks. `NoteEmitter` no se toca — recibe
   un instante y no sabe de dónde salió.

9. **El playhead sigue la rejilla, no el desplazamiento.** El anillo mide tiempo
   musical y `product-guidelines.md` pide que la animación derive del transporte;
   el transporte es la rejilla. La pantalla es el reloj, el oído es el groove.
   Además evita meter la aritmética de Timing y Delay en el camino de dibujo, que
   obligaría a una medición de jitter más por carga visual nueva.

**Sobre lo que hay que medir:**

10. **La medición de jitter es obligatoria y son dos, no una.** La recta, contra
    la referencia de 0,134 ms / σ 0,020 ms de la rebanada 3 —es la regresión y la
    atribución de las rebanadas 4 y 5—; y la desplazada, que es lo que esta
    rebanada tiene que demostrar: **que un instante desplazado se entrega donde
    se pidió, no donde caía la rejilla.**

    El arnés compara lo pedido contra lo entregado, así que mide el desplazamiento
    sin saber que existe. Lo que le falta hoy es poder correr con un Groove que
    no sea el default: eso entra en esta rebanada.

## Functional Requirements

### FR1 — Timing desplaza cada segundo Step

Un porcentaje 50–75% por Track, default 50%. Es la posición del segundo Step del
par dentro del par: al 50% la rejilla es recta y ningún Step se mueve; al 66,7%
el par es un tresillo; al 75%, el máximo, el Step impar cae medio Step tarde.

Los Steps pares nunca se mueven por Timing. La paridad es la del índice absoluto
de la rejilla, no la de la posición en el anillo (decisión 3).

### FR2 — Delay desplaza el Track entero

Un porcentaje −100…+100% de la Division, default 0%. Positivo arrastra la voz,
negativo la empuja por delante de la rejilla. Se aplica a **todos** los Steps por
igual, se sumen o no al desplazamiento de Timing.

### FR3 — Los dos desplazamientos se suman, y no invierten el orden

El desplazamiento de un Step es la suma de los dos. Sobre cualquier combinación
del rango, **la secuencia de instantes de emisión es monótona no decreciente**:
ningún Step se emite antes que su predecesor.

### FR4 — Ningún evento se pide para un instante que ya pasó

Ni en el arranque ni en régimen, con cualquier combinación de Timing y Delay,
incluido Delay −100%. El mecanismo es el presupuesto de adelanto de la decisión 5,
aplicado en los dos sitios.

El recorte a cero que hoy hace `SchedulerThread` (`max(0, offset)`) se conserva
como red de seguridad, y su documentación pasa a decir cuál es el único caso que
puede dispararlo: bajar el Delay a negativo **mientras suena**, que mueve un
presupuesto que el origen ya no puede acompañar.

### FR5 — Con Delay ≥ 0 no cambia nada de lo que ya funciona

Presupuesto 0: mismo origen de Play, mismo horizonte de 20 ms, misma latencia de
knob. Es la mitad del rango donde vive el default, y no puede pagar el coste de
la otra mitad.

### FR6 — Los dos se ajustan con knobs

Timing y Delay son parámetros generativos, así que van del lado del knob
(`product-guidelines.md`). Cada uno se frena en sus extremos, como los cinco
anteriores: son escalas con principio y fin.

### FR7 — `TrackParameter` cubre los nueve

Se añaden `.timing` y `.delay` a los siete existentes, en la familia Groove, con
sus dos CC en el bloque contiguo (77 y 78). El comportamiento de los siete
anteriores no cambia y sus tests siguen verdes sin reescribirse.

`TrackParameter` documenta hoy que «Timing y Delay llegan en la rebanada 6»; esa
frase se retira al cumplirse.

### FR8 — Los dos se ven en pantalla

Se leen en el estado persistente con el acento cromático de la familia Groove, y
girar cualquiera de los dos levanta el valor grande transitorio, con el anillo
siempre visible debajo.

El playhead **no** refleja el desplazamiento (decisión 9).

### FR9 — El arnés de medición puede correr desplazado

`JitterHarness` acepta el Groove con el que medir, conservando el default actual.
Sin eso, la medición que esta rebanada necesita —que el desplazamiento se entrega
donde se pidió— no se puede expresar.

Su modo `everyStep` sigue usando el Groove default, que ahora es también la
rejilla recta: la medición de regresión no cambia de forma.

### FR10 — El camino de tiempo real no engorda

`Track` sigue siendo trivial: Timing y Delay son enteros dentro de `Groove` y
`_isPOD(Track.self)` sigue en verde. Calcular el desplazamiento y el presupuesto
no asigna, no toma locks y no espera; aritmética entera, sin coma flotante.

### FR11 — Lo entregado sigue en pie

Transporte, anillo, playhead, valor transitorio, pool tonal, Scale y Root,
Velocity, Sustain, Probability, selección de dispositivo y el estado de solo
lectura siguen funcionando. Sin controlador conectado los dos parámetros nuevos
no se editan —son material generativo— pero se leen.

## Non-Functional Requirements

- **NFR1 — Realtime safety.** El cálculo del desplazamiento y del presupuesto
  corren en el hilo del scheduler: sin asignaciones, sin locks, sin `await`, sin
  logging. Marcador `/// Realtime:` en todo lo que corra ahí.
- **NFR2 — `Track` sigue siendo trivial.** `_isPOD(Track.self)` sigue en verde
  con los dos parámetros nuevos dentro de `Groove`.
- **NFR3 — Medición de jitter obligatoria, y son dos.** *(Enmendado el
  2026-08-30: solo se ejecuta la recta. Ver la enmienda de la Fase 6 en
  `plan.md`.)* Es el caso que
  `workflow.md` nombra explícitamente: *«Swing (Timing), Delay y cualquier
  parámetro que desplace eventos respecto a la rejilla.»* Recta contra la
  referencia de la rebanada 3, y desplazada contra lo pedido. En dispositivo,
  nunca solo en simulador. Una regresión bloquea la tarea.
- **NFR4 — Verificación en dispositivo, sí.** El swing se juzga con el oído: el
  criterio de cierre es que suene musical con el BeatStep Pro y un sintetizador
  real.
- **NFR5 — Cobertura:** `Engine` ≥90%, `MIDI` ≥80% (medida en un solo proceso y
  filtrando `Engine/Sources`, según las dos ampliaciones de `workflow.md`).
- **NFR6 — La lógica no vive en `App`.** El rango, el acotado al girar, la
  aritmética del desplazamiento y el presupuesto son `Engine`; su aplicación al
  instante es `MIDI`. `App` cablea y dibuja.
- **NFR7 — Vocabulario de la Pre Spec.** `Timing`, `Delay`, `Groove`. Sin
  sinónimos: no se introduce `swing` ni `shuffle` como término de código o de
  pantalla donde el dominio dice `Timing`, ni `offset` donde dice `Delay`.
  «Swing» se usa para explicar, nunca para nombrar.

## Acceptance Criteria

**Criterio principal:**

> Con el transporte corriendo, subir Timing convierte la línea recta en swing
> —tresillo reconocible al 66,7%— y girar Delay adelanta o atrasa la voz entera
> contra el pulso, los dos audibles y sin que el jitter se degrade respecto a la
> rebanada 3.

Además:

- [ ] Timing 50% deja **todos** los instantes exactamente donde los deja hoy la
      rejilla, comparado contra `MusicalTimeline` y no contra números escritos a
      mano.
- [ ] Timing 66,7% coloca el par en proporción 2:1, y 75% deja el Step impar
      medio Step tarde.
- [ ] Los Steps pares no se mueven nunca por Timing.
- [ ] La paridad es la del índice absoluto: con Steps impares, el swing y el
      anillo desfasan de una vuelta a la siguiente, y eso está fijado por un test.
- [ ] Delay 0% no mueve nada; +100% atrasa un Step entero; −100% lo adelanta.
- [ ] Delay se aplica a todos los Steps por igual, con y sin Timing.
- [ ] **La secuencia de instantes de emisión es monótona no decreciente**, sobre
      un barrido exhaustivo del rango de los dos parámetros.
- [ ] Ningún offset pedido cae por detrás del instante de arranque, con Delay
      −100% y en cualquier tempo y Division del rango.
- [ ] Con Delay ≥ 0 el presupuesto es 0: mismo origen y mismo horizonte que hoy,
      verificado y no supuesto.
- [ ] `_isPOD(Track.self)` sigue en verde.
- [ ] Girar cada uno de los dos knobs se frena en sus extremos y publica un
      snapshot; girar contra un extremo no publica nada.
- [ ] `TrackParameter` cubre los nueve y los tests de los siete anteriores pasan
      sin reescribirse.
- [ ] La pantalla muestra los dos con el acento de Groove y su valor grande
      transitorio; el playhead sigue avanzando regular.
- [ ] **Medición recta en iPad:** en línea con 0,134 ms / σ 0,020 ms de la
      rebanada 3. Registrada en la git note.
- [ ] **Medición desplazada en iPad:** con Timing 66,7% y con Delay ±50%, la
      desviación contra lo pedido está en el mismo orden que la recta. Registrada
      en la git note.
- [ ] `swift test` sobre `Engine` y `MIDI` pasa sin simulador ni hardware.

## Known Limitations

1. **Delay negativo retrasa el arranque.** El origen de la rejilla es
   `Play + presupuesto`, así que con Delay −100% pulsar Play tarda un Step entero
   en sonar. Es proporcionado —y a 1/16 y 120 BPM son 125 ms, imperceptibles—
   pero en Divisions muy lentas es visible: 1/1 a 20 BPM son 12 segundos. Es el
   precio literal de lo que se pidió, y se prefiere a recortar el rango del
   parámetro o a meter outliers en el arranque.
2. **Bajar el Delay a negativo mientras suena produce un salto de una ventana.**
   Los Steps que ya estaban a punto de calcularse pasan a necesitar un instante
   que el origen no puede acompañar, y se recortan una vez. Acotado a los ~20 ms
   siguientes al giro y solo en ese sentido del knob; subirlo no tiene el
   problema.
3. **El solape de Sustain empeora con Timing.** Un Step adelantado por swing
   acorta su hueco con el siguiente, así que el corte que la rebanada 5 documentó
   como limitación 1 aparece con Sustain más bajos. Mismo defecto, mismo arreglo
   pendiente, umbral distinto.
4. **Sin Timing como modulación por nota.** La Pre Spec lo lista como destino de
   Random Modulation —«varía delay distinto por nota del acorde»—, que exige
   Random Modulation y polifonía, las dos fuera de v1.
5. **Delay se mide contra la rejilla, no contra otros Tracks.** La Pre Spec lo
   describe como «mueve toda la voz contra el resto del Pattern» y en v1 hay un
   solo Track: el efecto es real contra el hardware externo, y su sentido pleno
   llega con varios Tracks.
6. **Sin persistencia.** Los dos valores se pierden al cerrar la app, como todo
   lo demás hasta que exista Autosave.
7. **El mapeo de los CC es fijo y provisional.** MIDI Learn llega en la
   rebanada 7.

## Documented Deviations

Una nota fechada en `tech-stack.md`, escrita **antes** de implementar, según el
paso 8 del Task Workflow:

1. **El horizonte de look-ahead deja de ser constante.** `tech-stack.md` dice que
   «la ventana de look-ahead se equilibra contra la respuesta al knob: un giro
   debe oírse en el step siguiente, así que esa latencia acota el tamaño de la
   ventana». Con Delay negativo el horizonte de **selección** crece en el
   presupuesto de adelanto, y con él la latencia de knob. La nota registra la
   razón —un evento adelantado tiene que calcularse antes de su instante— y el
   límite del coste: el presupuesto es dinámico, así que con Delay ≥ 0, donde
   vive el default, la ventana no cambia.

   La misma nota recoge que el origen de la rejilla deja de ser el instante de
   Play y pasa a ser `Play + presupuesto`.

## Out of Scope

- Accent y la forma/LFO de la variación de velocity — fuera de v1 por
  `product.md`.
- Repeats, Time, Ramp y Pace (Note Repeater).
- Random Modulation sobre Timing, LFO y Cycles.
- La mitad counter-clockwise de Probability y los botones de fase 8/16.
- El playhead desplazado y cualquier representación visual del swing en el
  anillo.
- Corregir el solape de Sustain — sigue siendo la limitación conocida de la
  rebanada 5.
- Preset del BeatStep Pro y MIDI Learn — rebanada 7.
- Persistencia, Autosave y Backup Project.
- Múltiples Tracks, Patterns y Banks.
