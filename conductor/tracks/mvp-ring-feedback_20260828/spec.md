# Spec — MVP rebanada 3: Anillo, playhead y valor transitorio

**Track ID:** `mvp-ring-feedback_20260828`
**Track type:** Feature

## Overview

`ContentView` es hoy una lista de texto que su propia documentación declara
provisional: *«Ni anillo circular, ni overlay de valor grande, ni acentos por
familia: eso llega en el track de UI.»* Este es ese track.

El principio rector de `product-guidelines.md` es **el controlador es el
instrumento; la pantalla es el espejo**. Hoy no hay espejo: hay un informe. La
diferencia importa porque las dos cosas que el documento exige leer a un metro
—dónde está el tiempo y qué dispara, y el valor grande al girar un knob— no
existen ninguna de las dos.

**No toca el motor.** Steps, Pulses, Rotate y Division ya están en `Engine` con
cobertura del 100%, publicados en caliente y movidos por knobs reales. Esta
rebanada solo los mira. Es deliberado: entra entre dos rebanadas de motor
—Tonal y Groove— para que aquéllas se desarrollen viendo el patrón en vez de
leyendo `Steps 16 · Pulses 5`.

**Cierra una deuda de medición.** `product.md` dejó anotado tras la rebanada 1:
*«la σ sube con el tempo; conviene volver a mirarlo cuando exista el anillo
circular, que es la carga visual que aún falta.»* El anillo redibujándose a
velocidad de refresco es la última carga que el jitter no ha visto.

### El problema que no es de dibujo

Un anillo estático es trivial. **El playhead no lo es.** El scheduler corre en
su propio hilo a prioridad máxima, sin locks ni asignaciones, y la interfaz
necesita saber en qué Step está a velocidad de refresco. Hoy no hay ningún
camino de vuelta: `TrackHandoff` publica del control al scheduler, y esta
rebanada necesita lo contrario.

Ese camino de vuelta **no puede costarle nada al scheduler**. Es el mismo
compromiso que la rebanada 1 resolvió en la otra dirección, y se resuelve con
las mismas reglas: un valor que el scheduler escribe sin bloquearse y la interfaz
lee sin bloquearlo.

### Qué se toma del handoff y qué no

El [handoff](../../../design_handoff/README.md) describe la pantalla 1 con
anillos concéntricos para cinco Tracks, pestañas de familia SHAPE/GROOVE/TONAL y
una fila de selectores de Track. **Nada de eso aplica todavía**: hay un Track y
una sola familia con parámetros reales. Se toma lo que tiene sentido con lo que
existe —el anillo como representación del patrón, el readout grande, el acento
verde de Shape— y se deja el resto para cuando haya material que poner debajo.

El handoff es además **lofi declarado**: layout, estructura e interacción son
vinculantes; color, espaciado y tipografía son ilustrativos.

## Functional Requirements

### FR1 — El anillo representa el patrón

Los Steps se disponen como posiciones sobre un círculo y los Pulses se marcan
sobre ellas. Cambiar Steps, Pulses o Rotate con el knob se ve en el anillo
inmediatamente.

`Rotate` se lee **literalmente como una rotación** del anillo: el gesto y su
representación coinciden. No se redibuja como un patrón distinto en la misma
posición.

### FR2 — El playhead sigue al reloj

Una marca recorre el anillo indicando el Step en curso, y vuelve al completar la
vuelta. Su movimiento deriva del transporte, nunca de un temporizador propio de
la interfaz: si el transporte está parado, el playhead no se mueve.

Con el transporte corriendo, la posición mostrada corresponde al Step que está
sonando. Un desfase de un fotograma es aceptable; uno de un Step no lo es.

### FR3 — El playhead no le cuesta nada al scheduler

Publicar la posición no introduce asignaciones, locks, `await`, logging ni
llamadas a la interfaz en el hilo del scheduler. La interfaz lee sin bloquear al
scheduler, y no leer a tiempo no puede atrasarlo ni hacerle perder un Step.

### FR4 — Valor grande transitorio

Al girar un knob, el valor del parámetro afectado aparece en grande y se
desvanece tras la inactividad. **Se dibuja sobre el anillo, que permanece
siempre visible bajo él y nunca se oculta**: nunca se sustituye el contexto por
el detalle.

Debe leerse a un metro, lo que obliga a tipografía muy grande y jerarquía muy
marcada.

### FR5 — Acento cromático de la familia

