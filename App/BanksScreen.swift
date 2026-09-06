import Engine
import SwiftUI

/// La pantalla `banks`: bancos, patterns y a qué pattern responde cada Track.
///
/// **Es una cáscara visual, y conviene leerlo antes de creerse lo que dibuja**
/// (FR25). No existe modelo de `Bank` ni persistencia: el proyecto tiene **un**
/// `Pattern` —`Pattern.swift` lo dice de sí mismo: «más de uno —ni Banks, ni
/// Project— es una limitación de alcance»— y esta pantalla enseña dieciséis
/// huecos de banco y dieciséis de pattern de los cuales solo el primero de cada
/// uno tiene algo detrás.
///
/// **Lo que sí es cierto de lo que se ve:**
///
/// - Que el pattern 01 tenga material o no sale del `Pattern` real.
/// - Que esté sonando sale del transporte real.
/// - El tempo del pie es el tempo real.
/// - Los quince restantes dicen `empty` porque **están vacíos de verdad**: no
///   existen.
///
/// **Lo que no:** mover la selección de banco o de pattern no cambia lo que
/// suena, porque no hay nada a lo que cambiar. La selección se mueve para que la
/// forma de la app se pueda ver y aprender; no finge un cambio que no ocurre.
///
/// **Por qué se dibuja igualmente**, decidido con el usuario al planear el
/// track: enseñar la forma completa y decir qué está vacío es más honesto que
/// entregar tres pantallas y una pestaña que no lleva a ninguna parte. El día
/// que exista el modelo de `Bank` —la rebanada 4 de la v2— esta pantalla deja de
/// ser cáscara sin cambiar de forma.
struct BanksScreen: View {

    let model: TransportModel

    /// **Estado local, y ese es el punto.** No hay dónde guardarlo: un banco
    /// elegido que no existe no puede vivir en el modelo sin inventarse un
    /// modelo. Vive aquí, se pierde al salir de la pantalla, y eso es exacto —
    /// no hay nada que recordar.
    @State private var selectedBank = 0
    @State private var selectedPattern = 0

    var body: some View {
        // **Alineados arriba y sin estirar.** Con los cards ocupando toda la
        // altura, el pie del banco quedaba pegado al borde inferior y se
        // recortaba; cada uno mide ahora lo que mide su contenido.
        HStack(alignment: .top, spacing: 20) {
            BankGrid(
                selected: $selectedBank,
                tempo: model.tempoDescription,
                patternsWithMaterial: model.patternHasMaterial ? 1 : 0
            )

            PatternGrid(
                selected: $selectedPattern,
                hasMaterial: model.patternHasMaterial,
                isPlaying: model.isPlaying
            )

            TrackAssignments(selected: model.selectedTrackIndex)
        }
    }
}

/// Los dieciséis bancos.
struct BankGrid: View {

    @Binding var selected: Int
    let tempo: String
    let patternsWithMaterial: Int

    /// Cuántos declara la Pre Spec. Es una constante del dominio y no de la
    /// rejilla que la dibuja; cuando exista `Bank` en `Engine`, sale de allí.
    static let count = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(display: "bank \((selected + 1).paddedForDisplay)")
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.text)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(0..<Self.count, id: \.self) { index in
                    let isSelected = index == selected

                    Button((index + 1).paddedForDisplay) { selected = index }
                        .font(isSelected ? Typography.bodyStrong : Typography.body)
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Palette.onAccent : Palette.mutedBright)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .contentShape(Rectangle())
                        // Off-white: elegir un banco es «éste entre iguales», no
                        // pertenece a ninguna familia de parámetros.
                        .brutalistControl(accent: Palette.offWhite, isSelected: isSelected)
                }
            }

            // **Cuenta los que tienen material, no los huecos.** El handoff
            // rotula «16 patterns», que es la capacidad; decir eso con quince
            // vacíos sería contar sitios y llamarlos contenido.
            Text(display: "\(tempo) · \(patterns)")
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brutalistPanel()
    }

    private var patterns: String {
        switch patternsWithMaterial {
        case 0: "no patterns"
        case 1: "1 pattern"
        default: "\(patternsWithMaterial) patterns"
        }
    }
}

