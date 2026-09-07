# Plan — v2 rebanada 4: Persistencia, Patterns y Banks

Sigue el `workflow.md`: tests antes de implementación, un commit por tarea, git
note por commit y checkpoint verificado al cerrar cada fase. Todo el track vive
en la rama `feat/persistence-banks` y entra por Pull Request.

**El orden va de dentro afuera, y deja el riesgo para el final.** Primero las
desviaciones, que el Task Workflow §8 y el principio 2 exigen *antes* de
implementar —hay dos: el alcance deja de ser «no es una rebanada de motor», y
entra un paquete SPM nuevo—. Después el modelo puro, que se prueba sin disco;
luego el formato, que se prueba sin sistema de ficheros; luego el disco; luego
las tres operaciones de guardado; luego el cambio cuantizado, que es lo único que
toca el hilo del scheduler; y por último la pantalla y el dispositivo.

**La Fase 6 es la que tiene el riesgo, no la 4.** Guardar en disco es código
aburrido con una costura inyectable y se prueba entero en el host. Lo que no se
prueba con un test de host es que la adopción de una ranura armada dentro del
bucle de ventana no rompa la disciplina que `PatternHandoff` documenta con
cuidado — y ese es código que ya funciona y que esta rebanada abre.

**Todas las fases cargan con FR3.** `_isPOD(Pattern.self)` sigue pasando y el
snapshot no crece ni un byte. Si una tarea empuja hacia meter `Bank` o `Project`
en algo que el hilo del scheduler pueda ver, es la señal de que el diseño se está
torciendo: parar y revisar antes de seguir.

**Ninguna fase mide jitter** (NFR4). La medición está suspendida desde el
2026-09-02 y, además, esta rebanada no mueve ningún instante: cambia qué material
se emite en un límite que ya existía. Queda anotado en la Fase 1 que aquí no se
abre excepción, a diferencia de `external-clock_20260903`.

**Nada se borra sin que se pueda recuperar.** `Reload` y el apartado de ficheros
ilegibles son los dos únicos caminos que tocan datos existentes, y los dos tienen
su test de que el fichero anterior sigue ahí.

## FASE 1: LAS DESVIACIONES QUEDAN ESCRITAS [checkpoint: e4512b1]

- [x] Task: Anotar que la rebanada sí toca el motor (Overview, FR6, FR7) — `e6dcd6e`
  - [ ] Nota fechada el 2026-09-07 en `conductor/tracks.md`, sobre la entrada de
        la rebanada 4: donde dice «no es una rebanada de motor», decir qué dejó
        de ser cierto y por qué se elige igualmente — un Pattern que solo entra
        parando es un fichero, no una sección de live.
  - [ ] Precisar el alcance real del cambio: **el snapshot no crece**, no hay
        trabajo nuevo por evento, y lo que entra en el hilo del scheduler es una
        lectura atómica más por ventana y una comparación de enteros.
  - [ ] Anotar en `product.md`, *Success Criteria*, que este es el tercer cambio
        desde la suspensión del 2026-09-02 que roza el hilo del scheduler, que
        **no se abre excepción** y por qué: no mueve instantes, sólo material.
- [x] Task: Sacar Patterns y Banks de «Fuera de v1» en `product.md` (FR1, FR25) — `6cf70f7`
  - [ ] Nota fechada: Patterns, Banks y guardado salen de la lista de *Fuera de
        v1* por la misma vía por la que salieron Cycles y los múltiples Tracks.
  - [ ] Actualizar la nota del 2026-09-06 sobre las cuatro pantallas: `banks`
        deja de ser cáscara, y **la frontera del tacto se enmienda** — `banks`
        pasa a tener un gesto que se usa tocando, no solo antes de tocar.
  - [ ] Dejar escrito lo que sigue fuera: Backup Project, Program Change,
        encadenado, nombres y disparo desde el controlador.
