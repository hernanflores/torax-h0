# Verificación en dispositivo — La Division no mueve la rejilla mientras suena

**2026-09-11.** iPad con BeatStep Pro conectado. Encoders en `Relative #2`.

**Por qué este documento existe.** El defecto se reportó de oído, sobre una
pista rítmica de one-shots, y **sin medición de jitter** (NFR4) el oído es la
única prueba de timing que queda. Lo que hay abajo es lo observado fase a fase,
no lo esperado, y por eso incluye lo que falló. Donde el usuario respondió solo
«ok», se registra así, sin atribuirle más detalle del que dio.

## Los catorce criterios de aceptación

| # | Criterio | Qué pasó | Fase |
|---|---|---|---|
| 1 | Girar Division de 1/16 a 1/8 dobla el tiempo entre Steps, y a 1/32 lo divide | Correcto en iPad | 2 |
| 2 | El cambio no reinicia nada: mismo índice de Step, misma vuelta, mismo cursor de Cycles | Correcto en iPad: no salta al principio del anillo | 2 |
| 3 | El Step que abre la rejilla nueva conserva su instante: ninguno repetido, perdido ni en el pasado | Correcto en iPad, sin notas repetidas ni perdidas en el corte | 2, 3 |
| 4 | Sin deriva tras N cambios seguidos | Por tests: `AnchoredTimelineTests` | 1 |
| 5 | Dos Cycles de Divisions distintas cambian de rejilla en el límite de vuelta | Correcto en iPad: 1/16 ↔ 1/8 y 1/16 ↔ 1/32 | 3 |
| 6 | Los otros Tracks no se enteran | Correcto en iPad: girar un Track no mueve los demás anillos | 5 |
| 7 | Repeats: ninguna repetición pisa el Pulse siguiente ni se descarta una que cabía | «ok» | 4 |
| 8 | Sustain 100% legato exacto; 200% liga con la siguiente | «ok» | 4 |
| 9 | Delay negativo: ningún evento para un instante pasado | **Fallaba, lo destapó un test.** Arreglado en `bdcd478`; «ok» | 4 |
| 10 | El anillo marca el Step que suena y un Track que no giró se dibuja como antes | **Falló el caso con Delay −100%.** Ver abajo | 5 |
| 11 | Temp y Ctrl All sobre Division suenan y vuelven sin perder ni repetir | «ok» | 6 |
| 12 | La vía del arnés sigue construyendo su rejilla fija | Por tests: `JitterHarnessTests` y `testTheMeasurementPathNeverRebases` | 7 |
| 13 | `MIDI` ≥80%, `Engine` ≥90%, suite en verde | `Engine` 945 tests, 98,74%. `MIDI` 944 tests, 92,00%; los 7 fallos son el flake conocido de `VirtualLoopbackTests` | 7 |
| 14 | Pista rítmica de one-shots, un solo Cycle: la línea cambia de velocidad, audible e inmediata | Correcto en iPad. Es el caso del reporte | 2 |

## El criterio 9, que destapó un test

No lo encontró el iPad, sino `DelayBudgetDivisionTests`. Con Delay negativo, una
Division más lenta hace crecer el presupuesto de adelanto, y el Step del corte
se pedía tarde: hasta 110 ms con −100%. El usuario decidió arreglarlo en el
track. Desde entonces el ancla se retrasa lo que crece el presupuesto, y el
Step del corte suena cuando sonaba. Es la enmienda de FR17 en el `spec.md`.

## El criterio 10, que falló en el iPad

**Lo observado:** con Delay −100% y una Division más lenta, el playhead de ese
Track se desfasaba. Los otros tres casos de la fase —sin Delay, varios Tracks,
dos Cycles— dieron bien.

**Diagnóstico**, con una simulación a 120 BPM de 1/16 a 1/8. Eran dos efectos:

1. **Un salto atrás, de este track.** El anillo cambiaba a la rejilla nueva en
   el ancla, pero el ancla retrasada del criterio 9 ya no coincide con el
   instante del corte. Mientras tanto la rejilla vieja seguía contando: 9,2,
   9,6 y, a los 1250 ms, vuelta a 9,0. Se arregló en `b35ef92`: ahora cambia en
   el instante en que las dos rejillas marcan lo mismo, que sin Delay es el
   ancla.
2. **Un desfase constante de un Step, de la rebanada 6.** Con Delay −100% el
   anillo marca el Step anterior al que suena, antes y después de girar: es la
   decisión 9 de `mvp-groove-temporal`, «el playhead sigue la rejilla, no el
   desplazamiento». Al pasar a una Division más lenta ese Step dura más —de 125 a
   250 ms— y se nota más. **El usuario decidió mantenerlo.** Queda en *Known
   Limitations* del `spec.md`.

**Comprobado después, en el mismo iPad:** «ok».

## Escucha larga (NFR4)

**Hecha el 2026-09-11.** Es lo único que sustituye a la medición de jitter
suspendida. Lo propuesto: varios minutos de pista rítmica con cambios de
Division repetidos en los dos sentidos, algún fill de Temp y algún giro de
Ctrl All, escuchando tropiezos, golpes dobles o perdidos y deriva entre Tracks
que no se giraron.

**Lo que dijo el usuario, entero:** «Validado ok». No detalló cuánto duró ni
qué combinaciones probó, y aquí no se le atribuye más de lo que dijo.

**Lo que esto no es.** No es una medición: no hay un número de jitter para este
track, y no lo habrá — la suspensión del 2026-09-02 sigue en pie y
`workflow.md` lleva escrito el coste y la vuelta atrás. Si algún día aparece
una regresión de timing, el arnés sigue en el repositorio y la referencia
contra la que comparar es la de la rebanada 2 de la v2: máx 0,158 ms,
σ 0,013–0,014 ms.
