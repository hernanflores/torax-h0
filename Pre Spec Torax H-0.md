## 1. Qué es el H-0

El **H-0 no genera audio**: es un secuenciador algorítmico que controla instrumentos externos por MIDI (para posteriores versiones considerar Ableton Link). Su idea central no es programar cada evento fijo, sino definir reglas de ritmo, altura, dinámica, tiempo y variación que producen una secuencia reproducible pero viva.

Cada Pattern tiene **16 Tracks polifónicos**. Un Track genera notas; usa Shape, Groove, Tonal y Setup.

## 2. Estructura de datos y memoria

```text
Project (estado completo + ajustes guardados)
└── 16 Banks (cada uno guarda tempo)
    └── 16 Patterns por Bank
        └── hasta 16 Tracks por Pattern
            └── hasta 16 Cycles por Track
```

- **Project:** estado completo del projecto: 16 Banks, sus Patterns/Tracks y ajustes asociados.
- **Bank:** contenedor musical de alto nivel (canción, setup o sección de live). Tiene 16 Patterns y tempo propio.
- **Pattern:** una sección musical que reproduce el estado de sus 16 Tracks en conjunto: groove principal, break, fill, variante, etc. Puede dispararse cuantizado, encadenarse y seleccionarse por MIDI Program Change.
- **Track:** una voz/carril musical y de control. Es donde residen los parámetros generativos.
- **Cycle:** snapshot de parámetros de un Track. Permite que ese Track varíe en pasadas sucesivas del loop sin cambiar de Pattern.

> **Nota del 2026-09-02 — son doce Tracks por Pattern, no dieciséis.** Esta
> sección escribe 16 en tres sitios —la línea de la sección 1, el árbol de
> memoria y la definición de Pattern— y la app implementa **12** desde el track
> `ui-declutter_20260902`.
>
> **La razón es de lectura, no de motor.** Los dieciséis Tracks se dibujan como
> anillos concéntricos y el ancho de banda de cada uno sale de repartir el radio
> entre `trackCount - 1`. Con dieciséis, cada banda queda en unos pocos puntos y
> el playhead deja de leerse a un metro, que es el requisito de
> `product-guidelines.md` —no una preferencia estética, sino la condición de uso:
> la pantalla se mira de reojo, en movimiento y con poca luz—. Con doce, la misma
> fórmula da bandas un tercio más anchas sin tocar el dibujo.
>
> **El modelo no cambia de forma.** Doce es un límite de legibilidad puesto sobre
> una constante, `Pattern.trackCount`, de la que todo lo demás deriva: el reparto
> de los anillos, el número de schedulers, las voces que se apagan al parar y la
> fila de selección. No hay ningún concepto nuevo ni ninguno que desaparezca, y
> si algún día el ancho deja de ser el problema —una pantalla mayor, otra
> representación— la constante vuelve a subir.
>
> **Lo que sí pierde el hardware.** El BeatStep Pro tiene dieciséis step buttons y
> cada uno seleccionaba un Track; del 13 al 16 dejan de seleccionar. No es un
> error: no publican, como un CC sin asignar. El preset no cambia, porque la
> tabla describe el hardware y no lo que la app hace con él.

> **Nota del 2026-09-02 — mute y solo por Track, y por qué no están en este
> árbol.** La Pre Spec no los menciona en ningún sitio: se añaden en el track
> `mute-solo_20260902`, un par **M / S** por Track accionable desde la pantalla y
> desde el controlador.
>
> **No entran en la estructura de arriba a propósito.** Todo lo que cuelga de
> `Project` es **material**: lo que el Pattern dice que suene. Mute y solo son
> **mezcla** —qué se escucha ahora mismo de ese material—, y meterlos en el Track
> los ataría al Pattern: cambiar de Pattern movería los silencios, y silenciar un
> Track sería editarlo. Viven por encima, en una capa que no se guarda con el
> material.
>
> **Mute no para el Track: le quita la salida.** La rejilla avanza, el playhead
> gira y los Cycles rotan igual; lo único que se suprime es la emisión. Quitarlo
> devuelve el Track **en fase** con el resto, que es lo que hace un mixer y lo que
> un «stop del Track» rompería.
>
> **El solo es aditivo y el mute manda sobre él.** Varios Tracks pueden estar en
> solo a la vez y suenan todos ellos —aislar bombo y caja juntos es la operación
> normal, y el solo exclusivo la prohibiría—. Un Track soleado **y** muteado
> calla: la regla se lee del revés con facilidad, y de ahí que se escriba.
>
> **En el hardware son los step buttons 15 y 16**, mantenidos como modificador:
> con el 16 hundido, pulsar el N mutea el Track N; con el 15, lo solea. Los dos
> quedaron libres al bajar a doce Tracks (nota de arriba), así que el gesto no le
> quita nada a la selección.

