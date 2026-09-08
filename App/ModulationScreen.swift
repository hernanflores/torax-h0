import Engine
import SwiftUI

/// La pantalla `modulation`: la forma del movimiento de la velocity y cuánto
/// se desvía (FR10, FR11).
///
/// **Aquí el dedo opera**, como en `scale`, `midi` y `banks`. No contradice al
/// principio rector: lo que `product-guidelines.md` protege es que no haga falta
/// mirar el iPad *para tocar*, y esto se configura antes. La pantalla `track`
/// sigue siendo la que se lee mientras suena, y ahí no se edita nada.
///
/// **Dos columnas, ~70/30 como el handoff** (FR11). A la izquierda lo que se
/// elige —la rejilla de ondas— y lo que se mira —el panel de respuesta—; a la
/// derecha el card alto de `accent` y el resumen al pie.
///
/// **El mauve no es un color nuevo.** `Palette.groove` ya es `#AA6DA8`, y la
/// pantalla lo usa porque **lo que modula es velocity**, que es Groove: el color
/// sigue codificando qué tipo de parámetro se toca, que es lo que
/// `product-guidelines.md` le exige. No se añade un cuarto acento que habría que
/// verificar a un metro.
struct ModulationScreen: View {

    let model: TransportModel

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 20) {
                ModulationContext(
                    track: model.selectedTrackIndex,
                    cycle: model.editingCycle
                )

                WaveformSelector(
                    waveform: model.modulation.waveform,
                    onSelect: { model.setModulation(model.modulation.with(waveform: $0)) }
                )

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
    }
}

/// De qué Track y de qué Cycle se está editando la modulación (FR16, FR17).
///
/// **Nombra los dos, y no solo el Track.** `modulation` escribe sobre el Cycle
/// **en edición**, que puede no ser el que suena: sin decirlo, editar el B
/// mientras suena el A parece que la pantalla miente.
///
/// **Es una etiqueta y no un selector** (FR17), a diferencia de la de `scale`.
/// El Track se elige con el controlador —el instrumento— y esta pantalla solo lo
/// lee: no lleva la franja de doce. Los dos cursores los mueven los knobs, y
/// duplicar esa vía aquí sería inventar un segundo sitio donde se decide lo
/// mismo.
struct ModulationContext: View {

    let track: Int
    let cycle: Int

    var body: some View {
        Text(display: "track \(Self.two(track + 1)) · cycle \(Self.two(cycle + 1))")
            .font(Typography.caption)
            .foregroundStyle(Palette.mutedBright)
            .monospacedDigit()
    }

    /// Dos cifras, como el handoff: `track 04`, no `track 4`.
    ///
    /// **Con ancho fijo el texto no se mueve** al pasar del Track 9 al 10, que es
    /// lo que se mira de reojo mientras se ajusta.
    private static func two(_ number: Int) -> String {
        number < 10 ? "0\(number)" : "\(number)"
    }
}

/// La rejilla 2×2 con las cuatro ondas (FR11, FR19).
///
/// **El orden es el de `Waveform.allCases`**, que es parte del contrato del tipo
/// y está fijado por test: `saw`, `triangle`, `sine`, `pulse`.
///
/// **Escribe sobre el Cycle en edición**, y esa regla no vive aquí sino en
/// `ControlInput.setModulation` — donde hay tests. Esta vista solo dice qué onda
/// se ha tocado.
struct WaveformSelector: View {

    let waveform: Waveform
    let onSelect: (Waveform) -> Void

    private static let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(display: "waveform")
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.text)

            LazyVGrid(columns: Self.columns, spacing: 12) {
                ForEach(Waveform.allCases, id: \.self) { candidate in
                    WaveformCard(
                        waveform: candidate,
                        isSelected: candidate == waveform,
                        onSelect: { onSelect(candidate) }
                    )
                }
            }
        }
    }
}

/// Una onda de la rejilla: su dibujo y su nombre (FR19, FR20).
///
/// **Seleccionada es un bloque de mauve plano con la etiqueta oscura**; las
/// otras tres van hundidas con borde neutro. Es la misma gramática que el resto
/// del sistema —lo elegido se rellena, lo demás lleva trazo— con el acento de
/// Groove, porque lo que se modula es velocity.
///
/// **El objetivo táctil es el card entero.** Se toca sin mirar de cerca, así que
/// el `contentShape` cubre los 96 puntos de alto y no solo el trazo de la onda.
struct WaveformCard: View {

    let waveform: Waveform
    let isSelected: Bool
    let onSelect: () -> Void

