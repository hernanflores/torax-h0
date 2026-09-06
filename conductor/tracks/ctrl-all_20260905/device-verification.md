# Verificación en dispositivo — Ctrl All

**Estado: pendiente.** Rellenar con el iPad y el BeatStep Pro delante.

Hardware de referencia: iPad Air (4ª gen) + Arturia BeatStep Pro, el mismo con el
que se verificaron las rebanadas anteriores.

**Sin medición de jitter** (NFR6): suspendida desde el 2026-09-02. El track no la
retoma, aunque Timing y Delay sean desplazables con el gesto.

**Sin test de coste del hilo de control** (NFR4): decidido sin número. Un clic
reescribe hasta doce Tracks contra el único de Temp; si el gesto se siente
pastoso al girar rápido, es el sitio donde anotarlo.

---

## 0. Preparación

- [ ] Cargar `preset/torax-h0.beatstep-pro.json` (**version 3**) en MIDI Control
      Center.
- [ ] Confirmar que los encoders están en **`Relative #2`**. Sin esto, un clic se
      lee como ±63 y todo salta a sus extremos — el síntoma no se parece a la
      causa (nota del 2026-08-28).
- [ ] `xcodebuild build -scheme ToraxH0 -destination 'generic/platform=iOS'` e
      instalar en el iPad.

## 1. El remapeo de knobs (Fase 2, AC15)

- [ ] El **knob 7** mueve **Delay** (no Probability).
- [ ] El **knob 9** mueve **Probability** (no Delay).
- [ ] Los knobs 1–6 y el 8 siguen donde estaban.
- [ ] El **knob 13** mueve el **Cycle en edición** del Track seleccionado.
- [ ] El **knob 10 no hace absolutamente nada**: sin salto, sin publicación.
- [ ] La línea de Groove en pantalla sigue en orden de dominio
      —`Velocity · Sustain · Probability · Timing · Delay`— aunque la fila de
      knobs vaya en otro orden. **Confirmar que es legible así**; es la decisión
      del 2026-09-05 y este es el momento barato de desdecirse.

## 2. El supuesto que el track no probó (FR1)

- [ ] El **step 14 es momentary y no toggle**: al soltarlo el gesto se va. Se
      asumió por el precedente del 13, contiguo y verificado. Si falla, el
      preset necesita otro modo y el riesgo del spec se materializó.

## 3. El gesto (AC1, AC2, AC3)

- [ ] Mantener **step 14** y girar Velocity: los doce Tracks suben. Soltar
      devuelve el balance anterior.
- [ ] **Desplaza y no iguala:** con dos Tracks de Pulses claramente distintos,
      los dos se mueven **manteniendo su diferencia**. Si suenan iguales, el
      gesto está haciendo lo de Temp.
- [ ] Con varios Cycles activos en un Track, cada Cycle conserva su valor propio
      desplazado, y al soltar recupera **el suyo**.
- [ ] Un parámetro que no se giró conserva su valor distinto por Track y por
      Cycle.

## 4. Los extremos (AC4, AC5)

- [ ] Un Track topado contra su extremo **no arrastra a los demás**: los otros
      siguen moviéndose.
- [ ] Giro largo contra el tope y vuelta: **el knob responde enseguida**, no se
      queda muerto decenas de clics. Es FR5, y su cálculo se corrigió durante la
      implementación.
- [ ] Tras el gesto, soltar devuelve la base exacta aunque se haya saturado.

## 5. Rotate (AC6)

- [ ] Con dos Tracks de Steps distintos (p. ej. 16 y 12), el mismo
      desplazamiento los **desfasa entre sí**, y soltar los devuelve.
- [ ] El knob de Rotate no se queda muerto por mucho que se gire: envuelve.

## 6. La convivencia con Temp (AC9, FR13)

- [ ] **13 y 14 hundidos a la vez** y girar → suena como **Temp**: solo el Track
      seleccionado.
- [ ] **Soltar el 13 sin soltar el 14** → Temp restaura, y el giro siguiente
      alcanza a los doce.
- [ ] **Soltar el 14 antes que el 13** → el Temp no se deshace antes de tiempo;
      sigue vivo hasta soltar el 13.
- [ ] Tras el cruce no queda nada armado: un giro suelto escribe en un solo
      Track.

## 7. El corte de entrada (AC8)

Con el **step 14 hundido**:

- [ ] Los step buttons 1–12 **no** cambian de Track.
- [ ] Mute y solo (15 y 16) **no** publican gesto.
- [ ] El knob del Cycle **no** mueve el cursor de edición.
- [ ] Los pads **no** tocan el pool.
- [ ] En pantalla: Scale, Root, canal, selección de Track y número de Cycles
      **no responden**.
- [ ] Al soltar, **todo vuelve a funcionar**: el corte dura lo que dura el hold.

## 8. La pantalla (AC12, Fase 5)

**Es la primera vez que los dos distintivos se ven juntos**: el simulador no pudo
verificarlo porque sin fuentes MIDI la app arranca en read-only.

- [ ] Step 13 → pastilla **TEMP** compacta.
- [ ] Step 14 → banda **CTRL ALL** cruzando el panel.
- [ ] **A un metro y de reojo se distinguen por el ancho**, sin leer la palabra.
      Si no, anotarlo: la alternativa es gastar un color, y eso obliga a decidir
      cuál.
- [ ] Sale en las tres pestañas (Shape, Groove, Tonal).
- [ ] Al soltar desaparece sola y la lectura vuelve a los valores base.

## 9. Reconexión y transporte (AC10, AC11)

- [ ] Con el 14 hundido, desenchufar y reconectar el cable: el desplazamiento
      **no se queda puesto**.
- [ ] El gesto se comporta **igual con el transporte parado**.
- [ ] **Sin notas colgadas** en ninguna de las pruebas anteriores.

---

## Resultado

*(Rellenar: qué se comprobó, qué falló, qué queda anotado.)*
