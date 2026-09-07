# Spec — v2 rebanada 4: Persistencia, Patterns y Banks

**Track ID:** `persistence_20260907`
**Track type:** Feature

## Overview

Hasta hoy la app tiene **un** `Pattern`, y cerrarla lo pierde entero. Esta
rebanada hace las dos cosas que faltan para que eso deje de ser cierto: el árbol
crece los dos niveles que la Pre Spec pone encima —**16 Banks de 16 Patterns**—
y aparece el **disco**.

Es el primer track del proyecto que escribe un fichero. Todo lo anterior vivía
en memoria porque el material cabía en una sesión; con Cycles dentro, cada
Pattern son doce Tracks por dieciséis Cycles, y perder eso al salir es perder
dieciséis veces más trabajo que antes de la rebanada 3.

**Y la pantalla `banks` deja de ser cáscara.** El rediseño del handoff la
entregó dibujando dieciséis huecos de banco y dieciséis de pattern de los que
solo el primero existía, con la promesa escrita en su propio encabezado: «el día
que exista el modelo de `Bank` —la rebanada 4 de la v2— esta pantalla deja de ser
cáscara **sin cambiar de forma**». Esta rebanada cobra esa promesa: la forma se
respeta y lo que cambia es que detrás hay algo.

### La desviación de alcance, escrita antes de empezar

La entrada del registro dice, literalmente, **«no es una rebanada de motor»**:
«lo que cruza al hilo del scheduler sigue siendo un Pattern de 37 KB; lo que
cambia es cuántos hay y de dónde salen».

**Deja de ser cierto por decisión del 2026-09-07.** Cambiar de Pattern con el
transporte corriendo es **cuantizado al compás**, y esa decisión la toma el hilo
del scheduler en el límite. Sigue sin haber trabajo nuevo por evento y el
snapshot no crece ni un byte —el Pattern que cruza es el mismo tipo de siempre—
pero hay una comparación y una adopción de ranura dentro del hilo de tiempo real,
y llamar a eso «no es motor» sería mentir en el sitio donde más caro sale.

**Por qué se elige igualmente.** La alternativa era cambiar de Pattern solo con
el transporte parado, y eso convierte el Bank —que la Pre Spec define como
«sección de live»— en algo que no se puede usar en directo. Un Pattern que solo
entra parando es un fichero, no una sección.

La Fase 1 escribe la nota fechada en `conductor/tracks.md`, en `product.md` y en
`tech-stack.md` antes de tocar código, como hizo `ui-declutter_20260902` con los
doce Tracks. El paso 8 del *Task Workflow* lo exige y aquí se aplica al alcance,
no solo a la implementación.

### Lo que esta rebanada no es

**No es Backup Project.** Exportar e importar el Project por la app Files es
otro problema —`UIDocument`, share sheet, ida y vuelta de ficheros ajenos— y no
toca el modelo. El formato JSON lo deja preparado; la UI de documentos no entra.

**No es Program Change ni encadenado de Patterns.** La Pre Spec dice que un
Pattern «puede dispararse cuantizado, encadenarse y seleccionarse por MIDI
Program Change». Entra lo primero. Encadenar es una estructura nueva —una cola
de Patterns con su propia edición— y Program Change es entrada de control que
`product.md` lista hoy como fuera de v1.

**No es un gesto de hardware.** No quedan step buttons libres: 1–12 seleccionan
Track, 13 es Temp, 14 Ctrl All, 15 y 16 solo y mute. Meter Patterns en el
controlador exige un modificador nuevo o robarle el gesto a otro, y eso es una
decisión de mapeo que toca el preset cerrado en la rebanada 7.

**No son nombres.** Banks y Patterns son números. Nombrar exige teclado en
pantalla sobre una app que se opera con las manos en los knobs.

**No es copiar Banks.** Copiar y borrar entran a nivel de Pattern, que es donde
se hace una variante. Duplicar un Bank es dieciséis veces más dato y un fichero
que se copia en vez de un valor.

### Dependencias

Ninguna bloqueante: `screens-redesign_20260906` entregó la pantalla y
`cycles_20260901` el nivel que hay que guardar, y las dos están cerradas.

