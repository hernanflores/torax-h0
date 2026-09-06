# Plan — Ctrl All: un knob mueve los doce Tracks

Sigue el `workflow.md`: tests antes de implementación, un commit por tarea, git
note por commit y checkpoint verificado al cerrar cada fase.

**El orden va de dentro afuera**, como en `temp-parameters`: primero la nota de
la desviación, que el Task Workflow §8 exige antes de implementar porque Ctrl All
no existe en la Pre Spec; después el remapeo de knobs, que abre el preset una
sola vez; luego el offset como valor puro en `Engine`; el gesto en
`ControlInput`, incluida su convivencia con Temp; y por último la pantalla. Al
cerrar la Fase 4 el gesto ya funciona con el controlador aunque la pantalla no lo
distinga todavía.

**La Fase 4 es la que tiene el riesgo de diseño**, no la 3: `ControlInput` pasa
de un modificador con estado a dos que se pisan, y FR13 es la única regla del
track que no se puede escribir sin tocar código que ya funciona.

**Ninguna fase mide jitter** (NFR6, suspendido el 2026-09-02) **ni coste del hilo
de control** (NFR4, decidido sin número).

**Nada nuevo cruza al hilo del scheduler** (NFR2). Si una tarea empuja hacia
`LookAheadScheduler`, `MusicalTimeline` o `SchedulerThread`, es la señal de que el
offset se está filtrando al camino de timing: parar y revisar el diseño antes de
seguir.

## FASE 1: LA DESVIACIÓN QUEDA ESCRITA [checkpoint: 7255180]

- [x] Task: Anotar Ctrl All en la Pre Spec y en `product.md` (NFR7) — `7255180`
  - [x] Nota fechada 2026-09-05 en `Pre Spec Torax H-0.md`: qué es Ctrl All, que
        se mantiene [step 14] y que **no escribe en el Pattern**.
  - [x] Dejar dicho lo que un lector daría por supuesto al revés, que es lo que
        separa este gesto de Temp: **desplaza, no iguala**. Las diferencias entre
        Tracks y entre Cycles sobreviven, y por eso la base se guarda por Track
        *y* por Cycle.
  - [x] Anotar el alcance completo: los doce Tracks, muteados incluidos (FR3), y
        las vías táctiles congeladas (FR11), que es un requisito que Temp no
        tiene.
  - [x] Fijar el vocabulario: «Ctrl All», no «global», «all tracks» ni «macro».
  - [x] Nota fechada en `conductor/product.md`, junto a la de Temp del
        2026-09-04, en la sección *Interaction Model*.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 2: EL PRESET SE REESCRIBE ENTERO [checkpoint: 3240033]

- [x] Task: Delay al 76 y Probability al 78 (FR20) — `60f0063`
  - [x] Tests (Red): CC 76 mueve Delay y CC 78 mueve Probability; ningún otro
        parámetro cambia de CC.
  - [x] Implementación (Green): el intercambio en `assignments` de
        `beatStepPro`. Es un diccionario explícito: no hay aritmética que tocar.
- [x] Task: El Cycle en edición pasa al knob 13, CC 82 (FR20) — `01e6549`
  - [x] Tests (Red): CC 82 mueve el Cycle en edición; **CC 79 se ignora en
        silencio**, con el mismo criterio que un CC sin asignar.
  - [x] Tests (Red): con un `knobBlock` distinto del por defecto, el Cycle sigue
        al bloque — el número no queda clavado al 82.
  - [x] Implementación (Green): `editingCycleController` deja de ser
        `knobBlock.number + 9` y pasa a ser un dato del mapeo, como `padBlock`.
  - [x] Documentar el porqué: un desplazamiento fijo escondido en una propiedad
        calculada es lo que hacía que mover un knob fuera un cambio de aritmética
        en vez de un cambio de tabla.
