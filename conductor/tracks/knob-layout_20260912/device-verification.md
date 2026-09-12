# Verificación en dispositivo — Reordenar los knobs del preset del BeatStep Pro

**Fecha:** 2026-09-12
**Dispositivo:** iPad (modelo no anotado)
**Hardware:** iPad + Arturia BeatStep Pro
**Resultado:** **OK** en la segunda pasada, confirmado por el usuario. La primera
pasada **falló**, y es lo mejor que trae este documento.

## Lo que encontró la primera pasada

**El bloque de CC no sigue al orden físico de los encoders.** La rebanada entera
se planificó suponiendo que el encoder N manda el CC 69+N, y por tanto que la
fila de arriba del controlador es el CC 70–77. Es falso. `Torax.beatsteppro`
asigna:

| controlId | Fila | CC |
|---|---|---|
| 32–39 | arriba | **78–85** |
| 40–47 | abajo | **70–77** |

La primera pasada movió el knob del Cycle en edición al CC 85 creyendo que era la
esquina inferior derecha. Es el knob 8: arriba a la derecha.

**Cómo se detectó.** Los cinco primeros pasos del guion fallaron con un patrón
que no era ruido:

| Paso | Se esperaba | Se obtuvo | CC real |
|---|---|---|---|
| Girar el knob 16 | Cycle en edición | Timing | 77 |
| Girar el knob 13 | nada | Velocity | 74 |
| Girar el knob 14 | nada | Sustain | 75 |
| Girar el knob 15 | nada | Delay | 76 |
| Temp + knob 16 | nada | Timing | 77 |

Cuatro knobs consecutivos devolviendo cuatro CC consecutivos es un
desplazamiento, no un fallo de lógica. Los knobs 13–16 mandaban los CC 74–77, de
donde sale que la fila de abajo empieza en el 70.

**Se confirmó contra el archivo del controlador** —el único sitio donde esto está
escrito— y después en el aparato: girar el knob de arriba a la izquierda mueve
Probability, que es el CC 78.

**Por qué la app no lo delataba.** Nada estaba roto: el mapeo hacía exactamente
lo que decía, y todos los tests pasaban. El error vivía en la traducción entre el
número de CC y el knob que se toca con el dedo, que es justo lo que ningún test
del repositorio puede ver. Es la clase de avería para la que existe este paso.

## Lo que verificó la segunda pasada

Con la tabla corregida —fila de arriba CC 78–85, fila de abajo CC 70–77—:

1. Build & Run con el BeatStep Pro conectado.
2. **Fila de arriba, de izquierda a derecha:** Steps · Pulses · Rotate ·
   Division · Repeats · Time · Ramp · Pace. Es el card Shape leído tal cual:
   primero sus cuatro de arriba, después sus cuatro de abajo.
3. **Fila de abajo, primeros cinco:** Velocity · Sustain · Probability · Timing ·
   Delay, en el orden del card Groove.
4. **Knobs 14 y 15:** no hacen nada.
5. **Knob 16**, esquina inferior derecha: mueve el cursor de Cycle en edición.
6. **Temp** (step 13) y **Ctrl All** (step 14) mantenidos + knob 16: el cursor no
   se mueve.
7. Con Temp hundido, un knob de cada fila: el valor cambia y al soltar vuelve.

**Confirmación del usuario: «OK».**

> **Lo que este documento no registra.** El usuario confirmó la segunda pasada en
> bloque, así que no hay notas por paso. Se anota tal cual en vez de inventar
> detalle: lo que vale es que ocurrió, y lo que no se escribió no se puede citar
> después. De la primera pasada sí hay detalle porque el usuario reportó paso a
> paso, y esos números son la evidencia del hallazgo.

## Sin medición de jitter

Por la suspensión del 2026-09-02, y porque este cambio no desplaza ningún
instante: cambia qué knob mueve qué parámetro, no cuándo cae un evento.
