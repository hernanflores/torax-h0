/// Qué hay que refrescar además del `Project` cuando se pega un Pattern.
///
/// **Lo encontró la verificación en dispositivo del 2026-09-10**, y es la razón
/// de que exista. Pegar escribía en el `Project` y dejaba intactas las dos
/// copias que el `Project` no gobierna:
///
/// - **La copia viva del Pattern cargado**, que es la que la pantalla edita y la
///   que se vuelca al Bank en cada edición. Sin refrescarla, la pantalla enseña
///   el material anterior y **el primer giro de knob lo escribe encima de lo
///   pegado**, que se pierde sin aviso.
/// - **El snapshot que el transporte ya tiene armado.** Se le entregó al armar,
///   antes del pegado, así que sin rearmar entra el material viejo en el límite
///   de compás — que era el síntoma reportado: lo pegado no sonaba hasta volver
///   a disparar el Pattern a mano.
///
/// **No contradice FR10.** Lo que aquélla prohíbe es armar un hueco distinto y
/// mover la selección; refrescar una copia no es ninguna de las dos, y rearmar
/// **el mismo** hueco con el material nuevo tampoco cambia a dónde va el
/// transporte, solo con qué.
public struct PatternPasteRefresh: Equatable, Sendable {

    /// Si hay que dejar la copia viva —y la entrada de control con ella— igual a
    /// lo que se acaba de pegar.
    public let refreshesLiveCopy: Bool

    /// Si hay que volver a armar el mismo hueco, ahora con el material nuevo.
    public let rearms: Bool

    /// Decide con las tres cosas que importan: dónde cae el pegado, qué hueco
    /// está cargado y cuál está armado, si hay alguno.
    ///
    /// Los dos pueden salir ciertos a la vez: sonando se puede rearmar el hueco
    /// que ya suena, y entonces el destino es lo cargado y lo armado.
    public init(destination: Int, loaded: Int, armed: Int?) {
        refreshesLiveCopy = destination == loaded
        rearms = destination == armed
    }
}
