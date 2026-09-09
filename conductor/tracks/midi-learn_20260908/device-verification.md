# Verificación en dispositivo — MVP rebanada 8: MIDI Learn

**2026-09-09**, iPad con BeatStep Pro y OP-Z conectados por USB.

El OP-Z hace de **segundo controlador**, que es lo que esta rebanada necesitaba
para probar algo: con solo el BeatStep Pro, aprender es reaprender el preset y no
demuestra nada.

## El diagnóstico de CoreMIDI

Dos pasadas, con el BeatStep conectado y sin él. Las salidas enteras están en la
git note del commit `dae873c`.

**Resultado: `kMIDIPropertyDriverOwner` distingue la sesión de red.**

| | driverOwner |
|---|---|
| `Red Session 1` | `com.apple.AppleMIDINetworkDriver` |
| OP-Z | `com.apple.AppleMIDIUSBDriver` |
| Arturia BeatStep Pro | `com.apple.AppleMIDIUSBDriver` |
| BeatStepPro OutEditor | `com.apple.AppleMIDIUSBDriver` |

**El volcado entero de `MIDIObjectGetProperties(deep: true)` no sirve en
iPadOS**: devuelve solo `uniqueID`. Las candidatas con nombre eran el camino, y
esto queda escrito para que nadie vuelva a gastar tiempo de dispositivo en ello.

`model` y `manufacturer` vienen **vacíos** en la sesión de red y también
distinguirían hoy, pero eso es una ausencia y no una afirmación: un controlador
que tampoco los declarara rompería la regla.

## Lo que se comprobó

| | Resultado |
|---|---|
| La sesión de red ya no se autoselecciona como **entrada** | ✅ |
| La sesión de red ya no se autoselecciona como **salida** | ✅ |
| La fuente elegida a mano se recuerda entre arranques | ✅ |
| Aprender un parámetro con un knob, y que el parámetro **no se mueva** | ✅ |
| El resto del giro no edita el control recién aprendido | ✅ |
| Aprender con el transporte sonando, sin cortes | ✅ |
| **Aprender con el OP-Z**, que es otro hardware | ✅ |
| El mapeo aprendido sobrevive a cerrar y abrir la app | ✅ |
| `factory preset` devuelve el mapeo del BeatStep Pro | ✅ |
| El card enseña el número de cada destino, y cambia en el acto | ✅ |
| Un mapeo que dejaría un control significando dos cosas se rechaza | ✅ |
| El card se lee a un metro; los cuatro por fila caben | ✅ |

## Los tres fallos que la verificación encontró

Ninguno de los tres se habría visto sin dispositivo, y los tres eran míos.

### 1. Aprender un bloque convertía los knobs en step buttons

Se aprendió uno de los tres destinos de bloque con un knob, el bloque de step
buttons aterrizó encima de los CC de los knobs, y desde entonces **cada giro
cambiaba de Track**: `receive` despacha los step buttons antes que los knobs. Y
se guardaba con la sesión, así que sobrevivía a relanzar la app; la única salida
era el botón de fábrica.

**Lo que escuece:** `hasFamilyOverlap` se construyó en la Fase 3 exactamente para
detectar esto, con sus cuatro tests, y **no se llamó en el único sitio capaz de
provocarlo**. Tener la comprobación escrita y no usarla es peor que no tenerla:
da la impresión de que el caso está cubierto.

Arreglado en `83223a1`, ampliado a las dos formas del choque.

### 2. El card no enseñaba el número

Aprender funcionaba, pero en pantalla no cambiaba nada: el único indicador era
«tiene control», y en el preset de fábrica lo tienen todos los parámetros. La
única forma de saber si había funcionado era girar el knob.

Arreglado en `5193de4`.

### 3. El card no repintaba hasta cambiar de pestaña

`mapping` y `learning` eran propiedades calculadas sobre `ControlInput`, que **no
es observable**: leerlas desde el cuerpo de una vista no registra dependencia y
nada invalida el card. El `TimelineView` de la pantalla no lo salva — vuelve a
evaluar su cuerpo, pero SwiftUI no vuelve a entrar en un hijo cuyos parámetros no
cambiaron, y el hijo solo lleva la referencia al modelo.

Los cards de endpoints sí repintaban porque `selection` y `sourceSelection` son
propiedades **almacenadas** y observables del modelo.

Arreglado en `a861bb0`, reflejándolas en el modelo como `syncFromControlInput` ya
hacía con `pattern` y `selectedTrackIndex`, y por esta misma razón.

> **Es la misma clase de fallo que `hardware-screen-sync_20260908`**: estado
> detrás de un objeto no observable que no invalida la pantalla. Allí es
> `Transport` y el hilo de recepción de CoreMIDI; aquí era `ControlInput` y el
> hilo principal. Vale como evidencia de que aquel track no es un caso aislado.

## Un cuarto hallazgo, sin código detrás

`Project` tenía `destinationName` y `sourceName` desde `persistence_20260907`,
con su documentación de por qué se guarda el nombre y no el `MIDIEndpointRef`, y
**ningún camino de la app los escribía**: se guardaba `null` en cada guardado y
no se recordaba nada nunca. Sin esto, FR15 habría sido letra muerta y sus tests
la habrían dado por buena.

Se encontró al cablear FR15, no probando: es de los que no tienen síntoma hasta
que alguien depende de ellos.

## Lo que no se pudo ver, y por qué

- **`No MIDI input` sigue sin ser visible en este iPad.** La regla de FR13 es
  correcta y sus tests la fijan, pero hay un OP-Z permanentemente conectado, así
  que el estado vacío solo se ve desenchufándolo todo. No es un defecto: es lo
  que hace falta para verlo.

- **Los dos puertos del BeatStep Pro.** Publica `Arturia BeatStep Pro` y
  `BeatStepPro OutEditor`, y **ninguna propiedad los distingue** — mismo `model`,
  `manufacturer`, `driverOwner` y dispositivo padre. Solo el nombre, que NFR4
  prohíbe usar. Hoy no muerde porque el puerto de interpretación va antes en la
  lista, pero es suerte de orden. Queda como limitación conocida.

## Segunda vuelta, el mismo día

Con los tres arreglos puestos:

| | Resultado |
|---|---|
| Aprender un **pad** y un **step button** | ✅ |
| Los cuarenta y ocho controles del preset restaurado contra `preset/README.md` | ✅ |

Con esto las **tres familias** se han visto funcionar con hardware, no solo con
tests, y el preset de fábrica sigue siendo el que la tabla del repositorio
declara: MIDI Learn no lo ha roto por el camino.

## Cobertura, tras la verificación

| Módulo | Líneas | Umbral |
|---|---|---|
| `Engine` | 98,67% | ≥90% |
| `MIDI` | 91,30% | ≥80% |
| `Persistence` | 97,60% | ≥90% |

`Engine` 888 tests, `MIDI` 851, `Persistence` 64. Cero fallos.

> La pasada de `MIDI` en un solo proceso —la que exige la medida de cobertura—
> pasó entera esta vez, sin el flake `clientCreationFailed(-50)`. No es una
> mejora: es la naturaleza del flake, que la ampliación del 2026-08-30 de
> `workflow.md` mide en pasadas y no en certezas.
