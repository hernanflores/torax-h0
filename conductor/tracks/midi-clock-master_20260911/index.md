# Track: Torax H-0 como maestro de MIDI clock

**ID:** `midi-clock-master_20260911` · **Type:** Feature · **Status:** new

**La app pasa a mandar.** Hoy `product.md` promete lo contrario —«La app no emite
clock. La sincronía va en un solo sentido»—: este track toma la decisión que
aquella nota dejó abierta. Play y Stop arrastran a los aparatos conectados, y el
tempo de Torax pasa a ser el tempo de la cadena.

**El pulso se genera, no se reenvía.** Los 24 pulsos por negra salen del hilo del
scheduler sellados hacia el futuro, con el mismo origen de rejilla y el mismo
`TempoMap` que las notas — así el tick cae donde cae la nota. Reenviar el tick
entrante al vuelo devolvería el jitter al planificador del sistema operativo, que
es la alternativa que `tech-stack.md` ya descartó por escrito para la entrada.

**Con `External` la app retransmite regenerando.** El `TempoMap` ya sigue al
maestro, así que los esclavos comparten la misma estimación que la app: un solo
generador de pulso para los dos modos, y no dos caminos que mantener iguales.

**No añade interfaz, ni modelo, ni fichero.** Sin interruptor, sin destino de
clock propio, sin clave nueva en el esquema: emite siempre que el transporte
suena, al mismo destino único que eligen las notas.

**El riesgo va solo en la Fase 4.** `start` y `stop` se sellan desde el hilo de
control mientras el hilo del scheduler sella ticks; un orden mal elegido deja al
esclavo corriendo después de Stop.

**Sin medición de jitter** (suspensión del 2026-09-02): los ticks no desplazan
ningún instante de nota. Se sustituye por una escucha larga en dispositivo.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [Sincronía de reloj externo](../external-clock_20260903/index.md): la otra
    mitad de la sincronía. De ahí salen `timingClock`, `start` y `stop` en
    `MIDIMessage`, el `ClockFollower` y el `TempoMap` que este track reutiliza
    para emitir.
-   [La Division no mueve la rejilla mientras suena](../division-hot-grid_20260911/index.md):
    dejó la rejilla anclada y en manos del material vigente. El pulso no depende
    de la Division de ningún Track — es del tempo — y por eso no hereda su ancla.
