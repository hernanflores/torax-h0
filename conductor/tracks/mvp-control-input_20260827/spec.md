# Spec — MVP rebanada 2: Entrada de control

**Track ID:** `mvp-control-input_20260827`
**Track type:** Feature (MVP, rebanada vertical)

## Overview

La app deja de ser de solo lectura.

La rebanada 1 dejó el motor sonando y el relevo de snapshot en caliente **implementado y probado**, pero nada publica Tracks nuevos: `TrackHandoff.publish` solo se llama desde tests. Esta rebanada conecta un controlador MIDI a ese camino, y con eso `product-guidelines.md` empieza a cumplirse en su principio rector — «el controlador es el instrumento; la pantalla es el espejo».

Corta fina otra vez, y por la misma razón que la rebanada 1: **solo los cuatro parámetros de Shape**, porque son los únicos que existen. Tonal y Groove no están todavía.

### Lo que esta rebanada NO trae, a propósito

Ni preset del BeatStep Pro ni MIDI Learn. Sin MIDI Learn, el preset es un fichero de constantes que ata la rebanada a un dispositivo concreto antes de que exista la forma de reasignarlo; y MIDI Learn exige interfaz táctil de mapeo, que es lenguaje visual aplazado al track de UI.

Tampoco el overlay de valor grande. `product-guidelines.md` lo exige para legibilidad a un metro, pero llega con el anillo circular: son la misma pieza de diseño.

## Functional Requirements

### FR1 — Entrada MIDI, simétrica a la salida

Enumeración de fuentes del sistema, selección de una, y desconexión tratada como **estado esperado** (`No MIDI input`), no como error. Se detecta por `onSetupChanged`, igual que la salida.

La lógica de selección y de reconsulta ya existe para destinos (`MIDIDestinationSelection`, `MIDIDestinationWatcher`): se reutiliza, no se duplica.

### FR2 — Decodificación de encoders relativos

Los encoders operan en **modo relativo** (`product-guidelines.md`): incrementan o decrementan desde el valor actual del software. Sin saltos, sin zona muerta de pickup. El estado del software es la única fuente de verdad; la posición física del knob es irrelevante.

Se implementa la convención de **complemento a dos de 7 bits**: `0x01`…`0x3F` = +1…+63; `0x7F`…`0x41` = −1…−63.

El decodificador **recibe la convención como parámetro**, no cableada. Añadir las del BeatStep Pro cuando llegue su preset será añadir casos, no reescribir. Sus valores exactos se verificarán contra el manual del fabricante entonces, no de memoria.

### FR3 — Mapeo fijo y provisional

Una tabla CC → parámetro de Shape, **declarada provisional en el código**. La sustituyen el preset y MIDI Learn.

Un CC sin mapear se ignora en silencio: no es un error.

### FR4 — Aplicación del delta, con acotado no destructivo

- **`Pulses` pasa a validarse 1–16 por sí solo**, y el reparto usa `min(pulses, steps)`. El valor guardado es la intención; el efectivo se deriva. Girar Steps de 16 a 4 y volver a subir no cuesta la configuración.
- `Steps` y `Division` se acotan a sus rangos. `Division` recorre una **lista ordenada de valores musicales**, no un entero libre, y se detiene en los extremos.
- `Rotate` ya envuelve sobre el anillo; sin cambios.

**Desviación de la Pre Spec, documentada según `workflow.md` paso 8.** La Pre Spec dice «Pulses: 1 hasta el número actual de Steps». Eso se sigue cumpliendo **en lo que suena**; lo que cambia es que el valor almacenado puede excederlo temporalmente.

Es la lectura que exige la regla de no destructividad de `product-guidelines.md` —«cambiar un parámetro nunca destruye material: el pool tonal sobrevive a un cambio de Scale reencuadrándose, no vaciándose»— y alinea `Pulses` con `Rotate`, que ya se comporta así por la misma razón: la envoltura la resuelve el reparto, que es quien conoce el tamaño del anillo.

