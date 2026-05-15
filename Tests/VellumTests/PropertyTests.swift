import Foundation
import Testing
@testable import Vellum

// MARK: - MoveNrTests · encoding and clamping

struct MoveNrTests {
  /// `.lastMove` always encodes as -1 — the sentinel value contract
  @Test func lastMove_hasValueMinusOne() { #expect(MoveNr.lastMove.value == -1) }

  /// `.specific` passes through its raw value unchanged
  @Test func specific_hasCorrectIntValue() { #expect(MoveNr.specific(3).value == 3) }

  /// MoveNr(clamping:) with any negative value collapses to `.lastMove` rather than `.specific`
  /// Boundary: negative is out-of-range — the floor of the valid input domain
  @Test func clamping_negativeInt_becomesLastMove() {
    #expect(MoveNr(clamping: -99) == .lastMove)
    #expect(MoveNr(clamping: -2) == .lastMove)
    #expect(MoveNr(clamping: -1) == .lastMove)
    #expect(MoveNr(clamping: 0) != .lastMove)
    #expect(MoveNr(clamping: 1) != .lastMove)
  }

  /// Average: round-tripping through JSON preserves both cases
  @Test func encode_decode_roundTrip() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let lastMoveDecoded = try decoder.decode(MoveNr.self, from: try encoder.encode(MoveNr.lastMove))
    let specificDecoded = try decoder.decode(
      MoveNr.self,
      from: try encoder.encode(MoveNr.specific(7))
    )
    #expect(lastMoveDecoded == .lastMove)
    #expect(specificDecoded == .specific(7))
  }
}

// MARK: - MoveHistoryPropertyTests · computed properties

struct MoveHistoryPropertyTests {
  /// `playedMoves` on a history with no moves returns an empty array
  @Test func emptyHistory_playedMovesIsEmpty() {
    let history = MoveHistory()
    #expect(history.playedMoves.isEmpty)
  }

  /// Average: `playedMoves` is sliced to `moveNr` when browsing
  @Test func browsingHistory_playedMovesIsSliced() {
    let move1 = mock.move(eid: "E1", target: .position([1, 0, 0]))
    let move2 = mock.move(eid: "E2", target: .position([2, 0, 0]))
    var history = MoveHistory()
    history.moves = [move1, move2]
    history.moveNr = 1
    #expect(history.playedMoves == [move1])
  }

  /// `cannotUndo` is true when the history has no moves
  @Test func cannotUndo_whenHistoryIsEmpty() {
    let history = MoveHistory()
    #expect(history.cannotUndo(animatingTowards: nil))
  }

  /// `cannotUndo` is true when `moveNr` is at zero — no further undo is possible
  /// Boundary: moveNr == 0 is the floor; one step further would underflow the index
  @Test func cannotUndo_whenBrowsedToMoveZero() {
    var history = MoveHistory()
    history.moves = [mock.move(eid: "E1", target: .position([1, 0, 0]))]
    history.moveNr = 0
    #expect(history.cannotUndo(animatingTowards: nil))
  }

  /// `cannotRedo` is true when `moveNr` is the sentinel -1 — already at the latest move
  /// Boundary: -1 is the ceiling sentinel; no future moves exist to redo
  @Test func cannotRedo_whenAtLatestMove() {
    var history = MoveHistory()
    history.moves = [mock.move(eid: "E1", target: .position([1, 0, 0]))]
    history.moveNr = -1
    #expect(history.cannotRedo(animatingTowards: nil))
  }
}

// MARK: - MagneticFieldMeta tests

typealias MagneticFieldMeta = v0.MagneticFieldMeta

struct MagneticFieldMetaTests {
  /// CoreMove with magneticField roundtrips through JSON
  @Test func coreMove_magneticField_roundTrip() throws {
    let meta = MagneticFieldMeta(stackOffset: [0.01, 0, 0])
    let coreMove = CoreMove(
      eid: EID.other(name: "TestMagnet"),
      target: .position([1, 0, 0]),
      magneticField: meta
    )
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(coreMove)
    let decoded = try decoder.decode(CoreMove.self, from: data)
    #expect(decoded.magneticField == meta)
    #expect(decoded.magneticField?.stackOffset == [0.01, 0, 0])
  }

