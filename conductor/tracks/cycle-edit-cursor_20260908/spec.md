# Spec — En pantalla no se puede elegir qué Cycle se edita

## Overview

**El cursor de edición se queda siempre en el Cycle 1.** Todo giro de knob cae
ahí, y los otros quince parecen copias que no guardan nada — que es exactamente
lo que son: nacen iguales (`Track.init(_:)` los reparte) y nunca reciben una
edición. Con el transporte corriendo se oye el desarrollo A/B/C que
`cycles_20260901` entregó, pero solo si alguien lo construyó con el knob 13; sin
controlador, no hay forma de construirlo.

Encontrado el 2026-09-03 verificando el reloj externo en iPad.

**La causa es un gesto que falta, no el modelo.** `Track` lleva sus dos cursores
—`cursor`, que mueve el scheduler en el límite de vuelta, y `editing`, que es de
pantalla— y `replacingEditing(_:)` escribe en el que toca. `withEditing(_:)`
existe, acota al rango activo y tiene tests. Lo que no existe es la vía que la
llame desde el dedo:

- En `App/TrackReadout.swift`, la celda del `CycleStrip` llama a
  `onActiveCountChange(number)`, que cambia **cuántos** Cycles se recorren.
- En `Packages/MIDI/Sources/MIDI/ControlInput.swift`, `moveEditingCycle(by:)` es
  **privada** y se mueve por deltas: es la traducción del knob, no una vía de
  pantalla.

> **Corrección del 2026-09-08 sobre lo que decía el registro.** El track estaba
> descrito con dos datos que caducaron: la fila de Cycles ya no vive en
> `App/TrackSelectorView.swift` —se movió al `CycleStrip` de
> `App/TrackReadout.swift` con `screens-redesign_20260906`— y el knob del Cycle
> ya no es el 10 con CC 79 —`ctrl-all_20260905` lo movió al 13, CC 82, y dejó el
> 79 para Repeats—. El defecto es el mismo; lo que cambia es dónde se toca.

**El reparto de gestos está decidido** (2026-09-03): **pulsar elige** el Cycle en
edición y **mantener pulsado cambia cuántos** están activos. El gesto frecuente
es el simple y el raro pide mantener, que es el mismo criterio con el que los
step buttons 15 y 16 hacen de modificadores de solo y mute.

## Functional Requirements

**FR1 — `ControlInput` mueve el cursor de edición a un índice.** Una vía pública
que fija el Cycle en edición del Track seleccionado, junto a `setActiveCycleCount`
y `setChannel`, que son las otras entradas táctiles. Hoy solo existe la privada
por deltas, que es la traducción del knob.

**FR2 — Se acota al rango activo, no a los dieciséis.** No se edita un Cycle que
no se recorre. Lo garantiza `Track.withEditing(_:)`, que ya lo hace; la vía
pública no vuelve a decidirlo.

**FR3 — Publica, y no toca material.** Mover el cursor de edición cambia el
`Track` que cruza al scheduler, así que se publica por el mismo camino que
`setActiveCycleCount`. **Ni una sola nota de material cambia**, ni el cursor de
reproducción se mueve: eso es del scheduler y del límite de vuelta.

**FR4 — Fijar el mismo índice no publica.** Por la misma razón que girar contra
un tope no publica: mandar un snapshot idéntico es trabajo y ruido para nada.

**FR5 — Pulsar una celda del `CycleStrip` elige el Cycle en edición.** Es el
gesto frecuente y por eso es el simple. El gesto de pulsación comprueba
`number <= activeCount` antes de llamar a la vía pública; si `number` excede
`activeCount`, no hace nada. No se edita lo que no se recorre, y subir el rango
es el otro gesto.

**FR6 — Mantener pulsada una celda cambia cuántos Cycles están activos.** Es lo
que la celda hacía hasta hoy, movido al gesto raro. Al cumplirse el tiempo de
mantenimiento **el cambio se aplica sin esperar a que se levante el dedo**, para
que el gesto tenga la misma respuesta que un botón del hardware.

**FR7 — Un gesto excluye al otro.** Levantar el dedo después de que el mantenido
haya disparado **no elige** ese Cycle además de haber cambiado el rango. Un solo
toque hace una sola cosa.