**Pero hay una dependencia de orden que conviene mirar de frente.** Las
rebanadas 5 y 6 —`note-repeater_20260906` y `modulation_20260906`— están
planificadas, sin empezar, y **las dos añaden campos al `Cycle`**: Repeats, Time,
Ramp y Pace la primera; waveform y accent la segunda. Si la persistencia entra
antes, el esquema v1 nace sabiendo que su primer cambio llega en la rebanada
siguiente.

**No se propone reordenar.** Es exactamente el caso que `tech-stack.md` prevé
—«toda estructura persistida lleva versión de esquema desde el primer commit; el
modelo va a crecer al incorporar lo que v1 dejó fuera»— y es la razón de que
`schemaVersion` y su punto de enchufe entren ahora en vez de cuando hagan falta.
Lo que sí hace esta spec es dejarlo escrito, para que el primer migrador se
escriba sabiendo que estaba previsto.

## Functional Requirements

### FR1 — El árbol crece dos niveles

Aparecen `Bank` y `Project`. Un `Project` tiene 16 `Bank`; un `Bank` tiene 16
`Pattern` y un tempo propio. Los nombres y las cardinalidades son los de la Pre
Spec, sin desviación.

### FR2 — Los 256 Patterns existen siempre y arrancan vacíos

Es el idioma que el código ya usa dos veces: `Pattern` documenta que «los doce
existen siempre y arrancan vacíos» y `Track` lo mismo con sus dieciséis Cycles.
Elegir un Pattern nunca crea nada, nunca falla y nunca asigna. Un Pattern vacío
es el que devuelve `Pattern()`: doce Tracks sin pool, que disparan y no tienen
material que emitir.

La pantalla sigue diciendo `empty` leyendo si tiene material, exactamente como
hoy.

### FR3 — `Bank` y `Project` no son POD, y `Pattern` sigue siéndolo

**La restricción de tiempo real no sube de nivel.** Solo `Pattern` y lo que
cuelga de él cruzan al hilo del scheduler, y ahí no cambia nada:
`_isPOD(Pattern.self)` vigila lo mismo que vigila hoy.

`Bank` y `Project` viven en el hilo principal con almacenamiento normal —arrays,
no tuplas—. Un `Bank` como tupla de dieciséis `Pattern` serían 592 KB de valor
copiándose en pila sin ninguna razón: nadie los lee desde el hilo de audio.

### FR4 — Cada Bank lleva su tempo

La Pre Spec: «16 Banks (cada uno guarda tempo)». Cambiar de Bank adopta su
tempo.

### FR5 — Con el transporte parado, elegir un Pattern es inmediato

No hay rejilla que respetar. El Pattern elegido pasa a ser el vigente y el
próximo Play arranca con él.

### FR6 — Con el transporte corriendo, el Pattern entra en el próximo compás

Un compás son **cuatro negras**. La app no tiene concepto de compás ni de
métrica —`MusicalTimeline` cuenta negras— así que esto es una decisión, no una
lectura: cuatro negras es el compás que asume cualquier secuenciador de hardware
y el que hace que un cambio de sección caiga donde el oído lo espera.

**No es el límite de vuelta de ningún Track.** Los doce tienen anillos de
longitudes distintas (Steps × Division) y esperar a que cierren todos no
converge. El compás es la única rejilla común.

### FR7 — El Pattern entrante se arma, y lo adopta el hilo del scheduler

El hilo principal publica el Pattern entrante en una ranura **armada**; el hilo
del scheduler la adopta al cruzar el límite de compás. El instante lo decide
quien conoce la rejilla.

`PatternHandoff` ya tiene la disciplina de ranura que esto necesita y **no cambia
de protocolo**: lo que se añade es un segundo contador de generación para lo
armado, que el lector consulta una vez por ventana. La adopción es una
comparación de enteros y una copia de ranura, sin asignar, sin lock y sin
`await`.

### FR8 — Los cursores de Cycle arrancan en el primer Cycle activo

El Pattern entra por el principio de su desarrollo, como si le acabaran de
pulsar Play. Disparar el break suena igual las dos veces, y el cursor de
reproducción —que mueve el hilo del scheduler— no se guarda en disco: es estado
de ejecución, no material.

El cursor de **edición** sí viaja con el Pattern: es de pantalla y es material de
trabajo.

### FR9 — Las notas ya programadas terminan como estaban programadas

Una nota con Sustain largo puede estar sonando al cruzar el límite. Su note-off
ya viaja sellado con timestamp por el look-ahead, y se respeta: la nota termina
cuando tenía que terminar aunque su Pattern ya no esté.

