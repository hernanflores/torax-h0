/// Qué parámetro se movió entre dos Shapes, y en cuánto quedó.
///
/// **Existe para el valor grande transitorio.** `product-guidelines.md` pide que
/// al girar un knob su valor aparezca en grande y se desvanezca; para eso hay
/// que saber cuál se movió, y eso es la diferencia entre el Shape de antes y el
/// de después. Es dominio, no presentación: la vista solo decide el tamaño de la
/// letra.
///
/// **Por qué no lo dice quien recibe el mensaje.** La entrada de control sí sabe
/// qué parámetro mapea un CC, pero también hay giros que no mueven nada —girar
/// contra un extremo— y publicaciones que no vienen de un knob. Comparar los dos
/// Shapes responde por el resultado y no por la intención, que es lo que la
/// pantalla debe reflejar.
public struct ShapeChange: Equatable, Sendable {

    /// Qué se movió.
    public let parameter: ShapeParameter

    /// Cómo quedó, listo para leerse.
    ///
    /// El término de la Pre Spec y el valor, sin adornos: la app informa, no
    /// conversa (`product-guidelines.md`).
    public let description: String

    /// Compara dos Shapes. Devuelve `nil` si no se movió nada.
    ///
    /// `nil` es el caso común y no es un error: llegan mensajes que no mueven
    /// nada y giros contra un extremo. Anunciar un valor ahí sería decir que
    /// pasó algo cuando no pasó.
    ///
    /// **Solo se anuncia el primero que difiera.** Un giro mueve un parámetro,
    /// así que el caso de dos a la vez no se produce por un knob; si el Shape
    /// cambiara entero —al cargar un Cycle, algún día— anunciar cuatro valores
    /// grandes a la vez sería peor que anunciar uno.
    public init?(from previous: Shape, to current: Shape) {
        guard previous != current else { return nil }

        if previous.steps != current.steps {
            parameter = .steps
            description = "Steps \(current.steps.count)"
        } else if previous.pulses != current.pulses {
            parameter = .pulses
            // El valor pedido, no `effectivePulses`: el knob está en este número
            // y mostrar el otro haría creer que se perdió.
            description = "Pulses \(current.pulses.count)"
        } else if previous.rotate != current.rotate {
            parameter = .rotate
            description = "Rotate \(current.rotate.amount)"
        } else if previous.division != current.division {
            parameter = .division
            description = "Division \(current.division)"
        } else {
            return nil
        }
    }
}
