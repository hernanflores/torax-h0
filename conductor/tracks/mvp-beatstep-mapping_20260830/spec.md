# Spec — MVP rebanada 7: Preset del BeatStep Pro — knobs, pads y step buttons

**Track ID:** `mvp-beatstep-mapping_20260830`
**Track type:** Feature

## Overview

La rebanada 6 cerró el Track generativo completo. Lo que queda de la v1 no es
motor: es **la superficie de control**. Hasta hoy el controlador funciona por
acumulación de decisiones provisionales tomadas para poder seguir adelante, y
esta rebanada las sustituye por un mapeo declarado, verificado en dispositivo y
entregado como artefacto cargable.

**La rebanada 7 se parte en dos.** El registro la definía como «preset del
BeatStep Pro y MIDI Learn»; por decisión del 2026-08-30 este track entrega **solo
el preset**, y MIDI Learn pasa a la rebanada 8. La razón es que las dos cosas no
comparten problema: el preset decide *qué significa cada control físico* —un
problema de dominio musical, que es donde están las decisiones difíciles de esta
rebanada—, y MIDI Learn decide *cómo se reasigna a otro hardware*, que es
infraestructura de entrada y arrastra el defecto `network-session-source`.
Mezclarlas habría metido una investigación de CoreMIDI dentro de una rebanada
cuyo núcleo es la escala.

### Las tres deudas que paga

**1. El mapeo de CC se declara a sí mismo provisional.** `ControlMapping` lo dice
en su propia documentación: *«Es fija y provisional. La sustituyen el preset del
BeatStep Pro y MIDI Learn, que son el track siguiente.»* Los nueve CC del bloque
70–78 son correctos y se conservan; lo que falta es que dejen de ser una tabla
escrita a mano dentro del código y pasen a ser **la mitad de un preset que el
controlador también tiene cargado**, con los otros siete knobs, los pads y los
step buttons definidos junto a ellos.

**2. Los pads son un teclado cromático, y en el BeatStep Pro eso los rompe.**
`ControlInput.toggle(_:)` lee el número de nota entrante como altura y descarta
lo que el marco tonal no admite. Sobre un teclado completo tiene sentido; sobre
dieciséis pads que envían un bloque contiguo de dieciséis semitonos, no:

- **La mayoría de los pads no hace nada.** Dieciséis semitonos contienen siete
  grados de una escala de siete notas. Los otros nueve pads se pulsan y se
  ignoran en silencio — *«no es un error»*, dice el código, y como criterio para
  un CC ajeno es correcto; para el control primario del pool es un pad muerto.
- **El registro alcanzable es un octavo del rango MIDI.** Dieciséis semitonos de
  128. No hay forma de meter en el pool una nota grave ni una aguda.
- **Qué pad da qué nota depende de la Scale y del Root**, y de una manera que no
  se puede aprender: cambiar de Root mueve los pads vivos a otras posiciones.

Es el defecto que este track viene a arreglar, y la razón por la que la solución
no es afinar el filtro sino **cambiar qué es un pad**.

**3. Siete knobs y dieciséis step buttons sin significado.** El BeatStep Pro
tiene dieciséis encoders y el Track tiene nueve parámetros; nadie ha decidido qué
pasa con los otros siete ni con la fila de step buttons. Sin decidirlo, el preset
no se puede escribir, porque un preset no es una lista de asignaciones: es
también la lista de lo que deliberadamente no se asigna.

### Las decisiones tomadas antes de planificar

**Sobre los pads — el núcleo de la rebanada:**

1. **Un pad es un índice, no una altura.** El número de nota entrante deja de
   leerse como `Pitch` y pasa a resolverse a un índice de pad 0–15 restando la
   nota base del preset. La altura la calcula la app a partir del índice, del
   marco tonal y del desplazamiento de octava vigente.

   La consecuencia es la que importa: **qué nota da un pad deja de depender de
   qué nota envía el controlador.** El preset decide la numeración; el dominio
   musical decide el sonido. Son dos cosas y hasta hoy eran una.

2. **Dos bloques de siete, alineados por octava.** Los pads 1–7 son los grados
   1–7 de la escala en la octava base; los pads 9–15 son **los mismos grados una
   octava por encima**. El pad 9 es siempre el pad 1 más doce semitonos, sea cual
   sea la escala y el Root.

   Ese alineamiento es lo que hace que los pads 8 y 16 puedan llamarse *octava*
   sin mentir, y es la razón de la decisión 3.

