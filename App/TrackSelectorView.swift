import Engine
import MIDI
import SwiftUI

/// Los doce Tracks: cuál se edita y cuáles tienen material.
///
/// **Es la fila de selección, no la representación del patrón.** Esa son los
/// anillos concéntricos, que viven en su propia columna; aquí solo se dice cuál
/// se edita, sin adivinarlo.
///
/// **Seleccionar desde aquí hace lo mismo que su step button.** Sin controlador
/// conectado es la única vía, y con controlador las dos llevan al mismo sitio:
/// si no, la pantalla mentiría sobre lo que el hardware acaba de hacer.
struct TrackSelectorView: View {

    let selected: Int
    /// Cuáles tienen material. Un Track vacío dispara y no suena, así que la
    /// diferencia importa antes de preguntarse por qué no se oye.
    let hasMaterial: [Bool]
    /// El acento de la familia activa, que es el que lleva el elegido (FR5).
    let accent: Color
    let onSelect: (Int) -> Void

    /// La mezcla vigente: quién está muteado, quién soleado y quién se oye.
    let mix: MuteState
    let onToggleMute: (Int) -> Void
    let onToggleSolo: (Int) -> Void


    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // **El par M/S va pegado a su pastilla**, con menos aire del que
            // separa este bloque de la fila de Cycles: es lo que hace que se lea
            // como un canal de mixer —el Track y sus dos botones— y no como
            // tres filas independientes que hay que cruzar con la vista.
            VStack(alignment: .leading, spacing: 6) {
                selector
                mixRow
            }
        }
    }

    // MARK: - Los doce

    /// **Una fila**, no dos de seis.
    ///
    /// Dos filas se leerían como dos grupos y los Tracks no están agrupados: el
    /// 6 y el 7 son tan contiguos como el 3 y el 4. En una fila el orden es el
    /// mismo que el de los step buttons del controlador, que es la superficie
    /// desde la que se seleccionan de verdad.
    ///
    /// **Cuántas hay lo dice `Pattern.trackCount`**, no un literal: la fila
    /// dibujaba dieciséis cuando ya había doce Tracks y las cuatro últimas eran
    /// botones muertos.
    private var selector: some View {
        HStack(spacing: 6) {
            ForEach(0..<Pattern.trackCount, id: \.self) { index in
                button(for: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Una pastilla: **su número, y nada más**.
    ///
    /// > **Perdió el canal el 2026-09-02.** La pastilla escribía debajo el canal
    /// > del Track en pequeño, y como el Track N arranca en el canal N eso era
    /// > el mismo número dos veces: un dato que no informaba y ocupaba alto.
    /// > El canal se edita ahora en la pantalla MIDI, donde se ven los doce a la
    /// > vez y un choque de canales se detecta sin ir Track por Track.
    ///
    /// Los tres estados se leen sin texto: el elegido va relleno del acento de
    /// la familia activa, los que tienen material llevan ese acento en el trazo,
    /// y los vacíos solo el borde en reposo.
    ///
    /// > **Se atenúa cuando el Track no se oye, desde el 2026-09-02.** Con un
    /// > solo puesto, once Tracks callan sin que ninguno lleve la `M` encendida:
    /// > sin esta marca, once silencios no tendrían nada que los explicara y
    /// > parecerían un fallo.
    private func button(for index: Int) -> some View {
        let isSelected = index == selected
        let sounds = hasMaterial.indices.contains(index) && hasMaterial[index]
        let audible = mix.isAudible(index)

        return Button {
            onSelect(index)
        } label: {
            // **Con cero delante, `01`–`12`.** El handoff los numera así en las
            // cuatro pantallas, y no es cosmética: con ancho monoespaciado, doce
            // etiquetas de dos cifras ocupan lo mismo y la fila deja de dar un
            // salto de medio carácter entre el `9` y el `10`.
            Text(display: (index + 1).paddedForDisplay)
                .font(isSelected ? Typography.bodyStrong : Typography.body)
                .foregroundStyle(
                    isSelected ? Palette.onAccent : (sounds ? accent : Palette.muted)
                )
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .brutalistControl(
            accent: accent,
            isSelected: isSelected,
            isPopulated: sounds,
            radius: Brutalist.radius
        )
        .opacity(audible ? 1 : 0.45)
    }

    // MARK: - Mute y Solo

    /// El par **M / S** debajo de cada pastilla (FR5).
    ///
    /// **Dos botones y no uno que cicle.** Los dos estados son independientes
    /// —un Track puede estar muteado y soleado a la vez— y un botón de tres
    /// posiciones no puede representar eso; además obligaría a pasar por mute
    /// para llegar a solo.
    ///
    /// **Es la fila de un mixer, y por eso está aquí y no en otra pantalla.** El
    /// prototipo del handoff los pone en la pantalla `5 · Tracks`, que no
    /// existe; cuando exista, enseñará este mismo estado — nota fechada del
    /// 2026-09-02 en `design_handoff/README.md`.
    private var mixRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<Pattern.trackCount, id: \.self) { index in
                HStack(spacing: 4) {
                    mixButton("m", isOn: mix.isMuted(index), color: Palette.groove) {
                        onToggleMute(index)
                    }
                    mixButton("s", isOn: mix.isSoloed(index), color: Palette.tonal) {
                        onToggleSolo(index)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Un botón del par: su letra, y el relleno cuando está puesto.
    ///
    /// **El color lo hereda del handoff**, no de la familia activa: `M` en el
    /// mauve de GROOVE y `S` en el púrpura de TONAL. Es la única cosa de esta
    /// pantalla que no cambia de acento al cambiar de familia, y a propósito —la
    /// mezcla no pertenece a ninguna de las tres.
    private func mixButton(
        _ letter: String, isOn: Bool, color: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(display: letter)
                .font(isOn ? Typography.captionBold : Typography.caption)
                .foregroundStyle(isOn ? Palette.onAccent : Palette.muted)
                .frame(maxWidth: .infinity, minHeight: 32)
                // **Sin esto solo se toca la letra**, que en una `m` de 13
                // puntos son unos pocos píxeles de tinta dentro de un botón de
                // 32. Es el mismo fallo que el `−` del tempo destapó en la
                // Fase 1: el relleno lo pone `brutalistControl` por fuera del
                // `Button` y no cuenta como superficie tocable.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .brutalistControl(accent: color, isSelected: isOn, radius: Brutalist.radiusSmall)
    }

}
