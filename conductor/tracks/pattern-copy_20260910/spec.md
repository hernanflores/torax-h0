# Spec — Copiar Patterns: acorde en directo y portapapeles

## Overview

**El botón `copy here` de la rejilla de patterns no hace nada, y no puede
hacerlo.** `BanksScreen.swift:179` llama `onCopy(selected)`, donde `selected` es
`model.selectedPatternIndex`; eso llega a `TransportModel.copyPattern(to:)` y de
ahí a `Project.copyingSelectedPattern(to:)`, que copia **el Pattern seleccionado
al índice recibido**. Origen y destino son el mismo hueco. La operación copia la
celda sobre sí misma y no cambia nada, ni en pantalla ni en disco.

El motor está bien y tiene tests: `PatternCopyTests` prueba `to: 7` y `to: 3`,
siempre con origen distinto del destino. **Nadie probó el caso que la vista
dispara.** Es un defecto de cableado, no de reglas.

Lo que falta es un **origen**. La pantalla solo sabe de un índice —el
seleccionado— y lo usa para las dos puntas de la copia.

**Este track no se limita a enchufar el origen.** El gesto de copiar un Pattern
tiene dos usos distintos y el mismo par de botones no sirve para los dos:

- **Organizar, con el transporte parado.** Duplicar un Pattern para variarlo,
  mover una idea a otro hueco o a otro Bank. Es trabajo de mesa y admite dos
  gestos separados.
- **Guardar una idea antes de romperla, en directo.** El equivalente por Pattern
  de lo que `reload` del Bank hace por Banco: dejo una copia del que suena en un
  hueco vacío y experimento encima sin miedo. Aquí no se puede parar, ni mirar la
  pantalla, ni pulsar dos botones en orden.

Por eso hay **dos interacciones**, y la frontera entre ellas es el transporte.

## Las dos interacciones

### Con el transporte corriendo: acorde de dos dedos

**Mantener el origen y tocar el destino.** Se copia en el acto. Sigue sonando lo
que sonaba.

Funciona porque hoy, sonando, el toque sencillo **ya no es inmediato**:
`TransportModel.selectPattern(_:)` arma el material para el próximo límite de
compás (`armForNextBar`) y la rejilla lo marca `queued` con la cuenta atrás. Hay
margen de sobra para decidir si el toque era un acorde antes de que tenga efecto.

La copia ocurre en el **`down` del segundo dedo**, no al levantar: da respuesta
inmediata y deja el orden de levantada sin importancia, que es la condición que
el gesto tiene que cumplir.

### Con el transporte parado: `copy` y `paste`

Dos botones bajo la rejilla, donde hoy está `copy here`. `copy` carga el hueco
vigente en el portapapeles; `paste` lo escribe en el destino. `copy here`
desaparece: su nombre describía un gesto de un solo paso que nunca existió.

**`paste` también funciona con el transporte corriendo**, y no por simetría: el
acorde no puede cruzar Banks —los dos dedos caen en la misma rejilla— y sin
`paste` en directo no hay forma de llevar una idea a otro Banco sin parar.

## Functional Requirements

### El portapapeles

- **FR1.** `TransportModel` guarda un portapapeles con **el Pattern copiado
  entero**, no un índice. Es lo que permite pegar en otro Bank, donde el hueco 3
  contiene otra cosa.
- **FR2.** El portapapeles recuerda también **de qué Bank y de qué hueco salió**,
  y eso es solo para dibujar la marca de origen (FR12). No participa en el
  pegado.
- **FR3.** Vive **mientras viva la app**. No se persiste: no toca `Persistence`,
  ni el formato de disco, ni `schemaVersion`. Se pierde al cerrar, y eso es
  aceptable para un portapapeles.
- **FR4.** Empieza vacío. Con el portapapeles vacío, `paste` está deshabilitado.

### Copiar

