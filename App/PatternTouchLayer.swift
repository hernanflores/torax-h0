import SwiftUI
import UIKit

/// La capa que resuelve los toques de la rejilla de Patterns.
///
/// **Existe porque dos `Button` hermanos de SwiftUI no ven toques
/// simultáneos.** Cada uno reclama el suyo y el segundo dedo no llega nunca, así
/// que el acorde —mantener el origen y tocar el destino— no se puede expresar
/// con dieciséis botones. La rejilla entera pasa a ser una sola vista que recibe
/// los toques crudos y los traduce a índices de celda.
///
/// **Solo traduce.** Qué significa un toque lo decide `PatternChord`, en
/// `Engine`, donde hay tests; aquí no hay ninguna regla que probar y por eso
/// esta capa puede vivir en `App`, que no se mide.
///
/// **Un toque que se levanta fuera de su celda se cancela** (FR21), que es lo
/// que un `Button` ya hacía y no se puede perder al sustituirlo.
struct PatternTouchLayer: UIViewRepresentable {

    /// Dónde cae cada celda, en el espacio de la rejilla. El índice del array es
    /// el del hueco.
    let cellFrames: [CGRect]

    let onDown: (Int) -> Void
    let onUp: (Int) -> Void
    let onCancel: (Int) -> Void

    func makeUIView(context: Context) -> TouchGridView {
        let view = TouchGridView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: TouchGridView, context: Context) {
        view.cellFrames = cellFrames
        view.onDown = onDown
        view.onUp = onUp
        view.onCancel = onCancel
    }
}

/// La vista que recibe los toques.
///
/// **Recuerda en qué celda empezó cada dedo**, y no dónde está ahora: un toque
/// pertenece a la celda donde bajó, y arrastrar fuera lo cancela en vez de
/// mudarlo. Es el comportamiento de un `Button`, escrito a mano.
final class TouchGridView: UIView {

    var cellFrames: [CGRect] = []
    var onDown: (Int) -> Void = { _ in }
    var onUp: (Int) -> Void = { _ in }
    var onCancel: (Int) -> Void = { _ in }

    /// La celda donde bajó cada dedo que sigue abajo.
    ///
    /// **Se indexa por el toque y no por la celda** porque dos dedos pueden caer
    /// en la misma, y porque `UITouch` es el mismo objeto durante toda la vida
    /// del toque — es lo que UIKit garantiza y lo que permite emparejar el `up`
    /// con su `down`.
    private var origins: [ObjectIdentifier: Int] = [:]

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let index = slot(under: touch) else { continue }

            origins[ObjectIdentifier(touch)] = index
            onDown(index)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let origin = origins.removeValue(forKey: ObjectIdentifier(touch)) else {
                continue
            }

            if slot(under: touch) == origin {
                onUp(origin)
            } else {
                onCancel(origin)
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let origin = origins.removeValue(forKey: ObjectIdentifier(touch)) else {
                continue
            }
            onCancel(origin)
        }
    }

    /// El hueco que hay bajo ese dedo, o `nil` si cayó entre celdas.
    private func slot(under touch: UITouch) -> Int? {
        let point = touch.location(in: self)
        return cellFrames.firstIndex { $0.contains(point) }
    }
}

/// Dónde acabó dibujada cada celda, recogido de las propias celdas.
///
/// **Se mide y no se calcula.** Deducir la rejilla de su geometría —cuatro
/// columnas, ocho puntos de separación— funcionaría hoy y se rompería en
/// silencio el día que alguien cambie el espaciado; preguntarle a cada celda
/// dónde quedó no se puede desincronizar.
struct PatternCellFrames: PreferenceKey {

    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, latest in latest }
    }
}
