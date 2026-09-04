# Spec — Sincronía de reloj externo: el BeatStep Pro manda el tempo

**Tipo:** Feature · **Fecha:** 2026-09-03

## Overview

Hoy el tempo de la app es una constante: `TransportModel` lo fija en
`Tempo(beatsPerMinute: 120)` y la barra superior lo imprime sin que nadie pueda
moverlo. Tocar con el BeatStep Pro delante significa que **el hardware y la app
corren cada uno por su lado**: no hay forma de que empiecen juntos ni de que
compartan pulso.

Este track hace que el controlador mande: la app sigue su **Start**, su **Stop**
y su **reloj a 24 ppqn**, y deriva de ahí el tempo. Y, como efecto necesario del
fallback, el tempo interno deja de estar clavado.

Tres decisiones lo definen:

1. **El look-ahead se conserva.** Es la propiedad que hace bueno el timing del
   proyecto —el jitter no depende de cuándo despierta el hilo— y no se cambia por
   seguir a otro. Los eventos se siguen sellando hacia el futuro con un **tempo
   estimado** a partir de los ticks recibidos.
2. **La fase se re-ancla una vez por negra.** Un tempo estimado acierta de media
   y se separa despacio; corregir cada 24 ticks acota la deriva sin meter el
   jitter del cable en cada evento, que es lo que haría corregir tick a tick.
3. **Quién manda lo decide el usuario, no el cable.** Un selector
   `Internal / External` en la pantalla `3 · MIDI`. Con `Internal`, un Start
   entrante no interrumpe lo que suena.

**No toca el material.** `Pattern`, `Track` y `Cycle` quedan como están; lo que
cambia es de dónde sale el tiempo.

## Functional Requirements

**FR1 — La entrada aprende a oír System Real-Time.**
`MIDIMessage.init(universalPacketWord:)` descarta hoy todo lo que no sea UMP
**tipo 0x2** (voz de canal), y clock, start y stop son **tipo 0x1**: hay que
abrir el tipo, no solo añadir casos. Entran tres mensajes:

| Mensaje | Byte | Efecto |
|---|---|---|
| Timing Clock | `0xF8` | Alimenta el estimador de tempo y el re-anclaje de fase |
| Start | `0xFA` | Arranca el transporte desde el paso 0 |
| Stop | `0xFC` | Para el transporte y desarma |

El resto de System Real-Time —Continue `0xFB`, Active Sensing `0xFE`, Reset
`0xFF`— **se declara y se descarta en silencio**, con el mismo criterio que
`ControlMapping` aplica a lo que no asigna: sin decir qué se ignora, cualquier
mensaje inesperado parece un defecto.

**FR2 — El tempo se estima con los ticks, en `Engine`.** Un tipo puro recibe
instantes de tick y devuelve el periodo estimado. Vive en `Engine`, junto a
`Tempo` y `MusicalTimeline`, porque es aritmética determinista y ahí se testea
sin CoreMIDI ni hardware.

Reglas del estimador:

- Promedia sobre una ventana del orden de **una negra (24 ticks)**: suficiente
  para no bailar con un tick tardío, corto para no arrastrar un tempo viejo.
- **Un tempo fuera de `Tempo.validRange` (20–300 BPM) se rechaza**, no se acota
  en silencio: se conserva el último válido y la pantalla lo dice (FR8).
- Es un valor, no un objeto con reloj propio: quien lo alimenta le pasa el
  instante; él no consulta la hora.

**FR3 — La fuente de reloj es una elección explícita.** `Internal` (por defecto)
y `External`, en la pantalla `3 · MIDI`, junto al tempo interno.

Con `Internal`, los tres mensajes de FR1 **se ignoran por completo**: conectar un
cable no puede cambiar lo que suena. Con `External`, el transporte de pantalla
arma y el maestro dispara (FR4).

**FR4 — Con `External`, el transporte del maestro manda sobre el de la app.** Su
Start arranca —desde el paso 0, con el origen de la rejilla en el instante del
Start y los doce Tracks **en fase**— haya pulsado Play alguien o no, y sobre un
transporte que ya suena lo reinicia. El botón de la app sigue arrancando en el
momento: el maestro manda, pero no hay que esperarlo.