    /// **Alto fijo y generoso.** El dibujo necesita sitio para leerse a un metro
    /// y el card es el objetivo táctil: 96 puntos son más del doble del mínimo
    /// cómodo, que es lo que pide `product-guidelines.md` de algo que se toca de
    /// pie.
    private static let height: CGFloat = 96

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 10) {
                WaveformPreview(waveform: waveform)
                    .stroke(
                        isSelected ? Palette.onAccent : Palette.mutedBright,
                        style: StrokeStyle(lineWidth: Brutalist.stroke, lineJoin: .round)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)

                Text(display: waveform.description)
                    .font(isSelected ? Typography.bodyStrong : Typography.body)
                    .foregroundStyle(isSelected ? Palette.onAccent : Palette.text)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            // Sin esto solo responden el trazo y las letras, que entre los dos
            // no llegan a la mitad del card. Es el mismo defecto que se corrigió
            // en los escalones del tempo.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .brutalistControl(
            accent: Palette.groove,
            isSelected: isSelected,
            isPopulated: false,
            radius: Brutalist.radius
        )
    }
}

/// El dibujo de una onda: **dos ciclos, trazo geométrico, sin relleno** (FR19).
///
/// **Dos ciclos y no uno**, como el handoff: con uno solo, `saw` y `triangle`
/// se distinguen mal —la diferencia está en el corte, y un corte necesita algo
/// después para leerse como corte—.
///
/// **Sale de `Waveform.value(atStep:of:)`, la misma función que suena.** Podría
/// dibujarse con una fórmula propia y sería más corto; sería también una segunda
/// definición de la forma, capaz de discrepar en silencio de lo que se emite. La
/// resolución del muestreo es cosa del dibujo —64 puntos por ciclo, que a este
/// tamaño es una curva continua— y la forma es la del motor.
///
/// > **Que `saw` se dibuje con su corte en el cuarto y no a media vuelta no es
/// > un error del dibujo.** Es la forma que se entrega, y alinear su pico con el
/// > de las otras tres es lo que hace que cambiar de onda no mueva el acento de
/// > sitio (FR5). El dibujo tiene que enseñar lo que suena.
///
/// > **`SwiftUI.Shape` con el módulo delante, y no por gusto.** `Engine.Shape`
/// > es la familia de Steps, Pulses, Rotate y Division, y este fichero importa
/// > los dos módulos: sin calificar, el nombre es ambiguo. Es el mismo choque
/// > que la suite de `MIDI` resuelve con un `typealias` para `Pattern`.
struct WaveformPreview: SwiftUI.Shape {

    let waveform: Waveform

    /// Puntos por ciclo. No es un parámetro del dominio: es cuánto se muestrea
    /// para que la línea se vea curva y no escalonada.
    private static let resolution = 64

    private static let cycles = 2

    /// Cuánto tiene que saltar el valor entre dos muestras vecinas para que el
    /// dibujo lo trate como un corte y no como una pendiente.
    ///
    /// > **Ciento veinte y no «cualquier bajada».** A esta resolución una
    /// > pendiente normal se mueve unas pocas unidades por muestra; los dos
    /// > cortes que existen —el de `saw` y los dos de `pulse`— valen 190 y 200.
    /// > Cualquier número entre medias sirve, y este deja sitio de sobra a los
    /// > dos lados.
    private static let discontinuity = 120

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let total = Self.resolution * Self.cycles

        func point(_ index: Int, _ value: Int) -> CGPoint {
            // La onda va de −100 a 100 y la `y` de una vista crece hacia abajo,
            // así que el signo se invierte: +100 es el borde de arriba.
            CGPoint(
                x: rect.minX + rect.width * CGFloat(index) / CGFloat(total),
                y: rect.midY - rect.height / 2 * CGFloat(value) / 100
            )
        }

        // Un punto extra para cerrar el segundo ciclo en su final, que si no
        // queda un hueco del ancho de una muestra contra el borde derecho.
        var previous = waveform.value(atStep: 0, of: Self.resolution)
        path.move(to: point(0, previous))

        for index in 1...total {
            let value = waveform.value(atStep: index, of: Self.resolution)

            // **Un corte se dibuja vertical, y solo un corte.**
            //
            // > **Se hacía en cada muestra de `saw` y de `pulse`, y se vio en la
            // > primera captura del simulador.** `pulse` salía bien —dos valores,
            // > así que el escalón coincide con la forma— pero `saw` salía como
            // > una escalera dentada en vez de una rampa: el paso horizontal más
            // > vertical se aplicaba también donde la onda solo sube un poco.
            // > Lo que distingue un corte de una pendiente es el tamaño del
            // > salto, no de qué onda se trate.
            if abs(value - previous) >= Self.discontinuity {
                path.addLine(to: point(index, previous))
            }
            path.addLine(to: point(index, value))
            previous = value
        }
        return path
    }
}
