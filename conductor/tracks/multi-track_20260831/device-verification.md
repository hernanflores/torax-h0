# Verificación en dispositivo — v2 rebanada 1: Dieciséis Tracks sobre un reloj

**Ejecutada el 2026-09-01 en iPad Air (4ª generación) con BeatStep Pro.**
**Resultado: aprobada.** Es la fase que decidía si la rebanada valía: el riesgo
que la v1 existió para acotar —el timing— se cobra aquí, con dieciséis voces
sobre un solo hilo.

---

## 1. Medición de jitter con los dieciséis sonando

Rejilla recta, 200 eventos por tempo, los tres tempos de siempre.

| Tempo | n | máx | media | σ |
|---|---|---|---|---|
| 60 BPM | 200 | 0,151 ms | +0,116 ms | 0,013 ms |
| 120 BPM | 200 | 0,144 ms | +0,105 ms | 0,015 ms |
| 174 BPM | 200 | 0,598 ms | +0,121 ms | 0,083 ms |

**VEREDICTO: CUMPLE.** Umbral máx < 2 ms y σ < 0,5 ms: el peor máximo queda 3,3
veces por debajo y la peor σ, 6 veces.

### La diferencia, explicada

El plan exige explicar la diferencia contra la referencia de la rebanada 6 —máx
0,151 ms, σ 0,009–0,013 ms— **suba o no**. Sube, y solo en un sitio.

A 60 y 120 BPM la medición es indistinguible de la referencia: el máximo de 60
BPM es idéntico —0,151 ms— y la σ se mueve dentro de los 2 µs. A **174 BPM** el
máximo se multiplica por 4 y la σ por 6,4.

**Lo que absuelve a la rebanada es que la media no se mueve.** Los tres tempos
dan entre +0,105 y +0,121 ms, el mismo desplazamiento constante de las cinco
mediciones anteriores. Si copiar dieciséis Tracks por ventana costara tiempo, el
coste sería sistemático: la media subiría y los tres tempos se degradarían a la
vez. No es lo que se ve. Lo que cambió es **la cola**, y solo en el tempo más
rápido —unos pocos eventos atrasados sobre una distribución que por lo demás
está donde estaba—.

Dicho con precisión: **esto es una lectura de los estadísticos de resumen, no una
medida de la distribución.** `writeReport()` (`App/JitterMeasurementModel.swift`)
persiste n, máximo, media y σ; las desviaciones por evento viven en
`JitterHarness.deviations()` y no se escriben. Distinguir «cuatro outliers» de
«la distribución se corrió» pide percentiles en el reporte, que no existen
todavía.

**Se cierra con esta explicación, por decisión del 2026-09-01.** El veredicto
CUMPLE con margen amplio y la media plana es evidencia suficiente para no
bloquear la rebanada. Queda anotado como lo que es: la primera cola que se
ensancha en seis mediciones, y el sitio por donde mirar si la rebanada 2 —o la 3,
con Cycles— empeora el número.

> **Nota de comparabilidad.** La referencia de la rebanada 6 usó 1000 eventos por
> tempo y ésta 200. Una muestra cinco veces menor tiende a dar un máximo *menor*,
> no mayor, así que el 0,598 ms no se explica por el tamaño de muestra — al
> contrario, lo hace más llamativo.

---

## 2. Verificación funcional

Aprobada, sin discrepancias:

- BeatStep Pro y varios instrumentos en canales distintos.
- Selección de Tracks con los step buttons, dando material a cada uno: **cada
  Track suena por su canal**.
- Dos Tracks en Divisions distintas: **se oye que están en fase**.
- Dos Tracks en tonalidades distintas: **la Scale de uno no mueve al otro** — la
  función que el marco tonal por Track existe para dar.
- `Stop` con los dieciséis sonando y con Delay positivo: **nada queda colgado**.

---

## 3. Cobertura

Medida el 2026-09-01, como dice `workflow.md`.

| Módulo | Umbral | Líneas | Regiones |
|---|---|---|---|
| `Engine` | ≥90% | **99,42%** | 97,31% |
| `MIDI` | ≥80% | **92,08%** | 87,85% |

`Engine`: 341 pruebas, ningún fallo.

`MIDI`: 330 pruebas, ningún fallo, con `VirtualLoopbackTests` excluido — **así que
el número es conservador**, la cobertura real es igual o mayor. La exclusión es
forzada, no elegida: con la suite en rojo `swift test` no fusiona el `.profdata`
y no hay cobertura que medir.

### Por qué estaba en rojo

`clientCreationFailed(-50)` en las 4 pruebas de `VirtualLoopbackTests`, ningún
otro test tocado. Es la firma de
[`midi-test-flake_20260826`](../midi-test-flake_20260826/index.md), **pero no su
tasa**: el registro dice 2 de 8 e intermitente, y el 2026-09-01 falló en 5 de 5
pasadas.

**`main` falla idéntico**, así que la rama queda absuelta por el procedimiento de
*Branching and Pull Requests* de `workflow.md`. El cambio de carácter —de
intermitente a determinista, en las dos ramas— apunta a estado de CoreMIDI en la
máquina de desarrollo y **es dato para `midi-test-flake`**, que sigue aplazado a
después de la v2.
