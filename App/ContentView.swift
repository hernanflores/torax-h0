import CoreMIDI
import Engine
import MIDI
import SwiftUI

/// El contenedor de la app: chrome compartido más el módulo que se esté mirando.
///
/// **Ya no es una pantalla.** Hasta el 2026-09-06 este tipo era la pantalla del
/// Track y, de paso, la barra, las pestañas y el conmutador. El rediseño reparte
/// esos papeles: la barra es `AppChrome`, la navegación es `ModuleNavigation`, y
/// cada módulo es su propia vista. Aquí queda lo único que no puede vivir en
/// ninguno de los tres — **el estado que todos comparten**.
///
/// **El controlador es el instrumento; la pantalla es el espejo**
/// (`product-guidelines.md`). Sin controlador conectado la app es de solo
/// lectura y transporte: los anillos y el playhead siguen viéndose, porque son
/// estado y no edición, y no se abre ninguna vía táctil para suplir un knob
/// ausente.
///
/// > **La medición de jitter ya no tiene panel**, y lleva sin tenerlo desde
/// > antes de este track: quedaba solo el enganche por argumento de lanzamiento.
/// > La documentación de este tipo decía que «el panel sigue debajo», que era
/// > falso. El modelo se conserva —la medición está suspendida, no retirada
/// > (`workflow.md`, 2026-09-02)— y su única puerta es el argumento.
struct ContentView: View {

    /// **El modelo lo posee la escena desde el 2026-09-07**, no esta vista.
    ///
    /// Vivía aquí, y la razón de moverlo es el ciclo de vida: al pasar la app a
    /// segundo plano hay que forzar la escritura pendiente del Autosave (FR14), y
    /// `scenePhase` se observa en `App`, no en una vista de dentro.
    ///
    /// **Lo que esta nota decía sigue siendo cierto**: cambiar de módulo
    /// recompone el cuerpo y este objeto no se vuelve a crear, así que el
    /// transporte sigue corriendo y el playhead está donde tiene que estar al
    /// volver. Ahora lo garantiza estar un nivel más arriba.
    let model: TransportModel

    /// Conservado sin puerta en la interfaz. Ver la nota del tipo.
    @State private var jitter = JitterMeasurementModel()

    /// Qué familia lleva el acento de la lectura grande.
    ///
    /// > **Ya no hay tabs que elegirla.** El handoff enseña los tres cards de
    /// > familia a la vez, así que la regla «el giro cambia el tab» se queda sin
    /// > tab que cambiar. Lo que sobrevive de ella es lo que valía la pena: la
    /// > lectura sigue a la mano, no al revés. Con los tres cards visibles esto
    /// > pasa a decidir solo el acento de la lectura grande, y en la Fase 2
    /// > pasará también a resaltar el card correspondiente (FR12).
    ///
    /// **Empieza en `shape` y no vacío** porque la lectura grande persiste el
    /// último parámetro tocado (FR12): al arrancar todavía no hay ninguno, y un
    /// hueco en el bloque más grande de la pantalla es peor que un valor cierto.
    @State private var family: ParameterFamily = .shape

    /// Qué módulo se está mirando.
    @State private var module: Module = .track

    /// El último parámetro que se movió, para que la lectura grande no se vacíe
    /// (FR12).
    ///
    /// **Es una copia y no una lectura del modelo** porque el modelo solo guarda
    /// lo *transitorio*: `transientChange` vuelve a `nil` a los 1,6 segundos, que
    /// es lo que hace que el acento se apague. Guardar aquí lo último visto es lo
    /// que separa «se apagó el acento» de «se borró el valor».
    @State private var lastChange: ParameterChange?

    var body: some View { content }

