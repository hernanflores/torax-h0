# Verificación en dispositivo — v2 rebanada 5: Note Repeater

**Track:** `note-repeater_20260906`
**Fecha:** _(pendiente)_
**Dispositivo:** iPad Air 4ª generación
**Controlador:** BeatStep Pro, encoders en `Relative #2`, **preset versión 4**

> **Reconfigura el preset antes de empezar.** `preset/torax-h0.beatstep-pro.json`
> subió a la versión 4 el 2026-09-07 y añade cuatro knobs: 10, 11, 12 y 14
> (CC 79, 80, 81 y 83). Sin recargarlo en MIDI Control Center, los cuatro knobs
> nuevos no envían nada y la mitad de este guion no se puede hacer.

## Por qué esta verificación es la que decide

**Esta rebanada crea instantes nuevos entre los Steps y no se mide** (NFR6). La
medición de jitter está suspendida desde el 2026-09-02, y aquí **no se abre
excepción** — la abrió `external-clock_20260903` y esta no—. Así que el único
juez de si la tirada cae donde debe es el oído, y por eso este documento es
parte del cierre y no un trámite.

Lo que un test no puede decir:

- Si un ratchet **se arrastra**. Con Repeats 8 y Time 1/128 hay hasta 108 eventos
  por Step con doce Tracks; el techo de coste se razonó, no se midió.
- Si el swing **lleva la tirada entera** o la desparrama.
- Si Sustain sobre el hueco deja **notas colgadas** al solaparse.
- Si el cambio se oye **en el Step siguiente**, que es lo que
  `product-guidelines.md` promete de cualquier giro de knob.

## Lo que hay que comprobar

### 1. FR16 primero: con Repeats en 0 no cambia nada

Es lo que sostiene la rebanada entera, así que se comprueba **antes** de tocar
nada nuevo.

1. Abrir un Pattern que conozcas de antes de hoy. Ponerlo a sonar.
2. Tiene que sonar **idéntico**: mismos golpes, mismas duraciones, misma
   dinámica, mismas omisiones de Probability.
3. Un Bank guardado antes del cambio **abre y suena igual**, con los cuatro
   parámetros en su neutro: `repeats 0 · time 1/32 · ramp 0% · pace 0%`.

- [ ] Resultado:

### 2. Los cuatro knobs

1. Knob 10 → `Repeats`, de 0 a 8. Knob 11 → `Time`, las nueve fracciones. Knob
   12 → `Ramp`, ±100%. Knob 14 → `Pace`, ±100%.
2. Cada giro enseña el **valor grande transitorio** con su unidad: `3`, `1/32`,
   `+40%`, `-20%`.
3. El cambio se oye **en el Step siguiente**, no dos después.
4. Contra los topes, el valor **se queda quieto**: ninguno envuelve.
5. El knob 13 sigue moviendo el **Cycle en edición**, y el 15 y el 16 no hacen
   nada.

- [ ] Resultado:

### 3. Los dos gestos que la rebanada existía para hacer

1. **Ratchet de hi-hat:** un Track corto, `Repeats 3`, `Time 1/32`. Cada golpe
   pasa a ser cuatro.
2. **Roll:** `Repeats 8`, `Time 1/64`. Sobre un ritmo disperso —`Pulses 1` en 16
   Steps— el roll **cruza los Steps vacíos** y se corta al cerrar la vuelta.
3. **Ramp arriba y abajo:** con `+100` las repeticiones suben hacia 127; con
   `-100` bajan y **no se apagan** — si alguna desaparece, la rampa está llegando
   a 0 y eso es un fallo.
4. **Pace a los dos lados:** positivo frena la tirada, negativo la acelera. Con
   Pace alto salen **menos repeticiones de las pedidas**, y es deliberado: el
   corte llega antes.

- [ ] Resultado:

### 4. Al oído, lo que no se puede medir (NFR6)

Es el punto por el que existe este documento.

1. **Que no se arrastre.** `Repeats 8`, `Time 1/128`, y **varios Tracks a la
   vez** — es el peor caso que el diseño admite. Si el conjunto pierde el pulso o
   la tirada llega tarde, se anota aquí con el número de Tracks sonando.
2. **Que el swing la lleve entera.** Con `Timing` al 66% la tirada tiene que
   viajar pegada a su golpe, sin que las repeticiones se queden en la rejilla
   recta.
3. **Que Delay la mueva entera**, igual.
4. **Que Sustain no deje notas colgadas.** `Sustain` al 200% con `Repeats 4`: las
   repeticiones se solapan a propósito —Choke y Tail quedaron fuera— pero **nada
   debe quedarse sonando** al parar el transporte.

- [ ] Resultado:

### 5. Probability sobre todas las notas

1. `Probability 50%` con `Repeats 4`.
2. La textura queda **agujereada**: unas repeticiones suenan y otras no.
3. **No** desaparecen tiradas enteras: un golpe callado conserva sus
   repeticiones.
4. Pulsar Play dos veces reproduce **las mismas omisiones**.

- [ ] Resultado:

### 6. Temp y Ctrl All

1. Mantener **[step 13]** y girar `Repeats`: el fill sube en los Cycles activos
   del Track seleccionado y **soltar lo devuelve**.
2. Mantener **[step 14]** y girar `Repeats`: suben **los doce Tracks** a la vez y
   soltar devuelve la base de cada uno.
3. Girar contra el tope con Ctrl All puesto y soltar: **tiene que volver la base
   exacta**, no un valor topado.

- [ ] Resultado:

### 7. La pantalla

1. Card `shape` en **dos líneas**, con los ocho valores al mismo tamaño que los
   de `groove`, legibles **a un metro**.
2. Card `tonal` en **una fila**: `scale`, `root` y las celdas del pool. Con las
   ocho alturas dentro sigue cabiendo.
3. La tira de **Cycles sale entera**, con sus dos renglones de 01 a 16.
4. **El anillo no dibuja las repeticiones**, solo los Pulses. Es deliberado.

- [ ] Resultado:

### 8. Persistencia de los cuatro

1. Mover los cuatro, `Save Bank`, `Reload`: vuelven como se dejaron.
2. Cambiar de Bank y volver: los cuatro del Bank son los suyos.

> **Ojo con el defecto abierto.** `ControlInput` no adopta el Pattern del Bank
> nuevo, así que **el primer giro de knob después de cambiar de Bank republica el
> Pattern anterior entero**. Tiene track propio en `conductor/tracks.md` y no es
> de esta rebanada. Si aparece aquí, es ése.

- [ ] Resultado:

## Sin medición de jitter

Por la suspensión del 2026-09-02, y **este es el segundo cambio desde entonces
que toca la rejilla temporal**. La nota fechada está en `product.md`, en *Success
Criteria*. El coste queda escrito allí: sin arnés no hay número que diga cuánto
se ensancha la cola con 108 eventos por Step, y es también por qué el tope de
Repeats se quedó en 8 y no en los 48 de la Pre Spec.

## Lo que no cumplió

_(Se rellena al hacer la verificación. Si algo falla, va aquí — el guion no se
cierra en verde por omisión.)_
