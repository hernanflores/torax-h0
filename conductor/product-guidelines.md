# Product Guidelines — Torax H-0

## Principio rector

**El controlador es el instrumento; la pantalla es el espejo.** Ninguna decisión de diseño debe exigir mirar el iPad para tocar. La pantalla se lee de reojo, en movimiento, a veces con poca luz.

## Voz y tono

- **Preciso, no conversacional.** La app no explica ni acompaña: informa. `steps 16 · pulses 5`, no "Has elegido 5 pulsos".
- **Vocabulario de la Pre Spec, en inglés, sin traducir.** Steps, Pulses, Rotate, Division, Velocity, Sustain, Timing, Delay, Probability, Scale, Root, Pitch. Un solo término por concepto en UI, código y documentación — sin sinónimos, sin capa de traducción.
- **Sin mensajes de error emotivos.** Un dispositivo MIDI desconectado se comunica con un estado (`no midi device`), no con una disculpa.

> **Enmienda del 2026-09-06 — la interfaz se escribe en minúsculas. Cambia la
> caja, no el término.** El handoff de iPadOS exige que **todo texto visible esté
> en minúsculas**, y el rediseño de las cuatro pantallas
> (`screens-redesign_20260906`) lo adopta: la pantalla escribe `steps`, `pulses`,
> `dorian`, `no midi device`.
>
> **La regla de arriba sobrevive entera, porque no era una regla de caja.** Lo que
> fija es *qué palabra* se usa y que sea una sola por concepto, en inglés y sin
> traducir. Eso no se toca: `Steps` sigue siendo `Steps` en código, tests,
> Pre Spec y documentación, y sigue sin tener sinónimo. Lo único que cambia es
> cómo se dibuja en pantalla.
>
> **Dónde vive la conversión: en la capa de presentación y en ningún otro sitio.**
> Un identificador en minúsculas dentro de `Engine` sería traducir el modelo para
> complacer al dibujo, y entonces sí se habría roto el «un solo término por
> concepto en UI, código y documentación» — el término sería el mismo, pero
> habría dos formas de escribirlo compitiendo dentro del código.
>
> **Por qué se acepta.** La minúscula constante es lo que hace que el chrome se
> lea como un aparato y no como una app de sistema, que es el mismo criterio por
> el que el tratamiento neo-brutalista no usa pastillas completas. Es una decisión
> de superficie con una consecuencia de superficie.

## Lenguaje visual

**Lo expresivo es el material musical; el resto es discreto.**

> **Cerrado el 2026-09-02, con la rebanada 2 de la v2.** Hasta entonces los
> valores concretos —colores, tipografía, tratamiento de los controles— eran
> ilustrativos y vivían en un solo sitio «para poder cambiarlos cuando el
> lenguaje visual se cierre». Se cierra aquí:
>
> - **Figtree** (400/600/700) en todo el texto de la interfaz.
> - Los **acentos definitivos**: Shape `#9AAB79`, Groove `#AA6DA8`, Tonal
>   `#7C5FD9`. Groove era ámbar y pasó a mauve; se comprobó a un metro y con
>   poca luz que sigue separándose del violeta de Tonal.
> - Un **tratamiento neo-brutalista** que es un sistema y no un estilo por
>   vista: trazos de 2px —3px en la raíz elegida—, radios de 3 a 8px, rellenos
>   de acento planos, sombras duras sin blur en lo seleccionado, y **borde
>   discontinuo para lo que existe pero todavía no se puede usar**.
>
> Los tres viven cada uno en un solo fichero de `App`. **Una vista que invente
> su propio color, su propia fuente o su propio borde es un fallo**, no una
> variación.

> **Enmienda del 2026-09-06 — el fondo pasa a neutro; lo demás del cierre sigue
> en pie.** El fondo era `#211823`, un violeta muy oscuro. El handoff de iPadOS
> lo sustituye por el neutro **`#111211`**, y el rediseño de las cuatro pantallas
> (`screens-redesign_20260906`) lo adopta.
>
> **Qué cambia y qué no.** Cambia el fondo y, con él, los neutros que se
> derivaban de un violeta: toolbar, panel hundido, bordes, posición vacía del
> anillo y los dos grises de texto. **No cambian los tres acentos** —Shape
> `#9AAB79`, Groove `#AA6DA8`, Tonal `#7C5FD9`— **ni la tipografía ni el
> tratamiento neo-brutalista**, que siguen siendo exactamente los cerrados el
> 2026-09-02. La nota de arriba se enmienda en una línea, no se retira.
>
> **Por qué se acepta.** El violeta oscuro se eligió cuando el lenguaje visual
> era ilustrativo, y su tinte competía con dos de los tres acentos por estar del
> mismo lado del círculo cromático. Un fondo neutro no compite con ninguno: lo
> que codifica familia vuelve a ser lo único cromático de la pantalla, que es lo
> que esta sección pide cuando dice que el color nunca decora.
>
> **Lo que reabre, y hay que escribirlo porque ya estaba escrito.** El cierre del
> 2026-09-02 dice que el mauve de Groove «se comprobó a un metro y con poca luz
> que sigue separándose del violeta de Tonal». **Esa comprobación se hizo contra
> el violeta oscuro y no vale contra el neutro.** `ShapeTheme.swift` ya dejaba la
> pregunta abierta —los dos quedan del mismo lado del círculo y se separan más
> por saturación que por tono— y este cambio la vuelve a poner encima de la mesa.
> Se decide con la app en la mano, a un metro y con poca luz; no se revierte por
> precaución ni se da por buena por deferencia al handoff.

