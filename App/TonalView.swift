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
    let surface: PadSurface
    let onFrameChange: (TonalFrame) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            scales
            keyboard
            statusLine
            HStack(alignment: .top, spacing: 32) {
                poolReadout
                padsReadout
            }
        }
    }

    private var keys: TonalKeyboard { TonalKeyboard(frame: frame) }

    // MARK: - La rejilla de escalas

    /// **Seis botones**: las cinco escalas y `+User`.
    ///
    /// `+User` va con borde discontinuo. La Pre Spec admite escalas de usuario
    /// —«la escala puede ser preset o de usuario»— y esta rebanada no las
    /// entrega; el borde discontinuo es el signo que el handoff define para
    /// «todavía no», el mismo que llevan las tres pestañas que no existen.
    private var scales: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Scale")
            HStack(spacing: 10) {
                ForEach(Scale.ordered, id: \.self) { scale in
                    button(
                        title: name(of: scale),
                        isSelected: scale == frame.scale,
                        action: { onFrameChange(TonalFrame(scale: scale, root: frame.root)) }
                    )
                }

                Text("+User")
                    .font(Typography.body)
                    .frame(minWidth: 96, minHeight: 52)
                    .brutalistUnavailable(radius: Brutalist.radiusLarge)
            }
        }
    }

    // MARK: - El gráfico de notas

    /// Una barra por nota: **las de la escala altas, las de fuera cortas y
    /// oscuras**, y la raíz con trazo de 3px y etiqueta destacada.
    ///
    /// **Las doce siguen siendo tocables**, y ahí no se sigue al handoff. La
    /// razón está escrita en `TonalKeyboard.Key.canBecomeRoot`: elegir una nota
    /// de fuera construye un marco nuevo en el que esa nota es la fundamental,
    /// así que «está en la escala vigente» no dice nada sobre si puede ser raíz.
    /// La altura de la barra informa; no restringe.
    private var keyboard: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Root")
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(keys.keys, id: \.pitchClass) { key in
                    bar(for: key)
                }
            }
            .frame(height: 132)
        }
    }

    private func bar(for key: TonalKeyboard.Key) -> some View {
        let shape = RoundedRectangle(cornerRadius: Brutalist.radiusSmall)

        return Button {
            onFrameChange(TonalFrame(scale: frame.scale, root: Root(key.pitchClass)!))
        } label: {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(key.name)
                    .font(key.isRoot ? Typography.bodyStrong : Typography.caption)
                    .foregroundStyle(labelColour(for: key))
                    .padding(.bottom, 10)
            }
            // Las de fuera de la escala miden un tercio: se ven, se pueden
            // tocar, y a un metro no se confunden con las de dentro.
            .frame(maxWidth: .infinity)
            .frame(height: key.isInScale ? 132 : 44)
            .background(fill(for: key), in: shape)
            .overlay(
                shape.stroke(
                    key.isRoot ? Color.white : (key.isInScale ? Palette.tonal : Palette.border),
                    // 3px solo en la raíz: es el tratamiento que el handoff
                    // reserva para distinguirla de «está en la escala».
                    lineWidth: key.isRoot ? Brutalist.strokeEmphasis : Brutalist.stroke
                )
            )
        }
        .buttonStyle(.plain)
    }

    private func fill(for key: TonalKeyboard.Key) -> Color {
        if key.isRoot { return Palette.tonal }
        return key.isInScale ? Color.clear : Palette.inset
    }

    private func labelColour(for key: TonalKeyboard.Key) -> Color {
        if key.isRoot { return Palette.toolbar }
        return key.isInScale ? Palette.tonal : Palette.muted
    }

    /// `Scale · <nombre>   Root · <nota>`, con la raíz en color.
    private var statusLine: some View {
        HStack(spacing: 8) {
            Text("Scale · \(name(of: frame.scale))")
                .foregroundStyle(Palette.mutedBright)
            Text("Root · ")
                .foregroundStyle(Palette.mutedBright)
                + Text(frame.root.description).foregroundStyle(Palette.tonal)
        }
        .font(Typography.bodyStrong)
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
                    .font(Typography.parameterLine)
                    .foregroundStyle(Palette.muted)
            } else {
                HStack(spacing: 8) {
                    ForEach(0..<pool.count, id: \.self) { index in
                        Text(pool.pitch(at: index)!.description)
                            .font(Typography.parameterLineStrong)
                            .foregroundStyle(Palette.tonal)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            // **Trazo, no tinte.** Era un relleno del acento al
                            // 15%, y el handoff no admite tintes: los estados se
                            // dicen con un bloque plano o con un borde, nunca
                            // con una transparencia.
                            .brutalistPanel(radius: Brutalist.radius)
                    }
                }
            }
        }
    }

    // MARK: - La octava de los pads

    /// En qué registro están los pads ahora mismo.
    ///
    /// **Sin esto, pulsar un pad y no reconocer la nota no tiene explicación
    /// visible** — y en el tope, un pad que deja de responder parecería un
    /// defecto. Es la razón de que esta lectura exista (FR11).
    ///
    /// **Estado persistente, no valor grande transitorio.** No lo mueve un knob:
    /// lo mueven los pads 8 y 16, y se queda donde se dejó. El valor grande que
    /// se desvanece es para lo que cambia mientras se gira.
    ///
    /// Se nombra por las alturas que se van a oír —el primer pad y el noveno, que
    /// es el mismo doce semitonos arriba—, no por un número de octava: el número
    /// habría que traducirlo, y el nombre de la nota se compara directamente con
    /// lo que suena.
    private var padsReadout: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Pads")

            HStack(spacing: 12) {
                Text(range)
                    .font(Typography.parameterLineStrong)
                    .foregroundStyle(Palette.tonal)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .brutalistPanel(radius: Brutalist.radius)

                if let limit {
                    Text(limit)
                        .font(Typography.captionStrong)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }

    /// Las dos octavas de la superficie, por el nombre de su primera nota.
    private var range: String {
        guard let first = surface.pitch(at: 0), let ninth = surface.pitch(at: 8) else {
            return "—"
        }
        return "\(first.description) – \(ninth.description)"
    }

    /// Qué se acabó, cuando se acabó.
    ///
    /// **Un pad que no responde sin explicación visible es el defecto que esta
    /// lectura existe para evitar.** En el tope se dice cuál, y en medio no se
    /// dice nada: no hay nada que avisar.
    private var limit: String? {
        switch (surface.canShiftDown, surface.canShiftUp) {
        case (false, true): "Lowest octave"
        case (true, false): "Highest octave"
        case (false, false): "No room to move"
        case (true, true): nil
        }
    }

    // MARK: - Piezas

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Typography.captionStrong)
            .foregroundStyle(Palette.muted)
    }

    private func button(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View
    {
        Button(title, action: action)
            .font(isSelected ? Typography.bodyStrong : Typography.body)
            .foregroundStyle(isSelected ? Palette.toolbar : Palette.muted)
            // Objetivo táctil holgado: se toca de pie, delante del sintetizador.
            .frame(minWidth: 52, minHeight: 52)
            .brutalistControl(
                accent: Palette.tonal,
                isSelected: isSelected,
                radius: Brutalist.radiusLarge
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