Esto **revisa una decisión de la rebanada 1** (commit `71d8bb8`), que ató `Pulses` a `Steps` para que ningún sitio de uso tuviera que revalidar. Lo que aquella decisión no anticipó es que el usuario giraría Steps.

### FR5 — Girar publica

Cada cambio publica un `Track` nuevo por `TrackHandoff`. Se recoge en la ventana siguiente, que es lo que `product-guidelines.md` exige: «un giro debe producir cambio audible dentro del siguiente step».

**El camino de tiempo real no cambia de forma.** Decodificar y publicar corren en el hilo de control.

### FR6 — Controlador virtual de desarrollo

Inyecta eventos MIDI relativos sin hardware. `product-guidelines.md` lo pide explícitamente como consecuencia de la frontera táctil/knob: probar el motor sin hardware no puede hacerse abriendo una puerta de edición táctil por detrás.

Es **herramienta de test, excluida del build de producción**. La exclusión se verifica sobre el binario final, no por inspección del código.

### FR7 — Feedback en la pantalla existente

El texto `Steps 16 · Pulses 5 · Rotate 0 · Division 1/16` se actualiza al girar. Sin lenguaje visual nuevo.

## Non-Functional Requirements

- **NFR1 — Pureza de `Engine`:** sigue sin importar nada más allá de la stdlib.
- **NFR2 — Realtime safety:** la entrada **no corre en el hilo del scheduler**. El camino de timing no cambia de forma; si acabara cambiando, `workflow.md` paso 7 exige medir en dispositivo antes de cerrar la tarea.
- **NFR3 — Determinismo:** mismo mensaje, mismo delta. Sin aleatorio.
- **NFR4 — Cobertura:** `Engine` ≥90%, `MIDI` ≥80%.
- **NFR5 — Vocabulario:** términos de la Pre Spec sin sinónimos.
- **NFR6 — Sin dependencias de terceros.**

## Acceptance Criteria

**Criterio principal:**

> Girar el knob de Pulses cambia el patrón **audible en el Step siguiente**.

Además:

- [ ] Bajar Steps por debajo de Pulses acota sin destruir; subirlo lo restaura — verificado con tests.
- [ ] El controlador virtual permite verificar todo lo anterior **sin hardware conectado**.
- [ ] Desconectar el controlador a media sesión se refleja como estado, no como error ni caída.
- [ ] `swift test` sobre `Engine` y `MIDI` pasa sin simulador ni hardware.
- [ ] El binario de Release **no contiene** el controlador virtual.
- [ ] Sin controlador conectado, la app sigue siendo de solo lectura y transporte.
- [ ] Los casos euclidianos de la Pre Spec (16/4, 16/5, 12/7) siguen dando el mismo patrón tras el cambio de `Pulses`.

## Known Limitations

1. **Mapeo fijo.** Sin preset del BeatStep Pro ni MIDI Learn: los CC son constantes en el código.
2. **Sin overlay de valor grande.** Llega con el anillo, en el track de UI.
3. **Sin aceleración por velocidad de giro.** Los rangos de v1 son cortos (1–16); entra cuando entren los amplios (Steps 1–64).
4. **La latencia knob→MIDI no se mide en dispositivo.** Se verifica de forma determinista que el Track publicado se recoge en la ventana siguiente; el número en hardware queda pendiente.
5. **Solo Shape.** Tonal y Groove no existen todavía, así que no hay nada más que mapear.

## Out of Scope

- Preset del BeatStep Pro y MIDI Learn.
- Overlay de valor grande, anillo circular y lenguaje visual del producto.
- Aceleración por velocidad de giro.
- Tonal (pool, Scale, Root) y Groove (Velocity, Sustain, Timing, Delay, Probability).
- Pads como los 16 Value Buttons.
- Persistencia, Autosave, Backup Project.
- Múltiples Tracks, Patterns, Banks, Cycles.
