# Spec — Pitch y Harmony

## Overview

La Pre Spec ya nombra los dos controles que faltan en la familia Tonal: **Pitch**
«transpone el pool dentro de la Scale actual» y **Harmony** «mueve una voz del
acorde a la vez». La v1 los dejó fuera. Este track los entrega como dos
`TrackParameter` nuevos, movidos por knob, y usa como referencia de algoritmo el
PRD `conductor/Pitch_Harmony_PRD.docx`.

**Del PRD se toma el algoritmo, no el vocabulario ni el modelo de datos.** Todo
lo que el PRD propone y el proyecto ya tiene definido se queda como está:

| El PRD dice | En el proyecto es | Decisión |
|---|---|---|
| *Voice* | un **pitch del pool**, identificado por su índice en `PitchPool` | «Voz» ya es el Track (`product.md`). No se introduce el término. |
| *Base note*, `baseDegrees` | el **pool** | No se guarda una copia paralela en grados: el grado se deriva de `TonalFrame`. |
| *Scale lattice* | `TonalFrame` + `Scale.degrees` | No hay tipo nuevo con ese nombre. |
| Requantize al cambiar Scale/Root | `PitchPool.reframed(to:)` | Se conserva tal cual. Solo se añade limpiar Harmony. |
| Normalizar duplicados | `PitchPool` ya es un conjunto | Sin cambios. |
| `TonalState` guardado en preset/pattern | campos de **`Cycle`**, persistidos por `CycleRecord` | Inline y POD, con 8 huecos y sin arrays. Tampoco 16 voces: el pool tiene 8. |
| *Detent*, `harmonyControlValue` | el **delta** de un knob relativo (`RelativeEncoding`) | No se guarda valor absoluto del control. |
| Saltos de CC absoluto | no existen: los knobs son relativos | Sin política de salto. |
| *Reset Harmony* como comando | — | **Descartado.** No se implementa. |
| Automation, debug state | no existen en el proyecto | Fuera. |

**El índice del pool sirve como identidad estable.** El pool está ordenado de
grave a agudo, y Harmony prohíbe cruces y choques. Así el orden nunca cambia y el
pitch *i* sigue siendo el *i*-ésimo después de cualquier movimiento.

## Functional Requirements

### Modelo

- **FR1 — Estado por Cycle.** Cada `Cycle` guarda `pitch`, un offset con signo en
  grados de escala, y el estado de Harmony: un offset con signo en grados por
  hueco del pool (8 huecos) y un cursor. Es inline y POD, y `_isPOD(Cycle.self)`
  sigue siendo cierto. Por defecto `pitch` 0, offsets 0 y cursor 0. Con los
  valores por defecto la salida es idéntica a la de antes del track.
- **FR2 — Pool que suena.** La altura emitida para el pitch *i* es
  `grado(pool[i]) + harmony[i] + pitch`, convertida a MIDI con el `TonalFrame`
  del Cycle. El grado es la posición en la escala contando octavas: en Do mayor,
  subir uno desde B3 da C4. Todo consumidor del pool en el camino de emisión
  (`PoolTraversal`, Note Repeater) usa el pool que suena. El pool base sigue
  siendo el que editan los pads.
- **FR3 — Siempre en la escala.** Toda altura emitida pertenece al marco
  (`TonalFrame.allows`) y está en 0–127.

### Pitch

- **FR4 — Unidad.** Un clic es un grado de la escala del Cycle y aplica el mismo
  offset a todos los pitches del pool. Los intervalos en grados se conservan.
- **FR5 — Rango.** `pitch` ∈ −28…+28. Es el `displacementRange` que usa Ctrl All.
- **FR6 — Freno atómico.** Si el resultado llevaría algún pitch que suena fuera
  de 0–127, el giro se frena en el último valor válido: no se aplica en parte ni
  se acota nota a nota. Con el pool vacío Pitch se mueve libre dentro de FR5.
- **FR7 — Pitch no toca Harmony.** Cambiar `pitch` no altera offsets ni cursor.
  Volver a 0 devuelve la forma de Harmony a su registro original.

### Harmony

- **FR8 — Un clic, un paso.** Un delta de *n* se procesa como *n* pasos
  sucesivos. Cada paso mueve **como mucho un** pitch del pool un grado en el
  sentido del giro.
- **FR9 — Round robin.** El paso intenta primero el pitch del cursor y luego los
  siguientes en orden circular. El primero con movimiento válido se mueve, y el
  cursor pasa al siguiente de ese. Si ninguno puede moverse, el estado queda
  intacto.
- **FR10 — Movimiento válido.** Un movimiento es válido si la altura que suena
  resultante, ya con Pitch aplicado, cumple dos condiciones: queda en 0–127 y
  queda **estrictamente** entre la del pitch vecino inferior y la del superior.
  Esto excluye choques y cruces. Sin span máximo.
- **FR11 — Histéresis.** Invertir el sentido no reinicia el cursor ni deshace el
  paso anterior (ejemplo del PRD: tras tres clics horarios desde C4 E4 G4, uno
  antihorario da C4 F4 A4).
- **FR12 — Pool de menos de dos.** Con 0 o 1 pitches Harmony no hace nada y el
  cursor no avanza.
- **FR13 — Se limpia.** Offsets y cursor vuelven a 0 cuando cambia el pool base
  (pad que inserta o quita) y cuando cambia Scale o Root. `pitch` se conserva en
  los dos casos. No existe otro gesto de reset.

### Entrada

