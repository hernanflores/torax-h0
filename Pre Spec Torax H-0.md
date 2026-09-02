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

### Guardado

- **Autosave:** protege el estado de trabajo reciente y restaura el último Bank tras reiniciar.
- **Save Bank manual:** crea el punto de retorno intencional de *un* Bank; `Reload` descarta cambios no guardados y vuelve a ese punto.
- **Backup Project:** exporta/importa el estado completo. Úsalo para archivado, transferencia de setup o antes de un directo.

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

### Tonal: pool, escala y movimiento

- Cada Track puede contener **hasta 8 pitches**.
- **Scale + Root** restringen la salida a una escala y centro tonal; la escala puede ser preset o de usuario.
- **Pitch** inserta/elimina notas y transpone en semitonos dentro del marco tonal.
- **Harmony** desplaza una voz del acorde por vez para variación armónica.
- **Range + Phrase:** Range define cuánto varía la altura; Phrase elige una forma repetible de recorrer ese material. Es el LFO de pitch, no reemplaza el pool de notas.
- **Voicing + Style:** Voicing define la cantidad de movimiento de voces; Style define el patrón temporal (polifónico o monofónico). El principio: subir una octava la voz más grave o bajar una la más aguda; los estilos deciden cómo alternar entre voicing original y desplazado.

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

### Groove — interpretación temporal y dinámica

| Parámetro | Función |
|---|---|
| Velocity | Nivel dinámico base. **Probability** decide omisiones: clockwise afecta todas las notas; counter-clockwise sólo los Pulses. 0–100%; botones 8/16 desplazan la fase de su secuencia aleatoria. |
| Sustain | Duración de nota: de muy corta/percusiva a larga/solapada. Default: una Division completa. |
| Accent | Amplitud de variación de velocity alrededor de Velocity base. **Groove** escoge la forma/LFO de esa variación; se puede cambiar su longitud. |
| Timing | Desplaza cada segundo Step, creando swing/shuffle (rejilla no uniforme). |
| Delay | Desplaza el Track entero hacia adelante o atrás respecto a la rejilla. |

### Tonal

| Parámetro | Función |
|---|---|
| Pitch | Pool de notas del Track; insertar/quitar con botones, navegar octavas y transponer semitonos. |
| Harmony | Mueve una voz del acorde a la vez. |
| Scale | Set de notas permitido (presets o escala de usuario). |
| Root | Fundamental que transpone la Scale. |

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