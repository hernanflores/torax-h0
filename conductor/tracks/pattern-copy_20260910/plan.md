# Plan — Copiar Patterns: acorde en directo y portapapeles

Sigue el `workflow.md`: tests antes de implementación, un commit por tarea, git
note por commit y checkpoint verificado al cerrar cada fase.

**De dentro afuera, y lo testeable primero.** Las dos piezas que deciden algo
—el origen explícito en el motor y la regla del acorde— viven en `Engine`, se
prueban sin UIKit y no dependen de ninguna decisión de interacción. Van delante.
La capa de toques es la única parte que no se puede probar en CI, y llega cuando
todo lo que puede estar probado ya lo está.

**Cada fase deja el producto mejor que como lo encontró.** Al cerrar la Fase 3 el
defecto reportado **ya está arreglado**: con el transporte parado se copia y se
pega de verdad, entre huecos y entre Banks. Si las fases 4 y 5 no llegaran a
existir, lo entregado sirve y nada quedó a medias.

**Sin medición de jitter** (NFR4): no mueve ningún instante y no toca el hilo del
scheduler.

**El riesgo está localizado en la Fase 4.** Dos `Button` hermanos de SwiftUI no
ven toques simultáneos, así que la rejilla pasa a resolver los toques ella misma
sobre `UIViewRepresentable`. Es la fase que puede sorprender, y por eso va sola y
con la verificación en dispositivo detrás.

## FASE 1: EL MOTOR APRENDE UN ORIGEN [checkpoint: 3512343]

- [x] Task: Tests de `Project.copyingPattern(from:to:)` — `2ea61d4`
  - [x] Copia con origen distinto del seleccionado, dentro del Bank vigente.
  - [x] Opera sobre el Bank seleccionado, no sobre el primero.
  - [x] Origen o destino fuera de rango devuelven el `Project` intacto.
  - [x] `from == to` devuelve el `Project` intacto — el caso que el defecto
        disparaba, ahora escrito y esperado.
  - [x] No mueve la selección ni los ajustes de sesión.
- [x] Task: Implementar `Project.copyingPattern(from:to:)` — `27ce70c`
  - [x] Sobre `Bank.copyingPattern(from:to:)`, que ya existe.
- [x] Task: Tests de escribir un Pattern suelto en un hueco — `b17bfa3`
  - [x] Un `Pattern` cualquiera entra en el hueco indicado del Bank vigente.
  - [x] Fuera de rango, `Project` intacto.
  - [x] Es lo que el pegado entre Banks necesita y `copyingSelectedPattern(to:)`
        no puede expresar (FR22).
- [x] Task: Implementar la escritura de un Pattern suelto — `68218df`
- [x] Task: Retirar `copyingSelectedPattern(to:)` (FR23) — `3512343`
  - [x] Sin llamadores en `App` al terminar la Fase 3; aquí se decide si se retira
        o se reescribe sobre `copyingPattern(from:to:)`. **Decidido: se reescribe
        aquí como envoltorio y se retira en la Fase 3**, cuando `copy` y `paste`
        sustituyan al llamador de `TransportModel`.
  - [x] Adaptar `PatternCopyTests`, conservando lo que prueban.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)
  - [x] Suite de `Engine` en verde y cobertura ≥90%. **899 tests, 0 fallos;
        cobertura 98,67%.**

## FASE 2: LA REGLA DEL ACORDE, EN `Engine` [checkpoint: e175bc4]

- [x] Task: Tests de la máquina de estados del acorde (FR16, FR17) — `9f26047`
  - [x] `down(A)` solo: sin efecto. `up(A)`: selecciona A.
  - [x] `down(A)`, `down(B)`: copia A → B en el segundo `down`.
  - [x] Levantar A primero y B primero dan el mismo resultado: **nada**.
  - [x] Un tercer `down` con dos dedos abajo se ignora.
  - [x] `down(A)`, `down(A)`: no copia sobre sí mismo.
  - [x] Después de un acorde, el primer `down` siguiente vuelve a empezar limpio.
  - [x] Un toque cancelado no selecciona (FR21).