3. **Una escala de menos de siete grados deja pads inactivos.** Con
   `pentatonic` —cinco grados— los pads 6, 7, 14 y 15 no tienen nota asignada y
   se ignoran, como hoy se ignora un CC sin mapear.

   **Se aparta del requisito de partida** —«no deberíamos tener pads sin notas
   asignadas»— y es una decisión consciente. Rellenarlos siguiendo la escala
   —pad 6 = grado 1 de la octava siguiente— llenaría los dieciséis, pero el pad 9
   dejaría de estar una octava por encima del pad 1: quedaría a dos octavas y una
   tercera, distinto para cada escala. Los pads 8 y 16 pasarían a desplazar algo
   que ya no es una octava y la superficie dejaría de poder aprenderse. Se
   prefiere un hueco visible y estable a dieciséis pads con una relación que
   cambia con la Scale.

4. **Los pads 8 y 16 mueven la superficie, no el pool.** Bajar u subir una octava
   cambia qué nota tiene asignada cada pad **de ahí en adelante**. Las alturas ya
   metidas en el pool no se mueven: `product-guidelines.md` dice que cambiar un
   parámetro nunca destruye material, y transponer el pool bajo los pies del
   usuario es exactamente eso.

   La consecuencia deseada es que la superficie es un **teclado de registro
   móvil**: se baja, se meten dos notas graves, se sube y se meten dos agudas, y
   el pool acumula las cuatro.

5. **La octava base es la de C2 y el grado 1 la ocupa.** Al arrancar, el pad 1 es
   el grado 1 de la escala en la octava de C2 —la que empieza en la nota MIDI
   48—. Con Root en Do el pad 1 es C2 literalmente; con Root en Re es D2. **La
   base es una octava, no una nota fija**, porque el grado 1 es el Root por
   definición y clavar el pad 1 en Do lo desalinearía de la escala.

6. **El desplazamiento se detiene donde el rango MIDI se acaba, sin envolver y
   sin recortar.** Se puede seguir desplazando mientras **todas** las alturas
   asignadas quepan en 0–127; en el extremo, el pad 8 o el 16 deja de responder.
   No hay wrap —un salto de siete octavas en vivo es una sorpresa que nadie
   pidió— ni recorte silencioso, que dejaría dos pads sonando la misma nota sin
   decirlo.

7. **Pulsar un pad sigue siendo alternar la pertenencia al pool.** Lo único que
   cambia es qué altura le toca a cada pad. El pool sigue con capacidad 8, el
   noveno se rechaza sin publicar, y los note-off y los note-on de velocity cero
   siguen sin alternar. Los tests de `PadPoolInputTests` que describen ese
   comportamiento siguen valiendo.

**Sobre los knobs y los step buttons:**

8. **Nueve knobs asignados en el orden de `TrackParameter`, siete libres.** Los
   knobs 1–9 toman Steps, Pulses, Rotate, Division, Velocity, Sustain,
   Probability, Timing y Delay, sobre los CC 70–78 que ya existen y que no se
   mueven: el orden de los CC ya seguía al de `TrackParameter`, y ese es también
   el orden de la pantalla. Los knobs 10–16 quedan sin asignar y se ignoran en
   silencio; su sitio es de v2 —Cycles, Accent, Repeats, Time, Voicing, Range—.

   Scale y Root **no suben a knob**: `product-guidelines.md` los pone del lado
   táctil y esta rebanada no es el sitio para mover esa frontera.

9. **Los step buttons seleccionan Track, y en v1 solo responde el primero.** Se
   implementa la semántica final —step button N selecciona el Track N— y en v1,
   con un solo Track, los otros quince se ignoran en silencio. Es lo que evita
   que el preset tenga que reescribirse en v2: los números del controlador ya
   significan lo correcto, y lo único que falta después es que haya Tracks
   detrás.

**Sobre el preset como artefacto:**

10. **Los números se eligen aquí y se verifican en dispositivo antes de fijarse
    en código.** El preset asigna a los pads un bloque contiguo de dieciséis
    notas y a los step buttons un bloque contiguo de dieciséis CC, y se carga en
    el BeatStep Pro con MIDI Control Center. Lo que el código dé por cierto tiene
    que haberse visto llegar en el iPad primero — es la misma lección que dejó
    escrita la nota del 2026-08-28 sobre los encoders en `Relative #2`, donde una
    suposición sobre el controlador clavó todos los parámetros en su extremo.

