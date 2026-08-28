import Engine
import SwiftUI

/// El marco tonal y el material que hay dentro.
///
/// **Pool, no piano-roll.** `product-guidelines.md` es explícito: se muestra
/// únicamente el pool de notas sobre la Scale, y **no** qué nota sonó en cada
/// paso. Por eso esta vista no sabe nada del anillo ni del playhead: son dos
/// representaciones paralelas y separadas —cuándo suena algo, y de qué material
/// se elige—, y cruzarlas sugeriría que las alturas están clavadas a
/// posiciones.
///
/// **Es táctil a propósito.** Scale y Root son configuración, y la frontera de
/// la guía las pone del lado de la pantalla; el pool, que sí es material
/// generativo, solo se edita con los pads. Aquí se ve, no se toca.
///
/// > **Desviación del handoff.** Su pantalla 2 vive en una navegación de cinco
/// > pestañas que no existe: hay un Track, una familia con knobs y ninguna de
/// > las otras cuatro pantallas. Construir la navegación ahora sería chrome sin
/// > función. Entra como sección de la pantalla única y se moverá cuando haya
/// > dónde moverla.
struct TonalView: View {

    let frame: TonalFrame
    let pool: PitchPool
    let onFrameChange: (TonalFrame) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Tonal")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.tonal)

            scales
            roots
            poolReadout
        }
    }

    // MARK: - Scale

    private var scales: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Scale")
            // Envuelve porque a lo ancho de un iPad caben las cinco, pero el
            // objetivo táctil manda sobre la rejilla: se toca de pie.
            HStack(spacing: 10) {
                ForEach(Scale.ordered, id: \.self) { scale in
                    button(
                        title: name(of: scale),
                        isSelected: scale == frame.scale,
                        action: { onFrameChange(TonalFrame(scale: scale, root: frame.root)) }
                    )
                }
            }
        }
    }

    // MARK: - Root

    /// Las doce clases de altura, todas elegibles.
    ///
    /// No hay Roots «fuera de escala»: el Root es la fundamental **que
    /// transpone** la Scale (Pre Spec), así que es él quien decide dónde se
    /// apoya el conjunto, no al revés.
    private var roots: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Root")
            HStack(spacing: 6) {
                ForEach(0..<12, id: \.self) { pitchClass in
                    let root = Root(pitchClass)!
                    button(
                        title: root.description,
                        isSelected: root == frame.root,
                        action: { onFrameChange(TonalFrame(scale: frame.scale, root: root)) }
                    )
                }
            }
        }
    }

    // MARK: - El pool

    /// Qué alturas hay en el pool, con su octava.
    ///
    /// **Vacío es un estado, no un fallo.** El Track dispara sus Pulses y no
    /// tiene material que emitir; se dice y ya está, sin lenguaje de error ni
    /// disculpa.
    private var poolReadout: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Pool")

            if pool.isEmpty {
                Text("No pitches")
                    .font(.title3.monospaced())
                    .foregroundStyle(Palette.muted)
            } else {
                HStack(spacing: 8) {
                    ForEach(0..<pool.count, id: \.self) { index in
                        Text(pool.pitch(at: index)!.description)
                            .font(.title3.weight(.semibold).monospaced())
                            .foregroundStyle(Palette.tonal)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Palette.tonal.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                    }
                }
            }
        }
    }

    // MARK: - Piezas

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.muted)
    }

    private func button(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View
    {
        Button(title, action: action)
            .font(.body.weight(isSelected ? .bold : .regular))
            .foregroundStyle(isSelected ? .white : Palette.muted)
            // Objetivo táctil holgado: se toca de pie, delante del sintetizador.
            .frame(minWidth: 52, minHeight: 52)
            .background(
                isSelected ? Palette.tonal : Palette.inset,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Palette.tonal : Palette.border, lineWidth: 1)
            )
    }

    /// Los nombres van en inglés y sin traducir, como el resto del vocabulario
    /// de interfaz (`product-guidelines.md`).
    private func name(of scale: Scale) -> String {
        switch scale {
        case .minor: "Minor"
        case .major: "Major"
        case .dorian: "Dorian"
        case .phrygian: "Phrygian"
        case .pentatonic: "Pentatonic"
        }
    }
}