**No hay all-notes-off en el límite.** La cola de la frase anterior se solapa con
la nueva, que es lo que hace cualquier secuenciador y lo que un corte en seco
rompería. Y no exige tocar el camino de emisión.

### FR10 — Stop adopta el armado al instante

Si hay un Pattern esperando el compás y se pulsa Stop, el pendiente pasa a ser el
vigente inmediatamente. Parado no hay rejilla, el usuario ya dijo qué quiere, y
no queda estado armado que persistir entre sesiones.

### FR11 — Cambiar de Bank es cambiar de Pattern más el tempo

Con la misma cuantización de FR6: entra el Pattern seleccionado en el Bank
destino, y el tempo del Bank entra con él. Una sola regla de cuantización en el
producto.

### FR12 — Con reloj externo, el tempo del Bank no manda

Con la fuente en `External` el tempo lo pone el maestro y cambiar de Bank no lo
toca. El dato guardado no desaparece: vuelve a mandar en cuanto la fuente sea
`Internal`. Sin esto, la rebanada contradiría a `external-clock_20260903`.

### FR13 — Copiar y borrar un Pattern

Copiar el Pattern vigente a un hueco, y vaciar un hueco. Con dieciséis huecos y
sin copiar, hacer un break exige reconstruir doce Tracks a mano desde vacío: los
Patterns existirían sin poder usarse como se usan.

Borrar deja el hueco en `Pattern()`, que es lo que FR2 llama vacío.

### FR14 — Autosave con debounce, y forzado al ir a segundo plano

Un giro de knob no escribe a disco. Un par de segundos de calma sí, y el paso a
segundo plano fuerza la escritura pendiente. A cuarenta y ocho controles físicos,
escribir por evento sería escribir en ráfagas.

**Escribe solo el Bank tocado**, no los dieciséis.

### FR15 — El Autosave escribe también con el transporte corriendo

La escritura ocurre fuera del hilo del scheduler, sobre una copia del árbol, y el
look-ahead absorbe cualquier hipo del hilo principal mientras el trabajo quepa en
la ventana de 20 ms. Parar el Autosave mientras suena sería perder justo la
sesión que más importa.

### FR16 — `Save Bank` fija el punto de retorno del Bank vigente

De ése y solo de ése, que es lo que dice la Pre Spec: «el punto de retorno
intencional de *un* Bank». Un botón, sin selector que equivocar.

Son **dos capas distintas**: el Autosave guarda el trabajo en curso; `Save Bank`
copia ese estado a un punto de retorno declarado.

### FR17 — `Reload` descarta y vuelve al punto de retorno, cuantizado

Con el transporte corriendo entra en el compás, igual que un cambio de Pattern:
una sola regla en el producto.

**Sin confirmación**, coherente con el resto de la app, que no confirma nada.
Queda registrado en *Known Limitations* que es la única acción de la app que
destruye trabajo y que no hay deshacer.

Si el Bank nunca se guardó a mano, el botón **no está disponible y dice por qué**:
sin punto de retorno, volver a vacío no es volver, es borrar.

### FR18 — El formato: DTO `Codable`, JSON, un fichero por Bank

Tipos `Codable` espejo que traducen desde y hacia los POD. Los tipos de tiempo
real no ganan conformances ni cambian de forma, y el formato en disco puede
evolucionar sin arrastrar la disposición en memoria: mover un campo por razones
de tiempo real no puede romper un fichero guardado.

- Un fichero por **Bank**: su tempo y sus dieciséis Patterns.
- Un fichero de **Project**: índices, ajustes de sesión y `schemaVersion`.
- **Un Pattern vacío se serializa como una marca, no como 37 KB de ceros.** Sin
  esto, un Bank recién creado ocupa lo mismo que uno lleno.

### FR19 — `schemaVersion` desde el primer commit, sin migradores

Se escribe, se lee, y una versión desconocida cae en el camino de FR22. El punto
donde enchufar una migración queda hecho y vacío. Escribir un migrador de v1 a v2
antes de que exista v2 es probar una migración inventada.

### FR20 — Los ficheros viven en Application Support

El estado de trabajo no es un documento que el usuario administre: es la memoria
del instrumento. Fuera de la vista no se borra ni se mueve por accidente. No se
excluye de la copia de seguridad: el estado es pequeño y merece viajar.