- [x] Task: Documentar el paquete `Persistence` en `tech-stack.md` (NFR6) — `4565ecc`
  - [ ] Nota fechada en la sección *Estructura de módulos*: por qué no cabe en
        los paquetes que hay —`Engine` no importa fuera de la stdlib y
        `JSONEncoder` es Foundation; `MIDI` es CoreMIDI; `App` no se mide— y qué
        queda de cada lado: DTO y traducción en `Engine`, encoder, atomicidad y
        debounce en `Persistence`.
  - [ ] Ampliar la sección *Persistencia* con lo decidido: fichero por Bank más
        uno de Project, Application Support, escritura atómica, `schemaVersion`
        sin migradores, Pattern vacío como marca.
  - [ ] Añadir `Persistence` a la tabla de *Coverage Requirements* de
        `workflow.md` con umbral ≥90%, y el porqué: es la pieza que puede perder
        el trabajo del usuario.
- [x] Task: Anotar en la Pre Spec qué se entrega de §Guardado (FR14, FR16, FR17) — `e4512b1`
  - [ ] Nota fechada: entran Autosave y Save Bank/Reload; **Backup Project no**,
        con la razón (UI de documentos, no modelo) y la limitación que deja — el
        estado vive en el contenedor de la app y desinstalarla lo borra.
  - [ ] Fijar el vocabulario: `Bank`, `Pattern`, `Project`, `Save Bank`,
        `Reload`, `queued`. Ni «preset», ni «song», ni «slot».
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 2: EL MODELO — `Bank` Y `Project` EN `Engine` [checkpoint: 2655e43]

- [x] Task: `Bank`, dieciséis Patterns y un tempo (FR1, FR2, FR4) — `f7415cc`
  - [ ] Tests (Red): un `Bank` recién creado tiene 16 Patterns **vacíos**
        —iguales a `Pattern()`— y un tempo por defecto de 120 BPM; `pattern(at:)`
        devuelve `nil` fuera de 0…15 con el mismo criterio que `Pattern.track(at:)`.
  - [ ] Tests (Red): `replacing(_:at:)` cambia uno y deja los quince intactos.
  - [ ] Implementación (Green): `Bank` con almacenamiento **de array, no de
        tupla** (FR3), y su tempo.
  - [ ] Test de que `Bank` **no** pretende ser POD y de que
        `_isPOD(Pattern.self)` sigue pasando: la restricción de tiempo real no
        sube de nivel, y conviene que un test lo diga en voz alta.
- [x] Task: `Project`, dieciséis Banks y los índices de sesión (FR1, FR23) — `27320f0`, `2b2858f`
  - [ ] Tests (Red): 16 Banks vacíos; los índices de Bank, Pattern y Track
        seleccionados se acotan a su rango y no envuelven.
  - [ ] Tests (Red): `Project.initial` deja el material de arranque de hoy
        —`Pattern.initial`— en el Bank 1, Pattern 1, y los 255 restantes vacíos.
        Abrir la app por primera vez tiene que sonar como suena hoy.
  - [ ] Implementación (Green): `Project` con sus Banks, los tres índices y la
        fuente de reloj.
- [x] Task: Copiar y borrar un Pattern (FR13) — `e7b4732`
  - [ ] Tests (Red): copiar a un hueco produce un Pattern **igual por valor** al
        original y no toca el resto; copiar sobre uno con material lo sustituye;
        borrar deja `Pattern()`; los dos fuera de rango devuelven el Project
        intacto, sin fallar.
  - [ ] Implementación (Green), en `Engine` y como valores: son dos funciones
        puras y ahí se cubren.
- [x] Task: Qué Patterns tienen material (FR25) — `2655e43`
  - [ ] Tests (Red): un Bank sabe cuántos de sus Patterns tienen material,
        reusando el criterio que `TransportModel.patternHasMaterial` ya usa —hay
        pool en algún Track— y no inventando otro.
  - [ ] Implementación (Green) en `Engine`, para que la pantalla lo lea en vez de
        calcularlo: `BanksScreen` tiene hoy dos constantes y una clasificación de
        estado esperando bajar aquí.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 3: EL FORMATO — DTO `Codable` EN `Engine` [checkpoint: 8a5d684]