> **Enmendado el 2026-09-03, verificando en dispositivo.** La versión anterior
> decía que Play *armaba* y que la música empezaba con el Start del maestro, con
> un estado `Waiting for clock`. Con el hardware delante resultó no ser
> intuitivo: obligaba a pulsar Play en el iPad **antes** de darle a Play en el
> controlador, y sin ese paso el gesto del hardware no hacía nada. Elegir
> `External` ya es decir que el transporte lo lleva el hardware.
>
> Lo que se conserva es lo que la decisión original buscaba: **un solo maestro
> manda**, y no hay estado en el que la app y el hardware lleven transportes
> distintos.

**FR5 — El Stop externo para y desarma.** Simétrico al Start, y con el **mismo
barrido de notas** que `Transport.stop()` ya hace: `CC 123` por canal más el
barrido de alturas de los Cycles. Volver a sonar exige pulsar Play otra vez.

**FR6 — El look-ahead se conserva; la fase se re-ancla por negra.** El scheduler
sigue sellando la ventana futura con timestamps, calculados con el periodo
estimado vigente. Cada 24 ticks se compara la posición de la rejilla contra el
reloj del maestro y se corrige el origen.

Dos límites que la corrección respeta:

- **No se reprograma nada ya sellado.** Un evento entregado a CoreMIDI con su
  timestamp se emite en ese instante; la corrección afecta a la ventana
  siguiente.
- **La corrección no asigna, no toma locks y no espera.** Llega del hilo de
  recepción de CoreMIDI y la lee el hilo del scheduler: viaja por un atómico de
  `CToraxAtomics`, como ya hacen `PlayheadClock` y `PatternHandoff`.

**FR7 — El corte de clock no para la música.** Si no llega tick dentro de un
margen del orden de **una negra** sobre el periodo esperado, se declara el corte:
la app **sigue sonando con el último tempo conocido** y la pantalla lo indica. Si
el clock vuelve, se re-engancha sin parar y sin saltar al paso 0.

Es el criterio de `product-guidelines.md`: un dispositivo MIDI desconectado se
comunica con un estado, no con una disculpa.

**FR8 — El tempo interno deja de ser una constante.** Editable en la pantalla
`3 · MIDI`, en el rango 20–300 que el tipo `Tempo` ya valida. Es lo que hace útil
el fallback de FR7 y lo que evita que cambiar de tempo exija conectar un
controlador.

**FR9 — La barra dice el tempo y quién lo manda.** El `%.1f BPM` que ya existe
pasa a mostrar el tempo vigente, y junto a él una marca de fuente
(`INT` / `EXT`). En `External` el número se muestra **redondeado y estable**
—solo cambia cuando el cambio es real, no con cada tick—: la barra se lee de un
vistazo a un metro y un último decimal que fluctúa es ilegible.

**FR10 — El clock llega por la fuente ya elegida.** La misma que
`connectToSelectedSource` conecta para el control. No hay segunda lista de
endpoints ni segunda conexión.

## Non-Functional Requirements

**NFR1 — La aritmética del reloj vive en `Engine`.** El estimador, la corrección
de fase y el rechazo por rango son funciones puras y se testean sin simulador. En
`MIDI` queda el cableado: recepción, atómicos y transporte.

**NFR2 — Ni el hilo del scheduler ni el callback de recepción asignan, bloquean o
esperan.** El callback de CoreMIDI corre en su propio hilo y llega por cada tick
—40 veces por segundo a 100 BPM—: lo que haga tiene que ser aritmética y una
escritura atómica.

**NFR3 — Cobertura:** `Engine` ≥90%, `MIDI` ≥80%.

**NFR4 — Se mide el jitter, con reloj interno, como regresión.** Excepción
acotada a la suspensión del 2026-09-02, justificada porque este es el primer
cambio desde entonces que toca **la rejilla temporal misma** y no la carga.
Referencia: v2 rebanada 2 — máx **0,158 ms**, σ **0,013–0,014 ms**, 1000 eventos
por tempo. ~~Una regresión bloquea el cierre.~~