- **Protagonista:** la visualización del patrón. Todo lo demás es soporte.
- **Secundario:** controles, etiquetas y chrome. Neutros, planos, sin competir por atención.
- **Color por familia funcional:** Shape, Groove y Tonal tienen cada una su acento cromático, consistente en toda la app. El color codifica *qué tipo de parámetro es*; nunca es decorativo.
- **Fondo oscuro, alto contraste.** Requisito de uso, no preferencia estética.
- **El movimiento sigue al reloj.** Toda animación deriva del transporte (playhead, pulsos activos). Si algo se anima, comunica tiempo musical.

### Representación del patrón: anillo circular

Los Steps se disponen como posiciones en un **círculo**; los Pulses se marcan sobre ellas. La forma circular hace evidentes las dos propiedades que definen el motor:

- La **naturaleza cíclica** del Track: el playhead recorre el anillo y vuelve.
- La **simetría del reparto euclidiano**: 16/4 se ve regular, 16/5 se ve equilibrado pero asimétrico.
- **Rotate se lee literalmente como una rotación** del anillo — el gesto y su representación coinciden.

Con Steps > 16 el anillo aumenta su densidad de posiciones; no se convierte en rejilla. Si la legibilidad se degrada a valores altos, la solución es reducir el detalle por posición, no cambiar de metáfora.

### Representación tonal: pool, no melodía

Se muestra **únicamente el pool de notas sobre la Scale**. No se muestra qué nota sonó en cada paso.

Esta es una decisión de fidelidad al modelo, no de simplicidad: PITCH define un *pool*, no un piano-roll. Mostrar una nota por paso sugeriría que las alturas están fijadas a posiciones, que es exactamente el modelo mental que la app rechaza.

El pool y el anillo rítmico son **dos representaciones paralelas y separadas**: cuándo suena algo, y de qué material se elige.

### Legibilidad a distancia

Debe leerse a un metro:

1. **Playhead y pulsos activos** — dónde está el tiempo y qué dispara.
2. **El valor grande transitorio** al girar un knob.

Eso obliga a tipografía muy grande en el overlay de valor y a una jerarquía visual muy marcada. El resto del estado (pool, parámetros en reposo, configuración) puede requerir mirar de cerca.

> **Con dieciséis anillos, esto decide el reparto de la pantalla** (2026-09-02).
> El handoff daba al anillo un quinto del ancho, proporción dibujada para
> **cinco** anillos; con dieciséis, cada banda quedaba en unos 6 puntos y el
> playhead era ilegible por construcción. El anillo pasa a llevarse la columna
> ancha y la lectura la estrecha, que es lo que este apartado implica: el
> protagonista es la visualización del patrón, y el ancho se reparte según eso y
> no según cuánto texto hay que poner.
>
> **El valor grande dejó de dibujarse sobre el patrón.** Vive en su propia
> columna, así que la regla de que el patrón permanezca visible debajo deja de
> ser algo que haya que recordar al dibujar: son dos regiones que no se solapan.
>
> Y una consecuencia práctica: **una lectura que se corta no se lee**. Envolver
> a dos líneas es preferible a truncar, porque el texto grande existe para
> leerse de lejos y `Probabilit…` no cumple eso.
>
> **Y por eso los Tracks bajaron a doce el mismo día.** Ensanchar la columna
> arregló el reparto horizontal pero no el vertical: el ancho de cada banda sale
> de repartir el radio entre `trackCount − 1`, así que la única palanca que
> quedaba era el número de anillos. Doce da bandas un tercio más anchas sin tocar
> el dibujo. Es la misma decisión leída dos veces: cuánto sitio se le da al
> patrón, y cuántas cosas caben dentro sin dejar de leerse.

## Reglas de interacción

### Knobs — modo relativo

Los encoders operan en **modo relativo**: incrementan o decrementan desde el valor actual del software. Sin saltos, sin zona muerta de pickup, sin necesidad de "alcanzar" un valor. Es el comportamiento de un secuenciador hardware, y la razón de elegirlo: girar produce siempre un cambio inmediato y proporcional.

Implicaciones de diseño:

- El estado del software es la única fuente de verdad; la posición física del knob es irrelevante.
- La aceleración por velocidad de giro es deseable en rangos amplios (Steps 1–64), no en rangos cortos.
- Un giro debe producir cambio audible dentro del siguiente step. La latencia de knob a MIDI es un criterio de calidad, no un detalle de implementación.

### Feedback de parámetro

