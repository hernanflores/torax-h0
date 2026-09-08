import Engine
import SwiftUI

/// La lectura grande de la pantalla `track`.
///
/// **Nombre pequeño encima, valor grande debajo** (FR12), como el handoff:
/// `pulses` y `5 / 16`. Las dos piezas llegan ya separadas de `Engine`
/// —`FamilyReadout.label` y `.value`, o `ParameterChange.label` y `.value`—
/// porque partir una cadena de dominio buscando el espacio se rompe en silencio
/// el día que un valor lleve uno.
///
/// **Persiste el último parámetro tocado, y ahí está la decisión** (FR12). El
/// valor no se desvanece al soltar el knob: pierde el acento de su familia y se
/// queda escrito en off-white. Vaciarlo dejaría hueco el bloque más grande de la
/// pantalla durante casi toda la sesión, y un hueco no informa de nada; el
/// acento sí distingue «lo estoy moviendo ahora» de «esto es lo último que
/// moví».
///
/// **Sin panel.** Las tarjetas de abajo llevan su trazo de 2 pt y ésta no: es la
/// jerarquía del handoff, donde la lectura grande flota sobre el fondo y lo que
/// está encuadrado es lo agrupado. Un borde más aquí convertiría la columna en
/// cuatro cajas iguales y perdería cuál manda.
struct TrackReadout: View {

    /// Lo que se está girando ahora mismo, si hay algo.
    let change: ParameterChange?

    /// Lo último que se giró, para cuando ya no se gira nada.
    let lastChange: ParameterChange?

    /// De qué se habla cuando todavía no se ha girado nada en toda la sesión.
    let resting: FamilyReadout

    /// Qué familia colorea el valor.
    let family: ParameterFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // **El distintivo del gesto va encima de los dos estados.** Lo que
            // Temp o Ctrl All cambian no es el valor —se lee igual girando o en
            // reposo— sino si va a sobrevivir a soltar el botón, y eso es cierto
            // durante todo el hold.
            if let marker = resting.marker {
                Text(display: marker)
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.accent(for: family))
            }

            Text(display: label)
                .font(Typography.parameterLine)
                .foregroundStyle(Palette.muted)

            Text(display: value)
                .font(Typography.readoutCompact)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(tint)
                .animation(.easeOut(duration: 0.18), value: change)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// **Tres fuentes, en orden de recencia.** Lo que se gira ahora manda; si no
    /// se gira nada, lo último girado; y solo mientras no se haya girado nada en
    /// toda la sesión, el parámetro que encabeza la familia.
    private var shown: (label: String, value: String) {
        if let change { return (change.label, change.value) }
        if let lastChange { return (lastChange.label, lastChange.value) }
        return (resting.label, resting.value)
    }

    private var label: String { shown.label }
    private var value: String { shown.value }

    /// El acento **solo mientras se gira**.
    ///
    /// Es lo que separa los dos estados sin mover ni una letra: el mismo texto,
    /// encendido o en reposo. Codificar la familia con color y la recencia con
    /// intensidad deja las dos lecturas en un solo bloque, que es lo que se
    /// puede leer a un metro sin buscar.
    private var tint: Color {
        change == nil ? Palette.text : Palette.accent(for: family)
    }
}

/// El card `cycle`: en cuál va y cuántos hay activos.
///
/// **El icono es un indicador, no un botón** (decisión del 2026-09-06). El
/// handoff dibuja un símbolo de repetición arriba a la derecha sin etiqueta;
/// significa que el Track está encadenando Cycles, y se enciende cuando hay más
/// de uno activo. Hacerlo pulsable habría metido en `track` un gesto que la
/// pantalla no quiere y que además duplicaría lo que ya hacen las celdas.
///
/// **Las celdas sí se tocan, y eso no contradice a FR14.** Lo que FR14 prohíbe
/// aquí es editar parámetros generativos con el dedo —steps, pulses, rotate,
/// division y todo groove y tonal—; cuántos Cycles están activos no es ninguno
/// de ellos, es la estructura sobre la que varían. Y es la única vía que tiene:
/// el preset del BeatStep pone en el knob 82 **el cursor de edición**, y su
/// propia nota dice que «cuántos Cycles están activos se ajusta en pantalla».
/// Quitar el toque no habría cumplido FR14 mejor; habría dejado el parámetro sin
/// forma de moverse.
struct CycleStrip: View {

    /// Cuántos Cycles están activos, de 1 a `Cycle.maximum`.
    let activeCount: Int

    /// Cuál se está editando.
    let editing: Int

    /// Cuál suena ahora mismo, o `nil` con el transporte parado.
    ///
    /// **Es un cierre y no un valor** porque deriva del reloj: se pregunta al
    /// dibujar, como los playheads. Un valor pasado por parámetro se quedaría
    /// congelado en el instante en que se compuso la vista.
    let inCourse: () -> Int?

    /// El acento de la familia que se esté mirando.
    let accent: Color

    let onActiveCountChange: (Int) -> Void

