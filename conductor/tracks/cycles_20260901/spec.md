# Spec — v2 rebanada 3: Cycles, el Track varía por vuelta

**Track ID:** `cycles_20260901`
**Track type:** Feature

## Overview

Hasta hoy un Track tiene un juego de parámetros y lo repite idéntico hasta que
alguien gira un knob. Esta rebanada le da **desarrollo en el tiempo sin
intervención**: un Track puede tener de 1 a 16 **Cycles** —versiones completas de
sus ajustes— y avanza por ellos a cada vuelta del anillo. Es la A/B/C de la Pre
Spec: desarrollo estructurado sin duplicar el Pattern y sin escribir una nota.

Es la última de las cuatro capas del motor que describe `product.md`. Shape
decide *cuándo*, Tonal *qué alturas*, Groove *cómo se interpreta* y **Cycles
aporta el desarrollo**. Las tres primeras están entregadas desde la v1; ésta es
la que hace que una secuencia deje de ser un loop.

**El núcleo es un cambio de vocabulario que arrastra al modelo.** Lo que hoy se
llama `Track` —Shape, pool, marco tonal, Groove y canal— es lo que la Pre Spec
llama **Cycle**: «snapshot de parámetros de un Track». El `Track` pasa a ser el
contenedor: dieciséis Cycles, cuántos están activos y por cuál va. No es un
renombrado cosmético; es que el nivel donde viven los parámetros baja uno, y con
él bajan el snapshot que cruza al hilo del scheduler, la entrada de control y la
pantalla.

**El avance ocurre en el hilo del scheduler, en el límite de vuelta.** Es la
decisión cara de la rebanada y la que la hace sonar bien: el Cycle cambia
exactamente cuando el anillo cierra, no unos milisegundos después. El precio es
que los dieciséis Cycles de los dieciséis Tracks viajan en el snapshot, que pasa
de 2304 bytes a unos 36 KB.

### Lo que esta rebanada no es

**No es persistencia.** Los Cycles multiplican por dieciséis un estado que sigue
sin poder guardarse. Cerrar la app los pierde, igual que hoy pierde el Track.
Patterns, Banks y Autosave siguen fuera.

**No es Random Modulation.** La Pre Spec usa el Cycle como *unidad de
actualización* del aleatorio —«por Cycle» para Steps, Pulses, Division y
Velocity— y eso es la rebanada que viene después: primero tiene que existir el
Cycle.

**No es copiar Cycles entre Tracks.** Un Cycle nuevo nace copiando el vigente de
su propio Track; mover material de un Track a otro es gestión de contenido y
necesita la pantalla que la rebanada 2 entrega.

### Dependencias

No arranca hasta que estén cerradas:

1. **`multi-track_20260831`, Fase 6** — la medición de jitter con los dieciséis
   sonando y la verificación en dispositivo. Es la referencia contra la que se
   compara ésta; sin ella no hay línea base para el snapshot de 36 KB.
2. **v2 rebanada 2, la UI del handoff** — Cycles necesita mostrar el Cycle en
   curso, y `product.md` lo nombra explícitamente como estado de pantalla.
   Ponerlo en la pantalla de trabajo actual sería construir algo para
   desmontarlo.

## Functional Requirements

### FR1 — Un Track son dieciséis Cycles

El Track pasa a contener dieciséis Cycles de tamaño fijo, cuántos hay activos
(1–16) y por cuál va la reproducción. El **Cycle** lleva lo que hoy lleva el
Track: Shape (Steps, Pulses, Rotate, Division), Tonal (pool, Scale, Root, octava
de los pads), Groove (Velocity, Sustain, Probability, Timing, Delay) y el canal
MIDI.

El canal va dentro del Cycle y no fuera. Es discutible —es ruteo, no material— y
se decide por coherencia: el Cycle es «el juego completo de ajustes» de la Pre
Spec, y partirlo en dos sitios obliga a justificar cada campo por separado. Lo
que evita que un Track salte de canal por vuelta no es la estructura, sino que un
Cycle nuevo nace copiando el vigente.

### FR2 — De 1 a 16 Cycles activos, ajustados en pantalla

Cuántos Cycles recorre un Track se ajusta táctilmente, como Scale, Root y el
canal: es configuración, no material generativo. Por defecto **uno**, que es el
comportamiento de hoy.

### FR3 — Subir el número de Cycles copia el vigente

Un Cycle que empieza a existir nace como copia del Cycle en edición, no vacío ni
por defecto. Es lo que hace que A/B/C se construya tocando: se duplica lo que
suena y se le cambia una cosa.

### FR4 — Cada Track avanza en su propia vuelta

Un Track pasa al Cycle siguiente cuando cierra **su** anillo —sus Steps por su
Division—, no cuando lo cierra otro. Dieciséis Tracks con longitudes distintas
desarrollan a ritmos distintos, y ese desfase es la función. No hay
sincronización posterior, igual que hoy no la hay entre rejillas.

### FR5 — El avance ocurre en el hilo del scheduler