- **FR14 — Knobs de fábrica.** Pitch en el knob 14 (CC 75) y Harmony en el knob
  15 (CC 76). Ningún knob existente se mueve y `Torax.beatsteppro` no cambia.
- **FR15 — MIDI Learn.** Los dos se aprenden como cualquier `TrackParameter`.
  Al abrir un proyecto con mapeo aprendido que no los tiene, se completan con CC
  75 y 76 **solo si** esos números no están ya asignados.
- **FR16 — Ctrl All.** Pitch desplaza como el resto de parámetros (base + offset,
  tope por FR5, freno por FR6 en cada Cycle). Harmony usa el mismo mecanismo:
  cada Cycle se recalcula como el estado base más |neto| pasos en el sentido del
  neto. **Bajo Ctrl All Harmony no depende del camino** (decisión explícita). Al
  soltar vuelve el estado capturado.
- **FR17 — Temp.** Pitch se iguala en todos los Cycles activos, como cualquier
  parámetro. Igualar Harmony no tiene sentido, así que cada clic de Harmony da un
  paso en cada Cycle activo del Track, con su propio estado. Al soltar vuelve el
  estado de Harmony capturado de cada Cycle.
- **FR18 — Giro bloqueado.** No hay aviso: nada cambia y el readout sigue igual.

### Pantalla

- **FR19 — Valor de Pitch.** Se escribe con signo explícito y sin signo en el
  cero: `+2`, `0`, `-1`.
- **FR20 — Valor de Harmony.** No tiene número. El valor transitorio y el card
  Tonal muestran el pool que suena (p. ej. `D4 F4 A4`).
- **FR21 — Pads y rejilla `scale`.** Iluminan el **pool base**. Pulsar un pad
  edita el pool base (y limpia Harmony, FR13). Lo que suena se ve en el readout.

### Persistencia y copia

- **FR22 — Guardado.** `CycleRecord` guarda `pitch`, offsets y cursor. Guardar y
  cargar reproduce la salida exacta sin rehacer giros. Un proyecto anterior sin
  estos campos se decodifica con los valores por defecto.
- **FR23 — Copias.** Copiar Pattern o Cycle arrastra el estado exacto.

## Non-Functional Requirements

- **NFR1 — Tiempo real.** Calcular la altura que suena desde el hilo del
  scheduler no asigna memoria, no usa locks ni await. El cálculo pesado (validar
  pasos, frenar Pitch) vive en el hilo de control.
- **NFR2 — Determinismo.** El mismo estado inicial y la misma secuencia de deltas
  producen la misma salida.
- **NFR3 — Frontera.** Toda la regla vive en `Engine`, sin CoreMIDI ni UI
  (`DependencyBoundaryTests`).
- **NFR4 — Jitter.** No se mide. No desplaza ningún instante y la medición está
  suspendida desde el 2026-09-02.
- **NFR5 — Vocabulario.** Solo términos de la Pre Spec: Pitch, Harmony, pool,
  Scale, Root. Ni *voice* ni *degree offset* en UI.

## Acceptance Criteria

1. En Do mayor, C4 E4 G4 con Pitch +1 suenan D4 F4 A4, y con −1 suenan B3 D4 F4.
2. Volver Pitch a 0 restaura la forma de Harmony en su registro original.
3. Un clic de Harmony cambia cero o un pitch que suena, nunca dos.
4. Desde C4 E4 G4, tres clics horarios dan D4 E4 G4, D4 F4 G4 y D4 F4 A4, y un
   clic antihorario después da C4 F4 A4.
5. Combinado: Pitch +1, tres clics de Harmony y uno inverso dan D4 G4 B4. Pitch
   a 0 da C4 F4 A4.
6. Toda altura emitida está en el marco y en 0–127 (test por propiedades sobre
   escalas, Roots, pools y secuencias de deltas).
7. Pitch conserva todos los intervalos en grados entre pares de pitches.
8. Un paso bloqueado deja el Cycle idéntico.
9. Insertar o quitar un pitch con un pad, o cambiar Scale o Root, limpia Harmony
   y conserva Pitch.
10. Guardar y cargar un proyecto reproduce la salida. Un proyecto anterior carga
    con Pitch 0 y sin Harmony.
11. Con Pitch 0 y Harmony limpio, la salida es idéntica a la de antes del track.
12. Ctrl All y Temp restauran Pitch y Harmony exactos al soltar.
13. Verificado en iPad con BeatStep Pro: knobs 14 y 15 mueven Pitch y Harmony,
    y se evalúa de oído con pools de 2, 3 y 4 pitches en major, minor y
    pentatonic, con giros lentos y rápidos y cambios de sentido.

## Out of Scope

- Reset Harmony (descartado).
- Voicing/Style, Range/Phrase, Style *Poly*.
- Locks por Step de Pitch o Harmony.
- Puntuación de consonancia, grafo de acordes y selección aleatoria sembrada.
- Pitch cromático, cruces configurables, span máximo y bajo protegido.
- Automation.

## Known Limitations

- **Bajo Ctrl All Harmony pierde la histéresis** (FR16). Es la mecánica de base
  + offset reutilizada tal cual, aceptada a cambio de no abrir `CtrlAllOffset`.
- **Ctrl All y Temp tratan Harmony distinto** (FR16 frente a FR17).
- **Desviación de la Pre Spec:** Pitch transpone en grados, no en «semitonos
  dentro del marco tonal». Se anota antes de implementar (Task Workflow §8).
