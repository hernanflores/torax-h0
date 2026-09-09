# Spec — MVP rebanada 8: MIDI Learn, con `network-session-source` dentro

## Overview

**Cierra la v1.** `product.md` promete, desde su línea de Mapeo, «preset listo
para BeatStep Pro + **MIDI Learn** para reasignar a otro hardware», y su nota del
2026-08-31 dice con todas las letras que «hasta que cierre la 8, esta página
promete un MIDI Learn que la app todavía no hace».

Hoy `ControlMapping` es fija: los números viven en código —`beatStepPro`,
`defaultKnobBlock`, `defaultPadBlock`, `defaultStepButtonBlock`— y su propia
documentación declara que «reasignarla a otro hardware es MIDI Learn, que es la
rebanada 8 del MVP». `ControlInput` la recibe en el `init` como un `let` privado.

**Tres problemas, y solo uno es el aprendizaje:**

1. **Aprender.** Escuchar un control físico y asignarlo a un destino.
2. **Escuchar la fuente correcta.** Es `network-session-source`, y aquí sí
   bloquea: aprender de `Red Session 1` es aprender de nada.
3. **Que sobreviva a cerrar la app.** Un mapeo que hay que rehacer en cada
   arranque no es una reasignación, es una ceremonia.

## Lo que la persistencia ya cambió

El plan de `network-session-source` dejó escrito, en sus notas de riesgo: «Es
aceptable mientras no haya persistencia; cuando la haya, recordar la última
elección lo resuelve mejor que cualquier heurística».

La hay desde el 2026-09-07. `Project` guarda `sourceName` y `destinationName`, y
`ProjectRecord` los escribe en la cabecera. **Así que el reparto cambia**: la
elección recordada manda, y la regla de no autoseleccionar la sesión de red es lo
que hace falta para el primer arranque y para cuando lo recordado ya no está.

## Functional Requirements

### El mapeo deja de ser fijo

**FR1 — `ControlMapping` se puede construir aprendida, no solo declarada.** Sigue
existiendo `beatStepPro` como preset de fábrica y como valor por defecto: lo que
cambia es que deja de ser el único.

**FR2 — `ControlInput` adopta un mapeo nuevo en caliente.** Una vía pública, con
la forma de `adopt(_:)` para el Pattern. Hoy `mapping` es un `let` privado que
solo se escribe en el `init`, que es el mismo error de forma que
`control-input-adoption_20260908` arregló para el material.

**FR3 — Cambiar el mapeo no toca el material.** Ni una nota, ni un Cycle, ni el
Track seleccionado. Un mapeo es cómo se llega al material, no el material.

**FR4 — Un control aprendido desasigna al que ocupaba ese destino.** Un destino
tiene un control y solo uno. Aprender el knob 5 para Steps deja Steps con el knob
5 y sin el anterior; si el 5 movía otra cosa, esa otra cosa se queda sin control
y se dice en pantalla.

**FR5 — Lo no asignado sigue siendo un estado válido, no un error.** Es lo que
`ControlMapping` ya declara: «sin decir qué se ignora, cualquier mensaje
inesperado parece un defecto». Un destino sin control no se puede mover, y no
pasa nada más.

### Aprender

**FR6 — Se aprende destino a destino.** Se elige el destino en pantalla, se mueve
el control físico, y ese control queda asignado. No hay recorrido guiado de los
cuarenta y ocho: aprender uno es el gesto, y repetirlo es el recorrido.

**FR7 — Las tres familias se aprenden.** Knobs (CC relativos), pads (notas) y
step buttons (CC de conmutación). Son las tres que el BeatStep Pro tiene y las
tres que `ControlMapping` describe.

**FR8 — Un knob se aprende girándolo, y girar es más de un mensaje.** El primer
CC que llega decide el número; los siguientes del mismo control **no** reabren la
pregunta. Sin esto, un giro de tres clics aprendería tres veces.

**FR9 — Se puede cancelar sin asignar.** Entrar en aprendizaje y salir deja el
mapeo como estaba. Es lo que permite equivocarse de destino sin consecuencias.

**FR10 — Mientras se aprende, no se edita.** Un CC que llega en modo aprendizaje
asigna y **no** mueve el parámetro que tuviera asignado. Aprender girando el knob
de Steps no puede además cambiar Steps.

