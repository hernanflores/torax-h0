# Verificación en dispositivo — rebanada 5

**Requiere iPad, BeatStep Pro y un sintetizador.** Los tres parámetros son
audibles y ninguna suite los puede escuchar: es el criterio de cierre del track.

Fecha de ejecución: ____________  ·  Resultado: ____________

---

## 0. Antes de empezar

- [ ] **Los encoders en `Relative #2`**, en MIDI Control Center.

  Sin eso un clic se decodifica como ±63 y **todos los parámetros saltan a su
  extremo**. Con Groove el síntoma es más engañoso que antes: Velocity salta a
  127 o a 1 y Probability a 100% o a 0%, y un Track mudo parece un fallo del
  motor cuando es configuración. Nota del 2026-08-28 en `workflow.md`.

- [ ] **Los knobs mandan los CC 70–76**, en este orden:

  | CC | Parámetro | Familia |
  |---|---|---|
  | 70 | Steps | Shape |
  | 71 | Pulses | Shape |
  | 72 | Rotate | Shape |
  | 73 | Division | Shape |
  | 74 | **Velocity** | Groove |
  | 75 | **Sustain** | Groove |
  | 76 | **Probability** | Groove |

- [ ] Compilar e instalar en el iPad: destino iPad en Xcode y Run.
  `DEVELOPMENT_TEAM` ya está fijado, no hay nada más que configurar.

- [ ] Sintetizador conectado y recibiendo en **canal 6**.

- [ ] Al menos **tres notas en el pool**, con los pads. Con una sola nota el
      arpegio no se oye y la limitación 1 tapa el resto de la verificación.

---

## 1. Velocity — CC 74

- [ ] Pulsar Play. Suena el patrón.
- [ ] Girar Velocity hacia arriba: **la dinámica crece de forma audible y
      proporcional**, sin saltos.
- [ ] Girar hacia abajo hasta el mínimo: sigue sonando, muy flojo. **No
      enmudece** — para eso está Probability.
- [ ] El valor grande aparece en **ámbar** y no en verde, y el anillo sigue
      visible debajo.
- [ ] El cambio se oye **dentro del Step siguiente** al giro.

## 2. Sustain — CC 75

- [ ] Girar hacia abajo: la línea se vuelve **percusiva**, casi de percusión.
- [ ] Volver al 100%: cada nota dura **un Step exacto** — se toca con la
      siguiente sin solaparse.
- [ ] Subir hacia el 200%: la línea **liga**. Las notas se solapan con la
      siguiente y suena legato.
- [ ] Con Division 1/32 y tempo alto sigue comportándose: al 100% no hay solape,
      por encima sí.

## 3. Probability — CC 76

- [ ] Bajar a ~50%: la línea **se perfora**. Faltan notas.
- [ ] **El arpegio conserva su fase**: las notas que sí suenan caen en la misma
      altura que tendrían al 100%. La línea no se ralentiza ni cambia de
      contorno — es la misma con huecos.
- [ ] Bajar a 0%: **silencio total**, sin notas colgadas. No es un error.
- [ ] Volver a 100%: suena todo otra vez.
- [ ] **Dos vueltas seguidas del anillo no omiten los mismos Pulses.**

## 4. La repetibilidad

- [ ] Con Probability a ~50%, parar y volver a pulsar Play.
- [ ] **La secuencia de omisiones es la misma que la vez anterior.** Es la
      promesa de `tech-stack.md` tal como quedó precisada el 2026-08-29:
      repetible por arranque, no por vuelta.

## 5. La limitación 1, provocada a propósito

- [ ] Dejar **una sola nota** en el pool y Sustain al **200%**.
- [ ] Se oye que la nota **se corta a sí misma**: el note-off de un pulso apaga
      la nota del siguiente.
- [ ] Confirmar que el síntoma es **ese** y no otro (no una nota colgada, no
      silencio, no un salto de altura). Está en el spec como limitación conocida
      y se acepta a cambio de no rastrear notas pendientes en el hilo de tiempo
      real.

## 6. Parar no deja nada sonando

- [ ] Con Sustain largo, quitar del pool la nota que está sonando y **parar**.
- [ ] **No queda ninguna nota colgada.** Es el All Notes Off que se añadió en la
      Fase 3 junto al barrido del pool.

## 7. Lo entregado sigue en pie

- [ ] Transporte, anillo y playhead corriendo.
- [ ] Los cuatro knobs de Shape siguen respondiendo, con valor grande **verde**.
- [ ] El pool se edita con los pads; Scale y Root se cambian tocando, con el
      transporte corriendo y sin cortarlo.
- [ ] **Sin controlador conectado:** los tres de Groove se **leen** pero no se
      editan. Scale y Root sí, que son configuración y no material generativo.

## 8. Legibilidad

- [ ] A un metro se leen el playhead, los pulsos activos y el valor grande.
- [ ] Las tres familias se distinguen por color sin leer la palabra: Shape
      verde, Groove ámbar, Tonal violeta.

---

## Qué hacer si algo falla

**Antes de tocar código**, descartar configuración: los encoders en `Relative
#2` y los CC en 70–76 explican la mayoría de los síntomas raros, y el del modo
de encoder es especialmente engañoso porque Rotate parece funcionar —envuelve
módulo Steps en vez de acotar— y hace de mal testigo.

Si el fallo es real, anotarlo aquí con el síntoma exacto y el parámetro, y
volver a la fase que lo introdujo. Los checkpoints de fase están en `plan.md`
con su SHA.
