# Track: Rediseño de las cuatro pantallas — track, scale, midi y banks

**ID:** `screens-redesign_20260906` · **Type:** Feature · **Status:** new

La interfaz creció rebanada a rebanada y el chrome lo acusa: una sola fila arriba
mezclando pestañas, estado MIDI y transporte; pantallas con prefijo numérico
—`1 · Track`—; dos pestañas dibujadas con borde discontinuo porque no existían; y
un panel de medición de jitter que sobrevive a una medición suspendida el
2026-09-02. Este track sustituye esa capa por el rediseño del handoff: **un chrome
compartido** y **cuatro pantallas completas**.

**Es un cambio de sistema, no de estilo.** Lo que se rehace es el dibujo; el
motor, el estado y el camino de tiempo real no se tocan. Un diff de este track que
alcance `LookAheadScheduler`, `MusicalTimeline` o `SchedulerThread` es un error de
alcance, no una mejora.

**El principio rector no se mueve; el brief precisa dónde el dedo es legítimo.**
El controlador sigue siendo el instrumento y la pantalla el espejo. `track` se lee
mientras suena y ahí **no se edita ningún parámetro generativo con el dedo** —un
slider provisional para suplir un knob ausente es el antipatrón que
`product-guidelines.md` nombra—; `scale`, `midi` y `banks` se configuran antes de
tocar y ahí el dedo opera.

**Doce playheads, no uno.** El PNG dibuja una sola aguja porque su mock tiene los
doce tracks en la misma Division. Con divisiones distintas eso mentiría sobre once
de los doce, así que cada anillo lleva la suya. Es la misma clase de decisión que
el track anterior ya tomó con las proporciones del anillo: donde el handoff y el
estado real se separan, gana el estado.

**La rejilla del pool es el espejo literal de los pads del controlador.** `Engine`
ya lo tenía escrito —`padCount = 16`, `degreesPerBlock = 7`, `octaveDownIndex = 7`,
`octaveUpIndex = 15`—, así que la 4×4 son **14 pads de nota y 2 de octava**, no
dieciséis notas. Los de octava indican además en qué octava se está, información
que hoy no aparece en ninguna otra parte de la interfaz.

**`banks` es cáscara visual, y se declara.** No hay modelo de `Bank` ni
persistencia: la selección se mueve y no altera lo que suena. Enseñar la forma de
la app y decir qué está vacío es más honesto que fingir un cambio que no ocurre —
pero es una limitación conocida, no una funcionalidad.

**Dos desviaciones se documentan antes de escribir código**, por el paso 8 del
*Task Workflow*. El fondo pasa de `#211823` a `#111211`, contra un lenguaje visual
declarado cerrado el 2026-09-02 — cambia el fondo, **no los tres acentos ni el
tratamiento neo-brutalista**. Y la interfaz pasa a escribirse en minúsculas contra
el vocabulario capitalizado de la Pre Spec — cambia la caja, **no el término**:
`steps` en pantalla sigue siendo `Steps` en código, tests y documentación.

**El TDD de `workflow.md` queda casi siempre en reposo, y por su propia regla.**
`App` no se mide, y lo que ahí merece un test está en el sitio equivocado. La fase
roja solo se dispara cuando aparece lógica nueva, que baja a `Engine` con test
antes que con implementación. Cada fase lleva una tarea explícita para vigilarlo,
porque el fallo típico de un track de UI es dejar reglas sueltas dentro de una
`View`.

**Verificación por fase:** `xcodebuild` verde, captura del simulador en landscape
comparada con el PNG de la pantalla, y confirmación explícita del usuario. La
captura ocupa el sitio de la cobertura que `App` no tiene.

## Riesgo abierto que este track reabre

El mauve de Groove (`#AA6DA8`) y el violeta de Tonal (`#7C5FD9`) quedan del mismo
lado del círculo cromático, y su separación se juzgó contra el fondo violeta
oscuro. Sobre el neutro `#111211` esa comprobación no vale, y la pregunta que
`ShapeTheme.swift` dejó abierta el 2026-09-01 vuelve a estar viva: se decide con
la app en la mano, a un metro y con poca luz, no por precaución ni por deferencia
al handoff.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [Handoff de pantallas](../screen-handoff_20260901/index.md): cerró el lenguaje
    visual que este track enmienda en su fondo y en su caja.
-   [Doce Tracks, pantalla MIDI y limpieza del selector](../ui-declutter_20260902/index.md):
    de ahí salen los doce anillos y la pantalla `midi` que aquí se rehace.
-   [Feedback del controlador](../controller-feedback_20260904/index.md): la
    lectura grande y el resalte por familia que aquí pierden los tabs.
-   [Rebanada 3 de la v2 — Cycles](../cycles_20260901/index.md): el card `cycle` y
    sus dos cursores.
-   [Mute y Solo por Track](../mute-solo_20260902/index.md): la franja de doce
    tracks, y por qué un track muteado sigue girando.
-   Referencias visuales: `torax-h0-ipados-handoff/` — `coding-agent-brief.md`,
    `track.png`, `scale.png`, `midi.png`, `banks.png`.
