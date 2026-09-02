# Product Guidelines — Torax H-0

## Principio rector

**El controlador es el instrumento; la pantalla es el espejo.** Ninguna decisión de diseño debe exigir mirar el iPad para tocar. La pantalla se lee de reojo, en movimiento, a veces con poca luz.

## Voz y tono

- **Preciso, no conversacional.** La app no explica ni acompaña: informa. `Steps 16 · Pulses 5`, no "Has elegido 5 pulsos".
- **Vocabulario de la Pre Spec, en inglés, sin traducir.** Steps, Pulses, Rotate, Division, Velocity, Sustain, Timing, Delay, Probability, Scale, Root, Pitch. Un solo término por concepto en UI, código y documentación — sin sinónimos, sin capa de traducción.
- **Sin mensajes de error emotivos.** Un dispositivo MIDI desconectado se comunica con un estado (`No MIDI device`), no con una disculpa.

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
| **Pantalla táctil** | Configuración: selección de Scale y Root, mapeos MIDI, guardado, selección de dispositivo. Y el transporte. |

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