**FR11 — El transporte sigue sonando mientras se aprende.**
`product-guidelines.md` prohíbe modales que bloqueen con el transporte corriendo,
y aquí manda igual: se aprende con la secuencia sonando.

### La fuente correcta — `network-session-source` dentro

**FR12 — La sesión de red nunca se autoselecciona.** Sigue en `available` y
`selecting(_:)` la acepta: lo que cambia es que no se elige sola. Es FR3 del
track absorbido, y su NFR4 manda — **no se identifica por el nombre visible**,
que depende del idioma del sistema y de lo que el usuario le haya puesto. La
identificación se apoya en una propiedad del endpoint, y **cuál se decide con el
diagnóstico en dispositivo, no antes**.

**FR13 — El estado vacío vuelve a ser alcanzable.** Con solo la sesión de red en
la lista, `hasEndpoint` es `false` y se lee `No MIDI input` con el indicador
`read-only`. Es el comportamiento que `product-guidelines.md` especifica y que
hoy existe en el código sin poder verse en el producto.

**FR14 — Conectar un controlador basta.** Con la app abierta, conectar un
controlador lo convierte en la fuente activa sin tocar el selector.
Desconectarlo vuelve a FR13.

**FR15 — Lo recordado manda sobre la autoselección.** Si el `Project` recuerda
una fuente y esa fuente está presente, se elige — **incluida la sesión de red**,
porque haberla elegido a mano y guardado es una elección explícita. La regla de
FR12 es para cuando no hay nada recordado o lo recordado no está.

### Que sobreviva

**FR16 — El mapeo aprendido se guarda y se restaura.** Vive con los ajustes de
sesión del `Project`, junto a `clockSource`, `destinationName` y `sourceName`,
que es donde ya está lo que no es material.

**FR17 — Un fichero de una versión anterior abre, y abre con el preset de
fábrica.** `ProjectRecord.validated()` exige igualdad exacta de
`schemaVersion`, así que **añadir el mapeo obliga a decidir**: o el campo es
opcional y la versión no sube, o sube y entra el primer migrador —el punto que
`persistence_20260907` dejó preparado y deliberadamente vacío—. **La decisión se
toma en la Fase 1 y se escribe con su porqué**; lo que no es negociable es que un
fichero existente no se pierda.

**FR18 — Restaurar un mapeo no puede dejar la app muda.** Un mapeo guardado que
no case con nada de lo conectado es un estado legítimo; lo que no puede pasar es
que no haya vía de vuelta al preset de fábrica.

### La medición final de la v1

**FR19 — La v1 no cierra sin decidir qué pasa con la medición final.** El
`workflow.md` la nombra como una de las dos excepciones a la suspensión del
2026-09-02 —«antes de cerrar v1, una medición final»— y la suspensión es
posterior. **La decisión es del usuario y se toma en la Fase 1**, no al llegar al
final con la rama abierta. Las dos salidas son válidas y las dos se escriben:

- **Se mide**: se levanta la suspensión solo para esta pasada, con la rejilla
  `12-tracks-cycles`, y el número entra en `product.md` y en el registro.
- **No se mide**: se anota en `workflow.md` que la v1 cerró sin su medición
  final, con lo que eso cuesta —la última referencia válida es la de la rebanada
  2 de la v2, del 2026-09-02: máx 0,158 ms, σ 0,013–0,014 ms—.

> **Resuelto el 2026-09-09 — la v1 cierra sin su medición final.** Decisión del
> usuario, en la Fase 1. Manda la suspensión del 2026-09-02, y la excepción
> «antes de cerrar v1, una medición final» queda **anulada** en `workflow.md`,
> con su coste escrito y con cómo revertirla si algún día se quiere.
>
> **Consecuencia para este track:** la tarea de medición de la Fase 7 se reduce a
> comprobar que la nota está escrita. No hay número que recoger, y **no hace
> falta el arnés en dispositivo** para cerrar la v1 — lo que sí hace falta sigue
> siendo el iPad, para la Fase 2 y para la verificación de la 7.

## Non-Functional Requirements