/// Los dieciséis patterns del banco, con su estado.
struct PatternGrid: View {

    @Binding var selected: Int
    let hasMaterial: Bool
    let isPlaying: Bool

    static let count = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(display: "patterns")
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.text)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(0..<Self.count, id: \.self) { index in
                    cell(index)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brutalistPanel()
    }

    /// En qué estado está un pattern.
    ///
    /// **Solo el primero puede estar en otro que no sea vacío**, porque es el
    /// único que existe. Los quince restantes no se dibujan «apagados por
    /// ahora»: están vacíos, y `empty` es la palabra exacta.
    private enum State {
        case playing
        case ready
        case empty

        var label: String {
            switch self {
            case .playing: "playing"
            case .ready: "ready"
            case .empty: "empty"
            }
        }
    }

    private func state(_ index: Int) -> State {
        guard index == 0, hasMaterial else { return .empty }
        return isPlaying ? .playing : .ready
    }

    private func cell(_ index: Int) -> some View {
        let state = state(index)
        let isSelected = index == selected

        return Button(action: { selected = index }) {
            VStack(spacing: 4) {
                Text(display: (index + 1).paddedForDisplay)
                    .font(state == .playing ? Typography.valueTitle : Typography.parameterLine)
                    .monospacedDigit()
                    .foregroundStyle(state == .playing ? Palette.shape : Palette.mutedBright)

                Text(display: state.label)
                    .font(Typography.caption)
                    .foregroundStyle(state == .empty ? Palette.border : Palette.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: Brutalist.radius))
        .overlay {
            RoundedRectangle(cornerRadius: Brutalist.radius)
                .stroke(border(state: state, isSelected: isSelected), lineWidth: width(isSelected))
        }
    }

    /// **El que suena lleva el olivo de Shape; el elegido, el off-white.** Son
    /// dos cosas distintas y en el handoff coinciden porque su mock tiene
    /// elegido el que suena. Separarlas es lo que permite mirar un pattern sin
    /// dejar de ver cuál está sonando.
    private func border(state: State, isSelected: Bool) -> Color {
        if state == .playing { return Palette.shape }
        if isSelected { return Palette.offWhite }
        return state == .empty ? Palette.border : Palette.borderBright
    }

    private func width(_ isSelected: Bool) -> CGFloat {
        isSelected ? Brutalist.strokeEmphasis : Brutalist.stroke
    }
}

/// A qué pattern responde cada Track.
///
/// **Los doce dicen el mismo pattern, y es la verdad.** Con un solo `Pattern`,
/// los doce Tracks son suyos: no hay asignación que enseñar todavía. Inventar
/// doce asignaciones distintas para que se parezca al mock sería exactamente lo
/// que FR25 dice que esta pantalla no hace.
struct TrackAssignments: View {

    let selected: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(display: "track assignments")
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.text)

            // **Las doce filas van pegadas, con su propio espaciado.** Con el
            // del card —doce puntos entre bloques— las doce sumaban más de lo
            // que la columna tiene y `track 12` caía fuera de la pantalla.
            VStack(spacing: 4) {
                ForEach(0..<Pattern.trackCount, id: \.self) { index in
                    row(index)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brutalistPanel()
    }

    private func row(_ index: Int) -> some View {
        let isSelected = index == selected

        return HStack(spacing: 0) {
            Text(display: "track \((index + 1).paddedForDisplay)")
                .font(isSelected ? Typography.bodyStrong : Typography.body)
                .monospacedDigit()
                .foregroundStyle(isSelected ? Palette.shape : Palette.mutedBright)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(display: "pattern 01")
                .font(isSelected ? Typography.bodyStrong : Typography.body)
                .monospacedDigit()
                .foregroundStyle(isSelected ? Palette.shape : Palette.mutedBright)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: Brutalist.radiusSmall))
        .overlay {
            RoundedRectangle(cornerRadius: Brutalist.radiusSmall)
                .stroke(
                    isSelected ? Palette.shape : Palette.border,
                    lineWidth: isSelected ? Brutalist.strokeEmphasis : Brutalist.stroke
                )
        }
    }
}