- [x] Task: El preset y su justificación (FR17, FR20) — `3240033`
  - [x] Tests (Red): `PresetMappingTests` compara JSON, README y `ControlMapping`
        con los números nuevos, y falla si uno de los tres se queda atrás.
  - [x] `torax-h0.beatstep-pro.json`: los tres knobs, el CC 79 libre y el **step
        14 (CC 115) como Ctrl All**. Subir `version`/`updated`.
  - [x] `preset/README.md`: la tabla de knobs, la de step buttons, y **reescribir
        el párrafo del rango 70–79** en los dos sitios donde aparece la
        justificación, con nota fechada 2026-09-05 que diga por qué decía 70–79 y
        cuál era la regla de verdad.
  - [x] Anotar que el preset declara Ctrl All antes de que la app lo haga: la
        Fase 4 cierra esa ventana.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 3: EL OFFSET COMO VALOR DE DOMINIO

- [x] Task: `CtrlAllOffset` — la base de los doce y el desplazamiento acumulado (FR2, FR3, FR7, FR18, NFR3) — `b165a2e`
  - [x] Tests (Red): capturar un parámetro guarda su base **por Track y por Cycle
        activo**; capturarlo dos veces no re-guarda la base; un parámetro no
        tocado no aparece en el snapshot.
  - [x] Tests (Red): los Cycles inactivos no se capturan ni se tocan.
  - [x] Tests (Red): dos parámetros en el mismo hold acumulan offsets
        independientes.
  - [x] Tests (Red): el tipo acepta cualquier caso de `TrackParameter` — barrido
        sobre `allCases`, sin enumerar los nueve.
  - [x] Tests (Red): el snapshot vacío es el estado de reposo y restaurar desde él
        no cambia nada.
  - [x] Implementación (Green): `CtrlAllOffset` en `Packages/Engine`, valor puro
        con base por `(parámetro, Track, Cycle)` y offset por parámetro.
  - [x] Documentar **por qué guarda base y offset por separado y no el valor
        superpuesto**: es lo único que hace la ida y vuelta exacta cuando un Track
        topa (FR4).
  - [x] `Engine` sigue sin importar nada más allá de la stdlib.
- [x] Task: Aplicar el offset al Pattern, acotando sin destruir (FR2, FR4, FR6) — `9130a9a`
  - [x] Tests (Red): un delta desplaza el mismo parámetro en los doce Tracks y en
        todos sus Cycles activos, **conservando las diferencias** — Pulses 4 y 9
        siguen a distancia 5.
  - [x] Tests (Red): un Track topado no arrastra a los demás; el resto sigue
        moviéndose.
  - [x] Tests (Red): la ida y vuelta es exacta — subir hasta el tope y bajar el
        mismo número de clics devuelve todos los valores de partida, y el Track
        topado vuelve a **su** valor exacto en cuanto el desplazamiento reentra
        en su rango — no en el primer clic de vuelta, que es lo que el plan
        afirmaba antes del 2026-09-05 y era falso.
  - [x] Tests (Red): Rotate envuelve con el `steps.count` de **cada** Cycle; dos
        Tracks con Steps 16 y 12 se desfasan entre sí bajo el mismo offset.
  - [x] Tests (Red): un Track muteado recibe el offset igual que los demás (FR3)
        — el offset no consulta la máscara.
  - [x] Implementación (Green): apoyarse en `Cycle.setting(_:to:)` y
        `Cycle.applying(_:to:)`; **no duplicar la aritmética de parámetros** ni la
        del envolvimiento de Rotate.
  - [x] Documentar por qué el valor se recalcula desde la base y nunca desde el
        valor ya escrito.
