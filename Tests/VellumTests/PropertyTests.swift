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
  @Test func clamping_negativeInt_becomesLastMove() { #expect(MoveNr(clamping: -99) == .lastMove) }

  /// Round-tripping through JSON preserves both cases
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

  /// `playedMoves` is sliced to `moveNr` when browsing
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
