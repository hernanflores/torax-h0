# Verificación en dispositivo — Copiar Patterns: acorde en directo y portapapeles

**2026-09-10.** iPad con BeatStep Pro conectado. Encoders en `Relative #2`.

**Por qué este documento existe.** Dos de las cuatro interacciones que el track
entrega no se pueden verificar en ningún otro sitio. El multitouch **no existe en
el simulador** (NFR6), así que el acorde de dos dedos solo se puede ver aquí; y
el pegado con el transporte corriendo depende de que algo esté sonando, que sin
destino MIDI tampoco ocurre. Lo que hay abajo es lo observado, no lo esperado —
por eso incluye un fallo.

## Los trece criterios de aceptación

| # | Criterio | Qué pasó | Fase |
|---|---|---|---|
| 1 | Corriendo, mantener el 01 y tocar el 03 deja el material del 01 en el 03, y **sigue sonando el 01**, en los dos órdenes de levantada | Correcto | 4 |
| 2 | Ese acorde no arma nada: sin cuenta atrás y sin `queued` | Correcto | 4 |
| 3 | Corriendo, un toque sencillo sigue armando para el próximo compás con su cuenta atrás | Correcto | 4 |
| 4 | Parado, un toque sencillo sigue cargando el Pattern de inmediato | Correcto | 4 |
| 5 | Parado: `copy` en el 1, seleccionar el 9, `paste`, y el 9 contiene el material del 1 | Correcto en la rejilla. **Incompleto**: ver abajo | 3 |
| 6 | Parado: `copy` en el Bank 1, cambiar al Bank 5, `paste`, y el destino contiene el material del Bank 1 | Correcto | 3 |
| 7 | Con el portapapeles vacío, `paste` está deshabilitado | Correcto | 3 |
| 8 | Corriendo, tocar el 9 —que queda armado— y `paste` escribe en el 9, y lo que suena no cambia hasta el límite de compás | **Falló.** Ver abajo | 6 |
| 9 | Pegar encima del Pattern que suena no corta el audio | Correcto | 7 |
| 10 | La marca de origen se ve en su Bank y no se dibuja en otro | Correcto | 5 |
| 11 | La celda de destino destella al pegar y al copiar por acorde, tuviera material o no | Correcto | 5 |
| 12 | `Engine` ≥90% y la suite entera en verde | 921 tests, 0 fallos; **98,70%** de líneas | 7 |
| 13 | En iPad: acorde, toque sencillo, `copy`/`paste` parado y `paste` corriendo | Correcto tras la corrección | 7 |

## El criterio 8, que falló

**Lo observado:** la copia ocurría —el hueco 9 recibía el material— pero **lo
pegado no sonaba** al entrar el compás. Seguía sonando el material que el 9 tenía
antes, y para oír lo pegado había que volver a disparar el Pattern a mano.

**La causa.** Al armar el 9, `armForNextBar` ya había entregado al transporte el
snapshot del material **viejo**. Pegar después escribía en el `Project` y, por
FR10, no tocaba nada más — así que en el límite de compás entraba el snapshot
entregado antes del pegado.

**La mitad que no se ve, y que es peor.** Investigándolo apareció que
`TransportModel` mantiene una copia viva del Pattern cargado, `pattern`, que es
la que la pantalla `track` edita y la que `recordEdit()` vuelca al Bank en cada
edición. Pegar tampoco la refrescaba, así que al entrar el compás quedaba con el
material anterior y **el primer giro de knob lo escribía encima de lo pegado**:
el pegado se perdía sin aviso.

**Y alcanzaba al criterio 5.** Parado, pegar en el hueco seleccionado dejaba la
misma copia viva desactualizada, con la misma pérdida al primer knob. El criterio
5 se había dado por bueno mirando solo la rejilla, que lee el Bank y por eso
decía la verdad. La pantalla `track` decía otra cosa.

**Lo que se hizo.** Decidido con el usuario ese mismo día: arreglar las dos
mitades. El `spec.md` gana FR11b y la regla vive en `PatternPasteRefresh`, dentro
de `Engine`, con tests. Pegar refresca la copia viva cuando el destino es el
hueco cargado, y rearma **ese mismo** hueco con el material nuevo cuando el
destino es el armado. Ninguna de las dos arma un hueco distinto ni mueve la
selección, que es lo que FR10 prohíbe.

**Comprobado después, en el mismo iPad:**

| # | Qué se hizo | Qué pasó |
|---|---|---|
| 1 | Corriendo: armar el 9 y pegar | **Al límite de compás suena lo pegado** |
| 2 | Girar un knob justo después | El material pegado sigue ahí |
| 3 | Parado: pegar y mirar la pantalla `track` | Enseña lo pegado; el knob no lo pierde |
| 4 | Corriendo, sin nada armado: pegar encima del que suena | El audio no se corta |

## Lo que este track no midió

**Sin medición de jitter** (NFR4). Manda la suspensión del 2026-09-02, y además
este track no mueve ningún instante: cambia material en el `Project` y no toca el
hilo del scheduler ni el camino de emisión. La última referencia válida sigue
siendo la de la rebanada 2 de la v2 — máx 0,158 ms, σ 0,013–0,014 ms.

## La lección de método

Es la misma que dejó `hardware-screen-sync_20260908` y que este track ya citaba
en su índice: **lo que vive en el hardware se verifica en el hardware.** Aquí no
era el multitouch —que salió bien a la primera— sino el transporte sonando.

Y una que se añade: **el fallo del criterio 8 no lo habría dicho ninguna pasada
de tests.** La copia viva vive en `App`, que no se mide, y la regla que faltaba
no existía todavía en `Engine` para poder probarla. Lo que la encontró fue mirar
un caso concreto con el iPad delante, y lo que la cerró fue bajarla a `Engine`
para que a partir de ahora sí se pruebe.
