# Product Definition — Torax H-0

## Vision

Torax H-0 es un **secuenciador MIDI algorítmico para iPad**, operado con un controlador de knobs y pads (BeatStep Pro como referencia). No genera audio: controla instrumentos externos por MIDI.

Su premisa: no se programa cada evento fijo, se definen **reglas** de ritmo, altura, dinámica, tiempo y variación que producen una secuencia reproducible pero viva.

## Problem

Los secuenciadores por piano-roll obligan a escribir cada nota; los generativos suelen ser cajas negras impredecibles. Torax H-0 busca el punto medio: material musical acotado (pool tonal, escala, pulsos euclidianos) sobre el que la variación es controlada y repetible — desarrollo estructurado (Cycles), no caos.

## Target User

Uso personal y músicos que trabajan con hardware MIDI externo, cómodos operando con las manos sobre knobs en lugar de con el ratón. El controlador es el instrumento; el iPad es el cerebro y la pantalla de estado.

## Core Model

```
Project (estado completo + ajustes)
└── 16 Banks (tempo propio)
    └── 16 Patterns por Bank
        └── hasta 16 Tracks polifónicos
            └── hasta 16 Cycles por Track
```

- **Project:** estado completo: 16 Banks, sus Patterns/Tracks y ajustes asociados.
- **Bank:** contenedor musical de alto nivel (canción, setup o sección de live). 16 Patterns y tempo propio.
- **Pattern:** sección musical que reproduce el estado de sus 16 Tracks en conjunto (groove principal, break, fill, variante). Disparable cuantizado, encadenable, seleccionable por MIDI Program Change.
- **Track:** una voz/carril musical y de control. Donde residen los parámetros generativos.
- **Cycle:** snapshot de parámetros de un Track. Permite que ese Track varíe en pasadas sucesivas del loop sin cambiar de Pattern.

El motor por capas: **Shape** decide *cuándo* y con qué densidad ocurren eventos → **Tonal** define el pool de notas y su movimiento armónico → **Groove** convierte la secuencia en interpretación (dinámica, probabilidad, duración, desplazamiento) → **Cycles / LFO / Random** aportan desarrollo en el tiempo.

## Interaction Model

- **Controlador MIDI = entrada primaria.** Knobs para parámetros continuos; pads para el pool tonal. **Un pad es un grado de la escala, no una altura fija**: los catorce primeros dan dos octavas alineadas de la escala vigente y dos mueven el registro entero, así que qué suena depende de Scale y Root y no del número que envía el controlador. Detalle en la nota del 2026-08-31 de la Pre Spec.
- **Pantalla = feedback + edición secundaria.** Muestra estado (pasos activos, pool tonal, Cycle en curso) y expone lo que no cabe en knobs: Scale, guardado, mapeos.

> **Nota del 2026-08-31 — Scale y Root son de cada Track, no de la app.** Esta
> página y `product-guidelines.md` los describían como configuración táctil sin
> decir de qué, y con un solo Track daba igual. Con dieciséis no: la Pre Spec
> pone los parámetros generativos en el Track —«una voz/carril musical y de
> control»— y eso incluye el marco tonal. **Dónde se editan no cambia**: siguen
> siendo táctiles, del lado de la pantalla; lo que cambia es a quién afectan, que
> es el Track seleccionado.
>
> Lo hace posible un bajo en menor bajo un arpegio en mayor, que con un marco
> global no se podía expresar. Entra con la rebanada 1 de la v2
> (`multi-track_20260831`).
- **Mapeo:** preset listo para BeatStep Pro + **MIDI Learn** para reasignar a otro hardware.

## MVP Scope — v1

**Dentro:**

- Un **Track generativo completo**:
  - Shape: Steps (1–16), Pulses euclidianos, Rotate, Division (1/1–1/32). **Entregado** (rebanadas 1–2; 1/32 en la 5).
  - Tonal: pool de hasta 8 pitches, Scale + Root. **Entregado** (rebanada 4).
  - Groove: Velocity, Sustain, Probability. **Entregado** (rebanada 5).
  - Groove: Timing (swing) y Delay. **Entregado** (rebanada 6).
- Transporte (play/stop) y reloj interno.
- Salida MIDI por CoreMIDI a dispositivo externo.
- Mapeo del controlador + MIDI Learn. **Se parte en dos rebanadas** (ver la nota
  de abajo): el preset del BeatStep Pro, **entregado** (rebanada 7); MIDI Learn,
  en la 8.
- Pantalla de estado del Track.