> **Enmendado el 2026-09-04: se cierra con la regresión dentro.** Dos pasadas de
> 1000 eventos dan máx **0,525 ms** y σ hasta **0,030 ms** — CUMPLE el umbral del
> proyecto con 4,3× y 16× de margen, y **triplica el máximo de la referencia**.
> No es un episodio: se reproduce, y con un patrón claro —60 BPM limpio, 120 y
> 174 degradados—.
>
> **Lo decidió el usuario** con los dos números delante, y con el experimento que
> lo habría zanjado —medir `main` en el mismo iPad el mismo día— propuesto y
> descartado. El detalle, los sospechosos y la referencia nueva están en
> `device-verification.md`.

**NFR5 — Las dos desviaciones se escriben antes de implementar.** Lo exige la
regla 2 del workflow:

- `tech-stack.md`: enmienda a *Arquitectura de timing* — el tempo deja de ser
  fijo al arrancar y el origen de la rejilla puede corregirse en vuelo.
- `product.md`: el MVP promete «transporte (play/stop) y **reloj interno**». Nota
  fechada.

**NFR6 — Verificado en dispositivo**, con el BeatStep Pro como maestro y un sinte
recibiendo.

## Acceptance Criteria

1. Con `External`, pulsar Play en el BeatStep arranca la app **sin haber tocado
   el iPad**; y si ya estaba sonando, la reinicia desde el paso 0.
2. Los doce Tracks arrancan en fase entre sí y con el hardware.
3. Cambiar el tempo del BeatStep mueve el de la app, y la barra muestra el valor
   nuevo sin fluctuar en el último decimal.
4. Tocando dos minutos seguidos, la app **no se separa** audiblemente del
   secuenciador del BeatStep.
5. El Stop del BeatStep para la app, no deja ninguna nota colgada y la desarma.
6. Desconectar el cable con el transporte corriendo: la música **sigue** al
   último tempo conocido y la pantalla lo indica. Volver a conectarlo re-engancha
   sin parar ni reiniciar.
7. Con `Internal`, pulsar Play y Stop en el BeatStep no afecta a la app.
8. Con `Internal`, el tempo se edita en `3 · MIDI` en todo el rango 20–300 y se
   oye el cambio.
9. Un maestro fuera de rango se ignora y se dice; no se acota en silencio ni se
   para la música.
10. La medición de jitter con reloj interno CUMPLE el umbral del proyecto.
    *(Enmendado el 2026-09-04: pedía «sin regresión frente a la referencia» y hay
    regresión — ver NFR4.)*

## Limitaciones conocidas

1. **Sin Continue ni Song Position.** Siempre se arranca desde el paso 0.
   Reanudar a mitad de compás exige conservar la posición al parar, que hoy no se
   guarda.
2. **La app no emite clock.** Nada externo puede seguirla; el maestro es siempre
   el otro.
3. **Un cambio brusco de tempo tarda en verse.** Hasta una ventana de look-ahead
   más una negra, por FR2 y FR6. Un barrido rápido de tempo en el maestro se oye
   con retraso, y el re-anclaje puede dejar un salto perceptible si el maestro
   tiene mucho jitter propio.
4. **El maestro tiene que ser el mismo dispositivo que manda el control** (FR10).
   Un reloj de otra fuente no se soporta.
5. **El timing empeoró respecto a la referencia y se entrega así.** Máx 0,525 ms
   contra 0,158 ms, con σ 0,030 contra 0,013–0,014. Dentro del umbral y sin causa
   identificada; los dos sospechosos y el experimento pendiente están en
   `device-verification.md`.
6. **El modo esclavizado se entrega sin número de jitter.** NFR4 mide con reloj
   interno, que responde si se degradó lo que ya funcionaba; el jitter *siguiendo
   a un maestro* queda sin medir, porque el arnés no sabe comparar contra un
   reloj externo y enseñarle es un track propio. Se juzga tocando, contra el
   criterio 4.
7. **La fuente de reloj y el tempo no se guardan.** No hay persistencia todavía;
   al arrancar se vuelve a `Internal` y al tempo por defecto.

## Out of Scope

- **Todo el feedback visual en el controlador** — es el track siguiente, que
  queda registrado sin planificar.
- MIDI Learn y la generalización a otro hardware (rebanada 8 de la v1).
- La app como maestro de clock; Ableton Link; MIDI Program Change.
- Continue, Song Position Pointer y el tempo en un knob del controlador.
- Persistir la fuente de reloj y el tempo (llega con Patterns y Banks).