- [x] Task: Los DTO espejo y la traducción (FR18) — `f6e7165`
  - [ ] Tests (Red): **ida y vuelta** de `Cycle`, `Track`, `Pattern`, `Bank` y
        `Project` — de POD a DTO y de vuelta — devuelve un valor igual al
        original, campo por campo. El pool de ocho alturas empaquetado en un
        entero es el caso que hay que ver pasar.
  - [ ] Tests (Red): el DTO **no** es el POD: cambiar el orden de los campos del
        POD no cambia el JSON. Se comprueba contra una cadena JSON literal.
  - [ ] Implementación (Green): tipos `Codable` espejo en `Engine` —`Codable` es
        stdlib, así que la regla de importaciones se respeta— con claves
        estables y explícitas, nunca sintetizadas del nombre de la propiedad.
  - [ ] Un test enumera los campos esperados de cada DTO. Es lo que hace que
        añadir un parámetro al `Cycle` —rebanadas 5 y 6— rompa un test en vez de
        perder un dato en silencio.
- [x] Task: El Pattern vacío se escribe como marca (FR18) — `c4c9613`
  - [ ] Tests (Red): un Bank de dieciséis Patterns vacíos produce un JSON
        **órdenes de magnitud** menor que uno lleno, y releerlo devuelve los
        dieciséis vacíos.
  - [ ] Implementación (Green): el hueco vacío se codifica como marca y no como
        el árbol entero en ceros.
- [x] Task: `schemaVersion` y el punto de enchufe (FR19) — `d7efb5b`
  - [ ] Tests (Red): el fichero de Project lleva su versión; leer una versión
        **futura** falla con un error distinguible —no con un error genérico de
        decodificación— porque la Fase 4 tiene que poder tratarla igual que un
        fichero corrupto.
  - [ ] Implementación (Green): la versión, su lectura y una función de migración
        vacía con su punto de llamada. Sin migradores (FR19).
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

> **Enmienda del 2026-09-07 — «El JSON se lee con los ojos» se va a la Fase 4.**
> La tarea prueba que la salida esté indentada y con las claves ordenadas, y eso
> no es una propiedad de los DTO: es **configuración del `JSONEncoder`**, que
> vive en `Persistence` porque `Engine` no puede importar Foundation. Probarlo
> aquí exigiría configurar un encoder en el test y afirmar sobre él, que es
> probar Foundation en vez de código propio. Se mueve a la tarea que crea el
> almacén, donde el encoder existe.

## FASE 4: EL PAQUETE `Persistence` — DISCO, ATOMICIDAD Y RESCATE [checkpoint: 6019af3]

- [x] Task: Crear el paquete SPM `Persistence` (NFR6) — `06cbb1e`
  - [ ] `Packages/Persistence` con dependencia a `Engine`, target de tests, y
        añadido al proyecto de la app.
  - [ ] Una **costura de sistema de ficheros** inyectable desde el primer
        commit: los tests no tocan disco real, y es lo que permite provocar
        disco lleno y fichero corrupto sin ceremonia.
  - [ ] Verificar que `swift test --package-path Packages/Persistence` corre en
        host, sin simulador, como los otros dos.
- [x] Task: El JSON se lee con los ojos (NFR7) *(movida desde la Fase 3 el 2026-09-07)* — `41f30bc`
  - [ ] Test: el encoder del almacén produce salida **indentada y con claves
        ordenadas**, comprobada sobre un fichero pequeño literal. Es la mitad de
        la razón por la que `tech-stack.md` eligió JSON: «inspeccionable,
        diffeable».
- [x] Task: Escribir y leer un Bank (FR18, FR20) — `fd56209`, `41f30bc`
  - [ ] Tests (Red): escribir un Bank y releerlo devuelve un árbol igual;
        escribir el Bank 3 no toca los ficheros de los otros quince.
  - [ ] Tests (Red): las rutas cuelgan de Application Support y no de Documents.
  - [ ] Implementación (Green).
- [x] Task: La escritura es atómica (FR21) — `41f30bc`
  - [ ] Tests (Red): si la escritura falla a mitad, **el fichero anterior sigue
        intacto y legible**; no queda ningún temporal huérfano tras un fallo.
  - [ ] Implementación (Green): temporal más renombrado.
