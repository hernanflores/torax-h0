# Torax H-0

Secuenciador MIDI algorítmico nativo para iPad. Torax H-0 no genera audio: controla instrumentos externos mediante MIDI y produce secuencias reproducibles a partir de reglas rítmicas y musicales.

El controlador MIDI es el instrumento y el iPad funciona como cerebro, pantalla de estado y transporte.

## Estado del proyecto

El repositorio contiene una primera versión funcional del núcleo de timing y del MVP de transporte:

- Transporte `Play` / `Stop`.
- Salida MIDI mediante CoreMIDI hacia dispositivos externos.
- Entrada de control MIDI para encoders relativos.
- Selección de fuentes y destinos MIDI disponibles.
- Un `Track` generativo basado en ritmo euclidiano.
- Parámetros actuales de `Shape`: `Steps`, `Pulses`, `Rotate` y `Division`.
- Medición de jitter desde la propia app.
- Tests unitarios para los paquetes `Engine` y `MIDI`.

La interfaz actual es una pantalla mínima de estado y transporte. La representación circular del patrón y la edición completa de parámetros pertenecen a iteraciones posteriores.

## Requisitos

- macOS con Xcode 26.3 o posterior.
- iPadOS 17 o posterior para ejecutar la aplicación.
- Un iPad físico para validar la salida MIDI y las mediciones de timing.
- Para el flujo de control probado: Arturia BeatStep Pro configurado con encoders en modo `Relative #2`.

No se utilizan dependencias de terceros en v1.

## Ejecutar la aplicación

1. Abrir `ToraxH0.xcodeproj` en Xcode.
2. Seleccionar el esquema `ToraxH0`.
3. Elegir un iPad físico como destino.
4. Conectar un dispositivo MIDI externo por USB o Camera Kit.
5. Ejecutar la aplicación.

Sin un destino MIDI conectado, la aplicación permanece en modo de solo lectura para los parámetros generativos, aunque el estado y el transporte siguen disponibles.

La salida de producto está diseñada para hardware MIDI externo. Los endpoints MIDI virtuales solo se utilizan como instrumentación de medición en Debug.

## Tests

Los paquetes se prueban directamente porque el proyecto raíz es un proyecto Xcode y no contiene un `Package.swift`.

```bash
swift test --package-path Packages/Engine
swift test --package-path Packages/MIDI
```

Los tests de `MIDI` utilizan CoreMIDI en macOS. La suite que crea clientes y endpoints puede ejecutarse por separado si el entorno presenta problemas al crear hilos o endpoints virtuales:

```bash
swift test --package-path Packages/MIDI \
  --filter 'VirtualLoopbackTests|JitterHarnessTests|CoreMIDIOutputTests|CoreMIDIInputTests'

swift test --package-path Packages/MIDI \
  --skip VirtualLoopbackTests \
  --skip JitterHarnessTests \
  --skip CoreMIDIOutputTests \
  --skip CoreMIDIInputTests
```

La integración continua ejecuta esta partición en GitHub Actions sobre `macos-latest`.

## Compilar

```bash
xcodebuild build \
  -scheme ToraxH0 \
  -destination 'generic/platform=iOS'
```

Para formatear el código Swift:

```bash
swift format --in-place --recursive App Packages
```

## Medición de jitter

La app incluye un arnés de medición para comprobar la estabilidad de la entrega MIDI. Desde la sección `Jitter` se puede medir con 200 o 1000 eventos por tempo, a 60, 120 y 174 BPM.

El umbral utilizado es:

- Desviación máxima menor que 2 ms.
- Desviación estándar menor que 0,5 ms.

La medición se ejecuta en un iPad real, no en el simulador. También puede iniciarse automáticamente con los argumentos `--auto-measure` y `--samples=<n>`. El informe se guarda en el directorio `Documents` del dispositivo como `jitter-report.txt`, y la traza de progreso como `jitter-trace.txt`.

La arquitectura usa scheduling look-ahead con timestamps futuros de CoreMIDI. Las mediciones actuales validan el scheduler y CoreMIDI mediante loopback virtual; no validan todavía el cable USB-MIDI ni el comportamiento de un sintetizador externo bajo carga real.

## Arquitectura

El proyecto está dividido en capas con responsabilidades claras:

```text
App
├── SwiftUI y estado de presentación
├── Transporte y selección de dispositivos
└── Instrumentación de jitter

MIDI
├── CoreMIDI input/output
├── Transporte y scheduler look-ahead
├── Decodificación de controles relativos
├── Handoff de snapshots sin locks
└── Arnés de medición

Engine
├── Shape y Track
├── Ritmo euclidiano
└── Tiempo musical y divisiones

CToraxAtomics
└── Atómicos lock-free en C para iPadOS 17
```

`Engine` es un paquete Swift puro y no depende de SwiftUI, UIKit ni CoreMIDI. El scheduler recibe snapshots inmutables y evita asignaciones, locks y `await` en el camino crítico de timing.

## Estructura del repositorio

```text
App/                         Aplicación SwiftUI
Config/                      Configuración Debug de Info.plist
Packages/Engine/              Motor generativo y tests
Packages/MIDI/                MIDI, scheduler y tests
ToraxH0.xcodeproj/            Proyecto Xcode de iPadOS
.github/workflows/swift.yml   CI para build y tests de paquetes
conductor/                    Especificaciones y documentación interna
```

## Alcance de v1

El MVP está orientado a validar el timing y el flujo de un único `Track`. Quedan fuera de v1:

- Múltiples `Tracks`, `Patterns` y `Banks`.
- `Cycles`, `LFO` y modulación aleatoria.
- `Tonal`, `Scale`, `Root` y pool completo de pitches.
- `Groove` completo, incluyendo `Velocity`, `Sustain`, `Timing`, `Delay` y `Probability`.
- Note Repeater, Harmony, Voicing y Style.
- Autosave, Backup Project y persistencia completa.
- Ableton Link, MIDI Program Change y encadenado de Patterns.
- Puertos MIDI virtuales como funcionalidad de producto.

La definición funcional completa se encuentra en [`conductor/product.md`](conductor/product.md) y el diseño original en [`Pre Spec Torax H-0.md`](Pre%20Spec%20Torax%20H-0.md).

## Desarrollo

Las decisiones de arquitectura, las restricciones del camino de timing y el flujo de trabajo están documentados en:

- [`conductor/tech-stack.md`](conductor/tech-stack.md)
- [`conductor/workflow.md`](conductor/workflow.md)
- [`conductor/product-guidelines.md`](conductor/product-guidelines.md)

Los cambios que afectan al scheduler o a la entrega MIDI deben verificarse con el arnés de jitter y probarse en un dispositivo real.

## Licencia

Este repositorio no incluye actualmente un archivo de licencia.
