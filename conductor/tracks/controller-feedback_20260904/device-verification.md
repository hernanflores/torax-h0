# Verificación en dispositivo — Fase 1, y cierre del track

**2026-09-04.** iPad con el BeatStep Pro conectado, sonda de LEDs
(`--led-probe`) enviando al controlador. Es la fase que podía cancelar el track
(NFR1).

## Primera vuelta: no ilumina con MIDI de canal

**No se encendió nada.** Ni los pads con note-on ni los step buttons con control
change, con la sonda apuntando al controlador.

Con eso el track se cerró el mismo día. **Se reabrió unas horas después**, por lo
que sigue.

## Segunda vuelta: SysEx, reabierta el 2026-09-04

**El cierre duró unas horas.** Al revisar la documentación pública apareció que
el feedback de LED por SysEx existe en otros aparatos de Arturia, así que la
pregunta «¿y por SysEx?» —que el plan había puesto fuera de alcance— pasó a
tener candidatos concretos que probar en vez de ser una investigación abierta.

Lo que dice la documentación pública:

| Aparato | Feedback de LED | Cómo |
|---|---|---|
| BeatStep (1ª generación) | **Sí** | note-on enciende, note-off apaga. Solo rojo, y **solo con el pad en modo Note, no en Control** |
| MiniLab MkII | **Sí** | `F0 00 20 6B 7F 42 02 00 10 7n cc F7` — `7n` el pad, `cc` el color. Confirmado por un administrador de Arturia |
| BeatStep **Pro** | **Sin documentar** | El repositorio del SysEx del Pro solo cubre la configuración del preset. Los scripts de Bitwig para el Pro no encienden nada, y uno lo dice: «you cannot control the lights of the pads and steps» |

**La conjetura que se prueba.** El Pro sí acepta la cabecera de Arturia y la
dirección `02 00` para configurarse — `02 00 06 [knob] [val]` cambia los knobs
entre absoluto y relativo—. Que la subdirección `10` de los pads exista también
en el Pro es **plausible, no probable y desde luego no seguro**: nadie lo ha
publicado ni a favor ni en contra.

**Resultado: tampoco responde.** El frame del MiniLab MkII no encendió nada en
el BeatStep Pro, ni con el pad 0 ni con los otros quince, ni cambiando el color.

Con eso la conjetura queda descartada **con un experimento y no con
documentación ajena**, que era la debilidad del primer cierre. El track se cierra
aquí.

*(Pendiente de confirmar por separado: la variante de poner el pad en modo Note
en MIDI Control Center y repetir el note-on, que es la condición que pone el
BeatStep de primera generación. Si no llegó a probarse, es lo único del alcance
de esta fase que queda sin tocar.)*

## Qué se probó en la primera vuelta

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

**El SysEx no se probó en la primera vuelta.** Estaba fuera de alcance por el
plan; la segunda vuelta lo mete dentro, con candidatos concretos en vez de una
investigación abierta.

## La sonda

`App/LEDProbeView.swift`. Se borró al cerrar la fase, como declaraba NFR1, y se
recuperó al reabrirla: es exactamente el uso que justificaba dejarla en el
historial.

**Un solo cliente de CoreMIDI, y crudo.** La primera versión usaba
`CoreMIDIOutput` para las notas; al añadir el SysEx —que necesita la API de
paquetes clásica, porque el camino de la app manda un word dentro de un
`MIDIEventList`— abrió un segundo cliente, y el primero empezó a fallar con
`clientCreationFailed(-304)`. Ahora la sonda tiene su propio cliente y manda
todo por él, sin depender del paquete `MIDI` más que para leer los números del
preset. Borrarla no deja rastro.

Historial: `1ab9273` la sonda, `b753a5e` el desbordamiento de pila que la tumbó
en el primer intento —un `didSet` autoasignante bajo `@Observable`—.

## Conclusión

**El BeatStep Pro no ilumina desde el host, ni por MIDI de canal ni por el SysEx
de color de Arturia.** Las dos vías que estaban al alcance de esta fase se
probaron en dispositivo y ninguna encendió nada. El track se cierra sin entregar
nada: todo lo que prometía —los pads siguiendo la nota, los step buttons
diciendo qué Track se edita— depende de que el hardware responda.

Lo que queda fuera, y sigue sin explorarse: el resto del espacio de direcciones
SysEx del Pro, que no está documentado y cuya exploración a ciegas es otra
investigación y otro track. Nadie la ha pedido.

## Fuentes

- [Bome — control and color led in arturia beatstep](https://forum.bome.com/t/control-and-color-led-in-arturia-beatstep/3604)
- [Remotify — LED feedback on Arturia controllers](https://community.remotify.io/questions/question/led-feedback-on-arturia-controllers/)
- [Foro Arturia — LED color via SysEx en MiniLab MkII](https://legacy-forum.arturia.com/index.php?topic=93116.0)
- [Pl0p/Beatstep-pro-Sysex](https://github.com/Pl0p/Beatstep-pro-Sysex) — solo configuración del preset
- [benschmaus — Beatstep Pro and Bitwig](https://benschmaus.github.io/2016/01/beatstep-pro-and-bitwig/)
- [cyhex/BeatstepProController](https://github.com/cyhex/BeatstepProController) — `02 00 06` para los knobs, nada de luces
