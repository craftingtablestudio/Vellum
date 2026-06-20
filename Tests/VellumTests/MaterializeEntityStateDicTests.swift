import Foundation
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
  import simd
#endif
import Testing

@testable import Vellum

// MARK: - MaterializeEntityStateDicTests · recompute the materialised state from history

/// `materializeEntityStateDic` replaces the (removed) persisted `entityDic`: it forward-folds
/// `presetDic` + `history.moves[0..moveNr]` into `[EID: EntityState]` on demand (issue #203).
struct MaterializeEntityStateDicTests {
  /// Empty history materialises straight back to the preset baseline.
  @Test func emptyHistory_returnsPreset() {
    let history = MoveHistory()
    let dic = history.materializeEntityStateDic(presetDic: CHESS_PRESET_DIC)
    #expect(dic.count == CHESS_PRESET_DIC.count)
    #expect(dic[EID.other(name: "WP1")]?.magneticHugs?.hugging == EID.other(name: "A2"))
  }

  /// A single magnet move re-targets the moved entity while everything else stays on preset.
  @Test func magnetMove_updatesHuggingMagnet() throws {
    var history = MoveHistory()
    _ = try history.appendMove(
      mock.move(eid: "WP1", target: .magnet("A4")),
      initialStateDic: CHESS_PRESET_DIC,
      atIndex: nil,
      setMoveNr: true
    )
    let dic = history.materializeEntityStateDic(presetDic: CHESS_PRESET_DIC)
    #expect(dic[EID.other(name: "WP1")]?.magneticHugs?.hugging == EID.other(name: "A4"))
    // An untouched piece keeps its preset magnet.
    #expect(dic[EID.other(name: "WP2")]?.magneticHugs?.hugging == EID.other(name: "B2"))
  }

  /// A position move clears the hug and records the new position.
  @Test func positionMove_clearsHug_andSetsPosition() throws {
    var history = MoveHistory()
    _ = try history.appendMove(
      mock.move(eid: "WP1", target: .position([0.1, 0.0, 0.2])),
      initialStateDic: CHESS_PRESET_DIC,
      atIndex: nil,
      setMoveNr: true
    )
    let state =
      history.materializeEntityStateDic(presetDic: CHESS_PRESET_DIC)[EID.other(name: "WP1")]
    #expect(state?.magneticHugs?.hugging == nil)
    #expect(state?.position == SIMD3<Float>(0.1, 0.0, 0.2))
  }

  /// `upTo` materialises an earlier point in history — the latest move is not yet folded in.
  @Test func upTo_materialisesEarlierMoveNr() throws {
    var history = MoveHistory()
    _ = try history.appendMove(
      mock.move(eid: "WP1", target: .magnet("A4")),
      initialStateDic: CHESS_PRESET_DIC,
      atIndex: nil,
      setMoveNr: true
    )
    _ = try history.appendMove(
      mock.move(eid: "WP1", target: .magnet("A5")),
      initialStateDic: CHESS_PRESET_DIC,
      atIndex: nil,
      setMoveNr: true
    )
    // At move 1, only the first move is visible.
    let atMove1 = history.materializeEntityStateDic(
      presetDic: CHESS_PRESET_DIC,
      upTo: ActualMoveNr(1)
    )
    #expect(atMove1[EID.other(name: "WP1")]?.magneticHugs?.hugging == EID.other(name: "A4"))
    // At move 2 (current), the second move wins.
    let atMove2 = history.materializeEntityStateDic(presetDic: CHESS_PRESET_DIC)
    #expect(atMove2[EID.other(name: "WP1")]?.magneticHugs?.hugging == EID.other(name: "A5"))
  }

  /// An entity whose final magnet is a `.destroy` magnet is dropped from the materialised scene,
  /// mirroring the live capture-deletes-the-entity behaviour.
  @Test func destroyerBoundEntity_isDropped() throws {
    let stone = EID.other(name: "Stone1")
    let bowl = EID.other(name: "Bowl")
    let presetDic: [EID: EntityState] = [
      stone: EntityState(eid: stone, position: [0, 0, 0]),
      bowl: EntityState(eid: bowl, magneticField: v0.MagneticFieldPartial(hugEffect: .destroy)),
    ]
    var history = MoveHistory()
    _ = try history.appendMove(
      mock.move(eid: "Stone1", target: .magnet("Bowl")),
      initialStateDic: presetDic,
      atIndex: nil,
      setMoveNr: true
    )
    let dic = history.materializeEntityStateDic(presetDic: presetDic)
    #expect(dic[stone] == nil, "A captured (destroyer-bound) entity must not appear")
    #expect(dic[bowl] != nil, "The destroyer magnet itself stays")
    // The dropped stone must not dangle in the bowl's huggedBy.
    #expect(dic[bowl]?.magneticHugs?.huggedBy.contains(stone) != true)
  }

