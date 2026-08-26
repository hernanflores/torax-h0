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
- **App** — SwiftUI, presentación y estado de aplicación.

## Motor generativo

**Swift puro, sin dependencias de plataforma ni de UI.** Reparto euclidiano, Rotate, pool tonal, cuantización a Scale, Velocity/Probability/Sustain: funciones deterministas sobre estado.

Es lo que hace testeable el criterio de éxito y lo que permite añadir después Cycles, Random y LFO sin tocar la capa MIDI.

El aleatorio es **pseudoaleatorio con semilla**: la Pre Spec exige que sea repetible en loop, no caótico ("cambia, pero no es caos totalmente impredecible"). PRNG explícito y sembrado, nunca `Int.random()`.

## MIDI

**Salida: solo a hardware externo en v1.** CoreMIDI a dispositivos físicos (USB / Camera Kit). Coherente con el MVP y con medir timing contra hardware real, que es lo que se quiere validar.

Fuera de v1: puertos virtuales para otras apps del iPad, y Bluetooth MIDI (que introduce latencia y jitter propios, justo sobre lo que se quiere medir).

**Entrada de control:** CoreMIDI de entrada, encoders en **modo relativo**. Preset para Arturia BeatStep Pro + MIDI Learn para reasignar a otro hardware.

**Controlador virtual de desarrollo:** inyector de eventos MIDI relativos para probar el motor sin hardware conectado. Herramienta de test, excluida del build de producción.

## Persistencia

`Codable` → JSON en disco. El árbol completo (Project › Banks › Patterns › Tracks › Cycles) es estado pequeño y estructurado: JSON es inspeccionable, diffeable y **da el Backup Project (exportar/importar) prácticamente gratis**. Autosave por escritura atómica.

Toda estructura persistida lleva versión de esquema desde el primer commit — el modelo va a crecer al incorporar lo que v1 dejó fuera.

## Testing

Dos niveles, separados a propósito:

1. **Tests unitarios deterministas** sobre el motor puro: distribución euclidiana (16/4, 16/5, 12/7 de la Pre Spec), Rotate, cuantización a Scale, aplicación de Groove, reproducibilidad del PRNG sembrado.
2. **Arnés de medición de jitter**: captura timestamps reales de entrega contra un destino MIDI y reporta desviación. Convierte el criterio de éxito principal en un número, no en una impresión.

## Dependencias

**Ninguna de terceros en v1.** Todo lo necesario está en CoreMIDI y la stdlib de Swift. Añadir dependencias solo con justificación explícita.
