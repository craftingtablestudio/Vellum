import Foundation
import simd
import Vellum

enum MockTarget {
  case magnet(String, _ huggerIndex: Int? = nil), position(SIMD3<Float>), unset
}

enum mock {
  static func position() -> SIMD3<Float> {
    return [
      floor(Float.random(in: 10...20)) / 10, floor(Float.random(in: 10...20)) / 10,
      floor(Float.random(in: 10...20)) / 10,
    ]
  }

  static func coreMove(
    eid: String,
    target: MockTarget = MockTarget.unset,
    orientation: simd_quatf? = nil,
    opacity: Float? = nil,
    duration: Duration? = nil,
    revertToInitialState: Bool = false
  ) -> CoreMove {
    let target =
      switch target {
      case .magnet(let magnetEid, let huggerIndex):
        CoreMoveTarget.magnet(EID.other(name: magnetEid), huggerIndex)
      case .position(let position): CoreMoveTarget.position(position)
      case .unset: CoreMoveTarget.unset
      }
    return CoreMove(
      eid: EID.other(name: eid),
      target: target,
      orientation: orientation,
      opacity: opacity,
      duration: duration,
      revertToInitialState: revertToInitialState
    )
  }

  static func move(
    eid: String,
    target: MockTarget = .unset,
    orientation: simd_quatf? = nil,
    opacity: Float? = nil,
    duration: Duration? = nil,
    revertToInitialState: Bool = false
  ) -> Move {
    return Move([
      [
        mock.coreMove(
          eid: eid,
          target: target,
          orientation: orientation,
          opacity: opacity,
          duration: duration,
          revertToInitialState: revertToInitialState
        )
      ]
    ])
  }
}