- [x] Task: El tope del offset acumulado (FR5, FR6) — `ac84cce`
  - [x] Tests (Red): cuarenta clics contra el extremo y **un** clic de vuelta
        mueven algo; el offset no guardó los cuarenta.
  - [x] Tests (Red): el tope sale del **recorrido real de las bases
        capturadas**, no del ancho del parámetro ni del Track seleccionado — un
        Track con recorrido restante sigue moviéndose mientras otro está topado, y
        el tope es distinto en cada sentido si las bases están repartidas.
  - [x] Tests (Red): Rotate **no** se acota; su offset crece libre y sigue
        produciendo movimiento indefinidamente.
  - [x] Tests (Red): el tope no rompe la restauración — con el offset saturado,
        soltar devuelve exactamente la base.
  - [x] Implementación (Green): los extremos por parámetro salen de
        `TrackParameter.displacementRange`, leídos de los `validRange` que cada
        tipo ya declara; el tope se calcula contra las bases en `CtrlAllOffset`.
  - [x] Documentar el porqué con el síntoma delante: sin tope, un knob queda
        muerto durante decenas de clics, que es lo que la nota del 2026-08-28
        enseñó a reconocer como avería.
- [~] Task: Restaurar el Pattern entero (FR8, FR9)
  - [ ] Tests (Red): restaurar devuelve **cada** Cycle de **cada** Track a su
        valor propio.
  - [ ] Tests (Red): un parámetro no girado conserva su valor distinto por Track
        y por Cycle antes, durante y después.
  - [ ] Tests (Red): restaurar **no toca** `cursor`, `editing`, `activeCount`,
        pool, marco tonal, canal, `padOctaveShift` ni mute/solo — aunque los
        cursores hayan avanzado durante el hold.
  - [ ] Tests (Red): el Pattern completo antes y después de un hold es igual salvo
        los cursores (AC7) — comparación del valor entero, no campo a campo.
  - [ ] Cobertura `Engine` ≥90%.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 4: EL GESTO EN EL CONTROLADOR

- [ ] Task: [step 14] mantiene y suelta (FR1, FR12, FR14)
  - [ ] Tests (Red): CC 115 con 127 entra en Ctrl All y **no publica por sí
        solo**; con 0 sale y publica una vez el Pattern restaurado.
  - [ ] Tests (Red): con Ctrl All activo, girar Velocity publica un Pattern con
        los doce desplazados; soltar publica el Pattern base. Girar sin Ctrl All
        sigue escribiendo permanente en el Track seleccionado.
  - [ ] Tests (Red): un giro nulo no publica; un giro donde **el Track
        seleccionado topa pero otros se mueven sí publica** (FR12) — el caso que
        separa esta regla de la de Temp.
  - [ ] Tests (Red): comportamiento idéntico con el transporte parado — el gesto
        no consulta el transporte.
  - [ ] Implementación (Green): `ctrlAllModifierIndex = ControlMapping.controlsPerFamily - 3`
        junto a los otros tres, despachado en `stepButton(_:value:)` antes de la
        selección.
- [ ] Task: Con Ctrl All hundido, Ctrl All manda (FR10)
  - [ ] Tests (Red): step buttons 1–12 no cambian de Track; los modificadores 15 y
        16 no publican gesto de mezcla; el knob del Cycle no lo mueve; los
        dieciséis pads no tocan el pool.
  - [ ] Tests (Red): los knobs de parámetro **sí** responden, y son los únicos.
  - [ ] Implementación (Green): extender el corte que Temp ya tiene en
        `receive(_:)`, **en un solo sitio**. Repartirlo por rama dejaría cuatro
        sitios donde olvidarlo.
- [ ] Task: Temp y Ctrl All se ceden el paso (FR13)
  - [ ] Tests (Red): con 13 y 14 hundidos, los giros son Temp — el 14 no
        interfiere.
  - [ ] Tests (Red): soltar el 13 con el 14 hundido **restaura el Temp,
        publica**, y el giro siguiente es Ctrl All con base tomada del Pattern ya
        restaurado — no de la que Temp tenía.
  - [ ] Tests (Red): soltar el 14 antes que el 13 no deja nada pegado ni restaura
        el Temp por adelantado.
  - [ ] Tests (Red): el orden inverso de pulsación —14 y luego 13— llega al mismo
        sitio.
  - [ ] Implementación (Green): un solo punto de decisión sobre qué modificador
        está al mando; documentar que ninguno hereda el estado del otro.