    private var content: some View {
        VStack(spacing: 0) {
            AppChrome(model: model, module: module)

            ModuleNavigation(module: $module)

            // **El hueco se mide aquí, debajo del chrome, y no en la pantalla
            // entera.**
            //
            // > **Estuvo arriba del todo restando 64 puntos a ojo**, y ese número
            // > venía de cuando el chrome era una sola fila dentro del mismo
            // > relleno. Con la barra y la navegación fuera, restaba de menos y el
            // > anillo se calculaba contra una altura que no tenía: el usuario lo
            // > vio antes que el código —«el anillo no creció»— porque el efecto
            // > era un anillo pequeño, no un error.
            //
            // Va **fuera** del `ScrollView` a propósito. Dentro no serviría: el
            // `ScrollView` propone altura infinita a su contenido, que es justo
            // lo que el anillo no puede usar para decidir su lado.
            GeometryReader { area in
                ScrollView {
                    screen(
                        width: area.size.width - Self.screenPadding.horizontal * 2,
                        height: area.size.height - Self.screenPadding.vertical * 2
                    )
                    .padding(.horizontal, Self.screenPadding.horizontal)
                    .padding(.vertical, Self.screenPadding.vertical)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.background)
        .foregroundStyle(Palette.text)
        .onAppear { jitter.startIfRequestedByLaunchArguments() }
        // **La lectura sigue a la mano.** Mover un knob de otra familia cambia
        // el acento de la lectura grande en vez de enseñar el valor con un color
        // que no le corresponde: la pantalla es el espejo del controlador.
        //
        // > Esto era «el giro manda sobre el tab», cuando había tabs. Los tabs
        // > se fueron con el rediseño —el handoff enseña las tres familias a la
        // > vez— y la regla se queda con lo que valía de ella.
        .onChange(of: model.transientChange) { _, change in
            guard let change else { return }
            family = change.parameter.family
            lastChange = change
        }
    }

    @ViewBuilder
    private func screen(width: CGFloat, height: CGFloat) -> some View {
        switch module {
        case .track: trackScreen(width: width, height: height)
        case .scale: scaleScreen
        case .midi: midiScreen
        case .banks: banksScreen
        }
    }

    private var banksScreen: some View {
        BanksScreen(model: model)
    }

    // MARK: - Las cuatro pantallas

    /// La pantalla `track`: el patrón, su lectura y la franja de doce.
    ///
    /// **Aquí no se edita ningún parámetro generativo con el dedo** (FR14), y no
    /// es una aspiración sino algo comprobable. La pantalla entera tiene
    /// exactamente cuatro escrituras táctiles, auditadas el 2026-09-06:
    ///
    /// | Gesto | Escribe | Por qué se permite |
    /// |---|---|---|
    /// | Pastilla de Track | `selectTrack` | Elegir qué se mira, no qué suena |
    /// | `m` | `toggleMute` | Mezcla, no material (FR13) |
    /// | `s` | `toggleSolo` | Mezcla, no material (FR13) |
    /// | Celda de Cycle | `setActiveCycleCount` | Estructura, y su única vía |
    ///
    /// `RingStackView`, `TrackReadout`, `ParameterFamilyCard` y `TonalCard` no
    /// tienen **ni un solo** `Button`, `gesture` ni `onTapGesture`: son texto y
    /// dibujo. Steps, Pulses, Rotate, Division y los cinco de Groove no tienen
    /// ninguna vía táctil, ni siquiera sin controlador conectado — un slider
    /// provisional para suplir un knob ausente es el antipatrón que
    /// `product-guidelines.md` nombra.
    ///
    /// **Y sin hardware esta pantalla no cambia** (FR29). No hay una sola rama
    /// aquí que dependa de que haya controlador o destino: los anillos, los doce
    /// playheads, la lectura grande, los tres cards y la franja se dibujan igual
    /// con el cable puesto y sin él, porque **son estado y no edición**.
    ///
    /// Lo que sí cambia está donde tiene que estar: el punto y el texto de la
    /// barra, y los dos selectores de la pantalla `midi`. Auditado el 2026-09-06
    /// buscando `isReadOnly`, `canPlay`, `hasEndpoint` y `outputUnavailable` en
    /// todo `App`: ninguno aparece en las vistas de esta pantalla.
    ///
    /// > **La consecuencia práctica es que las capturas de este track valen.**
    /// > El simulador no tiene MIDI ninguno, así que todo lo que se ha verificado
    /// > en él es exactamente el estado sin hardware — y se ve completo.
    private func trackScreen(width: CGFloat, height: CGFloat) -> some View {
        // **El escenario recibe una altura, no la deduce.** Antes cada columna
        // se medía por su cuenta y el alto total salía de la más alta de las
        // dos, así que la franja de Tracks caía fuera de la pantalla cada vez
        // que la columna derecha crecía un card. Ahora el reparto es explícito:
        // esto es lo que queda al quitar la franja, y las dos columnas se atan a
        // ello.
        let stageHeight = max(height - Self.reservedBelowStage, Self.minimumStageHeight)

        return VStack(alignment: .leading, spacing: Self.trackScreenSpacing) {
            stage(width: width, height: stageHeight)
            TrackSelectorView(
                selected: model.selectedTrackIndex,
                hasMaterial: model.tracksWithMaterial,
                accent: Palette.accent(for: family),
                onSelect: { model.selectTrack($0) },
                mix: model.mix,
                onToggleMute: { model.toggleMute($0) },
                onToggleSolo: { model.toggleSolo($0) }
            )
        }
    }

    private var scaleScreen: some View {
        ScaleScreen(model: model)
    }

    private var midiScreen: some View {
        MidiScreen(model: model)
    }

    // MARK: - La composición apaisada

    /// **Los anillos a la izquierda, todo lo demás a su derecha** (FR14).
    ///
    /// Sustituye a la columna vertical única con el anillo arriba, que era lo
    /// mínimo para operar de la rebanada 1 y no la pantalla del producto.
    ///
    /// **Es lo que hace posible que el valor grande no tape nunca los anillos**
    /// (FR3). Hoy el valor se dibuja *sobre* el patrón y la guía obliga a que el
    /// patrón permanezca visible bajo él; con dos regiones que no se solapan la
    /// regla se cumple sin excepción, y deja de ser algo que hay que recordar.
    ///
    /// **El anillo se lleva la columna ancha**, que es lo que
    /// `product-guidelines.md` implica: lo expresivo es el material musical y el
    /// ancho se reparte según eso, no según cuánto texto hay que poner. Lo que se
    /// lee de un vistazo es la *forma* —cuáles tienen material, cuál está
    /// elegido, por dónde va el tiempo—; el detalle está en el panel.
    ///
    /// > La versión anterior de esta nota decía que el anillo ocupaba «un quinto
    /// > del ancho» y que eso era intencional. Se quedó de la época del handoff y
    /// > contradecía al reparto real, que hace justo lo contrario desde el
    /// > 2026-09-01. Ver `columns(in:)`.
    private func stage(width: CGFloat, height: CGFloat) -> some View {
        let columns = Self.columns(in: width)
        // **El anillo es cuadrado, así que lo acota la dimensión más corta.**
        // Con solo el ancho crecía hasta empujar el selector fuera de la
        // pantalla, y es un control: quedarse sin verlo es peor que un anillo
        // algo menor.
        //
        // `height` ya es la altura del escenario, no la de la pantalla: quien la
        // calcula es `trackScreen`, restando una sola vez lo que va debajo.
        let side = min(columns.rings, height)
        // **Lo que el anillo no usa no se queda muerto.** Cuando manda la altura,
        // el anillo sale más estrecho que su columna y esa diferencia era un
        // hueco vacío a la izquierda de la lectura. Se la queda la lectura, que
        // es texto que envuelve: `product-guidelines.md` pide que el valor grande
        // no se corte, y ancho de más es exactamente lo que evita partirlo.
        let slack = max(columns.rings - side, 0)

        return HStack(alignment: .top, spacing: Self.gutter) {
            rings
                .frame(width: side, height: side)

            // **La lectura no se ata al lado del anillo.** Lo estuvo, y con los
            // tres cards dentro el contenido pasó a ser más alto que el cuadrado
            // del anillo: el `VStack` desbordaba su marco y los cards se dibujaban
            // por encima de la navegación y por debajo de la franja de Tracks.
            // Con altura natural, el escenario mide lo que mida el más alto de
            // los dos y el `ScrollView` que ya lo envuelve se ocupa del resto.
            // **Atada a la altura del escenario, con su `Spacer` absorbiendo la
            // holgura.** Sin marco crecía por su cuenta y arrastraba la franja
            // de Tracks fuera de la pantalla; con marco, lo que sobra queda
            // debajo del último card y lo que falta se ve, en vez de empujar.
            readout
                .frame(width: columns.readout + slack, height: height, alignment: .top)
        }
    }

    /// **Solo lo que va debajo del escenario, y nada más.**
    ///
    /// > **Restaba de más en dos sitios, y el anillo lo pagaba.** Corregido el
    /// > 2026-09-06, con el usuario señalando que el anillo no había crecido:
    /// >
    /// > - Descontaba el chrome, que ya no está dentro de este hueco. El
    /// >   `GeometryReader` mide ahora lo que queda **debajo** de la barra y la
    /// >   navegación, así que restarlo otra vez eran 116 puntos contados dos
    /// >   veces.
    /// > - Y descontaba la fila de Cycles —68 puntos— que se mudó a la columna
    /// >   derecha en esta misma fase y ya no va debajo del escenario.
    /// >
    /// > Entre las dos le quitaban al anillo unos 184 puntos de lado que no
    /// > usaba nadie.
    ///
    /// **Es una suma escrita como suma, y no un número.** Antes fue un literal
    /// —260, luego 324— y eso lo dejó mintiendo dos veces el mismo día. Ahora ha
    /// vuelto a mentir siendo una suma, por sumar de más: la lección no es
    /// escribirla como suma, es **restar solo lo que de verdad está debajo**.
    static let reservedBelowStage: CGFloat =
        trackScreenSpacing + selectorRowHeight + mixRowSpacing + mixRowHeight

    /// El relleno de la pantalla dentro del hueco.
    static let screenPadding: (horizontal: CGFloat, vertical: CGFloat) = (20, 16)
    /// Por debajo de esto el anillo deja de poder contarse, así que antes de
    /// encogerlo más se prefiere que la pantalla haga scroll.
    static let minimumStageHeight: CGFloat = 320
    /// Entre el escenario y el selector.
    static let trackScreenSpacing: CGFloat = 24
    /// Una pastilla de Track: solo su número desde el 2026-09-02.
    static let selectorRowHeight: CGFloat = 44
    /// Entre la pastilla y su par M/S, que va pegado a ella.
    static let mixRowSpacing: CGFloat = 6
    /// El par M/S debajo de cada pastilla, desde el 2026-09-02.
    static let mixRowHeight: CGFloat = 32

    /// El hueco entre columnas.
    static let gutter: CGFloat = 24

    /// El reparto horizontal.
    ///
    /// > **Aquí el handoff se contradice consigo mismo, y gana la app.** El mock
    /// > da al anillo 190 puntos de 924 —un quinto— y el resto a la lectura. Esas
    /// > proporciones se dibujaron para **cinco** anillos; con doce, un quinto del
    /// > ancho deja cada banda en unos 8 puntos y el mapa deja de poder
    /// > contarse. El anillo es lo que la pantalla existe para enseñar
    /// > —`product-guidelines.md`: lo expresivo es el material musical— así que
    /// > se lleva el ancho grande y la lectura se queda con el estrecho.
    /// >
    /// > **Decidido con el usuario el 2026-09-01**, viendo la pantalla:
    /// > «la columna central es demasiado grande; el ancho del anillo debería ser
    /// > el ancho actual de la columna central».
    ///
    /// La lectura y los tabs se calculan primero y **el anillo se queda con lo
    /// que sobra**: así, en un iPad más ancho, el espacio de más va a donde se
    /// nota —más separación entre bandas— y no a estirar un texto que ya cabía.
    /// El reparto horizontal: **68 % para el patrón, 32 % para la lectura**
    /// (FR9).
    ///
    /// > **Los números son del brief y coinciden con lo que ya se había
    /// > decidido.** El handoff anterior daba al anillo un quinto del ancho —una
    /// > proporción dibujada para **cinco** anillos— y con doce cada banda
    /// > quedaba en unos 8 puntos: el mapa dejaba de poder contarse. El
    /// > 2026-09-01 se invirtió con el usuario delante de la pantalla. El brief
    /// > de iPadOS pide 68 / 32, que es la misma decisión con un número exacto
    /// > detrás, así que aquí solo se sustituyen los mínimos y máximos por la
    /// > proporción.
    ///
    /// **Ya no hay tercera columna.** Eran los tabs de familia, que el rediseño
    /// retira porque el handoff enseña las tres a la vez.
    static func columns(in total: CGFloat) -> (rings: CGFloat, readout: CGFloat) {
        let usable = total - gutter
        let rings = usable * 0.68
        return (rings, usable - rings)
    }

    /// La columna izquierda: los doce anillos y nada más.
    private var rings: some View {
        // `TimelineView` redibuja al ritmo de la pantalla, pero **la posición no
        // la decide él**: cada fotograma vuelve a preguntar al modelo, que la
        // resuelve contra el origen que publicó el bucle del scheduler. El
        // movimiento deriva del reloj musical; lo que el temporizador decide es
        // cuándo repintar, no dónde está el tiempo.
        //
        // > **Y de aquí sale cómo hay que medir la carga visual** (NFR2). Lo que
        // > hace que el `Canvas` se repinte no es el `TimelineView` por sí solo:
        // > es que los playheads cambien de fotograma a fotograma. Con el
        // > transporte parado, sus entradas son idénticas y SwiftUI no vuelve a
        // > dibujar aunque el temporizador siga latiendo — comprobado con una
        // > sonda: menos de 30 ejecuciones del `Canvas` en 8 segundos, incluso
        // > forzando `paused: false`.
        // >
        // > Consecuencia: **el arnés por sí solo no produce carga visual
        // > ninguna.** Corre su propio scheduler en una tarea aparte y no toca
        // > `TransportModel`, así que los anillos se quedan quietos y lo que se
        // > mediría es el timing con la pantalla congelada. La medición de la
        // > Fase 6 exige el transporte de la app corriendo *a la vez* que el
        // > arnés; está escrito en `device-verification.md`.
        TimelineView(.animation(paused: !model.isPlaying)) { _ in
            RingStackView(
                stack: model.rings,
                selected: model.selectedTrackIndex,
                playheads: model.playheads,
                audible: model.audibleTracks
            )
        }
        .padding(16)
        .brutalistPanel()
    }

    /// La columna derecha: la lectura grande y los cards.
    ///
    /// **Sin panel envolvente.** Cada card lleva el suyo; encuadrar además el
    /// conjunto pondría un borde alrededor de tres bordes.
    private var readout: some View {
        // **El espaciado de esta columna es lo que decide el tamaño del
        // anillo**, y conviene saberlo antes de tocarlo. El escenario mide lo
        // que mida el más alto de los dos lados; con la columna más alta que el
        // cuadrado del anillo, cada punto que se le quita aquí es un punto que
        // el anillo puede crecer, y cada punto que se le añade sale de él.
        VStack(alignment: .leading, spacing: 6) {
            TrackReadout(
                change: model.transientChange,
                lastChange: lastChange,
                resting: FamilyReadout(
                    track: model.track, family: family, gesture: model.gesture),
                family: family
            )

            ParameterFamilyCard(
                family: .shape,
                entries: entries(for: .shape),
                isActive: family == .shape
            )

            ParameterFamilyCard(
                family: .groove,
                entries: entries(for: .groove),
                isActive: family == .groove
            )

            TonalCard(
                frame: model.frame,
                pool: model.poolNames,
                isActive: family == .tonal
            )

            CycleStrip(
                activeCount: model.activeCycleCount,
                editing: model.editingCycle,
                inCourse: { model.cycleInCourse },
                accent: Palette.accent(for: family),
                onActiveCountChange: { model.setActiveCycleCount($0) }
            )

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Los parámetros de una familia con su valor.
    ///
    /// **La lista y el orden los da `Engine`**, no la vista: `TrackParameter`
    /// declara los nueve y en qué orden se leen, que es el del dominio y no el de
    /// los knobs — el preset los reordenó el 2026-09-05 y la pantalla no siguió,
    /// a propósito.
    private func entries(for candidate: ParameterFamily) -> [(label: String, value: String)] {
        TrackParameter.allCases
            .filter { $0.family == candidate }
            .map { ($0.description, $0.value(in: model.track)) }
    }

    // MARK: - El patrón
}
