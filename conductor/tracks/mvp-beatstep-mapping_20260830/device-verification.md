# Verificación en dispositivo — rebanada 7

**2026-08-31.** iPad con el BeatStep Pro y el preset cargado, contra destino MIDI
real. Es el criterio de cierre del track (NFR4): los números del preset no valen
hasta verse llegar.

## Resultado

**Los cuarenta y ocho controles coinciden con la tabla.** Ninguna discrepancia,
así que no hubo nada que reconciliar — y se registra como resultado, no como
silencio: la tabla se verificó y coincidió.

| Qué se comprobó | Resultado |
|---|---|
| Los dieciséis pads, uno a uno, contra la tabla de C menor | Según la tabla |
| El pad 9 exactamente doce semitonos sobre el pad 1 | Según la tabla |
| Pads 8 y 16 con notas ya en el pool: el registro se mueve, el pool no | Según la tabla |
| Los dos extremos del desplazamiento: el pad deja de responder y la pantalla lo dice | Según la tabla |
| Los nueve knobs asignados (CC 70–78) y los siete libres (CC 79–85) | Según la tabla |
| Los dieciséis step buttons: sin efecto visible, sin romper nada | Según la tabla |
| Con `pentatonic`: los pads 6, 7, 14 y 15 no hacen nada | Según la tabla |

## El preset exportado

`preset/Torax.beatsteppro`, exportado desde MIDI Control Center contra el
controlador ya configurado. Es el archivo cargable que faltaba, y su contenido se
comprobó contra las tablas declaradas:

- **Dieciséis encoders** en CC **70–85**, todos en modo relativo.
- **Dieciséis step buttons** en CC **102–117**.
- **Dieciséis pads** en las notas **36–51**.

Coincide con `ControlMapping` y con `preset/README.md`. La nota de riesgo 1 del
plan —«el número del bloque de pads es una suposición hasta la fase 5»— queda
cerrada: la suposición era correcta y ningún test tuvo que cambiar de número.

## Lo que no se midió, y por qué

**Jitter.** La rebanada no mueve ningún instante: no toca `MusicalTimeline`,
`LookAheadScheduler` ni `SchedulerThread`, y no añade carga visual al ritmo del
reloj (NFR3). Es el caso que exime la nota del 2026-08-28 de `workflow.md`. La
medición final de v1 va con la rebanada 8.
