# Spec — Timing Spike: validación del reloj MIDI

**Track ID:** `timing-spike_20260826`
**Track type:** Spike / Foundation

## Overview

Validar que la arquitectura de **look-ahead scheduling con timestamps de CoreMIDI** definida en `tech-stack.md` alcanza el timing exigido por `product.md`, **antes** de construir el motor generativo encima.

Es el track que responde la pregunta que decide la viabilidad del proyecto: *¿puede un iPad emitir MIDI con precisión musical?* Si la respuesta es no, es preferible saberlo ahora.

El código no es desechable: scaffold, capa MIDI y scheduler se escriben con calidad de producción y son el primer ladrillo del proyecto.

## Functional Requirements

### FR1 — Scaffold del proyecto

Proyecto Xcode para iPadOS 17+, con paquetes SPM `Engine`, `MIDI` y target `App`. `Engine` no se usa en este track pero se crea con su frontera de dependencias ya impuesta.

### FR2 — Salida MIDI por CoreMIDI

Cliente CoreMIDI que enumera destinos, se conecta a uno y envía note-on/note-off vía `MIDISendEventList` **con timestamp de entrega futuro**.

### FR3 — Scheduler look-ahead

Reloj que calcula eventos de una ventana futura y los entrega ya sellados. Ejecuta en hilo dedicado, **sin asignaciones, locks ni `await`** en su camino (`code_styleguides/swift.md`). Tempo configurable; división fija 1/16.

### FR4 — Endpoint virtual de loopback *(instrumentación)*

Fuente y destino virtuales que permiten a la app recibir su propia salida y comparar el timestamp de recepción contra el programado.

> **Desviación de `tech-stack.md`:** los endpoints virtuales estaban fuera de v1. Se admiten **como instrumentación de medición, no como funcionalidad de producto**. Requiere nota fechada en `tech-stack.md` antes de implementar (`workflow.md`, paso 8 del Task Workflow).

### FR5 — Arnés de medición de jitter

Ejecuta un barrido de tempos, captura la desviación de cada evento y reporta **máximo, media y desviación típica** por tempo.

- Señal: nota fija a 1/16.
- Tempos: 60, 120 y 174 BPM.
- Muestra: **200 eventos por tempo** (~30 s cada uno), configurable.

### FR6 — UI mínima

Play/stop, selección de tempo y presentación de los resultados. Sin anillo, sin knobs, sin lenguaje visual: eso llega en tracks posteriores.

## Non-Functional Requirements

- **NFR1 — Realtime safety:** el hilo del scheduler no asigna, no bloquea, no registra logs, no toca SwiftUI. Toda función en ese camino lleva el marcador `/// Realtime:`.
- **NFR2 — Pureza de `Engine`:** el paquete no importa nada más allá de la stdlib, aunque en este track esté prácticamente vacío.
- **NFR3 — Sin dependencias de terceros.**
- **NFR4 — Cobertura:** `MIDI` ≥80%. La lógica de scheduling (cálculo de instantes, conversión tempo→ticks) es testeable sin hardware y debe estarlo.

## Acceptance Criteria

**Criterio principal — el que decide el track:**

> Medido por loopback en el iPad objetivo, a 60, 120 y 174 BPM:
> **desviación máxima < 2 ms** y **desviación típica < 0.5 ms**.

Además:

- [ ] `swift test` sobre `Engine` y `MIDI` pasa sin simulador ni hardware.
- [ ] El arnés corre en dispositivo y reporta las tres métricas por tempo.
- [ ] El resultado numérico queda registrado en la git note del commit correspondiente (`workflow.md`).
- [ ] Ninguna asignación ni lock en el camino del scheduler, verificado por revisión.
- [ ] `tech-stack.md` lleva la nota fechada sobre endpoints virtuales.

**Si el umbral no se cumple:** el track **para y reporta con datos**. No se itera indefinidamente ni se prueban arquitecturas alternativas dentro de este track; la decisión de cómo seguir es explícita del usuario. Un spike que falla y lo documenta ha cumplido su función.

## Known Limitations

1. **Tamaño de muestra.** 200 eventos por tempo dan una desviación típica fiable, pero son poca muestra para el criterio de *máximo*: un outlier de frecuencia baja (una vez por minuto) puede no aparecer. Antes de dar el resultado por definitivo, conviene una pasada larga (~1000 eventos).
2. **El loopback no cruza el cable.** Con endpoints virtuales se valida el scheduler y CoreMIDI, no la cadena completa hasta el sintetizador. La latencia y el jitter del interfaz USB-MIDI quedan sin medir.
3. **La medición es de ida y vuelta.** Incluye el sellado de timestamp en recepción, así que no separa el error de envío del de recepción. Como el criterio es la desviación total percibida es aceptable, pero no es un diagnóstico por etapas.
4. **Un solo dispositivo.** Se valida en el iPad objetivo. No dice nada del iPad más antiguo soportado por iPadOS 17.

## Out of Scope

- Motor generativo: euclidiano, pool tonal, Groove, Cycles, Random, LFO.
- Entrada de control MIDI, mapeo de BeatStep Pro, MIDI Learn.
- Anillo circular, pool tonal en pantalla y todo el lenguaje visual de `product-guidelines.md`.
- Persistencia, Autosave, Backup Project.
- Múltiples Tracks, Patterns, Banks.
- Bluetooth MIDI; endpoints virtuales como funcionalidad de producto.
- Optimizar el timing más allá del umbral: cumplir es terminar.
