# Verificación en dispositivo — Ctrl All

**Estado: verificado el 2026-09-05.** Comprobado por el usuario con el iPad y el
BeatStep Pro delante. Reportado como **«todo ok»**, sin incidencias.

Hardware de referencia: iPad Air (4ª gen) + Arturia BeatStep Pro, el mismo con el
que se verificaron las rebanadas anteriores.

**Sin medición de jitter** (NFR6): suspendida desde el 2026-09-02. El track no la
retoma, aunque Timing y Delay sean desplazables con el gesto.

**Sin test de coste del hilo de control** (NFR4): decidido sin número. Un clic
reescribe hasta doce Tracks contra el único de Temp; si el gesto se siente
pastoso al girar rápido, es el sitio donde anotarlo.

---

## 0. Preparación

- [x] Cargar `preset/torax-h0.beatstep-pro.json` (**version 3**) en MIDI Control
      Center.
- [x] Confirmar que los encoders están en **`Relative #2`**. Sin esto, un clic se
      lee como ±63 y todo salta a sus extremos — el síntoma no se parece a la
      causa (nota del 2026-08-28).
- [x] `xcodebuild build -scheme ToraxH0 -destination 'generic/platform=iOS'` e
      instalar en el iPad.

## 1. El remapeo de knobs (Fase 2, AC15)

- [x] El **knob 7** mueve **Delay** (no Probability).
- [x] El **knob 9** mueve **Probability** (no Delay).
- [x] Los knobs 1–6 y el 8 siguen donde estaban.
- [x] El **knob 13** mueve el **Cycle en edición** del Track seleccionado.
- [x] El **knob 10 no hace absolutamente nada**: sin salto, sin publicación.
- [x] La línea de Groove en pantalla sigue en orden de dominio
      —`Velocity · Sustain · Probability · Timing · Delay`— aunque la fila de
      knobs vaya en otro orden. **Confirmar que es legible así**; es la decisión
      del 2026-09-05 y este es el momento barato de desdecirse.

## 2. El supuesto que el track no probó (FR1)

- [x] El **step 14 es momentary y no toggle**: al soltarlo el gesto se va. Se
      asumió por el precedente del 13, contiguo y verificado. Si falla, el
      preset necesita otro modo y el riesgo del spec se materializó.

## 3. El gesto (AC1, AC2, AC3)

- [x] Mantener **step 14** y girar Velocity: los doce Tracks suben. Soltar
      devuelve el balance anterior.
- [x] **Desplaza y no iguala:** con dos Tracks de Pulses claramente distintos,
      los dos se mueven **manteniendo su diferencia**. Si suenan iguales, el
      gesto está haciendo lo de Temp.
- [x] Con varios Cycles activos en un Track, cada Cycle conserva su valor propio
      desplazado, y al soltar recupera **el suyo**.
- [x] Un parámetro que no se giró conserva su valor distinto por Track y por
      Cycle.

## 4. Los extremos (AC4, AC5)

- [x] Un Track topado contra su extremo **no arrastra a los demás**: los otros
      siguen moviéndose.
- [x] Giro largo contra el tope y vuelta: **el knob responde enseguida**, no se
      queda muerto decenas de clics. Es FR5, y su cálculo se corrigió durante la
      implementación.
- [x] Tras el gesto, soltar devuelve la base exacta aunque se haya saturado.

## 5. Rotate (AC6)

- [x] Con dos Tracks de Steps distintos (p. ej. 16 y 12), el mismo
      desplazamiento los **desfasa entre sí**, y soltar los devuelve.
- [x] El knob de Rotate no se queda muerto por mucho que se gire: envuelve.

## 6. La convivencia con Temp (AC9, FR13)

- [x] **13 y 14 hundidos a la vez** y girar → suena como **Temp**: solo el Track
      seleccionado.
- [x] **Soltar el 13 sin soltar el 14** → Temp restaura, y el giro siguiente
      alcanza a los doce.
- [x] **Soltar el 14 antes que el 13** → el Temp no se deshace antes de tiempo;
      sigue vivo hasta soltar el 13.
- [x] Tras el cruce no queda nada armado: un giro suelto escribe en un solo
      Track.

## 7. El corte de entrada (AC8)

Con el **step 14 hundido**:

- [x] Los step buttons 1–12 **no** cambian de Track.
- [x] Mute y solo (15 y 16) **no** publican gesto.
- [x] El knob del Cycle **no** mueve el cursor de edición.
- [x] Los pads **no** tocan el pool.
- [x] En pantalla: Scale, Root, canal, selección de Track y número de Cycles
      **no responden**.
- [x] Al soltar, **todo vuelve a funcionar**: el corte dura lo que dura el hold.

## 8. La pantalla (AC12, Fase 5)

**Es la primera vez que los dos distintivos se ven juntos**: el simulador no pudo
verificarlo porque sin fuentes MIDI la app arranca en read-only.

- [x] Step 13 → pastilla **TEMP** compacta.
- [x] Step 14 → banda **CTRL ALL** cruzando el panel.
- [x] **A un metro y de reojo se distinguen por el ancho**, sin leer la palabra.
      Si no, anotarlo: la alternativa es gastar un color, y eso obliga a decidir
      cuál.
- [x] Sale en las tres pestañas (Shape, Groove, Tonal).
- [x] Al soltar desaparece sola y la lectura vuelve a los valores base.

## 9. Reconexión y transporte (AC10, AC11)

- [x] Con el 14 hundido, desenchufar y reconectar el cable: el desplazamiento
      **no se queda puesto**.
- [x] El gesto se comporta **igual con el transporte parado**.
- [x] **Sin notas colgadas** en ninguna de las pruebas anteriores.

---

## Resultado

**Todas las secciones pasan.** Verificado en dispositivo el 2026-09-05; el usuario
lo reportó como «todo ok» y no anotó ninguna incidencia.

Lo que eso cierra, por ser lo que estaba genuinamente abierto:

- **El step 14 es momentary** (§2). Era el único supuesto del track que no se
  probó en ningún sitio: se aceptó por el precedente del 13, contiguo y
  verificado, y el spec lo listaba como riesgo. Queda confirmado, y con él la
  serie de los cuatro modificadores del bloque 102–117.
- **Los dos distintivos se distinguen por el ancho** (§8). Era la primera vez que
  se veían juntos: el simulador no pudo enseñarlo porque sin fuentes MIDI la app
  arranca en read-only. No hizo falta gastar un color, que era la alternativa.
- **El remapeo de knobs** (§1), incluido el orden de la línea de Groove en
  pantalla, que desde el 2026-09-05 ya no coincide con el de la fila de knobs. Se
  confirma legible así.

**Sin medición de jitter** (NFR6), suspendida desde el 2026-09-02, y **sin test de
coste del hilo de control** (NFR4), decidido sin número. Ninguna de las dos se
retomó, y el gesto no se reportó pastoso al girar rápido — que era el síntoma que
habría obligado a mirar el coste.
