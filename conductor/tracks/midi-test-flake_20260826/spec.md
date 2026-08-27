# Spec — Flake `clientCreationFailed(-50)` en MIDITests

**Track ID:** `midi-test-flake_20260826`
**Track type:** Bug
**Status:** en espera de `scheduler-lifecycle_20260826`

## Overview

`swift test --package-path Packages/MIDI` falla de forma intermitente con `clientCreationFailed(-50)` — `paramErr` de `MIDIClientCreateWithBlock`. Medido sobre `main` limpio el 2026-08-26: **~1 de cada 12 pasadas**.

El patrón: una vez que aparece, **todas** las creaciones de cliente posteriores del proceso también fallan. Empieza en `JitterHarnessTests` o en `VirtualLoopbackTests` según la pasada; cuando golpea temprano el fallo se propaga más y la suite termina en ~5 s en vez de ~24 s. No son dos modos distintos: es el mismo fallo golpeando antes o después.

Con la CI ya reparada y todo el trabajo entrando por Pull Request, esto pone PRs en rojo sin culpa del cambio bajo revisión — que es el coste real y la razón de arreglarlo.

### Por qué está en espera

`scheduler-lifecycle_20260826` introduce un cierre explícito y ordenado de los recursos de CoreMIDI en el arnés. Es plausible que comparta causa con este flake: hoy el desmontaje ocurre en `deinit`, en el instante en que ARC decida liberar, potencialmente con entregas en vuelo. **Este track no arranca hasta que aquel cierre esté en `main`.** Entonces se vuelve a medir y la respuesta decide su forma:

- **Si el flake desapareció:** el track se reduce a verificarlo con rigor y documentar la causa.
- **Si sigue:** arranca el diagnóstico con una hipótesis ya descartada y el terreno acotado.

### Lo que ya se descartó

- **No es un límite de clientes CoreMIDI por proceso.** Una sonda aislada crea 200 clientes seguidos sin un solo fallo.
- **No lo introduce ningún cambio del track `timing-spike`.** `main` limpio lo reproduce.
- **No es `Thread.isFinished`.** Sustituir esa espera por una bandera atómica propia no cambió nada.

## Functional Requirements

### FR1 — Re-medición de partida

Con el cierre explícito ya en `main`, medir la tasa de `-50` con el mismo protocolo que la referencia: pasadas consecutivas de la suite completa, contando fallos. Sin este número el track no puede afirmar nada.

### FR2 — Causa raíz documentada

Explicar el fallo con evidencia: qué recurso de CoreMIDI se agota o se corrompe, y en qué momento. Si el cierre explícito lo resolvió, la explicación es igualmente obligatoria — «desapareció» no es una causa.

### FR3 — Arreglo, si hace falta

Si el flake persiste, corregirlo. La forma del arreglo la decide el diagnóstico de FR2, no se prejuzga aquí.

## Non-Functional Requirements

- **NFR1 — Sin ocultar el síntoma.** Reintentar, silenciar o saltar el test que falla no es un arreglo. Si la conclusión fuese que hay que aislar los tests que tocan CoreMIDI, debe justificarse con la causa raíz en la mano, no adoptarse para poner la CI en verde.
- **NFR2 — Cobertura de `MIDI` ≥80%,** según `workflow.md`.

## Acceptance Criteria

- [ ] **20+ pasadas consecutivas de la suite `MIDI` sin un solo `-50`.** El número no es arbitrario: con una tasa de ~1 entre 12, menos de 20 pasadas no distingue un arreglo de la suerte.
- [ ] La causa raíz queda documentada con evidencia, en el track y en `tech-stack.md` si afecta a una decisión de arquitectura.
- [ ] `swift test` sobre `Engine` y `MIDI` pasa sin simulador ni hardware.

## Known Limitations

1. **Medido solo en macOS.** El arnés corre en host; el comportamiento de CoreMIDI en iPadOS puede ser otro. Este track no lo cubre.
2. **Una tasa baja se mide mal.** Incluso 20 pasadas limpias dejan margen para un flake mucho más raro. El criterio acota el riesgo, no lo elimina.

## Out of Scope

- La carrera de `start()`/`stop()` del scheduler — es `scheduler-lifecycle_20260826`.
- Cualquier cambio en el cálculo de timestamps o en la matemática de la ventana.
