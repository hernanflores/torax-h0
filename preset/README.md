# Preset del BeatStep Pro para Torax H-0

Qué significa cada control físico del Arturia BeatStep Pro cuando controla la
app. **Los mismos números que declara `ControlMapping`** en
`Packages/MIDI/Sources/MIDI/ControlMapping.swift`: si uno de los dos cambia, el
otro está mal.

La tabla legible por máquina está en
[`torax-h0.beatstep-pro.json`](./torax-h0.beatstep-pro.json).

## Antes que nada: los encoders van en `Relative #2`

**Sin esto no funciona nada y el síntoma no se parece a la causa.** Es el único
modo que la app decodifica —complemento a dos: `0x01` = +1, `0x7F` = −1—. En
cualquier otro, un solo clic se lee como un delta de ±63 y **todos los parámetros
saltan a su extremo**: Steps, Pulses y Division se quedan clavados en 1 o en 16.

Rotate parece funcionar, y por eso es el peor testigo de los cuatro: es el único
que envuelve módulo Steps en vez de acotar.

Se configura en MIDI Control Center, por encoder o para todos a la vez.

## Los dieciséis knobs — CC 70 a 85

Los nueve primeros son los nueve parámetros del Track, en el mismo orden en que
aparecen en la pantalla.

| Knob | CC | Parámetro |
|---|---|---|
| 1 | 70 | Steps |
| 2 | 71 | Pulses |
| 3 | 72 | Rotate |
| 4 | 73 | Division |
| 5 | 74 | Velocity |
| 6 | 75 | Sustain |
| 7 | 76 | Probability |
| 8 | 77 | Timing |
| 9 | 78 | Delay |
| 10–16 | 79–85 | **Sin asignar.** Se ignoran en silencio |

Los siete libres están declarados a propósito, no olvidados: su sitio es de v2
—Cycles, Accent, Repeats, Time, Voicing, Range—. Girarlos no hace nada y no es un
error.

**Scale y Root no están aquí**: son configuración táctil y se tocan en la
pantalla del iPad.

## Los dieciséis pads — notas 36 a 51

**El número de nota es solo el índice del pad.** La altura que suena la decide la
escala vigente, no el mensaje: el pad 1 envía la nota 36 y puede meter en el pool
la nota 48. Son dos numeraciones distintas y no hay que confundirlas.

| Pad | Nota | Significado |
|---|---|---|
| 1–7 | 36–42 | Grados 1–7 de la escala, en la octava base |
| 8 | 43 | **Bajar** el registro una octava |
| 9–15 | 44–50 | Los mismos grados, una octava por encima |
| 16 | 51 | **Subir** el registro una octava |

- El pad 9 es siempre el pad 1 más doce semitonos, sea cual sea la escala y el
  Root. De ahí que los pads 8 y 16 puedan llamarse *octava* sin mentir.
- Con una escala de cinco grados —Pentatonic— **los pads 6, 7, 14 y 15 no tienen
  nota** y no hacen nada. Es querido: rellenarlos rompería el alineamiento por
  octava.
- Los pads 8 y 16 **no tocan el pool**. Mueven qué nota mete el pad siguiente;
  lo que ya está dentro se queda donde está.
- En el extremo del rango MIDI el pad de octava deja de responder, y la pantalla
  lo dice —`Lowest octave` / `Highest octave`—.

## Los dieciséis step buttons — CC 102 a 117

| Step button | CC | Significado |
|---|---|---|
| 1–12 | 102–113 | Seleccionar Track 1–12 |
| 13, 14 | 114, 115 | Nada: el Pattern tiene doce Tracks |
| 15 | 116 | **Modificador de solo** — mantenido |
| 16 | 117 | **Modificador de mute** — mantenido |

El bloque 102–117 está sin definir en la especificación MIDI, así que no pisa
nada con significado asignado.

**El preset no cambia y no ha cambiado nunca:** describe el hardware —dieciséis
step buttons contiguos desde el CC 102— y lo que significa cada uno lo decide la
app. Los cambios de esta tabla son de la app, no del `.beatstep` que se carga en
el controlador.

> **Los modificadores, del 2026-09-02.** Mantener el 16 y pulsar el N mutea el
> Track N; con el 15, lo solea (track `mute-solo_20260902`). Los dos quedaron
> libres al bajar el Pattern de dieciséis Tracks a doce, así que el gesto no le
> quita nada a la selección.
>
> **Mantenido de verdad, sin temporizador.** El BeatStep manda 127 al pulsar y 0
> al soltar, así que la app sabe si el botón está hundido sin medir cuánto duró
> la pulsación. Pulsados y soltados **solos, los dos no hacen nada**: un
> modificador que además actúa se dispara sin querer.
>
> Con los dos mantenidos a la vez manda el de mute.

## El canal no importa

La app no filtra por canal: el mismo mensaje en el canal 1 y en el 16 hace lo
mismo. Es deliberado —exigir un canal concreto sería un modo de fallo silencioso,
todo conectado y nada respondiendo— y está fijado por un test.

## Con un BeatStep Pro sin el preset cargado

Qué se rompe, y cómo se reconoce:

| Síntoma | Causa |
|---|---|
| Un clic de knob clava el parámetro en su extremo | Los encoders no están en `Relative #2` |
| Los knobs no hacen nada | Envían otros CC; el preset los pone en 70–78 |
| Los pads no meten notas, o meten las que no son | El bloque de pads no empieza en la nota 36 |
| Los step buttons mueven un parámetro | Sus CC caen dentro de 70–85 en vez de 102–117 |

Nada de eso es un error de la app: los mensajes sin asignar se ignoran en
silencio a propósito, porque en una sesión real llegan mensajes de todo tipo.

## Cómo cargarlo

1. Conectar el BeatStep Pro al ordenador y abrir **MIDI Control Center**.
2. Poner los dieciséis encoders en **`Relative #2`**.
3. Asignar los CC de los knobs (70–85) y de los step buttons (102–117), y el
   bloque de notas de los pads empezando en 36, según las tablas de arriba.
4. **Send To Device** para grabarlo en el controlador.
5. O, más corto: cargar [`Torax.beatsteppro`](./Torax.beatsteppro) desde MIDI
   Control Center y hacer **Send To Device**.

## El archivo del controlador

[`Torax.beatsteppro`](./Torax.beatsteppro) es el proyecto exportado desde MIDI
Control Center contra el BeatStep Pro ya configurado, el **2026-08-31**. No está
escrito a mano: sale del programa que lo carga, que es la única forma de que sea
cierto.

Su contenido coincide con las tablas de arriba —dieciséis encoders en CC 70–85 en
modo relativo, dieciséis step buttons en CC 102–117 y dieciséis pads en las notas
36–51— y con lo que declara `ControlMapping`. Los tres tienen que decir lo mismo:
si uno cambia, los otros dos están mal.
