# Track: Copiar Patterns: acorde en directo y portapapeles

**ID:** `pattern-copy_20260910` · **Type:** Bug · **Status:** new

**El botón `copy here` de la rejilla de patterns no hace nada, y no puede
hacerlo.** `BanksScreen.swift:179` llama `onCopy(selected)`, o sea el hueco
seleccionado, y eso acaba en `Project.copyingSelectedPattern(to:)`, que copia el
Pattern seleccionado al índice recibido. Origen y destino son el mismo hueco: la
celda se copia sobre sí misma.

El motor está bien y tiene tests —`PatternCopyTests` prueba `to: 7` y `to: 3`,
siempre con origen distinto—. **Nadie probó el caso que la vista dispara.** Lo
que falta es un origen: la pantalla solo conoce un índice y lo usa para las dos
puntas de la copia.

**Dos interacciones, separadas por el transporte.** Copiar un Pattern tiene dos
usos que el mismo par de botones no sirve para los dos:

- **Corriendo, un acorde de dos dedos**: mantener el origen y tocar el destino
  copia en el acto, y **sigue sonando lo que sonaba**. Es el equivalente por
  Pattern de lo que `reload` hace por Banco: dejar una copia antes de
  experimentar encima. Funciona porque sonando el toque sencillo ya no es
  inmediato —arma para el próximo compás—, así que hay margen para decidir si el
  toque era acorde.
- **Parado, `copy` y `paste`**: dos gestos y un portapapeles que guarda el
  Pattern entero, así que **se puede pegar en otro Bank**. `paste` también
  funciona corriendo, porque el acorde no cruza Banks: los dos dedos caen en la
  misma rejilla.

**Se permite pegar encima del Pattern que suena**, decidido con el usuario. El
audio no se corta: el transporte tiene su propio snapshot publicado y no lo relee
hasta la próxima adopción.

**El riesgo está en un sitio y es conocido.** Dos `Button` hermanos de SwiftUI no
ven toques simultáneos, así que la rejilla pasa a resolver los toques con
`UIViewRepresentable`. Va sola en la Fase 4, con la verificación en dispositivo
detrás — el multitouch no existe en el simulador, que es la misma lección de
método que dejó `hardware-screen-sync_20260908`.

**La Fase 3 cierra el defecto reportado.** Si las fases 4 y 5 no llegaran a
existir, copiar y pegar ya funcionan con el transporte parado y nada queda a
medias.

**Sin medición de jitter**: no mueve ningún instante y no toca el hilo del
scheduler.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [`ControlInput` no adopta el Pattern del Bank nuevo](../control-input-adoption_20260908/index.md):
    de ahí sale el mecanismo de armado y adopción con el que este track convive —
    el acorde no debe armar nada, y el destino de `paste` corriendo es el hueco
    armado.
-   [La pantalla no ve lo que cambia el hardware](../hardware-screen-sync_20260908/index.md):
    la lección de método sobre verificar en el hardware lo que solo existe en el
    hardware.
-   [Persistencia: Banks y Patterns en disco](../persistence_20260907/index.md):
    el autosave del Bank que copiar y pegar disparan.
