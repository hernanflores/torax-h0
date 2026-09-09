# Verificación en dispositivo — En pantalla no se puede elegir qué Cycle se edita

**Estado: verificado el 2026-09-09**, entero, en tres pasadas. Comprobado por el usuario con
el iPad delante. **El defecto está cerrado**: la pantalla elige el Cycle en
edición y el gesto mantenido cambia el rango.

Hardware de referencia: iPad Air (4ª gen) + Arturia BeatStep Pro, el mismo con el
que se verificaron las rebanadas anteriores.

**Sin medición de jitter** (NFR5): suspendida desde el 2026-09-02, y este cambio
no mueve ningún instante.

**Lo que decidía esta verificación era el reparto de gestos**, no el modelo. La
Fase 1 tiene 15 tests y `ControlInput.swift` al 100%; el riesgo estaba en que
SwiftUI repartiera mal tap y hold sobre la misma celda, y eso no se comprueba
compilando.

---

## Lo que se probó y pasó

- [x] **Pulsar una celda elige el Cycle en edición** (FR5). Reportado como
      «cambiar cycles con la pantalla funcionó».
- [x] **Mantener la celda 9 medio segundo sube el rango a nueve sin soltar**
      (FR6). El cambio cae al cumplirse el tiempo, no al levantar el dedo, que es
      lo que hace que responda como un botón del hardware.
- [x] **Al soltar después del mantenido, el contorno no se mueve al 9** (FR7).
      Un toque, una cosa: el reparto `simultaneousGesture` + guard de `didHold`
      aguanta en el dispositivo.
- [x] **El knob 13 mueve el mismo contorno** (FR10). Reportado como «knob de
      Cycles funcionó». La Fase 1 lo había hecho pasar por la misma vía pública
      que la celda, y no hay regresión.

## Segunda pasada, el 2026-09-09 — tres comprobaciones más

Reportadas OK por el usuario después de cerrar el track. Con ellas, el criterio
de aceptación 1 —el fallo reportado, que es la razón de existir del track— queda
verificado a mano y no solo por test.

- [x] **Los dos valores conviven** (AC1, AC2): elegir el Cycle 3, girar Steps,
      volver al 1 y comprobar que cada uno guarda el suyo.
- [x] **Con el transporte corriendo** (AC5), el relleno del que suena avanza solo
      y el contorno del que se edita se queda donde lo dejó el dedo.
- [x] **Los bordes del gesto**: mantener y arrastrar fuera de la celda, mantener
      y soltar sobre otra, dos dedos a la vez. Ninguno deja el cursor ni el rango
      en un valor que nadie pidió — que era el riesgo que el plan anunciaba para
      la Fase 2.

## Tercera pasada, el 2026-09-09 — las dos que quedaban

Reportadas OK por el usuario. Con ellas **el plan queda verificado entero**: no
queda ninguna comprobación de dispositivo sin ejecutar.

- [x] **Bajar el rango** con el mantenido acota el cursor de edición.
- [x] **Cambiar de Track y volver** conserva el Cycle en edición de cada uno
      (FR9). Cubierto además por
      `testEachTrackKeepsItsOwnEditingCycleAcrossSelection`, que ya existía antes
      de este track.

## Limitaciones que siguen en pie

Las dos que la `spec.md` ya declaraba, sin novedad del dispositivo:

- **Mantener pulsado no tiene affordance visible.** Quien no lo sepa no descubre
  cómo cambiar el número de Cycles activos.
- **El gesto mantenido tarda** medio segundo, cuando hasta hoy el cambio de rango
  era inmediato. Es el precio de que el gesto frecuente sea el simple.