- [x] Task: El fallo de guardado se propaga, no se traga (FR21) — `41f30bc`
  - [ ] Tests (Red): un disco lleno produce un error que llega a quien llamó, y
        un guardado posterior con éxito lo limpia. La barra de estado es de la
        Fase 7; lo que se prueba aquí es que el estado existe y es correcto.
  - [ ] Implementación (Green).
- [x] Task: Un fichero ilegible se aparta y no se pierde (FR22) — `41f30bc`
  - [ ] Tests (Red): JSON corrupto y `schemaVersion` futura toman **el mismo
        camino**; el fichero original sigue existiendo con marca de tiempo en el
        nombre; la carga devuelve un Project vacío y una señal de que ocurrió.
  - [ ] Tests (Red): apartar dos veces el mismo día no pisa el primero.
  - [ ] Implementación (Green).
- [x] Task: Cargar el Project completo (FR20, FR23) — `41f30bc`
  - [ ] Tests (Red): se cargan los Banks que existen y los que faltan salen
        vacíos —un Project a medio escribir no impide arrancar—; los índices y
        los ajustes de sesión se restauran; un endpoint MIDI guardado **que ya no
        existe** se tolera y no es un error.
  - [ ] Implementación (Green).
- [x] Task: Coste de guardar, medido (NFR3) — `6019af3`
  - [ ] Test de rendimiento en host: serializar y escribir un Bank lleno, con su
        número anotado en la git note. El presupuesto de 100 ms se verifica en
        dispositivo en la Fase 8; aquí se establece la línea base.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 5: AUTOSAVE, SAVE BANK Y RELOAD [checkpoint: 7641d27]

- [x] Task: El Autosave y su debounce (FR14) — `7641d27`
  - [ ] Tests (Red): N cambios seguidos producen **una** escritura, no N; la
        escritura ocurre tras la calma; se escribe solo el Bank tocado.
  - [ ] Tests (Red): el reloj del debounce es inyectable — un test que espere
        segundos de verdad es un test que algún día falla solo.
  - [ ] Implementación (Green) en `Persistence`.
- [x] Task: Forzar la escritura pendiente (FR14) — `7641d27`
  - [ ] Tests (Red): pedir el volcado inmediato escribe lo que estuviera
        pendiente y deja el debounce limpio; pedirlo sin nada pendiente no
        escribe.
  - [ ] Implementación (Green). El enganche al ciclo de vida de la escena es de
        la Fase 7.
- [x] Task: `Save Bank` fija el punto de retorno (FR16) — `7641d27`
  - [ ] Tests (Red): guardar el Bank vigente crea su punto de retorno y **no
        toca** los otros quince; guardar dos veces sustituye el punto.
  - [ ] Tests (Red): las dos capas son independientes — editar después de guardar
        cambia el estado de trabajo y **no** el punto de retorno.
  - [ ] Implementación (Green).
- [x] Task: `Reload` vuelve, y sabe cuándo no puede (FR17) — `7641d27`
  - [ ] Tests (Red): guardar, editar, recargar devuelve **exactamente** el estado
        guardado; sin punto de retorno la operación no está disponible y lo dice
        con un motivo legible, en vez de fallar en silencio o vaciar el Bank.
  - [ ] Implementación (Green). La cuantización de `Reload` con el transporte
        corriendo se conecta en la Fase 6, sobre el mismo mecanismo que el cambio
        de Pattern.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 6: EL CAMBIO CUANTIZADO — LA RANURA ARMADA [checkpoint: a624bd0]

- [x] Task: Medir antes de construir encima (NFR2) — `0891721`
  - [ ] Medir el tamaño del handoff con la ranura armada dentro y el coste de la
        lectura extra por ventana, con el método de `cycles_20260901`: tipo de
        prueba con la forma real, 200 000 lecturas por pasada, tres pasadas.
  - [ ] Presupuesto: la lectura añadida por debajo del 1% de la ventana de 20 ms.
        **Si no cabe, parar y decidir aquí**, no a mitad de la fase: la
        alternativa escrita es que el hilo principal publique al cruzar (FR7,
        opción descartada), y reabrirla exige que el número lo justifique.
  - [ ] Anotar el resultado en la spec, como hizo la Fase 1 de `cycles`.