**NFR1 — Nada nuevo en el camino de tiempo real.** El mapeo se consulta donde ya
se consulta —`ControlInput.receive`, en el hilo de entrada— y cambiarlo es una
operación del hilo principal. El scheduler no se entera de que esto existe.

**NFR2 — Testeable sin hardware.** `MIDIEndpointSelection` recibe la lista ya
enumerada, así que el caso de la sesión de red se reproduce inyectando una lista
(NFR1 del track absorbido). El aprendizaje se prueba inyectando mensajes, que es
como se prueba todo `ControlInput`.

**NFR3 — Cobertura.** `MIDI` ≥80%, `Engine` ≥90% y `Persistence` ≥90% si el mapeo
baja ahí.

**NFR4 — No identificar endpoints por nombre visible** (FR12). Es NFR4 del track
absorbido y se mantiene entero.

**NFR5 — La medición de jitter, según FR19.** Si se mide, es en dispositivo y con
la rejilla `12-tracks-cycles`; el arnés sigue en el repositorio con sus tests. Si
no, se documenta.

**NFR6 — El preset del repositorio y el código no se pueden separar.**
`preset/README.md` declara los mismos números que `ControlMapping.beatStepPro`.
Si el aprendizaje cambia la forma de la tabla, el preset se revisa en la misma
rama o deja de describir la app.

## Acceptance Criteria

1. Con un controlador que no sea el BeatStep Pro, aprender un knob para Steps y
   comprobar que **ese** knob mueve Steps y el del preset ya no.
2. Aprender un pad y un step button: los tres tipos de control funcionan (FR7).
3. Girar un knob durante el aprendizaje asigna **una vez**, no una por clic
   (FR8), y **no mueve el parámetro** (FR10).
4. Cancelar el aprendizaje deja el mapeo intacto (FR9).
5. Aprender con el transporte sonando no lo interrumpe (FR11).
6. Cerrar y abrir la app: el mapeo aprendido sigue puesto (FR16). Un fichero
   escrito antes de este track abre sin perderse (FR17).
7. Hay vía de vuelta al preset de fábrica desde la pantalla (FR18).
8. **Sin controlador conectado en un iPad real**: se lee `No MIDI input` y el
   indicador `read-only` (FR13). Conectar el BeatStep Pro lo activa sin tocar el
   selector (FR14).
9. La sesión de red se puede elegir a mano, y elegida sobrevive al refresco y al
   reinicio (FR12, FR15).
10. `MIDI` ≥80%, `Engine` ≥90%, `Persistence` ≥90% si aplica, y la suite entera
    verde.
11. FR19 resuelto: hay número, o hay nota fechada diciendo que no lo hay.

## Out of Scope

- **Aprender el mapeo del transporte y del reloj.** Start, Stop y clock los
  atiende `Transport`, y son mensajes de sistema en tiempo real: no llevan número
  que reasignar.
- **Perfiles de mapeo, varios a la vez, o exportar e importar mapeos.** Uno
  vigente, guardado con la sesión. Varios perfiles es un modelo más que nadie ha
  pedido.
- **Aprender modos de encoder distintos de `Relative #2`.** La nota del
  2026-08-28 de `workflow.md` sigue mandando: `RelativeEncoding` decodifica
  complemento a dos y nada más. Aprender **qué** control es no es aprender
  **cómo** codifica.
- **Recordar la última fuente entre dispositivos**, o cualquier cosa que exija
  identificar un endpoint más allá de su nombre guardado.
- **Los knobs 15 y 16** (CC 84 y 85), que siguen libres a propósito para Accent,
  Voicing y Range en v2.
- **El lado del destino de la sesión de red**: como salida es una elección
  legítima y no estorba a ningún estado especificado.

## Known Limitations

- **La propiedad que identifica la sesión de red puede no ser estable entre
  versiones de iPadOS** (limitación 1 del track absorbido). Por eso el
  diagnóstico se registra con los valores observados: si cambia, se sabrá contra
  qué comparar.
- **Un mapeo aprendido con un controlador y usado con otro no avisa.** Los
  números casan o no casan; la app no sabe qué hardware hay al otro lado.
- **Aprender es destino a destino** (FR6). Reasignar los cuarenta y ocho
  controles de un controlador nuevo son cuarenta y ocho gestos.
