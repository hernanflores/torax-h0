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

    /// **El modelo lo posee el contenedor, y ahí está FR8.** Cambiar de módulo
    /// recompone el cuerpo, pero este objeto no se vuelve a crear: el transporte
    /// sigue corriendo y el playhead está donde tiene que estar al volver.
    /// Navegar no toca el reloj porque navegar no llega hasta aquí.
    @State private var model = TransportModel()

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

    var body: some View {
        // **El ancho se lee una vez, arriba.** La altura del escenario depende
        // del ancho —el anillo es cuadrado y llena su columna— y un
        // `GeometryReader` dentro del `ScrollView` no puede dar las dos cosas
        // sin quedar circular: el `ScrollView` pregunta la altura al contenido y
        // el contenido la sacaría del `ScrollView`.
        GeometryReader { screen in
            content(width: screen.size.width - 64, height: screen.size.height - 64)
        }
    }

    private func content(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            AppChrome(model: model, module: module)

            ModuleNavigation(module: $module)

            ScrollView {
                screen(width: width, height: height)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
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

    /// **Provisional, y marcada como tal.** La construye la Fase 5; hasta
    /// entonces la entrada de navegación lleva a un módulo que existe y todavía
    /// no se puede usar, que es exactamente lo que el borde discontinuo del
    /// lenguaje visual significa.
    ///
    /// El signo está aquí y no en la navegación a propósito: FR7 pide que las
    /// cuatro entradas se vean iguales porque las cuatro pantallas existen. Lo
    /// que falta es el contenido de una, y se dice donde falta.
    private var banksScreen: some View {
        Text(display: "banks")
            .font(Typography.sectionTitle)
            .frame(maxWidth: .infinity, minHeight: 240)
            .brutalistUnavailable(radius: Brutalist.radiusLarge)
    }

    // MARK: - Las dos pantallas

    private func trackScreen(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            stage(width: width, height: height)
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
        TonalView(
            frame: model.frame,
            pool: model.track.pool,
            surface: model.surface,
            onFrameChange: { model.setFrame($0) }
        )
    }

    /// La pantalla `3 · MIDI`: por dónde sale cada Track.
    ///
    /// **El canal vivía en la pantalla Track y no le correspondía.** Es ruteo,
    /// no material generativo: qué instrumento suena, no qué toca. Aquí se ven
    /// los doce a la vez, que es lo que permite detectar dos Tracks compartiendo
    /// canal sin ir seleccionándolos uno a uno.
    ///
    /// **Falta MIDI Learn**, que es la rebanada 8 de la v1 y entra en esta misma
    /// pantalla. El estado de los endpoints se queda arriba, en la barra: es
    /// estado que se mira de reojo mientras se toca, no configuración que se
    /// visita.
    private var midiScreen: some View {
        // Mismo motivo que en la barra: el tempo y el estado del maestro los
        // escribe el hilo de recepción, así que hay que repreguntar.
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            VStack(alignment: .leading, spacing: 20) {
                endpoints
                channelMap
            }
        }
    }

    /// La elección de dispositivo, provisional y en su sitio definitivo.
    ///
    /// **Baja aquí desde la barra en la misma tarea que la vacía** (FR6), y no
    /// una fase más tarde. Al retirar el estado MIDI del chrome, estos dos
    /// selectores se quedaban sin ningún sitio hasta la Fase 4: con un solo
    /// dispositivo por lado no se nota —`MIDIEndpointSelection.refreshed` cae al
    /// primero disponible, para que la app funcione sin pasar por un selector—
    /// pero con dos sintetizadores enchufados no habría forma de cambiar de uno
    /// a otro durante cuatro fases. Eso es una regresión, no una fase
    /// intermedia.
    ///
    /// La Fase 4 los sustituye por los cards `midi input` y `midi output` del
    /// handoff. Lo que aquí hay es la función, sin su forma.
    private var endpoints: some View {
        HStack(spacing: 24) {
            endpointPicker(
                label: "midi output",
                status: model.outputUnavailable ?? model.destinationStatus,
                isConnected: model.selection.hasEndpoint,
                choices: model.selection.available,
                selection: destinationBinding
            )
            endpointPicker(
                label: "midi input",
                status: model.sourceStatus,
                isConnected: !model.isReadOnly,
                choices: model.sourceSelection.available,
                selection: sourceBinding
            )
        }
    }

    private func endpointPicker(
        label: String,
        status: String,
        isConnected: Bool,
        choices: [MIDIEndpointInfo],
        selection: Binding<MIDIEndpointRef>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(display: label)
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)

            HStack(spacing: 8) {
                Text(display: status)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(isConnected ? Palette.text : Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // **Solo si hay más de uno.** Con un único dispositivo, un menú
                // de un elemento sería una decisión que no existe.
                if choices.count > 1 {
                    Menu {
                        Picker("", selection: selection) {
                            ForEach(choices, id: \.endpoint) { choice in
                                Text(display: choice.displayName).tag(choice.endpoint)
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.mutedBright)
                            .frame(width: 28, height: 28)
                    }
                    .fixedSize()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brutalistPanel()
    }

    private var channelMap: some View {
        ChannelMapView(
            clock: ChannelMapView.Clock(
                revision: model.clockRevision,
                isExternal: model.followsExternalClock,
                beatsPerMinute: model.beatsPerMinute,
                status: model.clockStatus
            ),
            onClockSourceChange: { model.setFollowsExternalClock($0) },
            onTempoChange: { model.setTempo($0) },
            channels: model.channels,
            selected: model.selectedTrackIndex,
            accent: Palette.accent(for: family),
            onChannelChange: { model.setChannel($1, forTrack: $0) }
        )
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
        // Con solo el ancho crecía hasta empujar el selector y la fila de Cycles
        // fuera de la pantalla, y las dos son controles: quedarse sin verlos es
        // peor que un anillo algo menor.
        let side = min(columns.rings, height - Self.reservedBelowStage)
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
            readout
                .frame(width: columns.readout + slack)
        }
    }

    /// Lo que hay que dejar libre debajo del escenario: la fila de navegación,
    /// el selector de Tracks y la de Cycles, con sus separaciones.
    ///
    /// **Es una suma escrita como suma, y no un número.** Antes era un literal —
    /// 260, luego 324— y eso lo dejó mintiendo dos veces el mismo día: la fila de
    /// canal se fue a la pantalla MIDI y la pastilla bajó de 56 puntos a 44, pero
    /// el 324 seguía reservándolos. El anillo pagaba la diferencia, unos 108
    /// puntos de lado que no usaba nadie. Escrito así, cambiar el alto de una
    /// fila cambia la reserva sola.
    static let reservedBelowStage: CGFloat =
        chromeHeight + contentSpacing + trackScreenSpacing
        + selectorRowHeight + mixRowSpacing + mixRowHeight + rowSpacing + cyclesRowHeight

    /// El chrome compartido: la barra y la navegación, las dos de alto fijo.
    ///
    /// **Sale de las propias vistas y no de un literal.** Era un 44 escrito aquí
    /// cuando las pestañas, el estado y el transporte compartían una fila; ahora
    /// son dos filas con altura declarada, y copiar sus números los dejaría
    /// mintiendo en cuanto una de las dos cambie.
    static let chromeHeight: CGFloat = AppChrome.height + ModuleNavigation.height
    /// Entre la navegación y la pantalla.
    static let contentSpacing: CGFloat = 20
    /// Entre el escenario y el selector.
    static let trackScreenSpacing: CGFloat = 24
    /// Una pastilla de Track: solo su número desde el 2026-09-02.
    static let selectorRowHeight: CGFloat = 44
    /// Entre la pastilla y su par M/S, que va pegado a ella.
    static let mixRowSpacing: CGFloat = 6
    /// El par M/S debajo de cada pastilla, desde el 2026-09-02.
    static let mixRowHeight: CGFloat = 32
    /// Entre el selector y la fila de Cycles.
    static let rowSpacing: CGFloat = 16
    /// La fila de Cycles: su etiqueta, su separación y sus botones.
    static let cyclesRowHeight: CGFloat = 16 + 8 + 44

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
        VStack(alignment: .leading, spacing: 8) {
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

    /// El valor grande.
    ///
    /// Tipografía muy grande y jerarquía marcada porque el criterio es leerlo a
    /// Displays the description of a parameter change with its family-specific accent color.
    /// - Parameter change: The parameter change to display.
    /// - Returns: A view showing the change description.
    /// El distintivo del gesto momentáneo que está puesto.
    ///
    /// **La palabra la decide `FamilyReadout`**, en `Engine` y con tests; aquí
    /// solo se dibuja. Es la regla de `workflow.md`: si algo en `App` mereciera
    /// un test, está en el sitio equivocado.
    ///
    /// Lleva el acento de Tonal a propósito, que es el único de los tres que no
    /// pertenece a ningún knob: así no se confunde con la familia del parámetro
    /// que se esté girando, que es lo que colorea el valor grande.
    ///
    /// > **Temp y Ctrl All se separan por forma, no por color** (FR16). Los tres
    /// > acentos codifican familia y darle uno a un gesto haría que un
    /// > desplazamiento global se leyera como «Shape» de reojo. Lo que cambia es
    /// > el ancho, **y el ancho dice el alcance**: Temp es una pastilla compacta
    /// > porque alcanza a un Track; Ctrl All cruza el panel entero porque alcanza
    /// > a los doce. A un metro se distinguen sin llegar a leer la palabra, que
    /// > es el criterio de `product-guidelines.md` — de reojo, en movimiento y
    /// > con poca luz.
    private func gestureMarker(_ marker: String, gesture: ReadoutGesture) -> some View {
        let spansEverything = gesture == .ctrlAll
        return Text(marker.uppercased())
            .font(Typography.captionBold)
            .foregroundStyle(Palette.background)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: spansEverything ? .infinity : nil)
            .background(Palette.tonal, in: RoundedRectangle(cornerRadius: Brutalist.radiusSmall))
            .padding(.horizontal, 24)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.18), value: marker)
    }

    private func transient(_ change: ParameterChange) -> some View {
        Text(change.description)
            .font(Typography.readout)
            .minimumScaleFactor(0.5)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            // **El acento es el de la familia del parámetro que se movió**, no
            // uno fijo: `product-guidelines.md` pide que el color codifique qué
            // tipo de parámetro es. Girar Velocity y girar Steps tienen que
            // leerse distinto sin necesidad de leer la palabra.
            .foregroundStyle(Palette.accent(for: change.parameter.family))
            .padding(.horizontal, 24)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.18), value: change)
    }

    private var sourceBinding: Binding<MIDIEndpointRef> {
        Binding(
            get: { model.sourceSelection.selected?.endpoint ?? 0 },
            set: { endpoint in
                guard
                    let chosen = model.sourceSelection.available.first(where: {
                        $0.endpoint == endpoint
                    })
                else { return }
                model.selectSource(chosen)
            }
        )
    }

    private var destinationBinding: Binding<MIDIEndpointRef> {
        Binding(
            get: { model.selection.selected?.endpoint ?? 0 },
            set: { endpoint in
                guard
                    let chosen = model.selection.available.first(where: { $0.endpoint == endpoint })
                else { return }
                model.select(chosen)
            }
        )
    }

    /// Los valores de Shape y de Groove, en solo lectura.
    ///
    /// **Cada familia con su acento**, para que el estado en reposo se lea con
    /// el mismo código de color que el valor grande transitorio.
    ///
    /// No se muestra ninguna altura: el pool tiene su propia representación en
    /// `TonalView`, y enseñar una nota por paso contradiría el modelo de pool de
    /// la Pre Spec.
    private var parameters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.shapeSummary)
                .font(Typography.parameterLine)
                .foregroundStyle(Palette.shape.opacity(0.85))
            // Dos renglones, un solo acento: el color codifica la familia y
            // Groove es una. El corte lo decide `Engine` —por lo que se envía y
            // por cuándo se envía— y no el ancho de la pantalla, que dejaba
            // `Delay 0%` colgando solo.
            ForEach(model.grooveSummaryLines, id: \.self) { line in
                Text(line)
                    .font(Typography.parameterLine)
                    .foregroundStyle(Palette.groove.opacity(0.85))
            }
        }
    }

}

#Preview {
    ContentView()
}