- [x] Task: El compás como rejilla (FR6) — `52c5cff`
  - [ ] Tests (Red): dado un tempo y un instante, el próximo límite de compás
        —cuatro negras— cae donde debe; el caso de estar exactamente encima del
        límite es el que hay que fijar por test y no por intuición.
  - [ ] Implementación (Green) en `Engine`, junto a `MusicalTime`: es aritmética
        pura y ahí se cubre.
  - [ ] Dejar escrito en el código que **cuatro negras es una decisión** y no una
        lectura del modelo: la app no tiene métrica.
- [x] Task: La ranura armada en `PatternHandoff` (FR7) — `9b7c6cc`
  - [ ] Tests (Red): armar no cambia lo que devuelve `load()`; adoptar publica lo
        armado; armar dos veces seguidas deja lo último; adoptar sin nada armado
        no hace nada.
  - [ ] Tests (Red): el test de concurrencia que el handoff ya tiene se extiende
        al camino armado — un escritor armando en bucle y un lector adoptando no
        producen un Pattern mezclado.
  - [ ] Implementación (Green): un contador de generación para lo armado, sin
        tocar el protocolo de ranura publicado. **Sin asignar, sin lock, sin
        `await`** (NFR1).
- [x] Task: El scheduler adopta en el límite (FR6, FR7) — `f904e75`
  - [ ] Tests (Red): con el transporte corriendo, un Pattern armado entra en el
        primer Step del compás siguiente —comprobado **sobre el índice de Step**
        y no de oído—, ni antes ni después.
  - [ ] Tests (Red): con el transporte parado, elegir un Pattern es inmediato
        (FR5).
  - [ ] Implementación (Green) en el bucle de ventana.
- [x] Task: Los cursores de Cycle arrancan al entrar (FR8) — `b92570f`
  - [ ] Tests (Red): el Pattern entrante empieza por el primer Cycle activo de
        cada Track; el cursor de **edición** viaja con el Pattern y no se toca.
  - [ ] Implementación (Green).
- [x] Task: Las notas que cruzan el límite terminan (FR9) — `72ad555`
  - [ ] Tests (Red), sobre el loopback: una nota con Sustain que cruza el cambio
        **recibe su note-off**; no hay all-notes-off en el límite; ninguna nota
        queda colgada tras diez cambios seguidos.
  - [ ] Implementación (Green) si hiciera falta. Puede que no: el note-off ya
        viaja sellado, y confirmarlo con un test es parte del trabajo.
- [x] Task: Stop adopta lo armado (FR10) — `3f05eef`
  - [ ] Tests (Red): Stop con un pendiente lo deja vigente; el Play siguiente
        arranca con él; no queda estado armado que persistir.
  - [ ] Implementación (Green).
- [x] Task: Cambiar de Bank, y el tempo (FR11, FR12) — `a624bd0`
  - [ ] Tests (Red): cambiar de Bank entra en el compás con el Pattern
        seleccionado del destino y adopta su tempo con reloj `Internal`; con
        `External` el tempo **no** se toca y el dato guardado sobrevive.
  - [ ] Implementación (Green).
- [x] Task: `Reload` cuantizado sobre el mismo mecanismo (FR17) — `a624bd0`
  - [ ] Tests (Red): con el transporte corriendo, recargar entra en el compás,
        por el mismo camino que un cambio de Pattern y no por otro.
  - [ ] Implementación (Green).
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 7: LA PANTALLA `banks` DEJA DE SER CÁSCARA

- [ ] Task: Bajar a `Engine` lo que la cáscara dejó arriba (FR25)
  - [ ] `BankGrid.count` y `PatternGrid.count` se van con `Bank`, como su propia
        documentación promete; el estado de un Pattern pasa a ser **lectura
        directa** y se prueba en `Engine`.
  - [ ] Tests (Red) del cuarto estado: `playing`, `queued`, `ready`, `empty`, y
        cuál gana cuando coinciden —el que suena manda sobre el elegido, que es
        la regla que la pantalla ya tiene.