### Guardado

- **Autosave:** protege el estado de trabajo reciente y restaura el último Bank tras reiniciar.
- **Save Bank manual:** crea el punto de retorno intencional de *un* Bank; `Reload` descarta cambios no guardados y vuelve a ese punto.
- **Backup Project:** exporta/importa el estado completo. Úsalo para archivado, transferencia de setup o antes de un directo.

> **Nota del 2026-09-07 — de estos tres, entran dos.** La rebanada 4 de la v2
> (`persistence_20260907`) entrega **Autosave** y **Save Bank / Reload**; **Backup
> Project se queda fuera**.
>
> **El Autosave es el de arriba**: protege el trabajo reciente y restaura al
> reiniciar. Escribe tras un par de segundos de calma —no por evento, que a
> cuarenta y ocho controles físicos sería escribir en ráfagas—, fuerza la
> escritura al pasar la app a segundo plano, y toca **solo el Bank editado**.
> Sigue escribiendo con el transporte corriendo: ocurre lejos del hilo del
> scheduler, y pararlo mientras suena sería perder justo la sesión que más
> importa.
>
> **`Save Bank` y `Reload` son la otra capa**, y son del Bank vigente. Reload
> entra **cuantizado**, como un cambio de Pattern, y **no pide confirmación**,
> por coherencia con el resto de la app — que no confirma nada. En un Bank que
> nunca se guardó a mano el botón no está disponible y lo dice: sin punto de
> retorno, volver a vacío no es volver, es borrar.
>
> **Backup Project queda fuera porque no es modelo, es UI de documentos**:
> `UIDocument`, share sheet, ida y vuelta de ficheros ajenos. El formato JSON lo
> deja preparado y el track tiene la limitación escrita: hasta que entre, el
> estado vive en el contenedor de la app y **desinstalarla lo borra**.
>
> **Vocabulario, para que no aparezcan sinónimos.** `Bank`, `Pattern`, `Project`,
> `Save Bank`, `Reload`, `Autosave`, y `queued` para el Pattern que espera el
> compás. Ni «preset», ni «song», ni «slot», ni «guardar todo».

## 3. El motor: cómo se obtiene una secuencia

Una forma útil de leer el flujo es:

1. **Shape** decide *cuándo* y con qué densidad ocurren eventos.
2. **Tonal** define el pool de notas y cómo se mueve armónicamente.
3. **Groove** define dinámica, probabilidad, duración y desplazamiento temporal.
4. **Cycles, LFO y Random** introducen desarrollo en el tiempo.

No son algoritmos aislados: por ejemplo, un pulso euclidiano puede disparar repeticiones, una frase tonal puede elegir alturas de un pool limitado por escala y un Cycle puede sustituir el estado del Track en la siguiente vuelta.

## 4. Algoritmos y mecanismos generativos

### Ritmo euclidiano

Define **Steps** (posiciones) y **Pulses** (triggers). El H-0 reparte los Pulses lo más uniformemente posible entre los Steps.

- Ejemplos: 16/4 es muy regular; 16/5 conserva equilibrio con asimetría; 12/7 es más denso.
- **Rotate** desplaza todo el patrón sin cambiar Steps ni Pulses.

### Note Repeater (ratchet)

No cambia la estructura base: sobre cada Pulse añade triggers adicionales. Sirve para rolls, stutters, fills, tremolo y densidad micro-rítmica.

- **Repeats:** cuántos triggers extra genera cada Pulse.
- **Time:** separación entre repeticiones.
- **Ramp:** curva ascendente/descendente de velocity a través de las repeticiones.
- **Pace:** acelera o frena gradualmente la separación entre repeticiones.
- Modos **Choke/Tail** determinan el comportamiento de las notas repetidas.

