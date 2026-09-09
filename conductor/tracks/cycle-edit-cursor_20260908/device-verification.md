# Verificación en dispositivo — En pantalla no se puede elegir qué Cycle se edita

**Estado: verificado el 2026-09-09**, con matices. Comprobado por el usuario con
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

## Lo que no se probó

Se anota en vez de darse por bueno. Ninguno bloquea el cierre: los cuatro tienen
tests en `MIDI` que cubren la lógica, y lo que faltaba de verificar con el dedo
—el reparto de gestos— sí se verificó.

- [ ] **Los dos valores conviven**: elegir el Cycle 3, girar Steps, volver al 1 y
      comprobar que cada uno guarda el suyo. Cubierto por
      `testTwoCyclesCanHoldDifferentValues`, pero no confirmado a oído.
- [ ] **Con el transporte corriendo**, el relleno del que suena avanza solo y el
      contorno del que se edita se queda donde lo dejó el dedo.
- [ ] **Bajar el rango** con el mantenido acota el cursor de edición.
- [ ] **Cambiar de Track y volver** conserva el Cycle en edición de cada uno
      (FR9). Cubierto por `testEachTrackKeepsItsOwnEditingCycleAcrossSelection`,
      que ya existía antes de este track.

## Limitaciones que siguen en pie

Las dos que la `spec.md` ya declaraba, sin novedad del dispositivo:

- **Mantener pulsado no tiene affordance visible.** Quien no lo sepa no descubre
  cómo cambiar el número de Cycles activos.
- **El gesto mantenido tarda** medio segundo, cuando hasta hoy el cambio de rango
  era inmediato. Es el precio de que el gesto frecuente sea el simple.