- [x] Task: Implementar el valor de la regla — `e175bc4`
  - [x] Entradas `pressing(_:)` / `releasing(_:)`; salidas `.none`,
        `.select(Int)`, `.copy(from:to:)`. Con `cancelling(_:)` además, que FR21
        necesita y las entradas del plan no nombraban.
  - [x] Sin `import UIKit` ni `SwiftUI`: es una regla, y por eso se puede probar
        (NFR1).
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)
  - [x] Suite de `Engine` en verde y cobertura ≥90%. **911 tests, 0 fallos;
        cobertura 98,70%, y `PatternChord` al 100%.**

## FASE 3: PORTAPAPELES, `copy` Y `paste` — **cierra el defecto reportado** [checkpoint: e9790b7]

- [x] Task: El portapapeles en `TransportModel` (FR1–FR4) — `ca86e18`
  - [x] Guarda el `Pattern` entero, más el Bank y el hueco de origen para la
        marca. En `PatternClipboard`, dentro de `Engine`: la marca y el destino
        del pegado son reglas, y `App` no se mide.
  - [x] Empieza vacío; de memoria, sin tocar `Persistence` (NFR5).
- [x] Task: `copy` (FR5, FR6) — `e9790b7`
  - [x] Carga el hueco vigente del Bank vigente.
  - [x] Toma el material **guardado en el Bank**, no la superposición de un gesto
        en curso.
  - [x] Disponible con el transporte parado y corriendo.
- [x] Task: `paste` (FR7–FR11) — `e9790b7`
  - [x] Destino: parado, el seleccionado; corriendo, el armado si lo hay y si no
        el que suena.
  - [x] Escribe en el Bank vigente, venga el material del Bank que venga.
  - [x] No mueve la selección, no arma, no toca el transporte ni
        `pendingAdoption`.
  - [x] Dispara el autosave del Bank vigente.
- [x] Task: Sustituir `copy here` por `copy` y `paste` en `PatternGrid` — `e9790b7`
  - [x] `paste` deshabilitado con el portapapeles vacío.
  - [x] `clear` se queda como está (fuera de alcance).

  **Las tres tareas van en un commit**, a propósito: quitar `copy here` y añadir
  `copy` y `paste` es el mismo cambio de firma de `PatternGrid`, y separarlas
  dejaría un commit que no compila. Ahí se retira además
  `copyingSelectedPattern(to:)` (FR23), que era la decisión que la Fase 1 dejó
  aplazada.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)
  - [x] **Comprobación del defecto original**: parado, `copy` en un hueco y
        `paste` en otro cambian el contenido de verdad — lo que `copy here` nunca
        hizo. **Verificado: el hueco 09, vacío, pasa a `ready`.**
  - [x] Y entre Banks, que es lo que el portapapeles añade. **Verificado del
        Bank 1 al Bank 5.**

## FASE 4: LA CAPA DE TOQUES — el riesgo del track [checkpoint: d3952d3]

- [x] Task: Resolver los toques de la rejilla con `UIViewRepresentable` — `32f2849`
  - [x] `touchesBegan/Ended/Cancelled` sobre la rejilla entera; punto → índice de
        celda. **Las celdas dicen dónde quedaron** por una preference key, en vez
        de deducir la rejilla de su espaciado.
  - [x] Los `Button` por celda desaparecen; el resaltado de pulsación se conserva
        a mano, con `Brutalist.pressedOpacity`.
  - [x] La accesibilidad de cada celda no se pierde al dejar de ser `Button`.
- [x] Task: Enchufar la regla de la Fase 2 — `d3952d3`
  - [x] El acorde **solo con el transporte corriendo** (FR15). Parado, cada toque
        selecciona en el `up`, como hoy.
  - [x] `.select` llama a `selectPattern(_:)`; `.copy` copia y **carga el
        portapapeles** (FR19).
  - [x] El acorde no arma, no mueve selección, no toca transporte ni
        `pendingAdoption` (FR18).
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)
  - [x] En iPad, con el transporte corriendo: el acorde copia y **sigue sonando
        el mismo Pattern**, en los dos órdenes de levantada. **Verificado.**
  - [x] Un toque sencillo sigue armando, con su cuenta atrás. **Verificado**, y
        también que el acorde no arma nada.

## FASE 5: LO QUE SE VE [checkpoint: 7e01bd3]

- [x] Task: Marca de la celda de origen (FR12) — `7e01bd3`
  - [x] Visible desde `copy` hasta que el portapapeles se sustituye.
  - [x] Solo en el Bank de origen; en otro Bank no se dibuja nada.
  - [x] Distinguible de `playing`, `queued` y del seleccionado, que ya se reparten
        el borde: **es un bloque en la esquina, no un cuarto borde.**
