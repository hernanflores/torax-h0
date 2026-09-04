# Verificación en dispositivo — Fase 1, y cierre del track

**2026-09-04.** iPad con el BeatStep Pro conectado, sonda de LEDs
(`--led-probe`) enviando al controlador. Es la fase que podía cancelar el track
(NFR1), y lo hizo.

## Resultado: el BeatStep Pro no ilumina por MIDI in

**No se encendió nada.** Ni los pads con note-on ni los step buttons con control
change, con la sonda apuntando al controlador. Una búsqueda de documentación lo
respalda: el BeatStep Pro no expone control de sus LEDs por MIDI entrante.

Con eso, **no hay feature que entregar**. Todo lo que el track prometía —los pads
siguiendo la nota, los step buttons diciendo qué Track se edita— depende de que el
hardware encienda algo cuando se le manda, y no lo hace.

## Qué se probó

| Qué | Cómo |
|---|---|
| Pads | note-on y note-off del bloque 36–51, con velocities 1, 32, 64, 100 y 127 |
| Step buttons | control change del bloque 102–117, con valores 0, 1, 2, 16, 64 y 127 |
| Canal | los dieciséis, uno a uno |
| Fuera del preset | los bloques se pueden mover ±1 y ±12 desde los números declarados |

Un mensaje por gesto y mirando el controlador, que es la única forma de saber
**cuál** encendió algo. No se encendió ninguno.

## Lo que no se comprobó, y por qué importa

**No se hizo la prueba de control**: apuntar la sonda a un sintetizador y
confirmar que los mensajes salen de verdad. Estaba propuesta y se descartó al
cerrar, con la búsqueda de documentación como respaldo suficiente.

Lo que eso deja abierto: **el hallazgo no distingue «el hardware no escucha» de
«la sonda no enviaba»**. Las dos explicaciones producen exactamente lo que se
vio. Queda escrito aquí para que, si algún día alguien vuelve sobre esto, sepa
que la conclusión descansa en documentación externa y no en un experimento que
separe las dos causas.

**Tampoco se barrieron las 128 notas y los 128 CC** por los dieciséis canales.
Se probaron los bloques del preset y su vecindad, no el espacio entero.

**No se buscó SysEx ni protocolo propietario.** Estaba fuera de alcance por el
plan desde el principio: es otra investigación y otro track.

## La sonda

`App/LEDProbeView.swift`, borrada al cerrar la fase como declaraba NFR1. Vive en
el historial, en los commits `1ab9273` —la sonda— y `b753a5e` —el desbordamiento
de pila que la tumbó en el primer intento, un `didSet` autoasignante bajo
`@Observable`—. Si el asunto se reabre, recuperarla es un `git show`.