  /// A magnet whose only hugger moves away keeps a present-but-empty `MagneticHugsComponent`
  /// (mirroring the live scene), so its `huggedBy` reads `[]` rather than `nil`, and the moved
  /// piece's new magnet lists it.
  @Test func magnetThatLosesHugger_keepsEmptyComponent() throws {
    let piece = EID.other(name: "WN1")
    let from = EID.other(name: "B1")
    let to = EID.other(name: "A1")
    let presetDic: [EID: EntityState] = [
      piece: EntityState(
        eid: piece,
        magneticHugs: MagneticHugsComponent(hugging: from, huggedBy: [])
      ),
      from: EntityState(
        eid: from,
        magneticHugs: MagneticHugsComponent(hugging: nil, huggedBy: [piece])
      ), to: EntityState(eid: to, magneticHugs: MagneticHugsComponent(hugging: nil, huggedBy: [])),
    ]
    var history = MoveHistory()
    _ = try history.appendMove(
      mock.move(eid: "WN1", target: .magnet("A1")),
      initialStateDic: presetDic,
      atIndex: nil,
      setMoveNr: true
    )
    let dic = history.materializeEntityStateDic(presetDic: presetDic)
    #expect(dic[piece]?.magneticHugs?.hugging == to)
    #expect(
      dic[from]?.magneticHugs?.huggedBy == [],
      "vacated magnet keeps an empty component, not nil"
    )
    #expect(dic[to]?.magneticHugs?.huggedBy == [piece], "new magnet lists the moved piece")
    // Bidirectional consistency holds — no validation errors.
    #expect(magnetHugsAreConsistent(dic))
  }

  /// Local mirror of the magnet-hug bidirectional invariants `validateEntityDic` checks, kept in
  /// Vellum (which has no Magisterium dependency) so the perf/correctness suite is self-contained.
  private func magnetHugsAreConsistent(_ dic: [EID: EntityState]) -> Bool {
    for (eid, state) in dic {
      if let magnet = state.magneticHugs?.hugging {
        guard let magnetState = dic[magnet],
          (magnetState.magneticHugs?.huggedBy ?? []).contains(eid)
        else { return false }
      }
      for hugger in state.magneticHugs?.huggedBy ?? [] {
        guard dic[hugger]?.magneticHugs?.hugging == eid else { return false }
      }
    }
    return true
  }

  /// `physicsMode` comes from `presetDic`. A preset entity keeps its mode; a clone spawned
  /// mid-history (absent from `presetDic`) resolves to `nil` — intended, and harmless because no
  /// load path applies `entityDic.physicsMode` (see `materializeEntityStateDic` docs).
  @Test func physicsMode_fromPreset_nilForMidHistoryClone() throws {
    let board = EID.other(name: "Board")
    let clone = EID.clone(name: "Card", cloneId: mock.stableUUID("phys"))
    let presetDic: [EID: EntityState] = [
      board: EntityState(eid: board, position: [0, 0, 0], physicsMode: .static)
    ]
    var history = MoveHistory()
    // A mid-history clone placement — the clone is never part of presetDic.
    _ = try history.appendMove(
      Move([[CoreMove(eid: clone, target: .position([1, 0, 0]))]]),
      initialStateDic: presetDic,
      atIndex: nil,
      setMoveNr: true
    )
    let dic = history.materializeEntityStateDic(presetDic: presetDic)
    #expect(dic[board]?.physicsMode == .static, "preset entity keeps its persisted physicsMode")
    #expect(
      dic[clone]?.physicsMode == nil,
      "mid-history clone has no preset entry → nil (intended)"
    )
  }

  // MARK: - Perf gate (issue #203 validation step)

  /// Validation gate: 1000 moves over ~50 entities must cold-open recompute well under budget.
  /// The algorithm is linear in total CoreMoves; this guards the constant factor. Generous
  /// ceiling (CI is shared and slow) — the soft target is ~200ms on iPhone-class hardware.
  @Test func perf_thousandMoves_recomputesUnderBudget() throws {
    let entityCount = 50
    let moveCount = 1000

    // ~50 entities sitting at preset positions.
    var presetDic: [EID: EntityState] = [:]
    for i in 0 ..< entityCount {
      let eid = EID.other(name: "E\(i)")
      presetDic[eid] = EntityState(eid: eid, position: [Float(i), 0, 0])
    }
    // 1000 position moves spread across those entities.
    var history = MoveHistory()
    for m in 0 ..< moveCount {
      let i = m % entityCount
      _ = try history.appendMove(
        mock.move(eid: "E\(i)", target: .position([Float(i), 0, Float(m)])),
        initialStateDic: presetDic,
        atIndex: nil,
        setMoveNr: true
      )
    }

    let clock = ContinuousClock()
    let elapsed = clock.measure {
      let dic = history.materializeEntityStateDic(presetDic: presetDic)
      #expect(dic.count == entityCount)
    }
    print("⏱️ [materializeEntityStateDic] \(moveCount) moves / \(entityCount) eids → \(elapsed)")
    #expect(elapsed < .seconds(2), "Recompute should be well under budget; took \(elapsed)")
  }
}