11. **El preset se versiona en el repositorio.** Un archivo cargable por MIDI
    Control Center y un README de cómo cargarlo, junto a la tabla de números.
    Sin eso el mapeo es una convención oral y el próximo iPad o el próximo
    BeatStep Pro no lo cumple.

12. **Los LEDs del controlador quedan fuera.** Encender los pads exige SysEx
    propietario de Arturia y un camino de salida MIDI **hacia el controlador**
    que hoy no existe; el feedback vive en la pantalla, que es lo que dicen
    `product-guidelines.md`. Es un track futuro, no un olvido.

## Functional Requirements

### FR1 — El pad se resuelve a índice, no a altura

Un `noteOn` cuyo número caiga en el bloque de pads del preset se convierte en un
índice 0–15. Fuera del bloque se ignora en silencio, con el mismo criterio que un
CC sin mapear.

La altura ya no se lee del mensaje: se calcula. Ningún camino queda en el que el
número de nota entrante llegue a `Pitch`.

### FR2 — La superficie asigna un grado de escala a cada pad

Dados un `TonalFrame` y un desplazamiento de octava, la superficie responde qué
altura tiene cada uno de los dieciséis pads, o ninguna:

| Pad | Contenido |
|---|---|
| 1–7 | Grados 1–7 de la escala, en la octava base |
| 9–15 | Los mismos grados, una octava por encima |
| 8 | Bajar una octava |
| 16 | Subir una octava |

Con una escala de N grados y N < 7, los pads N+1..7 y N+9..15 no tienen altura
asignada. El pad 9 es siempre el pad 1 más doce semitonos.

### FR3 — El grado 1 es el Root, y la octava base es la de C2

Al arrancar, el pad 1 es el grado 1 del marco tonal vigente en la octava que
empieza en la nota MIDI 48. Cambiar el Root mueve la superficie entera con él,
manteniendo la octava.

### FR4 — Los pads 8 y 16 desplazan la superficie una octava

Bajar y subir doce semitonos todas las alturas asignadas. El pool no se toca:
las alturas que ya estaban dentro siguen donde estaban.

### FR5 — El desplazamiento se detiene en el rango MIDI

Se admite mientras **todas** las alturas asignadas queden dentro de 0–127. En el
extremo, el pad correspondiente no hace nada: no envuelve al otro extremo y no
recorta ninguna altura contra el borde.

### FR6 — Pulsar un pad sigue alternando el pool

Un pad con altura asignada la mete o la saca del pool. La capacidad sigue siendo
8 y el noveno se rechaza sin publicar. Los note-off y los note-on con velocity
cero no alternan. Un pad sin altura asignada no publica nada.

### FR7 — Cambiar Scale o Root reencuadra el pool y redibuja la superficie

Sigue valiendo lo de la rebanada 4: el pool se reencuadra, no se vacía. Lo nuevo
es que **la superficie de pads también se recalcula**, porque sus grados salen
del marco. El desplazamiento de octava vigente se conserva.

### FR8 — Nueve knobs con parámetro, siete sin él

Los CC 70–78 mueven los nueve parámetros del Track, en el orden de
`TrackParameter`, con la decodificación relativa que ya existe. Los knobs 10–16
no están asignados y no publican nada. El comportamiento de los nueve no cambia y
sus tests siguen verdes sin reescribirse.

### FR9 — Los step buttons seleccionan Track

Un step button pulsado selecciona el Track de su posición. En v1 solo el primero
corresponde a un Track existente; los otros quince se ignoran en silencio. La
soltada no hace nada, con el mismo criterio que el note-off de un pad.

### FR10 — El mapeo deja de llamarse provisional

`ControlMapping` pasa a describir el preset del BeatStep Pro entero —knobs, pads
y step buttons— y su documentación deja de decir que la sustituye un track
posterior. Lo que sí sigue pendiente es MIDI Learn, y se nombra como tal.

### FR11 — La pantalla muestra la octava de los pads

El desplazamiento vigente se lee en pantalla junto al pool: sin él, pulsar un pad
y no reconocer la nota no tiene explicación visible. Es estado persistente, no
valor transitorio — no lo mueve un knob.

### FR12 — El preset se entrega como artefacto

