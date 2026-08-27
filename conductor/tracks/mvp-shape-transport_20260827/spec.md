# Spec — MVP rebanada 1: Shape, transporte y primer sonido

**Track ID:** `mvp-shape-transport_20260827`
**Track type:** Feature (MVP, rebanada vertical)

## Overview

La primera vez que Torax H-0 suena.

El track `timing-spike_20260826` dejó construida la capa baja —reloj musical, scheduler look-ahead, salida CoreMIDI— y demostró que la arquitectura aguanta el criterio de timing. Pero `Engine` está vacío: no hay material musical, no hay transporte y no hay nada conectado a un sintetizador. Esta rebanada atraviesa el sistema de punta a punta por primera vez: **un Track con Shape sonando en hardware externo.**

Es una rebanada vertical y no una capa del motor a propósito. Corta fina en anchura —solo Shape, sin Tonal ni Groove— pero llega hasta el final: hasta que un sintetizador recibe notas. A partir de aquí el proyecto se puede escuchar, y las decisiones siguientes se toman oyendo en vez de razonando sobre documentos.

### El milestone es, literalmente, el estado «sin controlador conectado»

En esta rebanada **ningún parámetro generativo es editable**: el Track arranca con una configuración fija en la app, se reproduce y se ve su estado. No hay knobs todavía, y no se abre una puerta táctil provisional para suplirlos.

Eso no es una limitación que se tolera, es el producto funcionando como está especificado. `product-guidelines.md` define exactamente este estado: *«sin controlador conectado la app es de solo lectura y transporte: se reproduce y se ve el estado, no se editan parámetros generativos»*. Un slider provisional para Steps o Pulses sería precisamente el antipatrón que ese documento nombra —*«parámetros generativos que solo existan en pantalla»*— y habría que desmontarlo después.

La entrada de control (knobs relativos, controlador virtual de desarrollo, preset del BeatStep Pro, MIDI Learn) es el track siguiente.

## Functional Requirements

### FR1 — Shape en `Engine`

Reparto euclidiano puro y determinista, sin dependencias de plataforma:

- **Steps** 1–16. El rango 1–64 queda fuera de v1; el tipo se valida a 1–16.
- **Pulses** 1..Steps, repartidos euclidianamente.
- **Rotate**: desplazamiento del patrón sobre el anillo.
- **Division**: valor rítmico del Step. El tipo ya existe; aquí se conecta.

Los casos de la Pre Spec —**16/4, 16/5, 12/7**— son casos de test literales, según `workflow.md`.

### FR2 — Estado del Track y snapshot inmutable en caliente

El estado del Track se edita en el hilo principal y cruza al scheduler como **snapshot inmutable publicado atómicamente**. Sin locks en el camino de timing.

Es la pieza que el spike dejó explícitamente pendiente: su `SchedulerConfiguration` se capturaba una vez al arrancar y no volvía a leerse. Aquí el scheduler tiene que **recoger un snapshot nuevo mientras suena**, porque cambiar parámetros en caliente es el gesto central del producto y el mayor riesgo técnico que queda en pie tras el spike.

Se implementa y se cubre **con tests**, no con un gesto de usuario: publicar un snapshot nuevo a media reproducción y verificar que el scheduler lo recoge en la ventana siguiente, sin duplicar ni omitir Steps y sin tomar locks.

### FR3 — Transporte

Play/stop con reloj interno. El transporte es táctil, según el reparto de `product-guidelines.md` — es lo único, junto con la configuración, que esa frontera asigna a la pantalla.

### FR4 — Salida a hardware real

Enumeración de destinos MIDI del sistema y selección de uno. Es la primera vez que la salida va a un dispositivo físico y no a un endpoint de medición.

La desconexión se trata como **estado esperado** (`No MIDI device`), no como error — y se detecta por `onSetupChanged`, no por el resultado del envío, que no la reporta.

**Cada pulso emite note-on y note-off.** La duración del gate es fija y provisional: Sustain es un parámetro de Groove y está fuera de esta rebanada, pero sin note-off las notas quedan colgadas en el sintetizador. El note-off se programa con su propio timestamp futuro, por el mismo camino que el note-on — no con un sleep ni un temporizador, que reintroducirían justo el jitter que la arquitectura evita.

### FR5 — Pantalla mínima de estado

Transporte, selección de destino y los valores de Shape en curso, **en solo lectura**.

**Sin el lenguaje visual del producto**: el anillo circular, el overlay de valor grande y los acentos por familia llegan en el track de UI.