> **Nota del 2026-09-07 — el Note Repeater entra, y entra recortado.** La
> rebanada 5 de la v2 (`note-repeater_20260906`) implementa esta sección. Cada
> Pulse pasa a generar hasta ocho triggers extra sin tocar Steps, Pulses ni
> Rotate, y las repeticiones heredan del Track su Velocity, su Sustain, su swing
> y su Delay. Con **Repeats en 0 —el default— no cambia nada de lo entregado**:
> instantes, velocities, gates y consumo de aleatoriedad son los de antes de la
> rebanada.
>
> **Repeats es 0–8, no 0–48, y no hay «infinito».** El tope de la Pre Spec se
> recorta porque el techo de coste en el hilo del scheduler se **razona** en vez
> de medirse —la medición de jitter está suspendida desde el 2026-09-02— y con
> doce Tracks, 108 eventos por Step es un número defendible donde 588 no lo es.
> Ampliarlo más adelante es cambiar una constante, no rehacer el diseño.
>
> **Ramp y Pace son knobs propios, no secundarios de CTRL.** Es el mismo caso que
> resolvió la nota del 2026-09-02 sobre el gesto de CTRL: el BeatStep Pro no
> tiene CTRL, y el gesto agrupaba cosas porque el hardware de la Pre Spec lo
> hacía barato, no porque sean la misma cosa. Los cuatro van a los knobs 10, 11,
> 12 y 14 — CC 79, 80, 81 y 83.
>
> > **Corregido el 2026-09-12.** Los cuatro están ahora en los **knobs 5 a 8**
> > —CC 82 a 85—, cerrando la fila de arriba detrás de los cuatro del ritmo:
> > `knob-layout_20260912` dio una fila de knobs a cada card de la pantalla. La
> > tabla viva está en `preset/README.md`; esta línea registra dónde estaban al
> > entrar.
>
> **Los modos Choke y Tail quedan fuera.** Cada repetición emite su note-on y su
> note-off, y **el solape no se vigila**: con Sustain alto una repetición se pisa
> con la siguiente y el note-off de la primera apaga a la segunda. Es la
> limitación ya aceptada de `NoteEmitter`, en un sitio más donde ocurre.
>
> **El vocabulario queda fijado**, y es el de esta sección: `Repeats`, `Time`,
> `Ramp`, `Pace` y `Note Repeater`. «Ratchet» describe el efecto y no nombra
> ningún parámetro; «roll», «stutter» y «subdivisión» no se usan en código, en
> pantalla ni en los documentos.
>
> **Sin medición de jitter**, y es el segundo cambio desde la suspensión del
> 2026-09-02 que toca la rejilla temporal —el primero, `external-clock_20260903`,
> abrió una excepción acotada—. Aquí no se abre excepción: se verifica tocando,
> en dispositivo. Un ratchet que se arrastra se oye.

### Tonal: pool, escala y movimiento

- Cada Track puede contener **hasta 8 pitches**.
- **Scale + Root** restringen la salida a una escala y centro tonal; la escala puede ser preset o de usuario.
- **Pitch** inserta/elimina notas y transpone en semitonos dentro del marco tonal.
- **Harmony** desplaza una voz del acorde por vez para variación armónica.
- **Range + Phrase:** Range define cuánto varía la altura; Phrase elige una forma repetible de recorrer ese material. Es el LFO de pitch, no reemplaza el pool de notas.
- **Voicing + Style:** Voicing define la cantidad de movimiento de voces; Style define el patrón temporal (polifónico o monofónico). El principio: subir una octava la voz más grave o bajar una la más aguda; los estilos deciden cómo alternar entre voicing original y desplazado.

> **Nota del 2026-09-12 — Pitch y Harmony entran como knobs, y Pitch transpone
> en grados, no en semitonos.** El track `pitch-harmony_20260912` implementa las
> dos líneas de arriba. Toma el algoritmo del PRD
> `conductor/Pitch_Harmony_PRD.docx` y deja fuera su vocabulario y su modelo de
> datos.
>
> **Pitch transpone el pool entero un grado de la escala por clic**, no un
> semitono. «Semitonos dentro del marco tonal» se contradice consigo mismo: un
> semitono llevado a la nota permitida más cercana puede caer en la misma nota
> que el anterior, así que el knob tendría pasos muertos y el pool podría
> encoger. Contar en grados cumple la intención —«sigue en tonalidad»— sin ese
> coste, conserva los intervalos entre pitches y coincide con los pads, donde
> cada pad ya es un grado. El rango es ±28 grados, con freno atómico si alguna
> altura saldría de 0–127.
>
> **Harmony mueve un pitch del pool por clic, en round robin.** Un cursor dice
> cuál se intenta primero. Si ese pitch no puede moverse un grado en el sentido
> del giro, se prueba el siguiente; el que se mueve deja el cursor en el de
> después. **Sin cruces ni choques**: cada pitch queda estrictamente entre sus
> vecinos, así que el pool sigue ordenado y el pitch *i* sigue siendo el
> *i*-ésimo. **Con histéresis**: invertir el sentido no deshace el paso anterior.
>
> **No hay Reset Harmony.** El estado de Harmony se limpia al insertar o quitar
> un pitch con un pad y al cambiar Scale o Root; Pitch se conserva en los dos
> casos. **Los pads siguen editando el pool base**; Pitch y Harmony transforman
> el pool que suena.
>
> **Pitch y el estado de Harmony son de cada Cycle**, como el resto de
> parámetros, y se guardan con él.
>
> **El vocabulario queda fijado:** `Pitch`, `Harmony`, *pitch del pool*.
> *Voice*, *voz* (que en el proyecto nombra al Track), *degree offset* y
> *lattice* no se usan en código, en pantalla ni en los documentos.

### Control de Pitch: pool, no piano-roll