### FR21 — Escritura atómica, y el fallo se dice en pantalla

Se escribe a un temporal y se renombra: el fichero viejo nunca se pierde a medias.
Si el guardado falla —disco lleno, permisos— la barra de estado lo dice y **no se
calla hasta que un guardado funcione**. Un Autosave silencioso que lleva diez
minutos fallando es la peor forma de perder trabajo.

### FR22 — Un fichero ilegible se aparta, y la app arranca

Fichero corrupto o `schemaVersion` desconocida: se renombra a un lado con marca de
tiempo, la app abre con un Project nuevo y lo dice en pantalla. Nunca se pierde el
fichero del usuario y nunca se queda la app sin arrancar. `workflow.md` ya prevé
este caso en *Corrupted Project State*.

### FR23 — El Project guarda los índices y los ajustes de sesión

- Último Bank, Pattern y Track seleccionados — «restaura el último Bank tras
  reiniciar», que es lo que la Pre Spec pide por su nombre.
- Fuente de reloj (`Internal` / `External`).
- Destino y fuente MIDI elegidos, **tolerando que no existan** en el arranque
  siguiente: `MIDIEndpointSelection` ya trata la desconexión como estado esperado
  y no como error.

### FR24 — Mute y solo no se guardan

Lo decide la nota del 2026-09-02 de la Pre Spec: son **mezcla**, no material, y
viven «en una capa que no se guarda con el material». El canal de cada Track sí
se guarda, porque vive en el `Cycle` y es material.

### FR25 — La pantalla `banks` deja de ser cáscara, sin cambiar de forma

Los tres cards se quedan donde están. Lo que cambia:

- La rejilla de Patterns gana un cuarto estado, **`queued`**, y una **cuenta
  atrás** hasta el compás en que entra. Sin ella, pulsar un Pattern y no oír nada
  durante hasta cuatro segundos se lee como que el botón no funciona.
- `TrackAssignments` deja de decir doce veces `pattern 01`.
- Las dos constantes `count = 16` de `BankGrid` y `PatternGrid` bajan a `Engine`
  con el tipo `Bank`, como su propia documentación promete.
- Aparecen los controles de guardado: `Save Bank`, `Reload`, copiar y borrar
  Pattern.

## Non-Functional Requirements

- **NFR1 — El camino de tiempo real no admite regresión.** Ninguna asignación,
  lock, `await` ni logging nuevos en el hilo del scheduler. Lo que se añade ahí
  es una lectura atómica más por ventana y una comparación de enteros.
  `_isPOD(Pattern.self)` sigue pasando sin cambios: el snapshot no crece.

- **NFR2 — El handoff no crece.** El Pattern armado ocupa **una** ranura más, no
  un anillo nuevo. El Project entero —256 Patterns— vive en el hilo principal y
  **no se acerca** al hilo del scheduler. La Fase 6 lo mide antes de construir
  encima, con el mismo método que `cycles_20260901` usó para su snapshot.

  > **Medido el 2026-09-07, y la puerta se pasa de largo.** `Pattern` son
  > **27 936 bytes**, el anillo de cuatro **111 744**, y con la ranura armada
  > **139 680** — no los ~148 KB y ~185 KB que esta spec estimaba antes de
  > medir; el `Pattern` real es menor que el que la rebanada de Cycles proyectó.
  >
  > **El coste de la comprobación no es medible.** Con 200 000 lecturas por
  > pasada y tres pasadas: **4 637 ns** con la ranura armada contra **4 847 ns**
  > sin ella, en la misma pasada. La versión con el cheque sale *más rápida*, lo
  > que solo puede significar que la diferencia está por debajo del ruido. Es el
  > **0,0232%** de la ventana de 20 ms, contra un presupuesto del 1%.
  >
  > **Consecuencia: FR7 no cambia.** La adopción se queda en el hilo del
  > scheduler. La alternativa que el plan tenía escrita para el caso contrario
  > —que el hilo principal publique al cruzar— **queda descartada aquí y no se
  > vuelve a abrir a mitad de fase**: harían falta tres órdenes de magnitud para
  > que el presupuesto se rozara.

- **NFR3 — El coste de guardar está medido y acotado.** Un Bank son ~600 KB de
  JSON. Presupuesto: serializar y escribir un Bank por debajo de **100 ms**, y
  **nunca en el hilo principal**. Se mide en dispositivo, no en el host.

