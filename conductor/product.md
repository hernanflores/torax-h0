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

- **Controlador MIDI = entrada primaria.** Knobs para parámetros continuos, pads como los 16 Value Buttons.
- **Pantalla = feedback + edición secundaria.** Muestra estado (pasos activos, pool tonal, Cycle en curso) y expone lo que no cabe en knobs: Scale, guardado, mapeos.
- **Mapeo:** preset listo para BeatStep Pro + **MIDI Learn** para reasignar a otro hardware.

## MVP Scope — v1

**Dentro:**

- Un **Track generativo completo**:
  - Shape: Steps (1–16), Pulses euclidianos, Rotate, Division (1/1–1/32). **Entregado** (rebanadas 1–2; 1/32 en la 5).
  - Tonal: pool de hasta 8 pitches, Scale + Root. **Entregado** (rebanada 4).
  - Groove: Velocity, Sustain, Probability. **Entregado** (rebanada 5).
  - Groove: Timing (swing) y Delay. Pendiente (rebanada 6).
- Transporte (play/stop) y reloj interno.
- Salida MIDI por CoreMIDI a dispositivo externo.
- Mapeo del controlador + MIDI Learn.
- Pantalla de estado del Track.

**Fuera de v1:**

- Acordes polifónicos simultáneos (Style *Poly*) — explícitamente fuera de scope en la Pre Spec.
- Múltiples Tracks, Patterns, Banks; guardado/Autosave/Backup Project.
- Cycles; Note Repeater (Repeats/Time/Ramp/Pace); Harmony; Voicing/Style; Range/Phrase; LFO y Random Modulation.
- Ableton Link, MIDI Program Change, encadenado de Patterns.

## Success Criteria

**Criterio principal: timing MIDI estable en iPad.** Jitter bajo y consistente contra hardware real; swing (Timing) y Delay que se sientan musicales. Es el mayor riesgo técnico de la plataforma y lo que decide si el proyecto es viable — por eso v1 se reduce a un Track: validar el motor de punta a punta antes de escalar.

> **Estado (2026-08-26): validado.** Medido en iPad Air 4ª generación: σ ≈ 9 µs y máximo 0,149 ms, frente a un umbral de 0,5 ms / 2 ms. La arquitectura de look-ahead scheduling aguanta. Ver [`verdict.md`](./archive/timing-spike_20260826/verdict.md).
>
> **Actualización (2026-08-27): medido con carga.** Con el motor generativo y la interfaz corriendo: máximo 0,127 ms y σ 0,015 ms en el peor tempo. Sin degradación grosera. La σ sube de 8–9 µs a 12–15 µs respecto al spike —4–7 µs, inaudibles— y sube con el tempo. Ver [`measurement-200.txt`](./archive/mvp-shape-transport_20260827/measurement-200.txt).
>
> **Cierre (2026-08-28): medido con el anillo.** Era la carga visual que faltaba. Con el anillo circular y el playhead redibujándose: máximo **0,134 ms** y σ hasta **0,020 ms**, contra 0,127 ms y 0,015 ms sin él. El redibujado cuesta unos 5 µs de σ en el peor tempo —mismo orden que el salto anterior, e inaudible—, y la σ queda 25 veces por debajo del umbral de 0,5 ms. **La arquitectura de look-ahead aguanta también la carga de dibujo.** Ver la git note de `9189aec` (track `mvp-ring-feedback_20260828`).

Secundarios:

- Los knobs responden sin saltos de valor ni latencia perceptible.
- El comportamiento de los parámetros es fiel al modelo de la Pre Spec.

## Source

Basado en `Pre Spec Torax H-0.md` (documento de diseño original).