- **FR5.** `copy` carga en el portapapeles el Pattern del hueco seleccionado del
  Bank seleccionado. Está disponible **siempre**, con el transporte parado o
  corriendo: copiar no destruye nada.
- **FR6.** El material copiado es **el guardado en el Bank**, sin la
  superposición de un gesto en curso. Temp y Ctrl All superponen valores que
  vuelven solos al soltar y que `recordEdit()` no escribe en el Bank; copiar sigue
  la misma regla, y por el mismo motivo: congelar en un hueco un fill que el
  usuario espera que se deshaga sería material que nadie pidió conservar.

### Pegar

- **FR7.** `paste` escribe el Pattern del portapapeles en un hueco del **Bank
  vigente**. El Bank de origen no interviene: se pega donde se está mirando.
- **FR8.** El destino depende del transporte:
  - **Parado:** el hueco seleccionado.
  - **Corriendo:** el hueco **armado** si hay uno; si no lo hay, el que suena.
    Sonando, tocar un hueco no mueve `project.selectedPattern` —solo arma, y la
    selección se mueve cuando el material entra en el compás—, así que el armado
    es la única forma de apuntar a un hueco distinto del que suena.
- **FR9.** **Se permite pegar encima del Pattern que suena.** El audio no se
  corta: el transporte tiene su propio snapshot publicado y no lo relee hasta la
  próxima adopción. El material del hueco queda sustituido y entra al siguiente
  cambio de Pattern.
- **FR10.** Pegar **no mueve la selección, no arma nada, no toca el transporte y
  no cancela una adopción pendiente**. Escribe material y nada más.
- **FR11.** Pegar dispara el autosave del Bank vigente, como ya hacen copiar y
  borrar.
- **FR11b.** **Pegar refresca las dos copias que el `Project` no gobierna.**
  Añadido el 2026-09-10, después de que la verificación en dispositivo
  encontrara que sin esto el pegado no sonaba y se perdía:
  - Si el destino es el **hueco cargado**, la copia viva del Pattern y la entrada
    de control adoptan lo pegado. Esa copia es la que la pantalla `track` edita y
    la que se vuelca al Bank en cada edición, así que sin refrescarla **el primer
    giro de knob escribe el material anterior encima de lo pegado**, que se
    pierde sin aviso.
  - Si el destino es el **hueco armado**, se vuelve a armar **ese mismo hueco**
    con el material nuevo. El transporte recibió su snapshot al armar, antes del
    pegado, así que sin rearmar entra el material viejo en el límite de compás —
    que fue el síntoma observado: lo pegado no sonaba hasta volver a disparar el
    Pattern a mano.

  **No contradice FR10**, que prohíbe armar un hueco *distinto* y mover la
  selección. Refrescar una copia no es ninguna de las dos, y rearmar el mismo
  hueco no cambia a dónde va el transporte, solo con qué. El audio sigue sin
  cortarse (FR9).

### Lo que se ve

- **FR12.** La celda de origen lleva una **marca propia** desde que se pulsa
  `copy` hasta que el portapapeles se sustituye. Solo se dibuja **en su Bank**:
  mirando otro Banco no hay celda que marcar, y la señal de que hay algo cargado
  es que `paste` está habilitado.
- **FR13.** Al pegar, la celda de destino **destella**. Además cambia de estado si
  estaba vacía, que ya ocurre solo. El destello existe para el caso que FR9
  autoriza —pegar encima de un hueco con material—, donde el estado no cambia y
  sin él el gesto se lee como el botón muerto que este track viene a arreglar.
- **FR14.** El acorde produce el mismo destello, por el mismo motivo y con más
  razón: en directo nadie está mirando la pantalla de frente.

### El acorde

- **FR15.** El acorde **solo actúa con el transporte corriendo**. Parado, el toque
  sencillo carga el Pattern de inmediato, así que el `down` del primer dedo ya
  habría cambiado el material antes de saber si era un acorde.