- **NFR4 — Sin medición de jitter, y el porqué es una regla, no una excepción.**
  La medición está suspendida desde el 2026-09-02. Además, la nota del 2026-08-28
  del *Task Workflow* dice que se mide cuando cambia el **cuándo**, no el
  **cuánto**: esta rebanada **no mueve ningún instante** —cambia qué material se
  emite en un límite que ya existía— así que ni siquiera bajo la regla anterior
  habría exigido arnés. `external-clock_20260903` fue la excepción porque tocaba
  la rejilla temporal misma; ésta no la toca.

- **NFR5 — Cobertura.** `Engine` ≥90% y `MIDI` ≥80%, como siempre. El paquete
  nuevo de NFR6 entra con **≥90%**: es lógica pura con una costura de sistema de
  ficheros inyectable, y es la pieza que puede perder el trabajo del usuario.

- **NFR6 — La E/S no cabe en los paquetes que hay, y eso es un cambio de tech
  stack.** `Engine` no importa nada fuera de la stdlib y `JSONEncoder` es
  Foundation; `MIDI` es CoreMIDI y no tiene nada que ver; `App` **no se mide**, y
  meter ahí el guardado dejaría sin cobertura la pieza más delicada de la
  rebanada. Entra un paquete SPM nuevo —**`Persistence`**, que depende de `Engine`
  y de Foundation— y `tech-stack.md` lo documenta **antes** de implementarlo, como
  exige el principio 2 del workflow.

  Los DTO `Codable` y la traducción desde/hacia los POD viven en `Engine`
  (`Codable` es stdlib); el encoder, la atomicidad, el apartado de ficheros
  ilegibles y el debounce viven en `Persistence`.

- **NFR7 — El fichero se puede leer con los ojos.** JSON indentado y con claves
  estables, que es la mitad de la razón por la que `tech-stack.md` lo eligió:
  «inspeccionable, diffeable».

## Acceptance Criteria

**Criterio principal:**

> Se edita material en varios Patterns de un Bank, se cierra la app **por
> completo** y al volver a abrirla está todo: el mismo Bank, el mismo Pattern, el
> mismo Track seleccionado y el material intacto hasta el último Cycle. Con el
> transporte corriendo, pulsar otro Pattern lo hace entrar **en el compás
> siguiente** —no antes, no a media frase— y la pantalla dice cuánto falta.
> Verificado en iPad con el BeatStep Pro.

Además:

- [ ] `_isPOD(Pattern.self)` sigue pasando; `Bank` y `Project` no lo pretenden.
- [ ] Un Project recién creado tiene 16 Banks × 16 Patterns, todos vacíos, y
      elegir cualquiera de ellos no falla ni asigna en el camino del scheduler.
- [ ] Un Bank guardado y releído devuelve un árbol **idénticamente igual** al
      original, comprobado por igualdad de valor sobre los 16 Patterns.
- [ ] El cambio de Pattern cae en el primer Step del compás, comprobado sobre el
      índice y no de oído.
- [ ] Una nota con Sustain que cruza el límite recibe su note-off; ninguna queda
      colgada, comprobado en el loopback.
- [ ] Stop con un Pattern armado lo deja vigente; el Play siguiente arranca con él.
- [ ] Cambiar de Bank adopta su tempo con reloj `Internal`, y no lo adopta con
      `External`.
- [ ] `Save Bank` + editar + `Reload` devuelve exactamente el estado guardado.
- [ ] `Reload` está deshabilitado y explicado en un Bank nunca guardado.
- [ ] Copiar un Pattern a un hueco vacío produce un Pattern igual al original;
      borrarlo lo deja `empty` en la pantalla.
- [ ] Un fichero corrupto no impide arrancar: se aparta con marca de tiempo, la
      app abre vacía y lo dice.
- [ ] Una `schemaVersion` futura toma el mismo camino que un fichero corrupto.
- [ ] Un fallo de escritura se ve en pantalla y el aviso persiste hasta que un
      guardado funciona.
- [ ] Un Bank de dieciséis Patterns vacíos ocupa órdenes de magnitud menos que
      uno lleno.
- [ ] Serializar y escribir un Bank queda por debajo de 100 ms en dispositivo, y
      fuera del hilo principal.
- [ ] El Autosave escribe con el transporte corriendo sin que se oiga nada.
- [ ] Cobertura: `Engine` ≥90%, `MIDI` ≥80%, `Persistence` ≥90%.

