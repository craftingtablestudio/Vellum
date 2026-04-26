import Foundation
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
  import simd
#endif
import Vellum

typealias EID = v0.EID
typealias CoreMove = v0.CoreMove
typealias CoreMoveTarget = v0.CoreMoveTarget
typealias Move = v0.Move
typealias MoveHistory = v0.MoveHistory
typealias HistoryBackup = v0.HistoryBackup
typealias EntityState = v0.EntityState
typealias MagneticHugsComponent = v0.MagneticHugsComponent

/// Initial board positions for all chess pieces, derived from ChessboardMarble.usda.
/// Each piece starts hugging its initial square magnet.
let CHESS_PRESET_DIC: [EID: EntityState] = {
  func piece(_ eid: String, hugging square: String) -> (EID, EntityState) {
    let id = EID.other(name: eid)
    return (
      id,
      EntityState(
        eid: id,
        magneticHugs: MagneticHugsComponent(hugging: EID.other(name: square), huggedBy: [])
      )
    )
  }
  return Dictionary(uniqueKeysWithValues: [
    // Black pieces
    piece("BB1", hugging: "C8"), piece("BB2", hugging: "F8"), piece("BK", hugging: "E8"),
    piece("BN1", hugging: "B8"), piece("BN2", hugging: "G8"), piece("BP1", hugging: "A7"),
    piece("BP2", hugging: "B7"), piece("BP3", hugging: "C7"), piece("BP4", hugging: "D7"),
    piece("BP5", hugging: "E7"), piece("BP6", hugging: "F7"), piece("BP7", hugging: "G7"),
    piece("BP8", hugging: "H7"), piece("BQ", hugging: "D8"), piece("BR1", hugging: "A8"),
    piece("BR2", hugging: "H8"),
    // White pieces
    piece("WB1", hugging: "C1"), piece("WB2", hugging: "F1"), piece("WK", hugging: "E1"),
    piece("WN1", hugging: "B1"), piece("WN2", hugging: "G1"), piece("WP1", hugging: "A2"),
    piece("WP2", hugging: "B2"), piece("WP3", hugging: "C2"), piece("WP4", hugging: "D2"),
    piece("WP5", hugging: "E2"), piece("WP6", hugging: "F2"), piece("WP7", hugging: "G2"),
    piece("WP8", hugging: "H2"), piece("WQ", hugging: "D1"), piece("WR1", hugging: "A1"),
    piece("WR2", hugging: "H1"),
  ])
}()

enum MockTarget { case magnet(String, _ huggerIndex: Int? = nil), originalCloner, position(SIMD3<Float>), unset }

enum mock {
  static func coreMove(
    eid: String,
    target: MockTarget = MockTarget.unset,
    orientation: simd_quatf? = nil,
    opacity: Float? = nil,
    duration: Duration? = nil
  ) -> CoreMove {
    let target =
      switch target {
      case .magnet(let magnetEid, let huggerIndex):
        CoreMoveTarget.magnet(EID.other(name: magnetEid), huggerIndex)
      case .originalCloner: CoreMoveTarget.magnet(.originalCloner)
      case .position(let position): CoreMoveTarget.position(position)
      case .unset: CoreMoveTarget.unset
      }
    return CoreMove(
      eid: EID.other(name: eid),
      target: target,
      orientation: orientation,
      opacity: opacity,
      duration: duration
    )
  }

  static func coreMove(
    eidClone: String,
    target: MockTarget = MockTarget.unset,
    orientation: simd_quatf? = nil,
    opacity: Float? = nil,
    duration: Duration? = nil
  ) -> CoreMove {
    let target =
      switch target {
      case .magnet(let magnetEid, let huggerIndex):
        CoreMoveTarget.magnet(EID.other(name: magnetEid), huggerIndex)
      case .originalCloner: CoreMoveTarget.magnet(.originalCloner)
      case .position(let position): CoreMoveTarget.position(position)
      case .unset: CoreMoveTarget.unset
      }
    return CoreMove(
      eid: EID.clone(name: eidClone, cloneId: stableUUID(eidClone)),
      target: target,
      orientation: orientation,
      opacity: opacity,
      duration: duration
    )
  }

  /// Produces a deterministic UUID from a string so the same eidClone string
  /// yields the same EID across both history setup and assertions in a test.
  private static func stableUUID(_ string: String) -> UUID {
    var h: UInt64 = 14_695_981_039_346_656_037
    for byte in string.utf8 { h ^= UInt64(byte); h = h &* 1_099_511_628_211 }
    return UUID(uuid: (
      UInt8((h >> 56) & 0xFF), UInt8((h >> 48) & 0xFF),
      UInt8((h >> 40) & 0xFF), UInt8((h >> 32) & 0xFF),
      UInt8((h >> 24) & 0xFF), UInt8((h >> 16) & 0xFF),
      UInt8((h >> 8) & 0xFF), UInt8(h & 0xFF),
      0, 0, 0, 0, 0, 0, 0, 0
    ))
  }

  static func move(
    eid: String,
    target: MockTarget = .unset,
    orientation: simd_quatf? = nil,
    opacity: Float? = nil,
    duration: Duration? = nil
  ) -> Move {
    return Move([
      [
        mock.coreMove(
          eid: eid,
          target: target,
          orientation: orientation,
          opacity: opacity,
          duration: duration
        )
      ]
    ])
  }
}