El cursor de reproducción lo mueve el hilo que emite, en el límite de vuelta. El
primer Step de la vuelta nueva ya suena con el Cycle nuevo. No se delega al hilo
principal: eso metería una ventana de retraso justo donde el cambio tiene que ser
exacto.

### FR6 — Play reinicia los dieciséis al Cycle 1

Pulsar Play pone a los dieciséis Tracks en su Cycle 1. Es la promesa de
`tech-stack.md` llevada a Cycles: pulsar Play dos veces reproduce la misma
secuencia, omisiones y desarrollo incluidos.

### FR7 — Dos cursores con nombres distintos: el que suena y el que se edita

- **Cycle en curso:** por dónde va la reproducción. Lo mueve el scheduler.
- **Cycle en edición:** a cuál escuchan los knobs y los pads. Lo mueve el
  knob 10 del BeatStep Pro —libre desde la rebanada 7— sobre el Track
  seleccionado.

Son dos porque hacen falta dos: mientras suena el Cycle A se construye el B, que
es la forma natural de trabajar. Con el transporte parado el knob 10 es lo único
que decide qué se ve y se edita.

### FR8 — Editar edita el Cycle en edición

Los knobs, los pads y las ediciones táctiles mueven el Cycle en edición del Track
seleccionado. Los otros quince Cycles y los otros quince Tracks no se tocan.

### FR9 — Bajar el rango en caliente termina la vuelta

Si el Cycle en curso queda fuera del rango nuevo —de 4 activos, sonando el 3, se
baja a 2— la vuelta en curso se termina con él y el avance siguiente entra en el
rango: sigue por el 1. No se corta un patrón por la mitad. El Cycle en edición,
si queda fuera, se acota de inmediato: eso sí es pantalla, no sonido.

### FR10 — Con un Cycle activo, todo suena como hoy

Un Track con un solo Cycle se comporta exactamente como el Track de la rebanada
1: no hay avance, no hay reinicio audible y el material es el mismo. Es la
condición de no regresión y se comprueba con tests, no de oído.

### FR11 — La pantalla muestra el desarrollo

Del Track seleccionado: cuántos Cycles tiene activos, cuál está en curso y cuál
se está editando. `product.md` ya nombra el «Cycle en curso» como estado de
pantalla.

## Non-Functional Requirements

- **NFR1 — El camino de tiempo real no admite regresión.** Ninguna asignación,
  lock, `await` ni logging nuevos en el hilo del scheduler. El snapshot sigue
  siendo trivial —`_isPOD` extendido al tipo nuevo— y el avance del cursor es
  aritmética de enteros.
- **NFR2 — El coste del snapshot se mide antes de construir encima.** Pasa de
  2304 bytes a ~36 KB por copia y el anillo de cuatro ranuras de `PatternHandoff`
  de 9 KB a ~147 KB. Extrapolando la medición del 2026-08-31 —2,25 KB en 274 ns—
  salen ~4,4 µs contra una ventana de 20 ms, el 0,02%. **Es una extrapolación, no
  una medida**: la primera fase la convierte en un número real. Presupuesto: un
  `load()` por debajo del 1% de la ventana.

  > **Medido el 2026-09-02, y el diseño se queda como está.** El snapshot con los
  > 256 Cycles son **36 992 bytes** y el anillo **147 968**. Un `load()` cuesta
  > **~870 ns**, el **0,0044%** de la ventana —presupuesto: 1%—, medido sobre un
  > tipo de prueba con la forma que tendrá el modelo y una copia del protocolo de
  > ranura del handoff, con 200 000 lecturas por pasada y tres pasadas
  > (848–907 ns).
  >
  > La comparación honesta no es contra los 274 ns del 2026-08-31 —otra máquina y
  > un Track de 112 bytes—, sino contra el snapshot de hoy medido en la misma
  > pasada: **~125 ns**. Así que **16,05× más bytes cuestan 6,9× más tiempo**, no
  > dieciséis: una copia grande amortiza mejor que una pequeña, y la
  > extrapolación lineal era pesimista por un factor de cinco.
  >
  > **Consecuencia: FR5 no cambia.** El avance del Cycle se queda en el hilo del
  > scheduler y se sigue publicando el Pattern entero. Las dos alternativas que
  > el plan tenía escritas para el caso contrario —mover el avance al hilo
  > principal, o publicar por Track— **quedan descartadas aquí y no se vuelven a
  > abrir a mitad de la Fase 3**: harían falta tres órdenes de magnitud de
  > diferencia para que el presupuesto se rozara.
  >
  > Lo que este número **no** dice: es una copia de memoria en `debug` sobre
  > macOS, no jitter en un iPad. El coste real del hilo con los dieciséis
  > avanzando lo mide la Fase 6, que es la que puede bloquear la rebanada. Lo que
  > esta medición descarta es que el **tamaño** sea el problema.