El control **PITCH** determina el *pool* de notas que un Track puede usar; no escribe una melodía fija. Al pulsarlo, los 16 Value Buttons se comportan como teclado cromático, pero sólo están disponibles las notas permitidas por la Scale actual. Una nota activada entra al pool; una desactivada se excluye.

> **Nota del 2026-08-31 — los 16 Value Buttons dejan de ser un teclado cromático
> filtrado por la Scale.** Sustituido por la rebanada 7 del MVP
> (`mvp-beatstep-mapping_20260830`). Cada pad pasa a ser un **grado de escala**,
> no una altura leída del mensaje:
>
> | Pad | Contenido |
> |---|---|
> | 1–7 | Grados 1–7 de la escala, en la octava base (la que empieza en la nota MIDI 48) |
> | 9–15 | Los mismos grados, una octava por encima |
> | 8 | Baja el registro una octava |
> | 16 | Sube el registro una octava |
>
> **La razón, no solo la regla.** El mecanismo de arriba funciona sobre un
> teclado completo; sobre dieciséis pads que envían dieciséis semitonos
> contiguos, no. Dieciséis semitonos contienen siete grados de una escala de
> siete notas, así que **nueve de los dieciséis pads quedan muertos**; el
> registro alcanzable es **un octavo del rango MIDI** —dieciséis notas de 128, sin
> forma de meter una grave ni una aguda—; y qué pad da qué nota se mueve al
> cambiar el Root, de una manera que no se puede aprender.
>
> La superficie nueva **cumple la intención de esta línea —«sólo están
> disponibles las notas permitidas por la Scale actual»— mejor que el mecanismo
> que proponía**: toda altura que un pad puede meter en el pool sale de la
> escala, y ninguna se descarta en silencio.
>
> El precio es consciente: con una escala de menos de siete grados
> —`pentatonic`— los pads 6, 7, 14 y 15 quedan sin altura asignada. Se prefiere
> ese hueco estable a rellenarlos, porque rellenar rompería la invariante que
> sostiene todo lo demás: **el pad 9 es siempre el pad 1 más doce semitonos**, sea
> cual sea la escala y el Root. Es lo que permite que los pads 8 y 16 se llamen
> *octava* sin mentir.
>
> Decisiones completas en
> [`conductor/tracks/mvp-beatstep-mapping_20260830/spec.md`](./conductor/tracks/mvp-beatstep-mapping_20260830/spec.md).

- Girar **PITCH** transpone el pool dentro de la Scale actual, por lo tanto sigue en tonalidad. **Scale** determina las notas permitidas y **Root** su centro tonal.
- El pool puede tener desde una nota (centro estable) a ocho. Para empezar, 2–4 notas —por ejemplo fundamental, tercera y quinta— suele producir líneas más claras que habilitar toda la escala.
- Al cambiar Scale o Root se actualiza el teclado y el marco tonal.

### Acordes y arpegios: mismo material, distinta ejecución

No hay modos separados de “chord” y “arp”: ambos parten del mismo pool de Pitches.

| Configuración                   | Resultado                                                                                         |
| ------------------------------- | ------------------------------------------------------------------------------------------------- |
| Una nota                        | Comportamiento melódico simple.                                                                   |
| Varias notas + Style polifónico | Notas juntas: stabs, acordes, inversiones y figuras armónicas. (fuera de scope primera iteracion) |
| Varias notas + Style monofónico | Una nota por vez: arpegios, broken chords y patrones ascendentes/descendentes.                    |

**Voicing** decide cuánto y qué movimiento de octavas se aplica; **Style** decide su orden temporal. **Harmony** desplaza una voz del acorde a la vez: es la herramienta para hacer cambiar el color/relación interna del acorde sin reemplazar el pool. Para un acorde claro, comienza con tríada; para un arpegio menos cargado, reduce antes el número de notas del pool. Range/Phrase puede añadir movimiento melódico por encima de cualquiera de las dos configuraciones.

### Generación de melodías: receta por capas

La melodía surge de combinar ritmo y material tonal, no de un secuenciador de notas independiente:

1. Define el ritmo con **Steps/Pulses**: decide cuándo habrá nota.
2. Elige un pool reducido con **PITCH**.
3. Delimítalo con **Scale + Root**.
4. Transpone dentro de ese marco con PITCH y aplica **Voicing/Style** para ordenar y espaciar las notas.
5. Escoge **Phrase** (contorno repetible: cadencial o continuo) y aumenta **Range** para decidir cuánto recorre ese contorno.
6. Añade **Harmony** si quieres variación en las relaciones entre notas; usa locks por paso o Cycles para fijar puntos importantes.

Range pequeño da líneas más controladas; Range grande las vuelve más animadas/generativas. En Style, **Poly** toca las notas juntas y **Mono** una por vez, de modo que el mismo material puede pasar de fragmento melódico estable a movimiento tipo arpegio sin cambiar el pool.

