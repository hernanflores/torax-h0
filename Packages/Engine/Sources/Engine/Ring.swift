/// El patrón de un Shape dispuesto como posiciones sobre un círculo.
///
/// **La forma circular no es decoración.** `product-guidelines.md` la elige
/// porque hace evidentes las dos propiedades que definen el motor: la
/// naturaleza cíclica del Track, que el playhead recorre y cierra, y la
/// simetría del reparto euclidiano — 16/4 se ve regular, 16/5 equilibrado pero
/// asimétrico.
///
/// **Por qué la geometría vive en `Engine` y no en la vista.** `workflow.md`:
/// «si algo en `App` merece un test, está en el sitio equivocado». Repartir
/// posiciones sobre una vuelta y decidir cuáles llevan Pulse es lógica con
/// invariantes que se rompen en silencio, así que se escribe donde hay tests y
/// no donde hay píxeles.
///
/// **No recalcula nada.** El reparto ya lo hizo `EuclideanRhythm` al construir
/// el Shape, con Rotate incluido; esto solo lo lee posición a posición. Si aquí
/// se repartiera otra vez, habría dos algoritmos que podrían discrepar.
///
/// No es código de tiempo real: construir el anillo asigna memoria. Se hace en
/// el hilo principal, para dibujar.
public struct Ring: Equatable, Sendable {

    /// Una posición del anillo: dónde cae y si dispara.
    public struct Position: Equatable, Sendable {

        /// Índice del Step que ocupa esta posición.
        public let step: Int

        /// Dónde cae en la vuelta, como fracción en `[0, 1)`.
        ///
        /// **Fracción y no radianes ni píxeles.** Quien dibuja conoce el tamaño
        /// de la pantalla, el sentido de giro y dónde está el origen visual;
        /// este tipo no, y no debería. Convertir a un ángulo es una
        /// multiplicación en el sitio que sí lo sabe.
        public let turn: Double

        /// Si esta posición dispara.
        public let isPulse: Bool
    }

    /// Las posiciones del anillo, en orden de Step.
    public let positions: [Position]

    /// Dispone el patrón del Shape sobre la vuelta.
    ///
    /// **El Step 0 cae siempre en `0`.** Si su posición dependiera de cuántos
    /// Steps hay, el anillo entero giraría al mover el knob de Steps y Rotate
    /// dejaría de ser lo único que rota — que es justo lo que
    /// `product-guidelines.md` pide que se lea literalmente.
    public init(shape: Shape) {
        let count = shape.steps.count
        positions = (0..<count).map { step in
            Position(
                step: step,
                turn: Double(step) / Double(count),
                isPulse: shape.triggers(atStep: step)
            )
        }
    }
}