- **FR16.** La regla, en eventos de toque crudos:

  | Evento | Condición | Efecto |
  |---|---|---|
  | `down(A)` | nada pulsado | recuerda A; ningún efecto todavía |
  | `down(B)` | A ya pulsado, `B ≠ A` | copia A → B **ya**; el acorde queda consumido |
  | `down(C)` | dos o más ya pulsados | se ignora |
  | `up(X)` | el acorde está consumido | nada |
  | `up(X)` | X fue un toque solo | `selectPattern(X)`: el comportamiento de hoy |

- **FR17.** **El orden de levantada es indiferente.** El acorde se consume en el
  `down` del segundo dedo, y a partir de ahí ningún `up` tiene efecto hasta que se
  levanten todos los dedos. Sigue sonando el Pattern activo.
- **FR18.** El acorde **no arma, no mueve la selección, no toca el transporte ni
  `pendingAdoption`**. Lo que suena no se entera.
- **FR19.** El acorde **también carga el portapapeles** con el Pattern de origen.
  Un solo portapapeles para los dos gestos: el backup se hace con dos dedos y
  luego se puede llevar a otro Bank con `paste`, sin repetir nada.
- **FR20.** El toque sencillo pasa a resolverse en el **`up`**, que es donde un
  `Button` ya lo resolvía. Lo que cambia es que ahora se puede suprimir si hubo
  acorde.
- **FR21.** Un toque que empieza en una celda y se levanta fuera de ella no
  selecciona, como hoy.

### El motor

- **FR22.** `Project` gana `copyingPattern(from:to:)` —origen explícito, dentro del
  Bank vigente— y una forma de **escribir un Pattern suelto en un hueco**, que es
  lo que el pegado entre Banks necesita y `copyingSelectedPattern(to:)` no puede
  expresar.
- **FR23.** `copyingSelectedPattern(to:)` deja de tener llamadores en la app.
  Se retira o se reescribe sobre `copyingPattern(from:to:)`; sus tests se
  conservan, adaptados.
- **FR24.** Fuera de rango, las operaciones nuevas devuelven el `Project` intacto,
  como las que ya existen.

## Non-Functional Requirements

- **NFR1.** La regla del acorde (FR16, FR17) vive en `Engine` como valor
  testeable, con el precedente de `PatternSlotState`, que bajó de la vista el
  2026-09-07 justo por esto. La vista traduce toques a eventos; no decide.
- **NFR2.** Cobertura: `Engine` ≥90%. `App` no se mide — y por eso la regla no
  puede vivir ahí.
- **NFR3.** **No toca el hilo del scheduler ni el camino de emisión.** Ni el
  acorde ni el pegado publican material al transporte.
- **NFR4.** **Sin medición de jitter**, por la suspensión del 2026-09-02 y porque
  además no mueve ningún instante: cambia material en el `Project`, no cuándo
  suena nada.
- **NFR5.** **No cambia el formato de disco.** El portapapeles es de memoria
  (FR3).
- **NFR6.** El multitouch **no existe en el simulador**. Es la misma lección de
  método que dejó `hardware-screen-sync_20260908`: lo que vive en el hardware se
  verifica en el hardware. La capa de toques se valida en iPad, y con el
  transporte corriendo.

## Acceptance Criteria

1. Con el transporte corriendo, mantener el Pattern 1 y tocar el 3 deja el
   material del 1 en el 3, y **sigue sonando el 1**. Da igual qué dedo se levante
   primero.
2. Ese mismo acorde no arma nada: no aparece la cuenta atrás y la rejilla no marca
   `queued`.
3. Un toque sencillo sobre un hueco, con el transporte corriendo, sigue armando
   el cambio para el próximo compás, con su cuenta atrás.
4. Un toque sencillo con el transporte parado sigue cargando el Pattern de
   inmediato.
5. Con el transporte parado: `copy` en el hueco 1, seleccionar el 9, `paste`, y el
   9 contiene el material del 1.