### Cycles

Un Track puede tener de **1 a 16 Cycles** activos. Cada Cycle es una versión de sus ajustes: al repetirse el Track, avanza por ellos. Es desarrollo estructurado (A/B/C...) sin duplicar el Pattern.

### Modulación LFO y Random

| Sistema | Naturaleza | Destinos principales |
|---|---|---|
| LFO | Forma repetible, sincronizada al tempo. | **Phrase** para pitch mediante Range; **Groove** para variación de velocity mediante Accent. |
| Random | Secuencia pseudoaleatoria en loop: cambia, pero no es caos totalmente impredecible. | Parámetros del Track; intensidad y drift controlables. |

> **Nota del 2026-09-08 — entra la mitad del LFO, y solo sobre velocity.** La
> rebanada 6 de la v2 (`modulation_20260906`) implementa la fila **LFO** de esta
> tabla en su destino **Groove/Accent**. Lo que se entrega y lo que no:
>
> | | |
> |---|---|
> | **Entra** | LFO cíclico sobre **velocity**, por Cycle, con cuatro formas: `saw`, `triangle`, `sine`, `pulse`. |
> | **No entra** | El destino **Phrase/Range** para pitch — es la otra celda de la fila y no se toca. |
> | **No entra** | **Random Modulation**, la segunda fila entera. |
> | **No entra** | Modular nada que no sea velocity: Sustain, Timing, Division o el pool. |
>
> **«Sincronizada al tempo» se entrega como un ciclo por vuelta del anillo del
> propio Track.** La fase sale del índice de Step dentro de la vuelta dividido
> por los Steps del Track, así que no hay reloj de modulación ni estado que
> mantener: la sincronía es una consecuencia de cómo se calcula la fase. Cada
> Track modula a su velocidad, porque cada uno tiene sus Steps y su Division.
>
> **Vocabulario fijado** (`product-guidelines.md` pide un término por concepto):
> el módulo es `modulation`, la forma es **`waveform`** y la amplitud es
> **`accent`**; las formas son `saw`, `triangle`, `sine` y `pulse`. No se usa
> «LFO» como nombre de parámetro, ni «shape» —que ya nombra una familia—, ni
> «amount».
>
> **Por qué la forma no se llama `Groove`.** Esta especificación usa *Groove*
> para dos cosas distintas: la familia de Velocity, Sustain, Probability, Timing
> y Delay (§5), y el knob que escoge la forma del LFO (fila `Accent`, §5). El
> motor ya gastó el término en la primera —`Groove` es un tipo de `Engine`— y un
> segundo significado lo haría ambiguo justo donde más se lee. La forma toma
> `waveform`, que es como la rotula el propio handoff de diseño.

## 5. Referencia de parámetros

### Diseño melódico: interacción entre Shape, Groove y Tonal

**Shape construye la gramática**, **Tonal elige y transforma las alturas** y **Groove convierte esa secuencia en interpretación**. Para editar una melodía sin destruir su comportamiento generativo: fija el ritmo con Steps/Pulses, limita el pool con Pitch/Scale/Root, usa Phrase/Range para el contorno y bloquea sólo los pasos estructurales (inicio, cambio y cierre). Los demás pasos pueden seguir respondiendo a Cycles, Voicing, Harmony y Random.

En la práctica: Steps largos contra una Phrase de 16 posiciones generan desfase y desarrollo; Rotate cambia el punto de entrada rítmico sin modificar el material tonal; Division cambia la velocidad de la línea sin reescribirla; Retrigger reinicia también Random, Range, Accent y Voicing, útil como punto de comienzo de frase.

**Groove como edición de frase:** Velocity define jerarquía; Accent/Groove repite una forma dinámica; Probability omite eventos (sobre todas las notas o sólo Pulses); Sustain decide si la línea es staccato o se liga; Timing desplaza cada segundo paso para swing; Delay mueve toda la voz contra el resto del Pattern. Para una melodía legible, fija primero pitch y ritmo, luego prueba Sustain, Accent y Timing antes de añadir más notas.

### Shape — estructura rítmica/melódica