Un archivo cargable por MIDI Control Center, versionado en el repositorio, más un
README con la tabla completa de números y las instrucciones de carga, incluido el
modo `Relative #2` de los encoders que ya está documentado en `workflow.md`.

### FR13 — Lo entregado sigue en pie

Transporte, anillo, playhead, valor transitorio, pool tonal, Scale y Root, los
nueve parámetros del Track, la selección de dispositivo y el estado de solo
lectura siguen funcionando. Sin controlador conectado la superficie de pads se ve
pero no se edita.

## Non-Functional Requirements

- **NFR1 — La superficie de pads vive en `Engine`.** Qué grado y qué altura le
  toca a cada pad es dominio musical y es donde se puede testear. `MIDI` traduce
  el mensaje a índice; `App` cablea y dibuja. Ningún `switch` de escala en la
  vista.
- **NFR2 — El camino de tiempo real no se toca.** Esta rebanada es entrada, no
  scheduler. `Track` sigue siendo trivial y `_isPOD(Track.self)` sigue en verde.
- **NFR3 — Sin medición de jitter obligatoria.** No cambia ningún instante: no
  toca `MusicalTimeline`, `LookAheadScheduler` ni `SchedulerThread`, y no añade
  carga visual al ritmo del reloj. Es exactamente lo que la nota del 2026-08-28
  de `workflow.md` exime. La medición final de v1 se hace al cerrar la rebanada 8.
- **NFR4 — Verificación en dispositivo obligatoria.** Con el BeatStep Pro real,
  el preset cargado y un sintetizador. Es el criterio de cierre: los números del
  preset no valen hasta verse llegar.
- **NFR5 — Cobertura:** `Engine` ≥90%, `MIDI` ≥80%.
- **NFR6 — Vocabulario de la Pre Spec.** `Pitch`, `pool`, `Scale`, `Root`,
  `Track`. Los nombres del hardware —pad, step button, knob— se usan para el
  hardware y no para el dominio. Sin sinónimos nuevos.
- **NFR7 — Un pad fuera de sitio se ignora en silencio.** Nota fuera del bloque,
  pad sin grado, step button sin Track y CC sin asignar comparten criterio: no
  publican y no son un error. En una sesión real llegan mensajes de todo tipo.

## Acceptance Criteria

**Criterio principal:**

> Con el preset cargado en el BeatStep Pro, los dieciséis pads dan notas de la
> escala en dos octavas alineadas, los pads 8 y 16 mueven el registro entero
> arriba y abajo sin tocar lo que ya está en el pool, y los nueve knobs mueven
> los nueve parámetros — todo verificado en el iPad contra un sintetizador real.

Además:

- [ ] El pad 1 es el grado 1 del marco tonal en la octava de C2: con Root en Do
      es la nota 48, y con Root en Re es la 50.
- [ ] El pad 9 es exactamente el pad 1 más doce semitonos, sobre las cinco
      escalas y los doce Roots.
- [ ] Los pads 1–7 y 9–15 son grados consecutivos de la escala, verificado sobre
      las cinco escalas.
- [ ] Con `pentatonic`, los pads 6, 7, 14 y 15 no tienen altura y pulsarlos no
      publica nada.
- [ ] Pad 16 sube doce semitonos todas las alturas asignadas; pad 8 las baja
      doce. El ejemplo del requisito original —pad 1 en C2 y pad 9 en C3 pasan a
      C1 y C2 tras pulsar el pad 8, y a C3 y C4 tras pulsar el 16— es un test
      literal.
- [ ] Desplazar la octava **no cambia el pool**, verificado con notas dentro.
- [ ] El desplazamiento se detiene antes de que cualquier altura asignada salga
      de 0–127, en los dos extremos, sin envolver y sin recortar.
- [ ] Una nota fuera del bloque de pads del preset no publica nada.
- [ ] Pulsar un pad mete y saca su altura del pool; el noveno se rechaza; el
      note-off y el note-on de velocity cero no alternan. Los tests existentes de
      `PadPoolInputTests` pasan tras adaptarse al índice de pad.
- [ ] Cambiar Scale o Root recalcula la superficie conservando el
      desplazamiento, y el pool se reencuadra en vez de vaciarse.
- [ ] Los nueve knobs mueven sus nueve parámetros y se frenan en los extremos;
      los CC de los knobs 10–16 no publican nada.