> **Nota del 2026-08-31 — «Mapeo del controlador + MIDI Learn» es una línea y
> son dos rebanadas.** Escrito como una sola entrega, el alcance mezcla dos
> problemas que no comparten nada. El **preset** decide *qué significa cada
> control físico* —dominio musical: qué nota da cada pad, qué parámetro mueve
> cada knob— y **MIDI Learn** decide *cómo se reasigna a otro hardware*
> —infraestructura de entrada, que arrastra el defecto
> [`network-session-source`](./tracks/network-session-source_20260828/index.md) y
> con él una investigación de CoreMIDI—. Juntas metían esa investigación dentro
> de una rebanada cuyo núcleo es la escala.
>
> - **Rebanada 7** (`mvp-beatstep-mapping_20260830`): el preset del BeatStep Pro
>   —knobs, pads y step buttons—, versionado en el repositorio y verificado en
>   dispositivo.
> - **Rebanada 8**: MIDI Learn, con `network-session-source` dentro, donde el
>   defecto sí bloquea: MIDI Learn tiene que escuchar la fuente correcta y en
>   iPad la sesión de red se autoselecciona.
>
> **Las dos siguen dentro de la v1**; lo que cambia es que se entregan por
> separado. La 7 cerró el 2026-08-31: el preset vive en
> [`preset/`](../preset/README.md) —tabla de los cuarenta y ocho controles y el
> proyecto exportado desde MIDI Control Center—, verificado con el controlador en
> la mano. Hasta que cierre la 8, esta página promete un MIDI Learn que la app
> todavía no hace.

**Fuera de v1:**

- Acordes polifónicos simultáneos (Style *Poly*) — explícitamente fuera de scope en la Pre Spec.
- Patterns, Banks; guardado/Autosave/Backup Project. *(Múltiples Tracks salieron de aquí el 2026-09-01: la v2 rebanada 1 entrega los dieciséis.)*
- Cycles; Note Repeater (Repeats/Time/Ramp/Pace); Harmony; Voicing/Style; Range/Phrase; LFO y Random Modulation.
- Ableton Link, MIDI Program Change, encadenado de Patterns.

## Success Criteria

**Criterio principal: timing MIDI estable en iPad.** Jitter bajo y consistente contra hardware real; swing (Timing) y Delay que se sientan musicales. Es el mayor riesgo técnico de la plataforma y lo que decide si el proyecto es viable — por eso v1 se reduce a un Track: validar el motor de punta a punta antes de escalar.

> **Estado (2026-08-26): validado.** Medido en iPad Air 4ª generación: σ ≈ 9 µs y máximo 0,149 ms, frente a un umbral de 0,5 ms / 2 ms. La arquitectura de look-ahead scheduling aguanta. Ver [`verdict.md`](./archive/timing-spike_20260826/verdict.md).
>
> **Actualización (2026-08-27): medido con carga.** Con el motor generativo y la interfaz corriendo: máximo 0,127 ms y σ 0,015 ms en el peor tempo. Sin degradación grosera. La σ sube de 8–9 µs a 12–15 µs respecto al spike —4–7 µs, inaudibles— y sube con el tempo. Ver [`measurement-200.txt`](./archive/mvp-shape-transport_20260827/measurement-200.txt).
>
> **Rebanada 6 (2026-08-30): medido con la rejilla desplazada dentro.** La
> primera medición desde la rebanada 3, con 1000 eventos por tempo: máximo
> **0,151 ms** y σ entre **0,009 y 0,013 ms**. La σ **bajó** respecto a la
> referencia de 0,020 ms, así que el intervalo sin medir de las rebanadas 4 y 5
> queda absuelto sin bisecar. El máximo sube porque la muestra es cinco veces
> mayor. Swing y Delay se juzgaron al oído, no con el arnés: ver la enmienda de
> la Fase 6 en el plan de `mvp-groove-temporal_20260830`.
>
> **Cierre (2026-08-28): medido con el anillo.** Era la carga visual que faltaba. Con el anillo circular y el playhead redibujándose: máximo **0,134 ms** y σ hasta **0,020 ms**, contra 0,127 ms y 0,015 ms sin él. El redibujado cuesta unos 5 µs de σ en el peor tempo —mismo orden que el salto anterior, e inaudible—, y la σ queda 25 veces por debajo del umbral de 0,5 ms. **La arquitectura de look-ahead aguanta también la carga de dibujo.** Ver la git note de `9189aec` (track `mvp-ring-feedback_20260828`).
>
> **v2 rebanada 1 (2026-09-01): medido con los dieciséis sonando.** Es la
> medición que la v1 existió para poder hacer. Con 200 eventos por tempo:
> máximo **0,598 ms** y σ hasta **0,083 ms**, contra los 0,151 ms y 0,013 ms de
> la referencia. **CUMPLE**, con el máximo 3,3 veces por debajo del umbral y la
> σ 6 veces. El exceso está **solo a 174 BPM**; a 60 y 120 BPM la medición es
> indistinguible de la referencia. Lo que absuelve al cambio es que **la media
> no se mueve** —entre +0,105 y +0,121 ms en los tres tempos, igual que en las
> cinco mediciones anteriores—: copiar dieciséis Tracks por ventana costaría
> tiempo de forma sistemática, y eso subiría la media y degradaría los tres
> tempos a la vez. Lo que se ensanchó es la cola en el tempo más rápido.
> **La arquitectura de look-ahead aguanta dieciséis voces sobre un hilo.** Ver
> [`device-verification.md`](./tracks/multi-track_20260831/device-verification.md),
> que deja anotado que los estadísticos de resumen no distinguen unos pocos
> outliers de un corrimiento de la distribución, y que hacerlo pide percentiles
> en el reporte del arnés.

Secundarios:

- Los knobs responden sin saltos de valor ni latencia perceptible.
- El comportamiento de los parámetros es fiel al modelo de la Pre Spec.

## Source

Basado en `Pre Spec Torax H-0.md` (documento de diseño original).