| Parámetro | Función principal | Secundario / detalle importante |
|---|---|---|
| Steps | Longitud del Track y posiciones de eventos. | 1–16 normal; 17–64 con CTRL. El aleatorio siempre tiene 16 pasos y se superpone/recorre loops largos. Puede insertar un Retrigger. |
| Pulses | Número de triggers distribuidos euclidianamente. | 1 hasta el número actual de Steps; **Rotate** desplaza el patrón. |
| Cycles | Selecciona/edita el Cycle actual. | Con CTRL ajusta 1–16 Cycles activos. |
| Division | Valor rítmico de cada Step; cambia velocidad sin cambiar estructura. | Ajuste fino; Fixed o Free Division. Default: 1/16. |
| Repeats | Triggers extra por Pulse. | 0–48; máximo clockwise = infinito. **Ramp** cambia velocity a través de ellos. |
| Time | Separación entre repeticiones. | **Pace** cambia gradualmente la separación; valores rectos, tresillos, cuantizado al Step o Free Division. |
| Voicing | Cantidad de movimiento del acorde. | **Style** decide el patrón de movimiento. |
| Range | Cantidad de variación de pitch. | **Phrase** decide la forma melódica y su longitud. |

> **Nota del 2026-09-02 — el gesto de CTRL se parte en dos.** La rebanada 3 de
> la v2 (`cycles_20260901`) implementa Cycles sobre el BeatStep Pro, **que no
> tiene CTRL**. El knob se queda con la función primaria —mover el Cycle en
> edición del Track seleccionado— y **cuántos Cycles hay activos se ajusta
> táctilmente**, en pantalla, junto a Scale, Root y el canal.
>
> **No es una concesión al hardware sino la frontera que el producto ya tenía
> trazada.** `product-guidelines.md` pone la configuración del lado táctil y el
> material generativo del lado de los knobs; cuántos Cycles recorre un Track es
> configuración, igual que por qué canal sale. El gesto de CTRL agrupaba las dos
> cosas porque en el hardware de la Pre Spec había un modificador que lo hacía
> barato, no porque sean lo mismo.
>
> Lo mismo aplica al «17–64 con CTRL» de Steps, que sigue fuera de alcance.
>
> Es el mismo tipo de desviación que la nota del 2026-08-31 sobre los pads: el
> mecanismo de la Pre Spec supone un controlador que no es el que hay delante.

**Retrigger:** reinicia la secuencia al llegar a ese Step; también reinicia Random, Range, Accent y Voicing desde ese punto.

> **Nota del 2026-09-08 — Retrigger reiniciaría `accent`, y Retrigger no
> existe.** Esta línea promete que Retrigger reinicia Accent desde su Step, y la
> rebanada 6 de la v2 entrega `accent` **sin** ese reinicio: la fase de la
> modulación sale siempre del índice de Step dentro de la vuelta, así que solo
> vuelve al principio cuando lo hace el anillo. No es una desviación de la
> modulación sino una deuda heredada —Retrigger no está implementado en ningún
> Step—, y se anota aquí para que el día que entre se sepa que arrastra este
> requisito con él. Lo mismo vale para Random, Range y Voicing, que tampoco
> existen todavía.

### Groove — interpretación temporal y dinámica

| Parámetro | Función |
|---|---|
| Velocity | Nivel dinámico base. **Probability** decide omisiones: clockwise afecta todas las notas; counter-clockwise sólo los Pulses. 0–100%; botones 8/16 desplazan la fase de su secuencia aleatoria. |
| Sustain | Duración de nota: de muy corta/percusiva a larga/solapada. Default: una Division completa. |
| Accent | Amplitud de variación de velocity alrededor de Velocity base. **Groove** escoge la forma/LFO de esa variación; se puede cambiar su longitud. |
| Timing | Desplaza cada segundo Step, creando swing/shuffle (rejilla no uniforme). |
| Delay | Desplaza el Track entero hacia adelante o atrás respecto a la rejilla. |

> **Nota del 2026-09-08 — cómo se entrega `Accent`.** La rebanada 6 de la v2
> (`modulation_20260906`) lo implementa con **tres desviaciones de esta fila**,
> escritas antes de implementar:
>
> 1. **La forma se llama `waveform`, no `Groove`.** Ver la nota de §4.
>
> 2. **La longitud no se puede cambiar.** Esta fila dice «se puede cambiar su
>    longitud» y el brief de producto pedía cuatro compases por defecto. Se
>    entrega **fija a un ciclo por vuelta del anillo**, que es lo que hace que la
>    sincronía no necesite ni reloj ni estado. La longitud ajustable queda fuera
>    de alcance, anotada aquí para que la deuda esté escrita.
>
> 3. **`Accent` no tiene knob: se edita con el dedo**, en la pantalla
>    `modulation`. Esta sección lista `Accent` entre los parámetros de Groove,
>    que son todos de knob, pero cae del lado táctil de la frontera del
>    2026-09-06 —se configura antes de tocar, como `scale`, `midi` y `banks`— y
>    los cuarenta y ocho controles del BeatStep Pro ya están asignados.
>
>    **Lo que eso cuesta, con el precio delante:** Ctrl All, Temp y la lectura
>    transitoria grande **no alcanzan a `accent`**, porque los tres operan sobre
>    `TrackParameter` y `accent` no lo es. Se arregla el día que tenga knob, y
>    ese día es otro track.
>
> **El rango es bipolar, −100 … +100, con default 0.** El 0 está dentro del
> rango y es el valor que **apaga** la modulación: con `accent = 0` la salida es
> idéntica a la de antes de la rebanada. La amplitud «alrededor de Velocity
> base» se entrega como ±63 unidades MIDI en el extremo, y la velocity
> resultante se acota a 1…127 como el resto.