- [ ] Task: La cuenta atrás hasta el compás (FR25)
  - [ ] Tests (Red) en `Engine`: cuánto falta para el límite, en la forma en que
        la pantalla lo va a pintar. La vista no calcula tiempo.
  - [ ] Implementación (Green) de la vista: el hueco `queued` y su cuenta atrás.
        Legible a un metro, que es condición de uso.
- [ ] Task: Elegir Bank y Pattern deja de ser `@State` local (FR5, FR11, FR25)
  - [ ] Quitar los dos `@State private var selected` de `BanksScreen` y leerlos
        del modelo: la nota que dice «no hay dónde guardarlo» deja de ser cierta
        y se sustituye por lo que ahora hace.
  - [ ] `TrackAssignments` deja de decir doce veces `pattern 01`.
- [ ] Task: Los controles de guardado (FR13, FR16, FR17)
  - [ ] `Save Bank`, `Reload` —deshabilitado y explicado sin punto de retorno—,
        copiar y borrar Pattern, sobre el chrome brutalista existente.
  - [ ] Ningún modal mientras el transporte corre, que `workflow.md` prohíbe.
- [ ] Task: El aviso de guardado fallido (FR21)
  - [ ] En la barra de estado, y **persistente hasta que un guardado funcione**.
- [ ] Task: Enganchar Autosave y arranque al ciclo de vida (FR14, FR20, FR23)
  - [ ] Cargar el Project al arrancar y restaurar índices y ajustes; forzar el
        volcado al pasar a segundo plano.
  - [ ] El Autosave escribe también con el transporte corriendo (FR15): fuera del
        hilo principal y lejos del scheduler.
  - [ ] Verificar en simulador que un fichero apartado se anuncia y la app abre.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 8: DISPOSITIVO Y CIERRE

- [ ] Task: Verificación en iPad con el BeatStep Pro
  - [ ] **El criterio principal**: editar en varios Patterns, cerrar la app por
        completo, reabrir y encontrarlo todo — Bank, Pattern, Track y material
        hasta el último Cycle.
  - [ ] Cambio de Pattern sonando: entra en el compás, la cuenta atrás se ve y
        se lee a un metro, y no se oye ningún corte ni nota colgada.
  - [ ] Cambio de Bank con `Internal` y con `External`.
  - [ ] `Save Bank`, editar, `Reload`. Y `Reload` en un Bank nunca guardado.
  - [ ] Copiar el Pattern 1 al 2, variarlo, alternar entre los dos en directo.
  - [ ] Autosave con el transporte corriendo durante varios minutos: no se oye
        nada al escribir.
  - [ ] **NFR3 en dispositivo**: guardar un Bank lleno por debajo de 100 ms.
  - [ ] Anotar todo en `device-verification.md`, con números.
- [ ] Task: Cobertura y estilo
  - [ ] `Engine` ≥90%, `MIDI` ≥80%, `Persistence` ≥90%. La de `MIDI` se mide en
        un proceso y filtrando `Engine/Sources`, según las ampliaciones del
        workflow; el flake `-50` se descarta comparando pasadas contra `main`.
  - [ ] `swift format`, y los dos style guides.
- [ ] Task: Sincronizar la documentación con lo entregado
  - [ ] `product.md`: la nota de las cuatro pantallas deja de llamar cáscara a
        `banks`; el Core Model deja de decir que Patterns y Banks no existen.
  - [ ] `product-guidelines.md`: la pantalla `banks` en el reparto táctil, con su
        gesto de directo.
  - [ ] `spec.md` del track: limitaciones confirmadas o corregidas con lo que se
        haya aprendido, en especial la 3 —el primer migrador— para que las
        rebanadas 5 y 6 lo encuentren escrito.
- [ ] Task: Pull Request
  - [ ] `gh pr create --base main`. Cuerpo corto: qué cambia, cómo se verificó en
        números, qué queda pendiente. Sin medición de jitter, con la razón de
        NFR4 en una línea.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