  /// CoreMove without magneticField decodes magneticField as nil (backwards-compatible)
  @Test func coreMove_noMagneticField_decodesNil() throws {
    let coreMove = CoreMove(
      eid: EID.other(name: "TestMagnet"),
      target: .position([1, 0, 0])
    )
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(coreMove)
    let decoded = try decoder.decode(CoreMove.self, from: data)
    #expect(decoded.magneticField == nil)
  }

  /// EntityState with magneticField roundtrips through JSON
  @Test func entityState_magneticField_roundTrip() throws {
    let meta = MagneticFieldMeta(stackOffset: [0, 0, 0.02])
    let state = EntityState(
      eid: EID.other(name: "TestMagnet"),
      position: [1, 0, 0],
      magneticField: meta
    )
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(state)
    let decoded = try decoder.decode(EntityState.self, from: data)
    #expect(decoded.magneticField == meta)
  }

  /// fillInEmptyParts populates magneticField from EntityState when nil
  @Test func fillInEmptyParts_populatesMagneticFieldFromEntityState() {
    let meta = MagneticFieldMeta(stackOffset: [0.01, 0, 0])
    let initialState = EntityState(
      eid: EID.other(name: "TestMagnet"),
      position: [1, 0, 0],
      magneticField: meta
    )
    var coreMove = CoreMove(
      eid: EID.other(name: "TestMagnet"),
      target: .position([2, 0, 0])
    )
    #expect(coreMove.magneticField == nil)
    coreMove.fillInEmptyParts(with: initialState)
    #expect(coreMove.magneticField == meta)
  }

  /// removePropsNillIn clears magneticField when the reference CoreMove has it nil
  @Test func removePropsNillIn_clearsMagneticField() {
    let meta = MagneticFieldMeta(stackOffset: [0.01, 0, 0])
    var coreMove = CoreMove(
      eid: EID.other(name: "TestMagnet"),
      target: .position([2, 0, 0]),
      magneticField: meta
    )
    let referenceCoreMove = CoreMove(
      eid: EID.other(name: "TestMagnet"),
      target: .position([2, 0, 0])
    )
    #expect(coreMove.magneticField != nil)
    coreMove.removePropsNillIn(referenceCoreMove)
    #expect(coreMove.magneticField == nil)
  }

  /// omit supports the magneticField CodingKeys case
  @Test func omit_clearsMagneticField() {
    let meta = MagneticFieldMeta(stackOffset: [0.01, 0, 0])
    let coreMove = CoreMove(
      eid: EID.other(name: "TestMagnet"),
      target: .position([2, 0, 0]),
      magneticField: meta
    )
    let omitted = coreMove.omit(.magneticField)
    #expect(omitted.magneticField == nil)
    #expect(omitted.eid == coreMove.eid)
  }

  /// description includes magneticField when present
  @Test func description_includesMagneticField() {
    let meta = MagneticFieldMeta(stackOffset: [0.01, 0, 0])
    let coreMove = CoreMove(
      eid: EID.other(name: "TestMagnet"),
      target: .position([2, 0, 0]),
      magneticField: meta
    )
    #expect(coreMove.description.contains("magneticField"))
  }
}

// MARK: - CoreMove delay tests

struct CoreMoveDelayTests {
  /// CoreMove with delay roundtrips through JSON — backwards-compatible (nil decodes from old data)
  @Test func coreMove_delay_roundTrip() throws {
    let withDelay = CoreMove(
      eid: EID.other(name: "Card1"),
      target: .position([1, 0, 0]),
      duration: .milliseconds(200),
      delay: .milliseconds(100)
    )
    let withoutDelay = CoreMove(
      eid: EID.other(name: "Card2"),
      target: .position([2, 0, 0]),
      duration: .milliseconds(200)
    )

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    // With delay: roundtrips correctly
    let dataWith = try encoder.encode(withDelay)
    let decodedWith = try decoder.decode(CoreMove.self, from: dataWith)
    #expect(decodedWith.delay == .milliseconds(100))
    #expect(decodedWith.duration == .milliseconds(200))

    // Without delay: decodes as nil (backwards-compatible)
    let dataWithout = try encoder.encode(withoutDelay)
    let decodedWithout = try decoder.decode(CoreMove.self, from: dataWithout)
    #expect(decodedWithout.delay == nil)

    // Merging preserves delay from other
    let merged = withoutDelay.merging(withDelay)
    #expect(merged.delay == .milliseconds(100))

    // Omit clears delay
    let omitted = withDelay.omit(.delay)
    #expect(omitted.delay == nil)
    #expect(omitted.duration == .milliseconds(200))
  }
}