- [ ] Un step button distinto del primero no publica nada ni rompe el estado.
- [ ] `_isPOD(Track.self)` sigue en verde.
- [ ] La pantalla muestra la octava vigente de los pads y se lee a un metro.
- [ ] El archivo de preset está en el repositorio y su README describe la tabla
      completa de números y el modo `Relative #2`.
- [ ] **Verificación en dispositivo:** los dieciséis pads, los dieciséis step
      buttons y los dieciséis knobs se pulsan/giran uno a uno con el preset
      cargado, y lo observado coincide con la tabla. Registrada en la git note.
- [ ] `swift test` sobre `Engine` y `MIDI` pasa sin simulador ni hardware.

## Known Limitations

1. **Con pentatónica sobran cuatro pads.** Decisión 3: el alineamiento por octava
   se prefiere al aprovechamiento. Es la desviación consciente del requisito de
   partida.
2. **La escala de más de siete grados no existe todavía, pero el diseño la
   acota.** Las cinco escalas de v1 tienen cinco o siete grados. Una escala de
   usuario cromática —admitida por la Pre Spec y fuera de v1— no cabría en siete
   pads, y esta superficie tendría que decidir qué hacer. Se deja escrito, no
   resuelto.
3. **El pool sigue sin persistencia.** El pool y la octava de los pads se pierden
   al cerrar la app, como todo lo demás hasta que exista Autosave.
4. **Sin MIDI Learn.** El preset es fijo y el hardware distinto del BeatStep Pro
   no se puede acomodar. Es la rebanada 8, y hasta entonces `product.md` promete
   algo que la app no hace.
5. **Sin LEDs en el controlador.** No hay forma de saber mirando el BeatStep Pro
   qué pads están en el pool ni en qué octava está la superficie; hay que mirar
   el iPad. Decisión 12.
6. **Los step buttons no hacen nada visible en v1.** Seleccionar el Track 1 es
   seleccionar el único que hay. La semántica está implementada y no se puede
   comprobar de verdad hasta que haya varios Tracks.
7. **`network-session-source` sigue abierto.** La sesión de red de iPadOS se
   autoselecciona como fuente y el BeatStep Pro hay que elegirlo a mano. No
   bloquea a esta rebanada —basta con seleccionarlo— pero sí a la 8.

## Documented Deviations

Notas fechadas y escritas **antes** de implementar, según el paso 8 del Task
Workflow:

1. **La Pre Spec, línea 70 — los pads dejan de ser un teclado cromático.** Dice:
   *«Al pulsarlo, los 16 Value Buttons se comportan como teclado cromático, pero
   sólo están disponibles las notas permitidas por la Scale actual.»* Esta
   rebanada lo sustituye por dieciséis pads que son grados de escala en dos
   octavas, con dos de ellos dedicados al desplazamiento de octava.

   La razón está en la deuda 2 del Overview: sobre dieciséis pads contiguos, el
   filtro cromático deja la mayoría muertos y acota el registro a un octavo del
   rango MIDI. La Pre Spec describe la intención —solo notas de la escala— y esta
   superficie la cumple mejor que el mecanismo que proponía. La nota va en la
   Pre Spec, no en `tech-stack.md`: es una decisión de dominio.

2. **`product.md` promete MIDI Learn dentro de la v1 y esta rebanada no lo
   entrega.** El alcance de v1 lista *«Mapeo del controlador + MIDI Learn»* como
   una sola línea. Se parte en dos rebanadas y se registra la razón —problemas
   distintos, `network-session-source` de por medio— con la 8 como sitio donde se
   cumple.

## Out of Scope

- **MIDI Learn** — rebanada 8, junto con `network-session-source`.
- **LEDs y feedback sobre el BeatStep Pro** (SysEx de Arturia) — track futuro.
- Escalas de usuario y escalas de más de siete grados.
- Los knobs 10–16 y todo lo que llenaría su sitio: Cycles, Accent, Repeats,
  Time, Ramp, Pace, Voicing, Style, Range, Phrase.
- Aceleración por velocidad de giro en los knobs.
- CTRL/Shift y los rangos extendidos que la Pre Spec asocia (Steps 17–64).
- Transposición por semitonos del pool, que la Pre Spec lista junto a la
  navegación de octavas.
- Persistencia, Autosave y Backup Project.
- Múltiples Tracks, Patterns y Banks — los step buttons se implementan, pero no
  hay Tracks detrás.
- Medición de jitter — no cambia ningún instante (NFR3).
