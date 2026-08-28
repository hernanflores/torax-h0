# Spec — La sesión MIDI de red monopoliza la entrada

**Track ID:** `network-session-source_20260828`
**Track type:** Bug

## Overview

Encontrado el 2026-08-28 en la verificación en dispositivo de la Fase 4 de
`mvp-control-input_20260827`, sobre un iPad Air (4ª gen).

iPadOS publica **siempre** la sesión MIDI de red (`Red Session 1`) como fuente,
esté o no en uso. La lista de entradas, por tanto, nunca está vacía. Dos
consecuencias, ambas observadas en el dispositivo:

1. **El estado vacío es inalcanzable.** `MIDIEndpointSelection.statusDescription`
   solo dice `No MIDI input` cuando `selected` es `nil`, y nunca lo es. Con ello
   `TransportModel.isReadOnly` es siempre `false` y el indicador `read-only` no
   aparece jamás. El comportamiento que `product-guidelines.md` especifica para
   «sin controlador conectado» —solo lectura y transporte— existe en el código y
   no se puede ver en el producto.

2. **La autoselección se queda pegada a la red.** `refreshed(with:)` conserva la
   elección vigente mientras el endpoint siga presente, y la sesión de red
   siempre sigue presente. Al conectar el BeatStep Pro la selección no se mueve
   y hay que elegir la fuente a mano. Eso contradice la intención declarada en
   el propio código: *«Elegir solo el primero es deliberado: con algo conectado,
   la app tiene que funcionar sin pasar antes por un selector.»*

La segunda es la que más molesta en uso real, y no se ve en los tests porque
`MIDIEndpointSelection` recibe la lista ya enumerada: en la máquina de CI no hay
sesión de red que aparezca sola.

**No es un defecto de CoreMIDI ni de la selección en sí.** La lógica hace lo que
dice hacer. Lo que falta es distinguir *fuente disponible* de *fuente que vale
como controlador por defecto*, distinción que hoy no existe.

## Functional Requirements

### FR1 — El estado vacío se puede ver

Con ningún controlador conectado, un iPad real muestra `No MIDI input` y el
indicador `read-only`. La presencia de la sesión de red no lo impide.

### FR2 — Conectar un controlador basta

Al conectar un controlador con la app abierta, pasa a ser la fuente activa sin
que nadie toque el selector. Al desconectarlo se vuelve a FR1.

### FR3 — La red sigue siendo elegible a mano

MIDI por red es una vía de entrada legítima y no se elimina: sigue en la lista y
se puede seleccionar. Lo que cambia es que **nunca se elige sola**.

### FR4 — La elección explícita manda

Una fuente elegida a mano —la de red incluida— se conserva al refrescar mientras
siga presente. Este track no toca esa garantía.

## Non-Functional Requirements

- **NFR1 — Testeable sin hardware.** `MIDIEndpointSelection` recibe la lista ya
  enumerada; el caso se reproduce inyectando una lista que contenga la sesión de
  red. No hace falta iPad para el Red/Green, solo para la verificación final.
- **NFR2 — Cobertura de `MIDI` ≥80%,** según `workflow.md`.
- **NFR3 — Sin regresión de jitter.** No se toca el camino de envío ni el
  scheduler.
- **NFR4 — No se identifica por nombre visible.** Filtrar por la cadena
  `"Red Session 1"` es frágil: depende del idioma del sistema y del nombre que
  el usuario le ponga. La identificación tiene que apoyarse en una propiedad del
  endpoint, no en su etiqueta.

## Acceptance Criteria

- [ ] Con la lista conteniendo **solo** la sesión de red, `statusDescription` es
      `No MIDI input` y `hasEndpoint` es `false`.
- [ ] Con la sesión de red y un controlador en la lista, el controlador queda
      seleccionado sin intervención.
- [ ] Partiendo de solo la sesión de red, añadir un controlador al refrescar lo
      selecciona; quitarlo vuelve al estado vacío.
- [ ] La sesión de red sigue en `available` y `selecting(_:)` la acepta.
- [ ] Una elección manual de la sesión de red sobrevive a un refresco.
- [ ] El destino no cambia de comportamiento: sus tests siguen en verde.
- [ ] Verificado en iPad: sin controlador se lee `No MIDI input` + `read-only`;
      al conectar el BeatStep Pro responde sin tocar el selector.

## Known Limitations

1. **La identificación del endpoint de red depende de CoreMIDI.** Si la
   propiedad elegida no distingue de forma fiable, la alternativa es marcar el
   driver, no el nombre — y eso se decide con el diagnóstico, no antes.

## Out of Scope

- MIDI Learn y el preset del BeatStep Pro.
- Recordar la última fuente elegida entre sesiones (no hay persistencia todavía).
- El lado del destino: `Red Session 1` también aparece ahí, pero como salida es
  una elección legítima y no estorba a ningún estado especificado.