- **NFR3 — El snapshot deja de copiarse una vez por evento.** `Transport.play()`
  llama hoy a `handoff.load()` dentro del cierre de emisión, para leer el canal y
  la Division del Track que emite: una copia del snapshot entero **por nota**.
  Con 2,25 KB pasaba desapercibido; con 36 KB no. Se corrige en esta rebanada,
  que es la que lo vuelve caro.
- **NFR4 — Medición de jitter obligatoria y bloqueante.** Con los dieciséis
  Tracks sonando y los dieciséis avanzando de Cycle. Umbral: máximo < 2 ms,
  σ < 0,5 ms. Referencias: rebanada 6 (máx 0,151 ms, σ 0,009–0,013 ms) y la que
  deje la Fase 6 de `multi-track`. Una regresión bloquea la rebanada.
- **NFR5 — El aleatorio sigue siendo reproducible.** Misma semilla, misma
  secuencia. Cambiar de Cycle no resiembra el generador: Probability es un valor
  del Cycle, el estado del generador es del scheduler, y esa frontera no se mueve.
- **NFR6 — Cobertura:** `Engine` ≥90%, `MIDI` ≥80%.
- **NFR7 — Vocabulario de la Pre Spec.** `Cycle`, `Track`, `Pattern`, `pool`,
  `Scale`, `Root`. El renombrado de `Track` a `Cycle` es precisamente para no
  inventar un sinónimo del concepto que ya tiene nombre.
- **NFR8 — Verificación en dispositivo.** Con el BeatStep Pro y un
  multitímbrico: dos Tracks con longitudes distintas y varios Cycles cada uno,
  desarrollando a ritmos distintos sin desalinearse.

## Acceptance Criteria

**Criterio principal:**

> Un Track con varios Cycles cambia de material al cerrar cada vuelta —sin que
> nadie toque nada— y dos Tracks con longitudes distintas desarrollan a ritmos
> distintos sobre el mismo reloj. El cambio cae en el primer Step de la vuelta,
> no después. El jitter con los dieciséis sonando y avanzando sigue dentro del
> umbral, medido en iPad.

Además:

- [ ] El snapshot con los dieciséis Cycles por Track es trivial, comprobado con
      `_isPOD`.
- [ ] El coste de `load()` está medido y por debajo del 1% de la ventana.
- [ ] Un Track con un Cycle activo suena exactamente como antes de la rebanada.
- [ ] Un Track con N Cycles activos los recorre en orden y vuelve al 1.
- [ ] El cambio de Cycle cae en el primer Step de la vuelta, comprobado sobre el
      índice de Step y no de oído.
- [ ] Cada Track avanza en su propia vuelta: uno de 16 Steps y otro de 12 no
      cambian de Cycle a la vez.
- [ ] Play deja a los dieciséis en el Cycle 1; dos pasadas de Play producen la
      misma secuencia.
- [ ] Subir el número de Cycles copia el vigente; el nuevo suena igual hasta que
      se edita.
- [ ] Bajar el rango con el Cycle en curso fuera de él termina la vuelta y sigue
      por el 1.
- [ ] Editar mueve solo el Cycle en edición del Track seleccionado.
- [ ] El snapshot no se copia una vez por evento emitido (NFR3).
- [ ] **Jitter con los dieciséis sonando y avanzando dentro del umbral**, medido
      en iPad y registrado con su número.
- [ ] `swift test` sobre `Engine` y `MIDI` pasa sin simulador ni hardware.

## Known Limitations

1. **Sin persistencia.** Dieciséis veces más estado que sigue sin poder
   guardarse: cerrar la app pierde los Cycles.
2. **Play reinicia al Cycle 1.** Editar el Cycle 3 con el transporte parado y
   pulsar Play no lo hace sonar hasta la tercera vuelta. Es el precio de la
   reproducibilidad y se elige a sabiendas.
3. **Sin Random Modulation por Cycle.** La Pre Spec usa el Cycle como unidad de
   actualización del aleatorio; eso llega después.
4. **Sin copiar Cycles entre Tracks**, ni reordenarlos, ni borrar uno del medio.
   Bajar el número descarta por el final.
5. **El knob 10 queda ocupado.** Quedan seis libres de los siete que dejó la
   rebanada 7 para Accent, Repeats, Time, Voicing y Range.
6. **Dieciséis por dieciséis es el techo, y está escrito.** El snapshot es de
   tamaño fijo por una razón de tiempo real, no por comodidad.
7. **El renombrado toca casi todo.** `Track` pasa a `Cycle` en `Engine` y en
   `MIDI`: es mecánico, pero es amplio, y los tests existentes se leerán distinto
   aunque midan lo mismo.

## Out of Scope

- Patterns, Banks, Project; Autosave, Save Bank y Backup.
- Random Modulation, LFO, Note Repeater, Harmony, Voicing/Style, Range/Phrase.
- Copiar, mover, reordenar o borrar Cycles arbitrariamente.
- Retrigger, que la Pre Spec relaciona con el reinicio de Random, Range, Accent
  y Voicing.
- Mute y solo por Track.
- MIDI Learn — es la rebanada 8 de la v1 y sigue pendiente.