## Known Limitations

1. **Hasta un compás de espera.** A 60 BPM son cuatro segundos entre pulsar un
   Pattern y oírlo. Es el precio de que el cambio caiga donde el oído lo espera;
   la cuenta atrás de FR25 existe para que la espera se vea.

2. **Sin Backup Project, el estado vive en el contenedor de la app.**
   Desinstalarla lo borra, y no hay forma de llevárselo a otro iPad. Es la
   limitación más grande que esta rebanada deja abierta, y su track propio.

3. **El primer cambio de esquema llega enseguida.** Las rebanadas 5 y 6 añaden
   campos al `Cycle`. Un fichero escrito por esta rebanada no lo abrirá una app
   con Note Repeater dentro hasta que alguien escriba ese migrador —y, hasta
   entonces, tomará el camino del fichero apartado, que es seguro pero pierde el
   trabajo de vista.

   > **Escrito para quien llegue con la rebanada 5, el 2026-09-07.** Lo que hay
   > que tocar está localizado y son tres sitios:
   >
   > 1. `CycleRecord` en `Packages/Engine/Sources/Engine/ProjectRecord.swift`:
   >    añadir los campos nuevos con su clave.
   > 2. `RecordRoundTripTests.testTheCycleJSONHasNoOtherKeys`, que **va a fallar
   >    y ése es su trabajo**: enumera las quince claves esperadas y no deja
   >    añadir un parámetro al `Cycle` sin decidir cómo se guarda.
   > 3. `ProjectRecord.migrated(_:)`, que hoy es `validated()` y nada más. Ahí va
   >    la primera migración de v1 a v2, y `SchemaVersionTests` tiene ya el test
   >    de la versión anterior separado del de la futura precisamente para que
   >    escribir ese migrador rompa **un** test y no dos.
   >
   > La versión anterior y la futura fallan las dos hoy, pero por razones
   > distintas: la anterior dejará de fallar con el primer migrador, la futura no
   > dejará de fallar nunca.

4. **`Reload` destruye trabajo con un toque y no hay deshacer.** Decidido sin
   confirmación por coherencia con el resto de la app. Es la única acción del
   producto con esa propiedad.

5. **Un Pattern armado no sobrevive a cerrar la app.** Es estado de ejecución y
   no se persiste. Cerrar con algo pendiente y volver deja el vigente.

6. **Los cursores de reproducción de Cycle se pierden al guardar.** Por FR8: el
   Pattern siempre vuelve por su primer Cycle activo. Quien esperara que un
   Pattern «siguiera vivo» donde lo dejó no lo encontrará así.

7. **Los 256 Patterns existen aunque estén vacíos.** En disco no pesan: FR18 los
   codifica como marca, y un Project vacío ocupa **menos de 4 KB** frente a los
   10,8 MB que ocupaba antes de la marca.

   > **Medido el 2026-09-07.** Un `Pattern` son **27 936 bytes** —menos de los
   > ~37 KB que esta spec estimaba— así que el Project lleno ronda los 7 MB
   > residentes, no 9,5. En disco, un Bank lleno son **660 KB** y uno vacío
   > **106 bytes**.

8. **El cambio de Pattern no llega a la pantalla ni al Project.** Encontrado en
   dispositivo el 2026-09-07, al cerrar el track. Lo que suena sí cambia —la
   adopción en el límite funciona y está probada sobre el índice de Step— pero
   **nadie avisa al modelo de que ocurrió**: el hueco se queda en `queued` para
   siempre, la selección no se mueve, y el siguiente giro de knob escribe el
   material del Pattern nuevo en el hueco del viejo.

   Cambiar de Bank no lo tiene porque mueve la selección en el acto. Falta el
   equivalente de `CyclePlaybackClock` para «qué Pattern está vigente». Track
   propio en el registro.

## Out of Scope

- Backup Project: exportar e importar por la app Files.
- MIDI Program Change y encadenado de Patterns.
- Disparar Patterns o Banks desde el controlador.
- Nombres editables de Bank o Pattern.
- Copiar, borrar o duplicar Banks.
- Mover material entre Tracks o entre Patterns con granularidad menor que el
  Pattern.
- Deshacer.
- Migradores de esquema (el punto de enchufe sí; los migradores no).
- iCloud y sincronía entre dispositivos.