Shape tiene su acento y se usa de forma consistente: el color codifica **qué
tipo de parámetro es**, nunca decora. Se declara como token en un solo sitio,
para que Tonal y Groove añadan el suyo sin tocar lo ya escrito.

Fondo oscuro y alto contraste, que en este producto son requisito de uso.

### FR6 — El estado de la rebanada 2 no se pierde

Transporte, destino, fuente de entrada y estado de solo lectura siguen visibles
y operativos. La pantalla gana el anillo; no pierde lo que ya informaba.

### FR7 — Sin controlador sigue habiendo espejo

El anillo y el playhead se ven igual sin controlador conectado: son estado, no
edición. El overlay de valor transitorio simplemente no se dispara, porque nadie
gira nada.

## Non-Functional Requirements

- **NFR1 — Realtime safety.** El bucle del scheduler sigue sin asignar, sin
  locks, sin `await` y sin logging. Verificable por revisión, y la publicación
  de la posición lleva el marcador `/// Realtime:` como el resto del camino.
- **NFR2 — Sin regresión de jitter, medida en dispositivo.** Con el anillo y el
  playhead dibujándose, sobre iPad real: máx < 2 ms y σ < 0,5 ms. Se compara
  contra la referencia de la rebanada 1 —máx 0,127 ms, σ 0,015 ms— y **se
  registra el número**, cumpla o no. Es el criterio que da sentido a la
  rebanada.
- **NFR3 — La lógica no vive en `App`.** `workflow.md`: *«si algo en `App`
  merece un test, está en el sitio equivocado.»* La geometría del anillo y la
  posición del playhead se calculan donde se pueden testear —`Engine` y `MIDI`—
  y `App` solo dibuja lo que le dan.
- **NFR4 — Cobertura:** `Engine` ≥90%, `MIDI` ≥80%.
- **NFR5 — Legibilidad a un metro** del playhead, los pulsos activos y el valor
  transitorio. Verificado en dispositivo, no en el simulador ni en el preview.
- **NFR6 — El movimiento deriva del reloj.** Ninguna animación que no comunique
  tiempo musical. Es un antipatrón declarado.

## Acceptance Criteria

**Criterio principal:**

> Con el transporte corriendo, el playhead recorre el anillo en sincronía con lo
> que se oye, y girar un knob cambia el anillo y muestra el valor grande sin que
> el anillo desaparezca.

Además:

- [ ] Las posiciones del anillo y los Pulses marcados salen de `Engine` y están
      cubiertas por tests, incluidos los casos de la Pre Spec (16/4, 16/5, 12/7).
- [ ] Rotate desplaza la marca sobre el anillo de forma coherente con el gesto.
- [ ] Con el transporte parado el playhead no se mueve.
- [ ] La publicación de la posición no añade asignaciones ni locks al hilo del
      scheduler — revisión explícita registrada en la tarea.
- [ ] El overlay aparece al girar, se desvanece por inactividad y **nunca**
      oculta el anillo.
- [ ] Sin controlador conectado, anillo y playhead siguen funcionando.
- [ ] Jitter medido en iPad **con el anillo corriendo**, comparado contra la
      referencia de la rebanada 1 y registrado en la git note.
- [ ] Legibilidad a un metro verificada en dispositivo.
- [ ] `swift test` sobre `Engine` y `MIDI` pasa sin simulador ni hardware.

## Known Limitations

1. **Un solo anillo.** El handoff dibuja cinco concéntricos para cinco Tracks;
   hay un Track. Los concéntricos entran cuando entren los Tracks.
2. **Una sola familia con acento.** Groove y Tonal tendrán el suyo cuando
   existan sus parámetros. El token queda preparado, no poblado.
3. **Steps 1–16.** El comportamiento del anillo por encima de 16 —densidad, no
   rejilla— se decide cuando exista el rango amplio.
4. **Lenguaje visual no final.** El handoff es lofi por declaración propia. Esta
   rebanada fija estructura e interacción; el acabado se revisa después.

## Out of Scope

- Tonal y Groove, y la representación paralela del pool.
- Las otras cuatro pantallas del handoff: Scale & Root, mapeo MIDI, Banks y el
  navegador Track×Pattern.
- Pestañas de familia y selector de Track.
- Preset del BeatStep Pro y MIDI Learn.
- Persistencia, Autosave y Backup Project.
- Múltiples Tracks, Patterns, Banks y Cycles.
