import Foundation
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
  import simd
#endif
import Testing
import Vellum

// MARK: - EntityStateCodableTests · Versions/V0.swift

struct EntityStateCodableTests {

  struct EntityStateTests {
    // Complex: EntityState with all optional fields set round-trips through JSON unchanged
    @Test func roundTrip_allFieldsPopulated() throws {
      let original = EntityState(
        eid: .other(name: "Rook"),
        position: [1, 2, 3],
        orientation: .getNonRotated(),
        scale: [2, 2, 2],
        physicsMode: .dynamic,
        magneticHugs: MagneticHugsComponent(hugging: .other(name: "Board"), huggedBy: [.other(name: "Pawn")]),
        modelMeta: ModelMetaComponent(name: "RookModel", pathTextureDic: ["path": "rook.png"]),
        opacity: 0.8
      )
      let decoded = try JSONDecoder().decode(EntityState.self, from: JSONEncoder().encode(original))
      #expect(decoded == original)
    }

    // Boundary: EntityState with all optional fields nil round-trips without writing nil keys
    @Test func roundTrip_allOptionalsNil() throws {
      let original = EntityState(eid: .other(name: "King"))
      let decoded = try JSONDecoder().decode(EntityState.self, from: JSONEncoder().encode(original))
      #expect(decoded == original)
    }
  }

  struct CoreMoveTests {
    // Complex: CoreMove with all optional fields set round-trips through JSON unchanged
    @Test func roundTrip_allFieldsPopulated() throws {
      let original = CoreMove(
        eid: .clone(name: "Pawn", cloneId: UUID()),
        target: .position([3, 0, 0]),
        orientation: .getNonRotated(),
        scale: [1, 1, 1],
        opacity: 0.5,
        modelMeta: ModelMetaComponent(name: "M", pathTextureDic: [:]),
        duration: .seconds(1),
        sound: .drop
      )
      let decoded = try JSONDecoder().decode(CoreMove.self, from: JSONEncoder().encode(original))
      #expect(decoded == original)
    }

    // Boundary: CoreMove round-trip with revertToInitialState=true persists that flag
    @Test func roundTrip_revertToInitialState() throws {
      let original = CoreMove(eid: .other(name: "A"), revertToInitialState: true)
      let decoded = try JSONDecoder().decode(CoreMove.self, from: JSONEncoder().encode(original))
      #expect(decoded.revertToInitialState == true)
    }
  }

  struct MoveHistoryTests {
    // Complex: MoveHistory with multiple moves encodes as [String:Move] and decodes back in order
    @Test func roundTrip_preservesMoveOrder() throws {
      let move1 = mock.move(eid: "A", target: .position([1, 0, 0]))
      let move2 = mock.move(eid: "B", target: .position([2, 0, 0]))
      let move3 = mock.move(eid: "C", target: .position([3, 0, 0]))
      let history = MoveHistory(moves: [move1, move2, move3], moveNr: 1)
      let decoded = try JSONDecoder().decode(MoveHistory.self, from: JSONEncoder().encode(history))
      #expect(decoded.moves == [move1, move2, move3])
      #expect(decoded.moveNr == 1)
    }

    // Boundary: MoveHistory with zero moves round-trips cleanly
    @Test func roundTrip_emptyMoves() throws {
      let history = MoveHistory()
      let decoded = try JSONDecoder().decode(MoveHistory.self, from: JSONEncoder().encode(history))
      #expect(decoded.moves.isEmpty)
    }
  }
}