    var body: some View {
        // **Diez veces por segundo, no sesenta.** El relleno se mueve cuando
        // cierra una vuelta, que a los tempos de la app son segundos: pedir un
        // repintado por fotograma para eso sería carga visual sin nada que
        // enseñar. Los anillos sí van a `.animation`, porque ahí lo que se mueve
        // es continuo.
        //
        // La posición sigue saliendo del reloj musical y no del temporizador: lo
        // único que éste decide es cuándo volver a preguntar.
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            card(sounding: inCourse())
        }
    }

    private func card(sounding: Int?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(display: "cycle")
                        .font(Typography.parameterLine)
                        .foregroundStyle(Palette.muted)

                    Text(
                        display:
                            "\(current(sounding).paddedForDisplay) / \(activeCount.paddedForDisplay)"
                    )
                    .font(Typography.valueTitle)
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
                }

                Spacer(minLength: 12)

                // El indicador de encadenamiento. Apagado con un solo Cycle
                // activo, porque entonces no hay nada que encadenar y un símbolo
                // encendido diría que sí.
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: Typography.symbol))
                    .foregroundStyle(activeCount > 1 ? Palette.mutedBright : Palette.border)
                    .accessibilityLabel(Text(display: "cycles chained"))
            }

            // **Los dieciséis, siempre, en dos filas de ocho.**
            //
            // > **Se dibujaban solo hasta `max(activeCount, 8)` y eso era un
            // > bug**, encontrado en la revisión del PR: con ocho Cycles activos,
            // > la celda del nueve no existía, así que no había forma de subir a
            // > nueve. El rango documentado es de uno a dieciséis.
            // >
            // > La fila que esto sustituyó ya lo hacía bien y su documentación
            // > decía por qué: «los que quedan fuera del rango activo se dibujan
            // > apagados en vez de desaparecer; si la fila cambiara de longitud,
            // > los números se moverían de sitio y dejarían de poder pulsarse sin
            // > mirar». Se perdió al traerla al card y vuelve con su razón.
            //
            // Dos filas y no una: en la columna estrecha, dieciséis celdas
            // seguidas quedarían por debajo del objetivo táctil.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6
            ) {
                ForEach(1...Track.cycleCount, id: \.self) { number in
                    cell(number, sounding: sounding)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brutalistPanel()
    }

    /// En cuál va: el que suena, o el que se edita con el transporte parado.
    private func current(_ sounding: Int?) -> Int { (sounding ?? editing) + 1 }

    private func cell(_ number: Int, sounding: Int?) -> some View {
        let index = number - 1
        let isActive = number <= activeCount
        let isSounding = index == sounding && isActive
        let isEditing = index == editing && isActive

        return Button(number.paddedForDisplay) { onActiveCountChange(number) }
            .font(isSounding || isEditing ? Typography.captionBold : Typography.caption)
            .monospacedDigit()
            .foregroundStyle(foreground(isActive: isActive, isSounding: isSounding))
            .frame(minHeight: 28)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .brutalistControl(accent: accent, isSelected: isSounding, radius: Brutalist.radiusSmall)
            // El contorno del Cycle en edición va **encima** del control, para
            // que se distinga del relleno del que suena aunque sean el mismo.
            .overlay {
                if isEditing {
                    RoundedRectangle(cornerRadius: Brutalist.radiusSmall)
                        .strokeBorder(accent, lineWidth: Brutalist.strokeEmphasis)
                }
            }
            .opacity(isActive ? 1 : 0.35)
    }

    private func foreground(isActive: Bool, isSounding: Bool) -> Color {
        guard isActive else { return Palette.muted }
        return isSounding ? Palette.onAccent : Palette.mutedBright
    }
}

/// El card de una familia de parámetros: `shape`, `groove` o `tonal`.
///
/// **Los tres se ven a la vez** (FR12). Antes había tabs y solo uno estaba
/// visible; el handoff los apila, y con ellos desaparece la única razón por la
/// que el tab existía. Lo que sobrevive de aquella regla es que **la pantalla
/// sigue a la mano**: girar un knob no cambia de card, lo resalta.
///
/// **El resalte es el trazo, no el relleno.** Un card relleno del acento de su
/// familia sería un bloque de color del tamaño de un cuarto de pantalla
/// compitiendo con el patrón, que es el protagonista. El trazo dice lo mismo y
/// no se lleva la mirada; es la misma decisión que el subrayado de la
/// navegación.
///
/// **Ninguno de sus valores se toca** (FR14). Es la pantalla del espejo: los
/// nueve parámetros se mueven con knobs, y aquí solo se leen.
struct ParameterFamilyCard: View {

    let family: ParameterFamily

