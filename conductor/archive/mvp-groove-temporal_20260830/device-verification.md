# Verificación en dispositivo — MVP rebanada 6: Groove temporal

**Requiere iPad, BeatStep Pro y un sintetizador.** Es la fase que decide si la
rebanada entra: `workflow.md` nombra explícitamente a Timing y Delay entre lo que
exige medir, y una regresión bloquea la tarea.

Se ejecuta en orden. Los bloques 1 y 2 son configuración; el 3 y el 4, las dos
mediciones; del 5 al 8, la escucha. Cada bloque dice qué se espera **y qué
significa si sale distinto**, para no tener que decidirlo en caliente.

---

## 0. Antes de empezar — lo que explica la mayoría de los síntomas raros

- [ ] **Los encoders del BeatStep Pro en `Relative #2`.** Se configura en MIDI
      Control Center. Sin eso, un clic se decodifica como ±63 y **todos los
      parámetros saltan a su extremo**: Timing se clava en 50 o 75 y Delay en
      ±100. Nota del 2026-08-28 en `workflow.md`.
- [ ] **El sintetizador conectado y sonando** con lo entregado hasta la rebanada
      5. Si algo no suena antes de tocar Timing, no es la rebanada 6.
- [ ] **Los CC nuevos:** Timing es el **77** y Delay el **78**. Los siete
      anteriores no se movieron de sitio.

---

## 1. La app arranca y lee los nueve

- [ ] La pantalla muestra tres renglones de parámetros: Shape en verde, y Groove
      en ámbar partido en dos —`Velocity · Sustain · Probability` y
      `Timing · Delay`—.
- [ ] Los valores de partida son `Timing 50%` y `Delay 0%`: la rejilla recta.
- [ ] Con el controlador desconectado se leen pero no se editan; Scale y Root sí,
      que son configuración.

---

## 2. Medición recta — la regresión y la atribución

> **Es la más importante de las dos, y no mide esta rebanada: mide las tres
> anteriores.** La σ viene subiendo de forma monótona —9 → 15 → 20 µs— y las
> rebanadas 4 y 5 no midieron. Si sale en línea, quedan absueltas sin bisecar.

- [ ] En la sección **Jitter**, dejar la rejilla en **`Recta`** y los eventos en
      **1000**.
- [ ] Pulsar **Medir** y esperar (~8 minutos: son tres tempos).
- [ ] Recoger `Documents/jitter-report-recta.txt`.

**Se compara contra la referencia de la rebanada 3: máx 0,134 ms · σ 0,020 ms.**

| Resultado | Qué significa |
|---|---|
| σ ≈ 20 µs, máx ≈ 0,13 ms | En línea. Las rebanadas 4 y 5 quedan absueltas y la 6 no rompió la rejilla. |
| σ claramente peor | **No apunta necesariamente a esta rebanada**: el intervalo sin medir incluye la 4 y la 5. Se bisecta con el arnés, que sigue ahí. |
| Umbral superado (máx ≥ 2 ms o σ ≥ 0,5 ms) | Bloquea la tarea. No se sigue a la medición desplazada. |

- [ ] El número se anota en la git note de la tarea. **Un número, no una
      impresión.**

---

## 3. Medición desplazada — lo que esta rebanada tiene que demostrar

> Que un instante **desplazado** se entrega donde se pidió, y no donde caía la
> rejilla. El arnés compara lo pedido contra lo entregado, así que mide el
> desplazamiento sin saber que existe.

Tres pasadas más, con **1000 eventos** cada una:

- [ ] Rejilla **`Timing 67%`** → `jitter-report-timing-67.txt`
- [ ] Rejilla **`Delay +50%`** → `jitter-report-delay-mas-50.txt`
- [ ] Rejilla **`Delay −50%`** → `jitter-report-delay-menos-50.txt`

**El criterio es que la desviación esté en el mismo orden que la recta.** No se
compara contra la rejilla: se compara contra lo pedido, y lo pedido ya lleva el
desplazamiento dentro.

| Resultado | Qué significa |
|---|---|
| Las tres en el orden de la recta | La rebanada cumple su criterio principal. |
| Solo `Delay −50%` peor | Apunta al presupuesto de adelanto: el origen o el horizonte. Es el único caso que los ejercita. |
| Las tres peor, con la recta limpia | Apunta a la aritmética del desplazamiento, no a la rejilla. |