6. Con el transporte parado: `copy` en el Bank 1, cambiar al Bank 5, `paste`, y el
   hueco de destino del Bank 5 contiene el material del Bank 1.
7. Con el portapapeles vacío, `paste` está deshabilitado.
8. Con el transporte corriendo, tocar el hueco 9 —que queda armado— y pulsar
   `paste` escribe en el 9, y lo que suena no cambia hasta el límite de compás.
   **Y en ese límite entra lo pegado, no el material que el 9 tenía al armarse**
   (FR11b, añadido el 2026-09-10 al observarlo fallar).
9. Pegar encima del Pattern que suena no corta el audio.
10. La celda de origen lleva su marca mientras se mira su Bank, y no se dibuja
    ninguna marca en otro Bank.
11. La celda de destino destella al recibir un pegado o una copia por acorde,
    tuviera material o no.
12. `Engine` ≥90% y la suite entera en verde.
13. Verificado en iPad, con el transporte corriendo: los cuatro gestos —acorde,
    toque sencillo, `copy`/`paste` parado, `paste` corriendo— hacen lo que dice
    esta lista.

## Out of Scope

- **`clear`.** Se queda exactamente como está hoy. No se toca ni su
  disponibilidad ni su destino.
- **Deshacer un pegado.** La vuelta atrás ya existe a nivel de Banco: el punto de
  retorno de `save`/`reload` (FR16/FR17 del producto). Añadir un undo propio para
  un gesto sería un mecanismo paralelo al que el proyecto ya eligió.
- **Persistir el portapapeles** entre sesiones (FR3).
- **Copiar Banks enteros.**
- **Arrastrar y soltar** un Pattern de un hueco a otro.
- **El acorde entre Banks.** Los dos dedos caen en la misma rejilla; para cruzar
  Banks está `paste`.

## Lo que enseñó la verificación en dispositivo

> **Nota del 2026-09-10.** El criterio 8 falló con el iPad delante: la copia
> ocurría, pero **el material pegado no sonaba** hasta volver a disparar el
> Pattern a mano. Investigándolo apareció una segunda mitad que no se ve y que es
> peor: al entrar el compás, la copia viva quedaba con el material anterior y
> **el primer giro de knob lo escribía encima de lo pegado**. Y no era solo el
> caso armado — parado, pegar en el hueco seleccionado tenía la misma pérdida; el
> criterio 5 pasó porque solo se miró la rejilla, que lee el Bank.
>
> **Este spec no lo había previsto.** Describía el pegado como una escritura en
> el `Project` y daba por hecho que el resto se enteraba, cuando `TransportModel`
> mantiene dos copias que el `Project` no gobierna. FR11b es la corrección, y la
> decisión de arreglar las dos mitades se tomó con el usuario ese mismo día.
>
> **El método es la lección que ya dejó `hardware-screen-sync_20260908`** y que
> este track citaba en su índice: lo que vive en el hardware se verifica en el
> hardware. Aquí no era el multitouch sino el transporte sonando, y ninguna
> pasada de tests lo habría dicho — `App` no se mide, y la regla que faltaba no
> existía todavía en `Engine` para poder probarla.

## Known Limitations

- **Pegar corriendo puede escribir sobre un hueco que va a entrar en menos de un
  compás** (FR8, rama del armado). Es el precio de poder apuntar a un hueco
  distinto del que suena mientras suena.
- **`clear` sigue disponible con el transporte corriendo**, como hoy, mientras que
  `paste` llega con reglas de destino propias. La asimetría es deliberada: sacar
  `clear` del alcance evita mezclar un cambio de comportamiento no pedido con el
  arreglo del defecto. Queda anotada por si molesta al usarla.
- **El acorde exige dos dedos sobre la rejilla**, que en un iPad sostenido con una
  mano no siempre es cómodo. No hay alternativa de un solo dedo para el caso de
  directo.