### Tonal

| Parámetro | Función |
|---|---|
| Pitch | Pool de notas del Track; insertar/quitar con botones, navegar octavas y transponer semitonos. |
| Harmony | Mueve una voz del acorde a la vez. |
| Scale | Set de notas permitido (presets o escala de usuario). |
| Root | Fundamental que transpone la Scale. |

> **Nota del 2026-09-12 — «transponer semitonos» es transponer grados.** Ver la
> nota del mismo día en *Tonal: pool, escala y movimiento*. Pitch y Harmony se
> mueven con los knobs 14 y 15 (CC 75 y 76).

> **Nota del 2026-09-04 — Temp: los parámetros se pueden mover sin escribirlos.**
> La Pre Spec no lo tiene en absoluto: todo giro de knob de esta sección escribe
> en el Pattern, siempre. Temp añade el gesto que faltaba —el track
> `temp-parameters_20260904`—: **mantener [step 13]** y girar superpone el cambio
> sobre el Track seleccionado, y **soltar lo devuelve**. En el Pattern no queda
> rastro.
>
> Es lo que hace posible un fill, un build o un breakdown sin gastar un Cycle ni
> un Pattern. Sin él, la única forma de volver atrás es deshacer a mano lo que se
> acaba de tocar, y no hay deshacer.
>
> **El overlay iguala, no aplana** — que es justo lo contrario de lo que se daría
> por supuesto. El parámetro girado toma **el mismo valor absoluto en todos los
> Cycles activos**, partiendo del que tenía el Cycle en edición, para que el fill
> se oiga aunque el cursor cruce de Cycle a media vuelta. Los parámetros que la
> mano no toca conservan su valor distinto en cada Cycle, y al soltar **cada
> Cycle recupera el suyo**: por eso lo que se guarda es la base por Cycle y no un
> valor único.
>
> **Con Temp hundido, Temp manda.** Se ignoran en silencio la selección de
> Track, los modificadores de mute y solo, el knob del Cycle en edición y los
> pads. El hold acota qué controles están vivos: un roce de dedo no puede
> deshacer el fill.
>
> **Es el tercer modificador mantenido y no inventa mecánica.** Los step buttons
> 15 y 16 ya son solo y mute desde la nota del 2026-09-02, con el mismo 127 al
> pulsar y 0 al soltar; del 13 al 16 no hay Track detrás desde que el Pattern
> bajó a doce.
>
> **El término es «Temp».** No «momentary», no «override», no «latch»: un
> concepto, un nombre.
>
> **Lo que Temp no toca:** pool, Scale, Root, canal y número de Cycles activos
> quedan fuera. El overlay es de parámetros; material y configuración no se
> superponen.

