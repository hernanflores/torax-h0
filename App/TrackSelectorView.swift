import Engine
import SwiftUI

/// Los dieciséis Tracks: cuál se edita y cuáles tienen material.
///
/// **No es la pantalla del handoff.** Los anillos concéntricos —uno por Track—
/// son la rebanada siguiente; esto es lo justo para que dieciséis Tracks se
/// puedan usar y verificar sin adivinar cuál está seleccionado.
///
/// **Seleccionar desde aquí hace lo mismo que su step button.** Sin controlador
/// conectado es la única vía, y con controlador las dos llevan al mismo sitio:
/// si no, la pantalla mentiría sobre lo que el hardware acaba de hacer.
struct TrackSelectorView: View {

    let selected: Int
    /// Cuáles tienen material. Un Track vacío dispara y no suena, así que la
    /// diferencia importa antes de preguntarse por qué no se oye.
    let hasMaterial: [Bool]
    let channel: Channel
    let onSelect: (Int) -> Void
    let onChannelChange: (Channel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Tracks")
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.shape)

            selector
            channelRow
        }
    }

    // MARK: - Los dieciséis

    private var selector: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Track \(selected + 1)")

            // Dos filas de ocho: dieciséis en una sola quedan estrechos, y el
            // objetivo táctil manda sobre la rejilla porque se toca de pie.
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(0..<8, id: \.self) { column in
                            button(for: row * 8 + column)
                        }
                    }
                }
            }
        }
    }

    private func button(for index: Int) -> some View {
        let isSelected = index == selected
        let sounds = hasMaterial.indices.contains(index) && hasMaterial[index]

        return Button("\(index + 1)") { onSelect(index) }
            .font(isSelected ? Typography.bodyStrong : Typography.body).monospacedDigit()
            .foregroundStyle(isSelected ? .white : (sounds ? Palette.shape : Palette.muted))
            .frame(minWidth: 52, minHeight: 52)
            .background(
                isSelected ? Palette.shape : Palette.inset,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    // El borde marca quién suena: relleno para el seleccionado,
                    // contorno para los que tienen material, nada para los
                    // vacíos. A un metro se distinguen los tres estados.
                    .stroke(
                        isSelected ? Palette.shape : (sounds ? Palette.shape : Palette.border),
                        lineWidth: sounds && !isSelected ? 2 : 1
                    )
            )
    }

    // MARK: - El canal

    /// Por dónde sale este Track.
    ///
    /// **Táctil, como Scale y Root**: es configuración y no material generativo,
    /// y `product-guidelines.md` pone esa frontera del lado de la pantalla.
    private var channelRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Channel")
            HStack(spacing: 6) {
                ForEach(1...16, id: \.self) { number in
                    let isSelected = number == channel.number
                    Button("\(number)") { onChannelChange(Channel(number)!) }
                        .font(isSelected ? Typography.captionBold : Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? .white : Palette.muted)
                        .frame(minWidth: 34, minHeight: 44)
                        .background(
                            isSelected ? Palette.shape : Palette.inset,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Typography.captionStrong)
            .foregroundStyle(Palette.muted)
    }
}