### FR6 — Medición de jitter con carga, indicativa

Repetir el barrido del spike (60, 120 y 174 BPM) **con el motor y la interfaz corriendo**, contra el mismo umbral: máximo < 2 ms, desviación típica < 0,5 ms.

**Es una lectura indicativa, no el veredicto definitivo.** La carga de esta rebanada no es la carga final: falta el anillo circular, que es la parte visualmente cara de la interfaz. La medición definitiva corresponde al track de UI, cuando exista esa carga. Lo que esta lectura sí puede hacer es detectar pronto una degradación grosera al meter el motor en el camino — que es barato de comprobar ahora que el arnés ya está construido.

Un resultado fuera de umbral **para el track y se reporta con datos**, igual que hizo el spike. No se itera sobre arquitecturas dentro de este track.

## Non-Functional Requirements

- **NFR1 — Pureza de `Engine`:** el paquete sigue sin importar nada más allá de la stdlib. El test de frontera ya existe y debe seguir pasando.
- **NFR2 — Realtime safety:** sin asignaciones, locks, `await`, logging ni SwiftUI en el camino del scheduler. Las funciones de ese camino llevan el marcador `/// Realtime:`.
- **NFR3 — Determinismo:** las funciones de Shape son deterministas. No hay aleatorio en esta rebanada; cuando llegue (Probability, en Groove) será PRNG sembrado y explícito, nunca `Int.random()`.
- **NFR4 — Cobertura:** `Engine` ≥90%, `MIDI` ≥80%, `App` ≥80%, según `workflow.md`.
- **NFR5 — Vocabulario:** los nombres del código usan los términos de la Pre Spec sin sinónimos. `trigger` y `pulse` no son intercambiables.
- **NFR6 — Sin dependencias de terceros.**

## Acceptance Criteria

**Criterio principal:**

> Con un sintetizador conectado al iPad: pulsar Play produce **pulsos euclidianos audibles** en el hardware, en las posiciones que marca la configuración del Track. Pulsar Stop detiene la emisión.

Además:

- [ ] 16/4, 16/5 y 12/7 de la Pre Spec pasan como tests literales.
- [ ] Rotate se comporta como rotación del anillo, verificado con tests.
- [ ] Publicar un snapshot nuevo a media reproducción se recoge en la ventana siguiente, sin duplicar ni omitir Steps — verificado con tests.
- [ ] `swift test` sobre `Engine` y `MIDI` pasa sin simulador ni hardware.
- [ ] El snapshot cruza al scheduler sin locks, verificado por revisión.
- [ ] Lectura indicativa de jitter con motor y UI corriendo, dentro del umbral, medida en el iPad y registrada en la git note del commit.
- [ ] Desconectar el dispositivo a media reproducción se refleja como estado, no como error ni como caída.

## Known Limitations

1. **La carrera de `stop()`/`start()` del scheduler sigue abierta.** Está registrada en `scheduler-lifecycle_20260826`. En cuanto exista transporte, parar y arrancar rápido puede duplicar notas. Este track **no** la arregla, pero es el primero que puede observarla en producto: si aparece de forma molesta, es señal de subir la prioridad de aquel track.
2. **La medición no es definitiva.** Ver FR6: falta la carga visual del anillo. Se repite en el track de UI.
3. **Altura fija.** Los pulsos suenan a una nota constante definida en código. No es una decisión de diseño sino la ausencia de Tonal: `product-guidelines.md` advierte explícitamente contra mostrar o sugerir una nota fija por paso, porque contradice el modelo de pool. Nada en esta rebanada debe consolidar esa idea — ni en la pantalla, ni en los nombres del código.
4. **Duración de nota fija.** El gate es una constante provisional, no un valor musical. Lo sustituye Sustain cuando llegue Groove.
5. **Un solo Track.** Sin Patterns, Banks ni Cycles.

## Out of Scope

- Entrada de control: knobs relativos, controlador virtual de desarrollo, preset del BeatStep Pro, MIDI Learn.
- Edición de parámetros generativos por cualquier vía, incluida la táctil.
- Tonal: pool de pitches, Scale, Root, cuantización.
- Groove: Velocity, Sustain, Timing (swing), Delay, Probability.
- El anillo circular, el overlay de valor grande y el lenguaje visual de `product-guidelines.md`.
- Persistencia, Autosave, Backup Project.
- Múltiples Tracks, Patterns, Banks, Cycles.