**Valor grande transitorio sobre estado persistente.** Al girar un knob, su valor aparece en grande y se desvanece tras la inactividad; el anillo del patrón permanece siempre visible bajo él y nunca se oculta. Nunca se sustituye el contexto por el detalle.

### Reparto táctil / knob

La frontera es firme:

| Superficie | Cubre |
|---|---|
| **Knobs y pads** | Todo parámetro generativo: Steps, Pulses, Rotate, Division, Velocity, Sustain, Timing, Delay, Probability, pool de Pitch. |
| **Pantalla táctil** | Configuración: selección de Scale y Root, **el canal MIDI de cada Track**, mapeos MIDI, guardado, selección de dispositivo. Y el transporte. |

> **Excepción del 2026-09-02: mute y solo están en las dos superficies.** Se
> accionan con el dedo —el par M/S bajo cada pastilla de Track— y con los step
> buttons 15 y 16 mantenidos como modificador. Las dos vías terminan en el mismo
> sitio, por la misma razón que la selección de Track: si no coincidieran, la
> pantalla mentiría sobre lo que el hardware acaba de hacer.
>
> **No rompe la frontera, porque no la cruza.** La tabla reparte *parámetros
> generativos* contra *configuración*, y la mezcla no es ninguna de las dos: no
> cambia lo que el Track toca, solo si se oye. Es también la razón por la que
> sigue disponible sin controlador conectado sin contradecir la regla de abajo
> —silenciar no es editar—.
>
> Track `mute-solo_20260902`.

> **Excepción del 2026-09-05: Ctrl All congela la configuración táctil mientras
> dura.** Con el step button 14 mantenido, Scale, Root, el canal, la selección de
> Track y el número de Cycles activos dejan de responder al dedo. Vuelven solos al
> soltar.
>
> **No es una frontera nueva sino su consecuencia.** Ctrl All promete que soltar
> devuelve exactamente lo que había, y esa promesa solo es cierta si nada más pudo
> escribir mientras tanto: un cambio de Scale reencuadra el pool, y el pool no
> está en lo que el gesto guarda para devolver. Congelar es lo que hace la promesa
> verdadera; dejarlo abierto la convertiría en una casi-promesa, que es peor que
> ninguna.
>
> **Temp no lo hace**, y la asimetría es deliberada: su promesa está acotada a un
> Track y a los parámetros que la mano toca, y convive con la pantalla desde
> `temp-parameters_20260904`.
>
> Track `ctrl-all_20260905`.

**Sin controlador conectado la app es de solo lectura y transporte:** se reproduce y se ve el estado, no se editan parámetros generativos. La configuración táctil sigue disponible — no es un parámetro generativo.

Consecuencia para el desarrollo: probar el motor sin hardware exige un **controlador virtual de desarrollo** que inyecte eventos MIDI relativos. Es una herramienta de test, excluida del build de producción; no es un modo de edición táctil por la puerta de atrás.

### Destructividad

Guardar es explícito; el estado de trabajo se protege solo (Autosave). Cualquier acción que descarte trabajo (`Reload`) se confirma. Cambiar un parámetro nunca destruye material: el pool tonal sobrevive a un cambio de Scale reencuadrándose, no vaciándose.

## Antipatrones

- Modales que bloqueen mientras el transporte corre.
- Parámetros generativos que solo existan en pantalla y no sean mapeables a un knob.
- Mostrar una nota fija por paso — contradice el modelo de pool.
- Animaciones no derivadas del reloj musical.
- Introducir un sinónimo para un término ya definido en la Pre Spec.

> **Nota del 2026-09-07 — `banks` es la pantalla que se toca mientras suena.**
>
> La rebanada 4 de la v2 (`persistence_20260907`) le pone detrás los dieciséis
> Banks, los 256 Patterns y el disco, y con eso **enmienda el reparto táctil**:
> `banks` estaba descrita del lado de «se configura antes de tocar», y elegir un
> Pattern es un gesto de directo.
>
> **La frontera real no era temporal, era qué se edita con el dedo.** En `banks`
> no se edita material generativo: se elige cuál suena, se guarda y se vuelve a
> un punto de retorno. `track` sigue con sus cuatro escrituras táctiles
> auditadas y ninguna toca Shape ni Groove.
>
> **Lo que la pantalla promete y tiene que cumplir:**
>
> - **Decir cuánto falta.** Entre pulsar un Pattern y el compás en que entra
>   pasan hasta cuatro segundos a 60 BPM. La cuenta atrás va en negras —«in 2»—
>   porque es una instrucción que se sigue tocando, no un dato que interpretar.
> - **Decir qué está vacío con la palabra exacta.** `empty` no es «apagado por
>   ahora»: el hueco existe y no tiene material.
> - **Explicar los botones que no se pueden pulsar.** `Reload` sin punto de
>   retorno lleva el motivo debajo. Un botón apagado sin explicación se lee como
>   un fallo de la app.
> - **No callarse un guardado que falla.** El aviso persiste hasta que uno
>   funcione, y va antes que el de MIDI en la barra: sin destino MIDI no se oye
>   nada y eso se nota solo; un Autosave fallando no se nota hasta perder el
>   trabajo.