    /// Los parámetros de la familia con su valor, ya escritos por `Engine`,
    /// **repartidos en las líneas que la familia necesite**.
    ///
    /// Shape trae dos desde el 2026-09-07: los cuatro del ritmo arriba y los
    /// cuatro del Note Repeater debajo. Ocho columnas en una sola fila dejarían
    /// de leerse a un metro, y juntarlas diría además algo falso — el Note
    /// Repeater es una capa sobre el ritmo, no el ritmo (FR15).
    ///
    /// Quién va en cada línea lo decide `Engine`, con
    /// `TrackParameter.isNoteRepeater`; aquí solo se dibuja.
    let rows: [[(label: String, value: String)]]

    /// Si es la familia que se está girando ahora mismo.
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(display: title)
                .font(Typography.parameterLine)
                .foregroundStyle(isActive ? Palette.accent(for: family) : Palette.muted)

            // **Una columna por parámetro, no una lista de renglones.** Con el
            // nombre encima del valor los nueve caben en dos filas cortas y se
            // comparan de un vistazo; en renglones `nombre valor` habría que
            // leerlos en orden para encontrar uno.
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(row, id: \.label) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(display: entry.label)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            Text(display: entry.value)
                                .font(Typography.bodyMedium)
                                .monospacedDigit()
                                .foregroundStyle(Palette.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(8)
        // **El card no cede altura, y desde el 2026-09-07 hace falta decirlo.**
        // Con la segunda línea de Shape la columna pasó a pedir más alto del
        // disponible, y quien cedía era este card: SwiftUI encogía su texto con
        // el `minimumScaleFactor`, así que los ocho valores se dibujaban a la
        // mitad de tamaño que los cinco de Groove. Ilegible a un metro, que es
        // el requisito de `product-guidelines.md`. Lo que cede ahora es el
        // anillo, que tiene de sobra.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: Brutalist.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: Brutalist.radiusLarge)
                .stroke(
                    isActive ? Palette.accent(for: family) : Palette.border,
                    lineWidth: isActive ? Brutalist.strokeEmphasis : Brutalist.stroke
                )
        }
    }

    /// El nombre lo pone `Engine`; la minúscula, `Text(display:)`.
    private var title: String { family.name }
}

/// El card `tonal`, que no es una lista de parámetros como los otros dos.
///
/// **Tonal no tiene knobs detrás**, así que no hay nueve columnas que enseñar:
/// hay un marco —`scale` y `root`— y el material que ese marco deja disponible.
///
/// **El pool se enseña y las alturas no se mapean a steps** (FR12, y la sección
/// «Representación tonal: pool, no melodía» de `product-guidelines.md`). PITCH
/// define un pool, no un piano-roll: una nota por paso sugeriría que las alturas
/// están fijadas a posiciones, que es exactamente el modelo mental que la app
/// rechaza.
struct TonalCard: View {

    let frame: TonalFrame

    /// Las alturas del pool, ya nombradas.
    let pool: [String]

    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(display: ParameterFamily.tonal.name)
                .font(Typography.parameterLine)
                .foregroundStyle(isActive ? Palette.tonal : Palette.muted)

            // **Una sola fila: el marco y el material.** El pool bajaba a un
            // renglón propio y eso costaba una fila entera de card para ocho
            // celdas que caben de sobra al lado — con la segunda línea de Shape
            // dentro, esa fila era lo que dejaba la tira de Cycles cortada
            // (2026-09-07). El pool tiene un máximo de ocho alturas, así que su
            // ancho está acotado por construcción.
            HStack(alignment: .center, spacing: 12) {
                labelled("scale", scaleName)
                labelled("root", "\(frame.root)")

                if pool.isEmpty {
                    // **El pool vacío se dice, no se disimula.** Es el estado de
                    // once Tracks al arrancar: disparan sus Pulses y no tienen
                    // material que emitir.
                    Text(display: "pool \(PitchPool().countDescription)")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.muted)
                } else {
                    // **Celdas de ancho propio, no repartidas.** Con
                    // `maxWidth: .infinity` un pool de una sola altura dibujaba
                    // una celda del ancho del card: parecía un campo de texto
                    // vacío en vez de una nota. Lo que hay que ver es cuántas
                    // hay, así que cada una mide lo suyo.
                    HStack(spacing: 4) {
                        ForEach(Array(pool.enumerated()), id: \.offset) { _, name in
                            Text(display: name)
                                .font(Typography.captionStrong)
                                .foregroundStyle(Palette.mutedBright)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(minWidth: 30, minHeight: 26)
                                .background(
                                    Palette.surface,
                                    in: RoundedRectangle(cornerRadius: Brutalist.radiusSmall)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: Brutalist.radiusSmall)
                                        .stroke(Palette.border, lineWidth: Brutalist.stroke)
                                }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: Brutalist.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: Brutalist.radiusLarge)
                .stroke(
                    isActive ? Palette.tonal : Palette.border,
                    lineWidth: isActive ? Brutalist.strokeEmphasis : Brutalist.stroke
                )
        }
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(display: label)
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
            Text(display: value)
                .font(Typography.parameterLineStrong)
                .foregroundStyle(Palette.text)
        }
    }

    /// El nombre lo pone `Engine`; la minúscula, `Text(display:)`.
    private var scaleName: String { frame.scale.name }
}
