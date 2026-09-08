# Verificación en dispositivo — v2 rebanada 6: LFO Modulation

**Track:** `modulation_20260906`
**Fecha:** 2026-09-08
**Dispositivo:** iPad + BeatStep Pro, encoders en `Relative #2`
**Sinte externo:** necesario. Es lo único que puede decidir el criterio 13.

> **El preset no cambia.** `waveform` y `accent` **no tienen knob** (FR9), así que
> no hay que recargar nada en MIDI Control Center: los cuarenta y ocho controles
> siguen haciendo exactamente lo que hacían. Es la primera rebanada de parámetros
> del proyecto que no toca el preset.

## Por qué esta verificación es la que decide

**La modulación cambia con cuánta fuerza suena cada Step, y eso solo se juzga
oyéndolo.** Los tests fijan los números —la serie de velocities de una vuelta
está escrita al Step— pero un número no dice si el resultado *respira* o si
suena a un volumen que sube y baja sin sentido musical.

Lo que un test no puede decir:

- Si el acento **se oye** como movimiento y no como un defecto.
- Si el recorte contra 127 se nota **asimétrico** al oído, que es la limitación
  que la spec anota como silenciosa.
- Si el playhead del panel va **con** el del anillo o con retraso visible.
- Si el panel y la lectura grande se leen **a un metro**.

**No lleva medición de jitter** (NFR3). La modulación cambia el *cuánto* y no el
*cuándo* —`Groove.modulated` deja Timing y Delay intactos—, que es el caso que la
nota del 2026-08-28 de `workflow.md` excluye; y la medición está suspendida desde
el 2026-09-02.

## Lo que hay que comprobar

### 1. El criterio 1 primero: con `accent` en 0 no cambia nada

Es lo que sostiene la rebanada entera, así que se comprueba **antes** de tocar
nada nuevo.

1. Abrir un Pattern que conozcas de antes de hoy. Ponerlo a sonar.
2. Tiene que sonar **idéntico**: mismos golpes, mismas duraciones, misma
   dinámica, mismas omisiones de Probability.
3. Un Bank guardado antes del cambio **abre y suena igual**, con la modulación en
   su neutro: `waveform triangle · accent 0`.

- [X] Resultado: OK

### 2. El acento se oye (criterio 13)

1. Un Track con `Velocity` sobre 64 —el centro del rango, donde la onda se oye
   entera sin recortar—, `triangle`, y subir `accent` hasta arriba.
2. Tiene que oírse como **una respiración a lo largo de la vuelta**: el golpe del
   cuarto de vuelta es el más fuerte, el de los tres cuartos el más flojo, y el
   primero de cada vuelta vuelve al medio.
3. `accent` a 0 y el Track vuelve a sonar plano, en el acto.

- [X] Resultado: OK

### 3. `pulse` acentúa media vuelta entera

1. La misma configuración con `pulse`.
2. La primera mitad de la vuelta entera suena por encima y la segunda por debajo,
   sin nada intermedio. Con Steps impares, el Step del medio cae en la mitad
   **alta**.

- [X] Resultado: OK

### 4. El recorte, que se ve y no se avisa

1. Dejar la `Velocity` en su default —100— y `accent` alto.
2. **En el panel:** las barras del cuarto de vuelta se aplanan contra el techo
   formando una meseta, mientras la línea de la onda sigue subiendo por encima.
3. **Al oído:** anotar cómo suena esa asimetría. Es la limitación que la spec
   declara «silenciosa en el sonido y visible solo en el panel», y aquí es donde
   se comprueba que la descripción es justa.

- [X] Resultado: OK

### 5. El playhead del panel (FR14)

Es lo único de la pantalla que el simulador no pudo verificar.

1. Con el transporte corriendo, el playhead cae **sobre la barra que suena** y
   avanza una barra por Step.
2. Va **con** el playhead del anillo de la pantalla `track`, sin retraso visible
   al cambiar de una a otra.
3. Al parar, el playhead **desaparece** y las barras se quedan dibujadas: son
   estado, no animación.

- [x] Resultado: **falló y se arregló.** El playhead no se movía. La causa no
  estaba en el cálculo sino en el redibujado: `TransportModel.playheads` no es
  estado observable —cambia de forma continua, y publicarlo obligaría a
  invalidar la vista entera a 60 Hz—, así que se consulta al dibujar y quien lo
  dibuja tiene que provocar su propio repintado. El anillo lo hace con un
  `TimelineView`; este panel recibía el valor por parámetro y lo leía una sola
  vez al construir el cuerpo. Arreglado en `d3d0667`: el playhead llega como
  cierre y solo él vive dentro del `TimelineView` —las barras se quedan fuera,
  porque son estado y no animación—. **Recomprobado en dispositivo: cumple.**

  > **Solo podía encontrarse aquí.** El simulador no tiene destinos MIDI, así que
  > no hay transporte que mueva el playhead y las seis capturas no podían verlo.
  > Es la razón por la que este documento existe.

### 6. Cada Track con su anillo (FR4)

1. Dos Tracks sonando, con Steps distintos —16 y 8, por ejemplo— y los dos con
   `accent` alto.
2. El de ocho tiene que respirar **al doble de velocidad** que el de dieciséis.
   El desfase es la función, no un defecto.

- [X] Resultado: OK

### 7. El Cycle en edición, y que la etiqueta no mienta (FR16)

1. Un Track con dos Cycles activos: el A sin acento, el B con `accent` alto.
2. Con el A sonando, mover el knob del Cycle en edición al B y ajustar su acento.
   **La etiqueta tiene que decir `cycle 02`** mientras suena el A.
3. Al cerrar la vuelta, el B entra **ya acentuado desde su primer Step**.

- [X] Resultado: OK

### 8. El slider, con el dedo (FR18, criterio 11)

1. Arrastrar cerca del centro: `accent` engancha en **0 exacto**.
2. Un toque simple sobre la pista salta a ese valor.
3. Los extremos **no** se imantan: cerca de ±100 el ajuste sigue siendo fino.

- [x] Resultado: **cumple.** El imantado funciona — confirmado el 2026-09-08.

### 9. Legibilidad a un metro

1. El panel `velocity response` se lee de pie y a un metro: se distingue la forma
   de la envolvente sin acercarse.
2. La lectura grande de `accent` —`+34`, `-12`, `0`— se lee a la misma distancia.

- [X] Resultado: OK

### 10. Sin controlador conectado

1. Desenchufar el BeatStep Pro. La pantalla `modulation` **no cambia**: es
   táctil de principio a fin y no depende de que haya knobs.

- [X] Resultado: OK

## Veredicto

**Cumple, los diez bloques.** Nueve pasaron a la primera; el 5 —el playhead del
panel, FR14— falló, se arregló en `d3d0667` y se recomprobó.

**El acento se oye** (criterio 13), que es lo que esta rebanada existía para
conseguir: con `triangle` y `accent` alto el patrón respira a lo largo de la
vuelta, y `pulse` acentúa media vuelta entera. Con `accent` en 0 un Pattern de
antes suena idéntico, y un Bank guardado antes abre con la modulación en su
neutro — el criterio 1, comprobado con el oído además de con los tests.

**Sin medición de jitter** (NFR3): la modulación cambia el *cuánto* y no el
*cuándo*, y la medición está suspendida desde el 2026-09-02.