- [ ] `Delay −50%` verifica en dispositivo lo que la Fase 3 verifica en test:
      **ningún evento se pide para un instante que ya pasó**. Si los primeros
      eventos salieran amontonados, el síntoma sería una ráfaga al pulsar Play.
- [ ] Los cuatro números se anotan en la git note.

---

## 4. Timing al oído — el swing

Con el transporte corriendo, un pool de 2–3 notas y Division 1/16:

- [ ] **Al 50% la línea es recta.** Punto de partida.
- [ ] **Subir el knob 77 mete swing de forma progresiva**, sin saltos de valor y
      audible dentro del Step siguiente al giro.
- [ ] **Al 67% el tresillo es reconocible.** Es el objetivo del rango; el valor
      exacto (66,67%) cae entre dos posiciones del knob y la diferencia es de
      0,8 ms — si se nota algo raro ahí, no es esto.
- [ ] **Al 75% es el extremo y sigue sonando ordenado**: las notas impares caen
      justo antes de las pares, nunca después. Si se oyera un desorden o un
      doblete, el tope está mal elegido y es un defecto de la rebanada.
- [ ] **Los Steps pares no se mueven.** Se oye como un vaivén, no como un
      arrastre general.

---

## 5. Delay al oído — la voz entera

- [ ] **Girar el knob 78 hacia arriba arrastra la voz** respecto al pulso, de
      forma audible y proporcional.
- [ ] **Hacia abajo la empuja por delante.** Contra un metrónomo externo o el
      propio BeatStep Pro se oye claramente adelantada.
- [ ] **El paso por el 0% no engancha:** el knob lo cruza como cualquier otro
      valor.
- [ ] **Los dos a la vez se suman**: con swing y Delay, el vaivén sigue ahí,
      desplazado en bloque.

---

## 6. Las dos limitaciones, provocadas a propósito

> Se provocan para confirmar que el síntoma observado es el previsto y no otro.
> Ver *Known Limitations* en `spec.md`.

- [ ] **Limitación 1 — Delay −100% retrasa el arranque.** Con Division lenta
      (1/4 o 1/2) y Delay al −100%, pulsar Play tarda **un Step entero** en
      sonar. Es proporcionado y es el precio literal de lo que se pidió. Lo que
      **no** debe pasar: que suene una ráfaga de notas amontonadas al arrancar.
- [ ] **Limitación 2 — bajar Delay a negativo mientras suena.** Girar el knob 78
      de 0 hacia abajo con el transporte corriendo produce **un salto de una
      ventana**, una sola vez. Subirlo no tiene el problema. Lo que **no** debe
      pasar: que el salto se repita en cada vuelta del anillo.
- [ ] **Limitación 3 — el solape de Sustain empeora con Timing.** Con pool de una
      nota, Sustain alto y swing alto, la línea se corta antes que sin swing. Es
      el mismo defecto que documentó la rebanada 5 con otro umbral, no uno nuevo.

---

## 7. El playhead sigue la rejilla

- [ ] **Con Timing al 75%, el playhead avanza regular.** La pantalla es el reloj;
      el oído es el groove. Si el anillo se moviera desigual, es que la
      aritmética del desplazamiento se coló en el camino de dibujo, y eso exige
      una medición de jitter más (`workflow.md`).

---

## 8. Lo entregado sigue en pie

- [ ] Transporte, anillo, playhead y valor grande transitorio.
- [ ] Pool tonal, Scale y Root.
- [ ] Velocity, Sustain y Probability, con su comportamiento de la rebanada 5.
- [ ] Selección de dispositivo y el estado de solo lectura sin controlador.
- [ ] Girar Timing o Delay **no toca** el Shape, el pool ni el resto del Groove.

---

## Cierre

- [ ] Cobertura: `Engine` ≥90% y `MIDI` ≥80%. `MIDI` en un solo proceso,
      filtrando `Engine/Sources`, y **fusionando el `.profdata` a mano** — ver la
      ampliación del 2026-08-30 en `workflow.md`.
- [ ] Si la CI falla con `clientCreationFailed(-50)`, comparar 3–4 pasadas contra
      `main` antes de atribuirlo al cambio. En esta rama, **en un solo proceso el
      fallo es determinista** y está documentado: la CI corre con la partición y
      pasa entera.