- [x] Task: Destello de la celda de destino (FR13, FR14) — `7e01bd3`
  - [x] Al pegar y al copiar por acorde, tuviera material o no.
  - [x] Dentro del lenguaje de `Brutalist`/`ShapeTheme`, sin animación nueva
        colgada del reloj.

  **Las dos van en un commit**: comparten el cuerpo de la celda y las constantes
  nuevas, y ninguna compila sin el cableado de la otra.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)
  - [x] Las dos señales se leen a un metro, que es la distancia de la pantalla.
        **Verificado.**

## FASE 6: DISPOSITIVO Y CIERRE

- [~] Task: Verificación en dispositivo (NFR6)
  - [ ] **Parada el 2026-09-10 por lo que encontró.** Ver *FASE 7*; se retoma con
        las correcciones dentro.
  - [ ] Los trece criterios de aceptación del `spec.md`, con el iPad delante.
  - [ ] Incluye pegar encima del que suena sin que el audio se corte.
  - [ ] Escribir `device-verification.md` con lo observado, no con lo esperado.
- [ ] Task: Cobertura y suite completa
  - [ ] `Engine` ≥90%. `MIDI` no debería moverse; comprobarlo.
  - [ ] `MIDI` se corre con la partición de CI, por el flake conocido de
        `VirtualLoopbackTests`.
- [ ] Task: Cerrar el defecto en el registro
  - [ ] Entrada en `tracks.md` con lo que entregó y lo que dejó fuera.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 7: CORRECCIONES DE LA VERIFICACIÓN EN DISPOSITIVO

**La encontró la Fase 6, con el iPad delante**, y es lo que la verificación en
dispositivo existe para encontrar. El criterio 8 copió bien pero **el material
pegado no sonaba** hasta volver a disparar el Pattern a mano.

**El síntoma tenía una mitad que no se ve, y es peor.** `TransportModel` guarda
una copia viva del Pattern cargado, `pattern`, que es la que la pantalla `track`
edita y la que `recordEdit()` vuelca al Bank en cada edición. `pastePattern()`
escribía en el `Project` y no la refrescaba, así que:

- Cuando el compás entra, `applyPendingAdoption` deja en `pattern` el material
  **anterior al pegado** y mueve la selección al hueco pegado. **El primer giro
  de knob lo escribe encima de lo pegado**, que se pierde sin aviso.
- Y no es solo el caso armado: parado, pegar en el hueco seleccionado deja la
  pantalla `track` enseñando lo viejo, con la misma pérdida al primer knob. El
  criterio 5 pasó porque solo se miró la rejilla, que lee el Bank.

**El `spec.md` no lo previó.** FR10 prohíbe armar y mover la selección; refrescar
la copia viva no es ninguna de las dos, y rearmar **el mismo hueco** con el
material nuevo tampoco arma uno distinto. Decidido con el usuario el 2026-09-10:
se arreglan las dos mitades.

- [x] Task: Tests de la decisión de refresco, en `Engine` — `35d6458`
  - [x] Qué hay que refrescar al pegar: nada, la copia viva, o la copia viva y
        lo armado.
  - [x] Depende de si el destino es el hueco cargado y de si es el armado.
- [x] Task: Pegar refresca la copia viva y lo armado — `d809ec9`
  - [x] Destino igual al hueco cargado: `pattern` y `ControlInput` adoptan lo
        pegado.
  - [x] Destino igual al hueco armado: se rearma **ese mismo** hueco con el
        material nuevo, y la adopción pendiente guarda el nuevo.
  - [x] Sigue sin mover la selección y sin armar un hueco distinto (FR10).
- [x] Task: Enmendar el `spec.md` con lo que la verificación enseñó — `13bf4ad`
  - [x] FR11b, el criterio 8 ampliado, y una sección con lo que la pasada en
        dispositivo enseñó sobre el método.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
  - [ ] Corriendo: armar el 09, pegar, y **al límite de compás suena lo pegado**.
  - [ ] Después de eso, girar un knob **no devuelve el material viejo**.
  - [ ] Parado: pegar en el seleccionado y ver la pantalla `track` con lo pegado.
