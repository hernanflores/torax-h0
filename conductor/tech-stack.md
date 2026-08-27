# Tech Stack — Torax H-0

## Plataforma

**iPadOS 17+, app nativa.**

Descartada la vía web: Safari en iOS/iPadOS **no implementa Web MIDI**, así que un secuenciador MIDI en navegador no es viable en iPad. Nativo es la única opción con acceso real al hardware.

iPadOS 17 como mínimo: cubre iPads desde ~2018 y da acceso a SwiftUI maduro (`Observable`, `Canvas`) sin código condicional para versiones antiguas.

## Resumen

| Capa | Elección |
|---|---|
| Lenguaje | Swift |
| UI | SwiftUI |
| MIDI | CoreMIDI |
| Reloj | Scheduler look-ahead + timestamps de CoreMIDI |
| Concurrencia | Snapshot inmutable, sin locks en el camino de timing |
| Persistencia | `Codable` → JSON en disco |
| Módulos | Paquetes SPM separados |
| Tests | XCTest sobre motor puro + arnés de medición de jitter |
| Dependencias de terceros | Ninguna en v1 |

## Arquitectura de timing — el núcleo del proyecto

> **Validado empíricamente el 2026-08-26** (track `timing-spike_20260826`), en iPad Air 4ª generación / iPadOS 26.5, con 1000 eventos por tempo a 60, 120 y 174 BPM: máximo **0,149 ms** y σ **0,009 ms** en el peor caso, frente a un umbral de 2 ms / 0,5 ms.
>
> Ver [`verdict.md`](./archive/timing-spike_20260826/verdict.md), **incluida su sección "Qué NO queda validado"**: la medición se hizo por loopback virtual (sin cruzar el cable USB) y sin carga — sin UI redibujando, sin motor generativo y sin 16 Tracks.

El criterio de éxito es *timing MIDI estable*, así que la arquitectura se organiza alrededor de él.

**Look-ahead scheduling con timestamps.** Un scheduler calcula los eventos de una ventana futura (del orden de decenas de ms) y los entrega a CoreMIDI vía `MIDISendEventList` **ya sellados con un timestamp de entrega futuro** (`mach_absolute_time` + offset). CoreMIDI se encarga de emitirlos en ese instante exacto.

La consecuencia es la razón de elegirlo: **el jitter deja de depender de cuándo despierta tu hilo.** El scheduler puede llegar tarde dentro de la ventana sin afectar al resultado audible. Un enfoque de "despertar y enviar ya" traslada cada hipo del planificador del SO directamente a la salida MIDI.

Implicaciones estructurales:

- **Timing y UI están desacoplados.** SwiftUI nunca está en el camino crítico; renderiza estado que ya ocurrió o va a ocurrir.
- **Timing musical (Sustain, Delay, swing) se expresa como offset de timestamp**, no como sleeps ni retardos de hilo.
- La ventana de look-ahead se equilibra contra la respuesta al knob: un giro debe oírse en el step siguiente, así que esa latencia acota el tamaño de la ventana.

## Concurrencia

**Estado inmutable con snapshot publicado atómicamente.** La UI edita el estado en el hilo principal; el scheduler lee un snapshot inmutable. **No hay locks en el camino de timing** — ni esperas, ni riesgo de inversión de prioridad, ni suspensiones por `await`.

Regla derivada: el hilo del scheduler no asigna memoria, no toma locks y no llama a código que pueda bloquear.

## Estructura de módulos

**Paquetes SPM separados**, con el motor generativo como paquete independiente sin acceso a SwiftUI ni UIKit.

Esto no es organización cosmética: **el compilador garantiza que el motor es puro**, y sus tests corren rápido y sin simulador. Separación mínima:

- **Engine** — motor generativo puro. Sin dependencias de plataforma.
- **MIDI** — CoreMIDI: scheduler, salida, entrada de control.
- **CToraxAtomics** — target C con atómicos sin lock, dentro del paquete `MIDI`.
- **App** — SwiftUI, presentación y estado de aplicación.

**Sobre `CToraxAtomics`:** el hilo del scheduler necesita comunicarse con el hilo de control sin bloquearse, y en iPadOS 17 no hay forma de hacerlo sin salir de la stdlib — `Synchronization.Atomic` de Swift 6 exige iOS 18 y `swift-atomics` sería una dependencia de terceros. Un target C propio con `<stdatomic.h>` resuelve el problema sin violar la regla de cero dependencias: es código del proyecto. Un test verifica que los atómicos son realmente lock-free y no una emulación con lock interno.

## Motor generativo

**Swift puro, sin dependencias de plataforma ni de UI.** Reparto euclidiano, Rotate, pool tonal, cuantización a Scale, Velocity/Probability/Sustain: funciones deterministas sobre estado.