**FR8 — El Cycle en edición se distingue del que suena, y eso ya está.** El
`CycleStrip` dibuja el que suena relleno y el que se edita con un contorno
encima. Este track **no cambia esa representación**: lo que cambia es que ahora
se puede llegar a ella con el dedo.

**FR9 — El cursor de edición sobrevive al cambio de Track.** Ya lo hace, porque
vive en el `Track` y no en la vista. Se declara aquí para que quede como
condición de no regresión: volver a un Track y encontrarlo editando otro Cycle
sería perder el sitio.

**FR10 — La pantalla y el knob llevan al mismo sitio.** El knob 13 y la celda
mueven el mismo cursor. Si no, la pantalla mentiría sobre lo que el hardware
acaba de hacer — es el criterio que `TrackSelectorView` ya declara para los
Tracks.

## Non-Functional Requirements

**NFR1 — El modelo no cambia.** `Track.withEditing(_:)` se usa tal cual. Si al
implementar hiciera falta tocarlo, es señal de que el diseño de
`cycles_20260901` no era el que se creía y hay que anotarlo antes de seguir.

**NFR2 — Nada nuevo en el camino de tiempo real.** Ni una línea en el hilo del
scheduler: esto publica un snapshot desde el hilo principal, que es lo que
cualquier edición táctil ya hace.

**NFR3 — Cobertura.** `MIDI` ≥80%. La vía de FR1 vive ahí, que es donde se testea
sin controlador de por medio. `Engine` no debería moverse (NFR1).

**NFR4 — El gesto en `App` no lleva tests, y por eso lleva poca lógica.** `App`
no se mide (`workflow.md`). La vía pública conserva el acotado de FR2 en
`Engine`; la vista solo distingue un gesto de otro, aplica el guard de FR5 y
llama.

**NFR5 — Sin medición de jitter.** La suspensión del 2026-09-02 manda, y además
este cambio no mueve ningún instante.

## Acceptance Criteria

1. Con cuatro Cycles activos, pulsar la celda 3 pone el cursor de edición en el
   Cycle 3: el contorno se mueve y el siguiente giro de knob edita **ese** Cycle.
2. Volver a la celda 1 y girar el mismo knob deja el Cycle 3 como estaba: dos
   Cycles con valores distintos, que es el desarrollo que el defecto impedía.
3. Pulsar la celda 9 con cuatro activos no hace nada. Mantenerla sube el rango a
   nueve.
4. Mantener pulsada una celda cambia el número de activos, y al levantar el dedo
   **el cursor de edición no se ha movido** a esa celda.
5. Con el transporte corriendo, el relleno del que suena sigue avanzando solo y
   el contorno del que se edita se queda donde lo dejó el dedo.
6. El knob 13 mueve el mismo contorno que la celda; cambiar de Track y volver
   conserva el Cycle en edición de cada uno.
7. `MIDI` ≥80% y la suite entera verde.

## Out of Scope

- **Copiar, pegar o limpiar un Cycle.** Este track da acceso al que se edita, no
  operaciones sobre el material.
- **Cambiar cómo se dibuja el `CycleStrip`** (FR8), incluidas las dos filas de
  ocho y el indicador de encadenamiento.
- **Elegir el Cycle desde el controlador con algo que no sea el knob 13.** Los
  dieciséis step buttons están ocupados desde `ctrl-all_20260905`.
- **Que el cursor de edición siga al de reproducción.** Que se puedan separar es
  justo lo que `cycles_20260901` entregó a propósito.
- **Medición de jitter** (NFR5).

## Known Limitations

- **Mantener pulsado no tiene affordance visible.** Un usuario que no lo sepa no
  descubre cómo cambiar el número de Cycles activos. Se acepta con el mismo
  criterio que los modificadores del hardware, que tampoco se anuncian; si
  molesta en uso, la respuesta es una pista en pantalla y no otro gesto.
- **El gesto mantenido tarda.** Entre pulsar y que el rango cambie hay que
  esperar el tiempo de mantenimiento, cuando hasta hoy era inmediato. Es el
  precio de que el gesto frecuente sea el simple.
