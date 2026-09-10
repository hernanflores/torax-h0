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

## FASE 1: EL MOTOR APRENDE UN ORIGEN

- [x] Task: Tests de `Project.copyingPattern(from:to:)` — `2ea61d4`
  - [x] Copia con origen distinto del seleccionado, dentro del Bank vigente.
  - [x] Opera sobre el Bank seleccionado, no sobre el primero.
  - [x] Origen o destino fuera de rango devuelven el `Project` intacto.
  - [x] `from == to` devuelve el `Project` intacto — el caso que el defecto
        disparaba, ahora escrito y esperado.
  - [x] No mueve la selección ni los ajustes de sesión.
- [x] Task: Implementar `Project.copyingPattern(from:to:)` — `27ce70c`
  - [x] Sobre `Bank.copyingPattern(from:to:)`, que ya existe.
- [~] Task: Tests de escribir un Pattern suelto en un hueco
  - [ ] Un `Pattern` cualquiera entra en el hueco indicado del Bank vigente.
  - [ ] Fuera de rango, `Project` intacto.
  - [ ] Es lo que el pegado entre Banks necesita y `copyingSelectedPattern(to:)`
        no puede expresar (FR22).
- [ ] Task: Implementar la escritura de un Pattern suelto
- [ ] Task: Retirar `copyingSelectedPattern(to:)` (FR23)
  - [ ] Sin llamadores en `App` al terminar la Fase 3; aquí se decide si se retira
        o se reescribe sobre `copyingPattern(from:to:)`.
  - [ ] Adaptar `PatternCopyTests`, conservando lo que prueban.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
  - [ ] Suite de `Engine` en verde y cobertura ≥90%.

## FASE 2: LA REGLA DEL ACORDE, EN `Engine`

- [ ] Task: Tests de la máquina de estados del acorde (FR16, FR17)
  - [ ] `down(A)` solo: sin efecto. `up(A)`: selecciona A.
  - [ ] `down(A)`, `down(B)`: copia A → B en el segundo `down`.
  - [ ] Levantar A primero y B primero dan el mismo resultado: **nada**.
  - [ ] Un tercer `down` con dos dedos abajo se ignora.
  - [ ] `down(A)`, `down(A)`: no copia sobre sí mismo.
  - [ ] Después de un acorde, el primer `down` siguiente vuelve a empezar limpio.
  - [ ] Un toque cancelado no selecciona (FR21).
- [ ] Task: Implementar el valor de la regla
  - [ ] Entradas `pressing(_:)` / `releasing(_:)`; salidas `.none`,
        `.select(Int)`, `.copy(from:to:)`.
  - [ ] Sin `import UIKit` ni `SwiftUI`: es una regla, y por eso se puede probar
        (NFR1).
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
  - [ ] Suite de `Engine` en verde y cobertura ≥90%.

## FASE 3: PORTAPAPELES, `copy` Y `paste` — **cierra el defecto reportado**

- [ ] Task: El portapapeles en `TransportModel` (FR1–FR4)
  - [ ] Guarda el `Pattern` entero, más el Bank y el hueco de origen para la
        marca.
  - [ ] Empieza vacío; de memoria, sin tocar `Persistence` (NFR5).
- [ ] Task: `copy` (FR5, FR6)
  - [ ] Carga el hueco vigente del Bank vigente.
  - [ ] Toma el material **guardado en el Bank**, no la superposición de un gesto
        en curso.
  - [ ] Disponible con el transporte parado y corriendo.
- [ ] Task: `paste` (FR7–FR11)
  - [ ] Destino: parado, el seleccionado; corriendo, el armado si lo hay y si no
        el que suena.
  - [ ] Escribe en el Bank vigente, venga el material del Bank que venga.
  - [ ] No mueve la selección, no arma, no toca el transporte ni
        `pendingAdoption`.
  - [ ] Dispara el autosave del Bank vigente.
- [ ] Task: Sustituir `copy here` por `copy` y `paste` en `PatternGrid`
  - [ ] `paste` deshabilitado con el portapapeles vacío.
  - [ ] `clear` se queda como está (fuera de alcance).
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
  - [ ] **Comprobación del defecto original**: parado, `copy` en un hueco y
        `paste` en otro cambian el contenido de verdad — lo que `copy here` nunca
        hizo.
  - [ ] Y entre Banks, que es lo que el portapapeles añade.

## FASE 4: LA CAPA DE TOQUES — el riesgo del track

- [ ] Task: Resolver los toques de la rejilla con `UIViewRepresentable`
  - [ ] `touchesBegan/Ended/Cancelled` sobre la rejilla entera; punto → índice de
        celda.
  - [ ] Los `Button` por celda desaparecen; el resaltado de pulsación se conserva
        a mano.
  - [ ] La accesibilidad de cada celda no se pierde al dejar de ser `Button`.
- [ ] Task: Enchufar la regla de la Fase 2
  - [ ] El acorde **solo con el transporte corriendo** (FR15). Parado, cada toque
        selecciona en el `up`, como hoy.
  - [ ] `.select` llama a `selectPattern(_:)`; `.copy` copia y **carga el
        portapapeles** (FR19).
  - [ ] El acorde no arma, no mueve selección, no toca transporte ni
        `pendingAdoption` (FR18).
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
  - [ ] En iPad, con el transporte corriendo: el acorde copia y **sigue sonando
        el mismo Pattern**, en los dos órdenes de levantada.
  - [ ] Un toque sencillo sigue armando, con su cuenta atrás.

## FASE 5: LO QUE SE VE

- [ ] Task: Marca de la celda de origen (FR12)
  - [ ] Visible desde `copy` hasta que el portapapeles se sustituye.
  - [ ] Solo en el Bank de origen; en otro Bank no se dibuja nada.
  - [ ] Distinguible de `playing`, `queued` y del seleccionado, que ya se reparten
        el borde.
- [ ] Task: Destello de la celda de destino (FR13, FR14)
  - [ ] Al pegar y al copiar por acorde, tuviera material o no.
  - [ ] Dentro del lenguaje de `Brutalist`/`ShapeTheme`, sin animación nueva
        colgada del reloj.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
  - [ ] Las dos señales se leen a un metro, que es la distancia de la pantalla.

## FASE 6: DISPOSITIVO Y CIERRE

- [ ] Task: Verificación en dispositivo (NFR6)
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