Es lo que hace testeable el criterio de éxito y lo que permite añadir después Cycles, Random y LFO sin tocar la capa MIDI.

El aleatorio es **pseudoaleatorio con semilla**: la Pre Spec exige que sea repetible en loop, no caótico ("cambia, pero no es caos totalmente impredecible"). PRNG explícito y sembrado, nunca `Int.random()`.

## MIDI

**Salida: solo a hardware externo en v1.** CoreMIDI a dispositivos físicos (USB / Camera Kit). Coherente con el MVP y con medir timing contra hardware real, que es lo que se quiere validar.

Fuera de v1: puertos virtuales como **funcionalidad de producto** (para que otras apps del iPad reciban de Torax H-0), y Bluetooth MIDI (que introduce latencia y jitter propios, justo sobre lo que se quiere medir).

**Entrada de control:** CoreMIDI de entrada, encoders en **modo relativo**. Preset para Arturia BeatStep Pro + MIDI Learn para reasignar a otro hardware.

**Controlador virtual de desarrollo:** inyector de eventos MIDI relativos para probar el motor sin hardware conectado. Herramienta de test, excluida del build de producción.

**Restricción de iOS — endpoints virtuales y modo de fondo.** Crear endpoints MIDI virtuales en iOS exige declarar el modo de fondo `audio`; sin él, `MIDIDestinationCreateWithProtocol` devuelve `kMIDINotPermitted (-10844)`. En macOS no hace falta, así que el fallo no aparece en los tests de host: solo en el dispositivo.

Se declara **solo en Debug** (`Config/Info-Debug.plist` vía `INFOPLIST_FILE`), para que el binario de producción no arrastre un modo de fondo que únicamente necesita la instrumentación. Verificado: el `Info.plist` de Release no contiene `UIBackgroundModes`.

Nota de implementación: `INFOPLIST_KEY_UIBackgroundModes` **no funciona** — Xcode solo reconoce una lista cerrada de claves `INFOPLIST_KEY_*`. Hace falta un `Info.plist` explícito, y tras cambiarlo hay que ejecutar `xcodebuild clean` porque el plist generado queda cacheado.

### Enmienda — 2026-08-26: endpoints virtuales como instrumentación

**Qué cambia.** Se admiten endpoints virtuales de CoreMIDI (fuente y destino) **como instrumentación de medición**, no como funcionalidad de producto.

**Por qué.** El track `timing-spike_20260826` mide el jitter por loopback: la app se envía a sí misma y compara el timestamp de recepción contra el programado. Sin endpoints virtuales no hay loopback, y sin loopback no hay forma automática y repetible de medir el criterio de éxito del proyecto.

**Alcance de la excepción.** Los endpoints virtuales:

- Existen para medir, y solo se crean cuando el arnés de medición está activo.
- **No** aparecen como destino elegible para el usuario ni como puerto publicado del producto.
- No cambian la decisión de v1: la salida de producto sigue siendo solo a hardware externo.

**Limitación que introduce.** Un loopback virtual no cruza el cable USB: valida el scheduler y CoreMIDI, no la cadena completa hasta el sintetizador. La latencia y el jitter del interfaz USB-MIDI quedan sin medir. Está registrado como limitación conocida en `conductor/archive/timing-spike_20260826/spec.md`.

**Cuándo revisar esto.** Si en algún momento se decide publicar un puerto virtual como funcionalidad real (para sintes en el propio iPad), esta enmienda deja de ser una excepción y pasa a ser una decisión de producto que hay que tomar en `product.md`.

## Persistencia

`Codable` → JSON en disco. El árbol completo (Project › Banks › Patterns › Tracks › Cycles) es estado pequeño y estructurado: JSON es inspeccionable, diffeable y **da el Backup Project (exportar/importar) prácticamente gratis**. Autosave por escritura atómica.

Toda estructura persistida lleva versión de esquema desde el primer commit — el modelo va a crecer al incorporar lo que v1 dejó fuera.

## Testing

Dos niveles, separados a propósito:

1. **Tests unitarios deterministas** sobre el motor puro: distribución euclidiana (16/4, 16/5, 12/7 de la Pre Spec), Rotate, cuantización a Scale, aplicación de Groove, reproducibilidad del PRNG sembrado.
2. **Arnés de medición de jitter**: captura timestamps reales de entrega contra un destino MIDI y reporta desviación. Convierte el criterio de éxito principal en un número, no en una impresión.

## Dependencias

**Ninguna de terceros en v1.** Todo lo necesario está en CoreMIDI y la stdlib de Swift. Añadir dependencias solo con justificación explícita.