- [ ] Task: Las vías táctiles que escriben callan (FR11)
  - [ ] Tests (Red): `selectTrack`, `setChannel`, `setChannel(forTrack:)`,
        `setFrame` y `setActiveCycleCount` devuelven `false` y no publican durante
        el hold.
  - [ ] Tests (Red): fuera del hold las cinco siguen funcionando exactamente
        igual.
  - [ ] Tests (Red): el caso que motiva la regla — `setActiveCycleCount` durante
        el hold no puede dejar un Cycle con offset y sin base.
  - [ ] Implementación (Green): un guard compartido; documentar que Temp no tiene
        este requisito y por qué Ctrl All sí (una escritura permanente colada
        dentro de un gesto que promete no escribir).
- [ ] Task: Reconexión y modificadores atascados (FR15)
  - [ ] Tests (Red): `releaseModifiers()` con Ctrl All hundido restaura y publica
        una vez.
  - [ ] Tests (Red): con Ctrl All y Temp hundidos a la vez, `releaseModifiers()`
        deja el Pattern base y publica sin duplicar la restauración.
  - [ ] Tests (Red): sin nada superpuesto no publica.
  - [ ] Cobertura `MIDI` ≥80%.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 5: LA PANTALLA ENSEÑA QUE ES GLOBAL

- [ ] Task: `isCtrlAllActive` y el distintivo (FR16)
  - [ ] Tests (Red): `isCtrlAllActive` es cierto entre la pulsación y la soltada,
        y falso el resto del tiempo, incluido el hold en el que no se giró nada.
  - [ ] Tests (Red): con Temp al mando (FR13), `isTempActive` y `isCtrlAllActive`
        no se contradicen — la pantalla puede elegir cuál enseñar sin desempatar
        por su cuenta.
  - [ ] Implementación (Green): lectura pública en `ControlInput`, sin vía para
        accionar el gesto (la táctil está fuera de alcance).
  - [ ] `App`: el valor grande transitorio de `mvp-ring-feedback` con un
        distintivo **propio y distinguible del de Temp**, siguiendo
        `Brutalist.swift` y `Typography.swift`.
  - [ ] Verificar en simulador que el distintivo se lee y no se confunde con el de
        Temp (`xcrun simctl io … screenshot`). Lo que el simulador no puede: el
        gesto mismo, que exige controlador.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 6: EN EL DISPOSITIVO

- [ ] Task: Verificación en iPad con BeatStep Pro (AC1–AC12, AC14, AC15)
  - [ ] Reconfigurar los encoders en MIDI Control Center con el preset exportado
        nuevo, en `Relative #2` — que sigue siendo la condición de que nada salte
        a su extremo.
  - [ ] El knob 7 mueve **Delay** y el knob 9 mueve **Probability**, no al revés.
  - [ ] El knob 13 mueve el Cycle en edición y el **knob 10 no hace nada**.
  - [ ] Confirmar que el step 14 es **momentary** y no toggle — el supuesto de
        FR1, heredado del precedente del 13.
  - [ ] Mantener [step 14] y girar Velocity: suben los doce conservando el
        balance; soltar lo devuelve. Sin notas colgadas.
  - [ ] Un giro largo contra el tope y vuelta: el knob no queda muerto (FR5).
  - [ ] Rotate global con Tracks de Steps distintos: se desfasan y vuelven.
  - [ ] 13 y 14 a la vez, soltando el 13 primero (FR13), con el transporte
        corriendo.
  - [ ] `releaseModifiers()`: desenchufar y reconectar con el botón hundido no
        deja el offset puesto.
  - [ ] Con el transporte parado (FR14).
  - [ ] Registrar el resultado en `device-verification.md` del track. **Sin
        medición de jitter** (NFR6).
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