> **Nota del 2026-09-05 — Ctrl All: un knob mueve los doce Tracks.** La Pre Spec
> tampoco lo tiene: todo giro de knob de esta sección alcanza a **un** Track, el
> seleccionado. Ctrl All añade el gesto que faltaba —el track
> `ctrl-all_20260905`—: **mantener [step 14]** y girar desplaza ese parámetro en
> **los doce Tracks a la vez**, y **soltar lo devuelve**. En el Pattern no queda
> rastro, igual que con Temp.
>
> Es lo que hace posible subir el Velocity de la mezcla entera, abrir el Sustain
> de todo o desfasar el Pattern con Rotate. Sin él harían falta ciento ocho
> vueltas de knob —nueve parámetros por doce Tracks— y ninguna se podría
> deshacer.
>
> **Ctrl All desplaza; Temp iguala. Ese es todo el parentesco y toda la
> diferencia.** Temp existe para que un parámetro suene **igual** en todos los
> Cycles del Track seleccionado. Ctrl All existe para lo contrario: mover el
> Pattern entero **conservando** lo que lo hace un Pattern y no doce copias. Un
> Track lento sigue siendo el lento; el que tenía menos Pulses sigue teniendo
> menos; y con varios Cycles activos, cada Cycle conserva su valor propio
> desplazado. Quien lea «afecta a todos los Tracks» dará por supuesto lo
> contrario, y de ahí que se escriba.
>
> **Lo que se guarda es la base y el desplazamiento, por separado.** El valor de
> cada Cycle se recalcula siempre como base + offset, nunca desde el valor ya
> escrito. Es lo único que hace exacta la ida y vuelta cuando un Track topa
> contra su extremo: el topado **no arrastra a los demás** y retoma **su** valor
> exacto en cuanto el desplazamiento reentra en su rango — no en el primer clic
> de vuelta, que es lo que esta nota afirmaba al escribirse y se corrigió el
> mismo día al implementarlo. El desplazamiento acumulado sí se acota
> al ancho del recorrido del parámetro —sin tope, cuarenta clics contra el
> límite dejan el knob muerto durante cuarenta clics de vuelta, que es el
> síntoma que la nota del 2026-08-28 sobre los encoders enseñó a reconocer como
> avería—. **Rotate queda fuera de ese tope:** envuelve módulo el Steps de cada
> Cycle en vez de acotar, así que nunca se muere, y con Steps distintos los
> Tracks se desfasan entre sí — que es lo que se le pide a un Rotate global.
>
> **Alcanza a los doce, muteados incluidos.** Mute es mezcla y no material: la
> rejilla del Track muteado sigue avanzando, así que dejarlo fuera del
> desplazamiento lo devolvería desalineado al desmutearlo, y el gesto dependería
> de un estado que no se ve en los knobs. Los Cycles inactivos no se tocan: el
> desplazamiento alcanza a lo que se recorre.
>
> **Con Ctrl All hundido, Ctrl All manda** —la selección de Track, los
> modificadores de mute y solo, el knob del Cycle en edición y los pads callan—
> **y además callan las vías táctiles que escriben**: Scale, Root, canal,
> selección de Track y número de Cycles activos. Es un requisito que Temp no
> tiene, y la razón es que el gesto promete no escribir: un cambio de Scale a
> media superposición reencuadra el pool y **no se deshace al soltar**, y un
> número de Cycles que sube deja Cycles sin base guardada que se quedarían con
> el desplazamiento puesto para siempre.
>
> **Con [step 13] y [step 14] hundidos a la vez gana Temp**, y ninguno hereda el
> estado del otro: al soltar el 13 con el 14 aún hundido, Temp restaura y Ctrl
> All arranca ahí, sobre el Pattern ya restaurado. Cada modificador entra y sale
> por su propio botón; un botón hundido que no hiciera nada sería peor que
> cualquiera de las dos respuestas.
>
> **Es el cuarto modificador mantenido y no inventa mecánica.** El 13, el 15 y el
> 16 ya son Temp, solo y mute, con el mismo 127 al pulsar y 0 al soltar; el 14 es
> el último de los cuatro que quedaban libres al bajar el Pattern a doce Tracks.
>
> **El término es «Ctrl All».** No «global», no «all tracks», no «macro»: un
> concepto, un nombre.
>
> **Lo que Ctrl All no toca:** pool, Scale, Root, canal, registro de pads y
> número de Cycles activos quedan fuera, igual que con Temp. El desplazamiento es
> de parámetros; material y configuración no se superponen.

## 6. Random Modulation: comportamiento por destino

La dirección importa: clockwise y counter-clockwise tienen semánticas distintas. Sólo se modula la función primaria del knob.

| Destino | Clockwise | Counter-clockwise | Unidad de actualización |
|---|---|---|---|
| Steps | suma Steps | resta Steps | por Cycle |
| Pulses | suma Pulses | resta Pulses | por Cycle |
| Cycles | salta el siguiente Cycle | repite aleatoriamente el actual | por Cycle |
| Division | varía dentro del tuplet elegido | varía y elige tuplet aleatorio | por Cycle |
| Repeats | suma repeticiones | resta repeticiones | Random Rate |
| Time | varía dentro del tuplet elegido | varía y elige tuplet aleatorio | Random Rate |
| Voicing | varía cantidad de voicing | varía y elige Style aleatorio | Random Rate |
| Range | varía distinto para cada nota del acorde | varía igual para todas | Random Rate |
| Velocity | varía distinto para cada nota del acorde | varía igual para todas | por Cycle |
| Sustain | suma distinto por nota del acorde | suma igual para todas | Random Rate |
| Timing | varía delay distinto por nota del acorde | varía delay igual para todas | Random Rate |
| Scale | escala aleatoria | escala y Root aleatorios | por Cycle |

## 7. Receta mental para programar sin perderse

1. Asigna un rol a cada Track (kick, bajo, acorde, arp).
2. Fija **Steps / Pulses / Division** para el esqueleto.
3. Usa **Rotate**, edición manual y **Repeats** para carácter rítmico.
4. Limita el material musical con **Scale / Root / Pitch**; agrega Range/Phrase o Voicing/Style sólo después.
5. Da interpretación con **Velocity, Accent/Groove, Sustain, Timing y Delay**.
6. Añade una dimensión temporal: **Cycles** para variaciones compuestas; Random para mutación controlada.
7. Bloquea por paso lo que debe permanecer musicalmente reconocible; guarda el Bank antes de experimentos grandes.