import Foundation
import Testing
import Vellum

// MARK: - MoveNrTests · encoding and clamping

struct MoveNrTests {
  // `.lastMove` always encodes as -1 — the sentinel value contract
  @Test func lastMove_hasValueMinusOne() { #expect(MoveNr.lastMove.value == -1) }

  // `.specific` passes through its raw value unchanged
  @Test func specific_hasCorrectIntValue() { #expect(MoveNr.specific(3).value == 3) }

  // Boundary: any negative int clamps to `.lastMove`
  @Test func clamping_negativeInt_becomesLastMove() { #expect(MoveNr(clamping: -99) == .lastMove) }

  // Round-tripping through JSON preserves both cases
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
  // `playedMoves` on a history with no moves returns an empty array
  @Test func emptyHistory_playedMovesIsEmpty() {
    let history = MoveHistory()
    #expect(history.playedMoves.isEmpty)
  }

  // `playedMoves` is sliced to `moveNr` when browsing
  @Test func browsingHistory_playedMovesIsSliced() {
    let move1 = mock.move(eid: "E1", target: .position([1, 0, 0]))
    let move2 = mock.move(eid: "E2", target: .position([2, 0, 0]))
    var history = MoveHistory()
    history.moves = [move1, move2]
    history.moveNr = 1
    #expect(history.playedMoves == [move1])
  }

  // `cannotUndo` is true when the history has no moves
  @Test func cannotUndo_whenHistoryIsEmpty() {
    let history = MoveHistory()
    #expect(history.cannotUndo(animatingTowards: nil))
  }

  // Boundary: `cannotUndo` is true when browsed all the way to move zero
  @Test func cannotUndo_whenBrowsedToMoveZero() {
    var history = MoveHistory()
    history.moves = [mock.move(eid: "E1", target: .position([1, 0, 0]))]
    history.moveNr = 0
    #expect(history.cannotUndo(animatingTowards: nil))
  }

  // Boundary: `cannotRedo` is true when `moveNr == -1` (at the latest move)
  @Test func cannotRedo_whenAtLatestMove() {
    var history = MoveHistory()
    history.moves = [mock.move(eid: "E1", target: .position([1, 0, 0]))]
    history.moveNr = -1
    #expect(history.cannotRedo(animatingTowards: nil))
  }
}

// MARK: - AppendMoveTests · appending moves and branching

struct AppendMoveTests {
  // Boundary: the first move appended to an empty history is stored at index 0
  @Test func appendMove_addsFirstMove_toEmptyHistory() throws {
    let move = mock.move(eid: "E1", target: .position([1, 0, 0]))
    var history = MoveHistory()
    let result = try history.appendMove(move, initialStateDic: [:], atIndex: nil, setMoveNr: true)
    #expect(result?.addOrBrowseIndex.addedAtIndex == MoveIndex(0))
    #expect(history.moves.count == 1)
  }

  // Appending an identical move returns nil — duplicate is ignored
  @Test func appendMove_duplicateMove_isIgnored() throws {
    let move = mock.move(eid: "E1", target: .position([1, 0, 0]))
    var history = MoveHistory()
    _ = try history.appendMove(move, initialStateDic: [:], atIndex: nil, setMoveNr: true)
    let result = try history.appendMove(move, initialStateDic: [:], atIndex: nil, setMoveNr: true)
    #expect(result == nil)
  }

  // While browsing, replaying the next move in history returns `.browsedToIndex` not `.addedAtIndex`
  @Test func appendMove_redoesMoveWhenMatchesNextInHistory() throws {
    let moveA = mock.move(eid: "E1", target: .position([1, 0, 0]))
    let moveB = mock.move(eid: "E1", target: .position([2, 0, 0]))
    var history = MoveHistory()
    history.moves = [moveA, moveB]
    history.moveNr = 1  // browsed back, currently seeing only moveA
    let result = try history.appendMove(moveB, initialStateDic: [:], atIndex: nil, setMoveNr: true)
    #expect(result?.addOrBrowseIndex.browsedToIndex == MoveIndex(1))
  }

  // Complex: while browsing, appending a diverging move removes future moves
  @Test func appendMove_divergesFromHistory_truncatesFuture() throws {
    let moveA = mock.move(eid: "E1", target: .position([1, 0, 0]))
    let moveB = mock.move(eid: "E1", target: .position([2, 0, 0]))
    let moveC = mock.move(eid: "E1", target: .position([3, 0, 0]))
    var history = MoveHistory()
    history.moves = [moveA, moveB]
    history.moveNr = 1  // browsed back; moveB is the future move that will be truncated
    _ = try history.appendMove(moveC, initialStateDic: [:], atIndex: nil, setMoveNr: true)
    #expect(history.moves == [moveA, moveC])
    #expect(history.moveNr == -1)
  }

  // Complex: when diverging removes more than one future move, a backup is returned
  @Test func appendMove_divergesMoreThanOne_createsBackup() throws {
    let moveA = mock.move(eid: "E1", target: .position([1, 0, 0]))
    let moveB = mock.move(eid: "E1", target: .position([2, 0, 0]))
    let moveC = mock.move(eid: "E1", target: .position([3, 0, 0]))
    let moveD = mock.move(eid: "E1", target: .position([4, 0, 0]))
    var history = MoveHistory()
    history.moves = [moveA, moveB, moveC]
    history.moveNr = 1  // browsed back 2 steps; 2 future moves (B, C) will be truncated
    let result = try history.appendMove(moveD, initialStateDic: [:], atIndex: nil, setMoveNr: true)
    #expect(result?.backupForDivergence != nil)
  }
}

// MARK: - RestoreHistoryTests

struct RestoreHistoryTests {
  // Complex: trimming to divergence point and appending backup.moves restores the full original history
  @Test func restoreOriginalHistory_trimsAndRestoresBackupMoves() throws {
    let moveA = mock.move(eid: "E1", target: .position([1, 0, 0]))
    let moveB = mock.move(eid: "E1", target: .position([2, 0, 0]))
    let moveC = mock.move(eid: "E1", target: .position([3, 0, 0]))
    let moveD = mock.move(eid: "E1", target: .position([4, 0, 0]))
    let moveE = mock.move(eid: "E1", target: .position([5, 0, 0]))
    let moveNew = mock.move(eid: "E1", target: .position([9, 0, 0]))
    var history = MoveHistory()
    history.moves = [moveA, moveB, moveC, moveD, moveE]
    history.moveNr = 2  // undid back to move 2

    // Diverge — creates a backup of moves C, D, E
    let appendResult = try history.appendMove(
      moveNew,
      initialStateDic: [:],
      atIndex: nil,
      setMoveNr: true
    )
    let backup = try #require(appendResult?.backupForDivergence)
    #expect(history.moves.count == 3)  // A, B, New
    #expect(backup.divergenceMoveNr == 2)
    #expect(backup.moves.count == 3)  // C, D, E

    // Restore
    history.moves = history.moves.slice(0, backup.divergenceMoveNr) + backup.moves
    history.moveNr = -1
    #expect(history.moves.count == 5)
    #expect(history.moves == [moveA, moveB, moveC, moveD, moveE])
  }
}

// MARK: - BrowseHistoryTests · undo, redo, and jump

struct BrowseHistoryTests {
  // Undo from the latest move returns one reversed move with `newMoveNr` decremented by 1
  @Test func browseHistory_undo_returnsReversedMove() {
    var history = MoveHistory()
    history.moves = [mock.move(eid: "E1", target: .position([1, 0, 0]))]
    history.moveNr = -1
    let result = history.browseHistory(
      action: .undo,
      animatingTowards: nil,
      currentlyAnimating: nil
    )
    if case .animateMoves(let movesAndNrs) = result {
      #expect(movesAndNrs.count == 1)
      #expect(movesAndNrs[0].oldMoveNr == ActualMoveNr(1))
      #expect(movesAndNrs[0].newMoveNr == ActualMoveNr(0))
    } else {
      #expect(Bool(false), "Expected .animateMoves result from undo")
    }
  }

  // Redo while browsing returns the next forward move with `newMoveNr` incremented by 1
  @Test func browseHistory_redo_returnsForwardMove() {
    let moveA = mock.move(eid: "E1", target: .position([1, 0, 0]))
    var history = MoveHistory()
    history.moves = [moveA]
    history.moveNr = 0  // browsed to the start, nothing visible yet
    let result = history.browseHistory(
      action: .redo,
      animatingTowards: nil,
      currentlyAnimating: nil
    )
    if case .animateMoves(let movesAndNrs) = result {
      #expect(movesAndNrs.count == 1)
      #expect(movesAndNrs[0].move == moveA)
      #expect(movesAndNrs[0].oldMoveNr == ActualMoveNr(0))
      #expect(movesAndNrs[0].newMoveNr == ActualMoveNr(1))
    } else {
      #expect(Bool(false), "Expected .animateMoves result from redo")
    }
  }

  // Complex: `.stopAnimating` fires when the user acts mid-animation and the new target falls between
  // `currentlyAnimating` and `animatingTowards`
  // e.g. showMove 5→0 in progress (animatingTowards=0, currentlyAnimating=2), user taps redo
  //      → newMoveNr = 0+1 = 1, which is between 2 and 0 → stopAt=1
  @Test func browseHistory_stopAnimating_firesWhenNewTargetIsBetweenCurrentAndDestination() {
    var history = MoveHistory()
    history.moves = [
      mock.move(eid: "E1", target: .position([1, 0, 0])),
      mock.move(eid: "E1", target: .position([2, 0, 0])),
      mock.move(eid: "E1", target: .position([3, 0, 0])),
      mock.move(eid: "E1", target: .position([4, 0, 0])),
      mock.move(eid: "E1", target: .position([5, 0, 0])),
    ]
    history.moveNr = -1
    let result = history.browseHistory(
      action: .redo,
      animatingTowards: ActualMoveNr(0),
      currentlyAnimating: ActualMoveNr(2)
    )
    if case .stopAnimating(let stopAt) = result {
      #expect(stopAt == ActualMoveNr(1))
    } else {
      #expect(Bool(false), "Expected .stopAnimating")
    }
  }

  // Complex: `showMove(.specific(0))` from the end of a 3-move history returns 3 reverse moves in order
  @Test func browseHistory_showMove_jumpsMultipleSteps() {
    let moveA = mock.move(eid: "E1", target: .position([1, 0, 0]))
    let moveB = mock.move(eid: "E1", target: .position([2, 0, 0]))
    let moveC = mock.move(eid: "E1", target: .position([3, 0, 0]))
    var history = MoveHistory()
    history.moves = [moveA, moveB, moveC]
    history.moveNr = -1
    let result = history.browseHistory(
      action: .showMove(moveNr: .specific(0)),
      animatingTowards: nil,
      currentlyAnimating: nil
    )
    if case .animateMoves(let movesAndNrs) = result {
      #expect(movesAndNrs.count == 3)
      #expect(movesAndNrs[0].oldMoveNr == ActualMoveNr(3))
      #expect(movesAndNrs[0].newMoveNr == ActualMoveNr(2))
      #expect(movesAndNrs[2].oldMoveNr == ActualMoveNr(1))
      #expect(movesAndNrs[2].newMoveNr == ActualMoveNr(0))
    } else {
      #expect(Bool(false), "Expected .animateMoves result from showMove")
    }
  }
}

// MARK: - MoveToPreviousCoreMovesTests · computing the reverse of a move

struct MoveToPreviousCoreMovesTests {
  // Undoing a capture where neither piece has prior history reverts both to their initial states
  @Test func chess_revertCaptureBackToInitialState() {
    let pawnCapturesRook = Move([
      [
        // black pawn moves to capture square
        mock.coreMove(eid: "BP1", target: .position([1, 0, 0])),
        // white rook is captured (side-effect: moves off its square)
        mock.coreMove(eid: "WR1", target: .position([0, 0, 0.5])),
      ]
    ])
    // unrelated prior move — confirms WP1 doesn't pollute the BP1/WR1 lookup
    let moveHistory: [Move] = [mock.move(eid: "WP1", target: .position([1, 0, 0]))]

    let reverseMoves = MoveHistoryHelpers.moveToPreviousCoreMoves(
      pawnCapturesRook,
      searchThrough: moveHistory
    )

    #expect(
      reverseMoves == [
        [
          mock.coreMove(eid: "WR1", revertToInitialState: true),
          mock.coreMove(eid: "BP1", revertToInitialState: true),
        ]
      ]
    )
  }

  // Undoing a move that followed a capture reverts the piece to its post-capture position
  @Test func chess_revertPawnBackToStateAfterCapture() {
    let moveHistory: [Move] = [
      // white pawn moves
      mock.move(eid: "WP1", target: .position([1, 0, 0])),
      // black pawn captures rook by moving to A2 (side-effect: rook gets displaced to [1,0,0])
      Move([
        [
          mock.coreMove(eid: "BP1", target: .magnet("A2")),
          mock.coreMove(eid: "WR1", target: .position([1, 0, 0])),
        ]
      ]),
    ]

    let reverseMoves = MoveHistoryHelpers.moveToPreviousCoreMoves(
      mock.move(eid: "BP1", target: .position([1, 0, 0])),
      searchThrough: moveHistory
    )

    let pawnCapturesRook_reversed = mock.coreMove(
      eid: "BP1",
      target: .magnet("A2"),
      revertToInitialState: true
    )
    #expect(reverseMoves == [[pawnCapturesRook_reversed]])
  }

  // Undoing a subsequent move of a captured piece reverts it to the position it was moved to on capture
  @Test func chess_revertCapturedPieceBackToStateAfterCapture() {
    let POS_ROOK: SIMD3<Float> = [5, 0, 0]
    let moveHistory: [Move] = [
      // black queen moves
      mock.move(eid: "BQ1", target: .position([1, 0, 0])),
      // black pawn captures rook (side-effect: rook moves to POS_ROOK)
      Move([
        [
          mock.coreMove(eid: "BP1", target: .position([1, 0, 0])),
          mock.coreMove(eid: "WR1", target: .position(POS_ROOK)),
        ]
      ]),
    ]

    let reverseMoves = MoveHistoryHelpers.moveToPreviousCoreMoves(
      mock.move(eid: "WR1", target: .position([1, 0, 0])),
      searchThrough: moveHistory
    )

    let rookGetsMoved_reversed = mock.coreMove(
      eid: "WR1",
      target: .position(POS_ROOK),
      revertToInitialState: true
    )
    #expect(reverseMoves == [[rookGetsMoved_reversed]])
  }

  // Complex: undoing a Go capture — whites with no prior history revert to initial state with no target;
  // captures undo first (reverse chunk order), then the black stone placement
  @Test func go_revertCaptureMove_whitesHaveNoHistory() {
    let blackMovesAndCaptures = Move([
      [
        // black stone places on the board
        mock.coreMove(eid: "GoStoneBlack:UUID1", target: .position([1, 0, 0]))
      ],
      [
        // surrounded white stones are captured — all go to the black player's bowl
        mock.coreMove(eid: "GoStoneWhite:UUID1", target: .magnet("BowlLidBlack")),
        mock.coreMove(eid: "GoStoneWhite:UUID2", target: .magnet("BowlLidBlack")),
        mock.coreMove(eid: "GoStoneWhite:UUID3", target: .magnet("BowlLidBlack")),
      ],
    ])
    // unrelated prior move — confirms UUID5 doesn't pollute the white-stone lookup
    let moveHistory: [Move] = [mock.move(eid: "GoStoneBlack:UUID5", target: .position([1, 0, 0]))]

    let reverseMoves = MoveHistoryHelpers.moveToPreviousCoreMoves(
      blackMovesAndCaptures,
      searchThrough: moveHistory
    )

    #expect(
      reverseMoves == [
        [
          mock.coreMove(eid: "GoStoneWhite:UUID3", revertToInitialState: true),
          mock.coreMove(eid: "GoStoneWhite:UUID2", revertToInitialState: true),
          mock.coreMove(eid: "GoStoneWhite:UUID1", revertToInitialState: true),
        ], [mock.coreMove(eid: "GoStoneBlack:UUID1", revertToInitialState: true)],
      ]
    )
  }

  // Complex: undoing a Go capture — whites with a known prior position carry that last known target
  // when reverting, rather than falling back to `.unset`
  @Test func go_revertCaptureMove_whitesHavePriorPosition() {
    let blackMovesAndCaptures = Move([
      [
        // black stone places on the board
        mock.coreMove(eid: "GoStoneBlack:UUID1", target: .position([1, 0, 0]))
      ],
      [
        // surrounded white stones are captured — all go to the black player's bowl
        mock.coreMove(eid: "GoStoneWhite:UUID1", target: .magnet("BowlLidBlack")),
        mock.coreMove(eid: "GoStoneWhite:UUID2", target: .magnet("BowlLidBlack")),
        mock.coreMove(eid: "GoStoneWhite:UUID3", target: .magnet("BowlLidBlack")),
      ],
    ])

    let reverseMoves = MoveHistoryHelpers.moveToPreviousCoreMoves(
      blackMovesAndCaptures,
      searchThrough: [
        Move([
          [
            mock.coreMove(eid: "GoStoneWhite:UUID1", target: .magnet("A1")),
            mock.coreMove(eid: "GoStoneWhite:UUID2", target: .magnet("A2")),
            mock.coreMove(eid: "GoStoneWhite:UUID3", target: .magnet("A3")),
          ]
        ])
      ]
    )

    #expect(
      reverseMoves == [
        [
          mock.coreMove(
            eid: "GoStoneWhite:UUID3",
            target: .magnet("A3"),
            revertToInitialState: true
          ),
          mock.coreMove(
            eid: "GoStoneWhite:UUID2",
            target: .magnet("A2"),
            revertToInitialState: true
          ),
          mock.coreMove(
            eid: "GoStoneWhite:UUID1",
            target: .magnet("A1"),
            revertToInitialState: true
          ),
        ], [mock.coreMove(eid: "GoStoneBlack:UUID1", revertToInitialState: true)],
      ]
    )
  }

  // Complex: undoing a chess capture where the same piece appears across multiple parts of the move
  @Test func chess_revertCaptureMoveAndSideEffects() {
    let blackMovesAndCaptures = Move([
      [
        // white pawn moves to A7 (on top of black pawn 1)
        mock.coreMove(eid: "WP1", target: .magnet("A7"))
      ],
      [
        // black pawn 1 is captured and moves away
        mock.coreMove(eid: "BP1", target: .magnet("MT1_1")),
        // white pawn moves to A7 again, so it can fall down while black pawn 1 moves away
        mock.coreMove(eid: "WP1", target: .magnet("A7")),
      ],
    ])
    let moveHistory: [Move] = []

    let reverseMoves = MoveHistoryHelpers.moveToPreviousCoreMoves(
      blackMovesAndCaptures,
      searchThrough: moveHistory
    )

    #expect(
      reverseMoves == [
        [
          mock.coreMove(eid: "WP1", target: .magnet("A7"), revertToInitialState: true),
          mock.coreMove(eid: "BP1", revertToInitialState: true),
        ], [mock.coreMove(eid: "WP1", revertToInitialState: true)],
      ]
    )
  }

  // Undoing a move that carried a stack of cards reverts all stacked cards to their initial state
  @Test func cards_revertMove_andCarriedStack() {
    let moveWithStack = Move([
      [
        // card 1 moves, carrying A, B, C stacked on top of it
        mock.coreMove(eid: "Card:UUID1", target: .position([1, 0, 0])),
        mock.coreMove(eid: "Card:UUIDA", target: .magnet("Card:UUID1")),
        mock.coreMove(eid: "Card:UUIDB", target: .magnet("Card:UUID1")),
        mock.coreMove(eid: "Card:UUIDC", target: .magnet("Card:UUID1")),
      ]
    ])
    let moveHistory: [Move] = [
      // some other card move that happened earlier
      mock.move(eid: "Card:UUID0", target: .position([1, 0, 0]))
    ]

    let reverseMoves = MoveHistoryHelpers.moveToPreviousCoreMoves(
      moveWithStack,
      searchThrough: moveHistory
    )

    #expect(
      reverseMoves == [
        [
          mock.coreMove(eid: "Card:UUIDC", revertToInitialState: true),
          mock.coreMove(eid: "Card:UUIDB", revertToInitialState: true),
          mock.coreMove(eid: "Card:UUIDA", revertToInitialState: true),
          mock.coreMove(eid: "Card:UUID1", revertToInitialState: true),
        ]
      ]
    )
  }

  // Complex: undoing a stack merge reverts all cards to their positions before the merge
  @Test func cards_revertStackMerge() {
    let POS_CARD1: SIMD3<Float> = [5, 0, 0]
    let moveHistory: [Move] = [
      // card A stacks on card 1
      mock.move(eid: "Card:UUIDA", target: .magnet("Card:UUID1")),
      // card B stacks on card 1
      mock.move(eid: "Card:UUIDB", target: .magnet("Card:UUID1")),
      // card 2 moves somewhere
      mock.move(eid: "Card:UUID2", target: .position([1, 0, 0])),
      // card 1 (with A+B stacked) moves to POS_CARD1
      mock.move(eid: "Card:UUID1", target: .position(POS_CARD1)),
    ]

    let card1MovesOnTopOf2WithStack = Move([
      [
        // card 1 (with A+B stacked) merges onto card 2
        mock.coreMove(eid: "Card:UUID1", target: .magnet("Card:UUID2")),
        mock.coreMove(eid: "Card:UUIDA", target: .magnet("Card:UUID2")),
        mock.coreMove(eid: "Card:UUIDB", target: .magnet("Card:UUID2")),
      ]
    ])
    let reverseMoves = MoveHistoryHelpers.moveToPreviousCoreMoves(
      card1MovesOnTopOf2WithStack,
      searchThrough: moveHistory
    )

    let bInStack_reversed = mock.coreMove(
      eid: "Card:UUIDB",
      target: .magnet("Card:UUID1"),
      revertToInitialState: true
    )
    let aInStack_reversed = mock.coreMove(
      eid: "Card:UUIDA",
      target: .magnet("Card:UUID1"),
      revertToInitialState: true
    )
    let card1Moves_reversed = mock.coreMove(
      eid: "Card:UUID1",
      target: .position(POS_CARD1),
      revertToInitialState: true
    )

    #expect(reverseMoves == [[bInStack_reversed, aInStack_reversed, card1Moves_reversed]])
  }

  // Complex: splitting a tower and undoing restores each card to its pre-split stack position
  @Test func splitTowerAndBringHalf() {
    let POS_CARD1: SIMD3<Float> = [5, 0, 0]
    let moveHistory: [Move] = [
      // card A stacks on card 1
      mock.move(eid: "Card:UUIDA", target: .magnet("Card:UUID1")),
      // card B stacks on card 1
      mock.move(eid: "Card:UUIDB", target: .magnet("Card:UUID1")),
      // card 2 moves somewhere
      mock.move(eid: "Card:UUID2", target: .position([1, 0, 0])),
      // card 1 (with A+B stacked) moves to POS_CARD1
      mock.move(eid: "Card:UUID1", target: .position(POS_CARD1)),
      // card 1 (with A+B stacked) moves on top of card 2
      Move([
        [
          mock.coreMove(eid: "Card:UUID1", target: .magnet("Card:UUID2")),
          mock.coreMove(eid: "Card:UUIDA", target: .magnet("Card:UUID2")),
          mock.coreMove(eid: "Card:UUIDB", target: .magnet("Card:UUID2")),
        ]
      ]),
    ]

    let cardAMovesToANewLocationAndBringsB = Move([
      [
        // card A splits off from the tower and moves to a new location
        mock.coreMove(eid: "Card:UUIDA", target: .position([1, 0, 0])),
        // card B rides on top of card A as it splits off
        mock.coreMove(eid: "Card:UUIDB", target: .magnet("Card:UUIDA")),
      ]
    ])

    let reverseMoves = MoveHistoryHelpers.moveToPreviousCoreMoves(
      cardAMovesToANewLocationAndBringsB,
      searchThrough: moveHistory
    )

    let aInStack_reversed = mock.coreMove(
      eid: "Card:UUIDA",
      target: .magnet("Card:UUID2"),
      revertToInitialState: true
    )
    let bInStack_reversed = mock.coreMove(
      eid: "Card:UUIDB",
      target: .magnet("Card:UUID2"),
      revertToInitialState: true
    )

    #expect(reverseMoves == [[bInStack_reversed, aInStack_reversed]])
  }

  // Undoing an opacity-only move with no prior history reverts to initial state
  @Test func cards_revertModelChangeAsInitialMove() {
    let moveHistory: [Move] = []
    let packsSwapOutOpacity = Move([
      [
        // open-state model becomes visible
        mock.coreMove(eid: "CardsPackOpen", opacity: 1.0),
        // closed-state model becomes hidden
        mock.coreMove(eid: "CardsPackClosed", opacity: 0.0),
      ]
    ])

    let reverseMoves = MoveHistoryHelpers.moveToPreviousCoreMoves(
      packsSwapOutOpacity,
      searchThrough: moveHistory
    )

    #expect(
      reverseMoves == [
        [
          mock.coreMove(eid: "CardsPackClosed", revertToInitialState: true),
          mock.coreMove(eid: "CardsPackOpen", revertToInitialState: true),
        ]
      ]
    )
  }

  // Undoing an opacity-only move when a prior matching move exists restores the prior opacity
  @Test func cards_revertModelChangeAsSubsequentMove() {
    let packOpens = Move([
      [
        // open-state model becomes visible
        mock.coreMove(eid: "CardsPackOpen", opacity: 1.0),
        // closed-state model becomes hidden
        mock.coreMove(eid: "CardsPackClosed", opacity: 0.0),
      ]
    ])
    let moveHistory: [Move] = [
      packOpens,
      // pack opens a second time (same opacity values — tests that prior history is found and used)
      Move([
        [
          mock.coreMove(eid: "CardsPackOpen", opacity: 1.0),
          mock.coreMove(eid: "CardsPackClosed", opacity: 0.0),
        ]
      ]),
    ]

    let reverseMoves = MoveHistoryHelpers.moveToPreviousCoreMoves(
      packOpens,
      searchThrough: moveHistory
    )

    #expect(
      reverseMoves == [
        [
          mock.coreMove(eid: "CardsPackClosed", opacity: 0.0, revertToInitialState: true),
          mock.coreMove(eid: "CardsPackOpen", opacity: 1.0, revertToInitialState: true),
        ]
      ]
    )
  }

  // Undoing an opacity change preserves the entity's position from a prior move
  @Test func cards_moveThenOpenPack() {
    let POS: SIMD3<Float> = [5, 0, 0]
    let packOpens = Move([
      [
        // open-state model becomes visible
        mock.coreMove(eid: "CardsPackOpen", opacity: 1.0),
        // closed-state model becomes hidden
        mock.coreMove(eid: "CardsPackClosed", opacity: 0.0),
      ]
    ])
    let moveHistory: [Move] = [
      // both pack variants move together to POS
      Move([
        [
          mock.coreMove(eid: "CardsPackClosed", target: .position(POS)),
          mock.coreMove(eid: "CardsPackOpen", target: .position(POS)),
        ]
      ])
    ]

    let reverseMoves = MoveHistoryHelpers.moveToPreviousCoreMoves(
      packOpens,
      searchThrough: moveHistory
    )

    #expect(
      reverseMoves == [
        [
          mock.coreMove(eid: "CardsPackClosed", target: .position(POS), revertToInitialState: true),
          mock.coreMove(eid: "CardsPackOpen", target: .position(POS), revertToInitialState: true),
        ]
      ]
    )
  }

  // Complex: undoing an opacity change correctly combines position from one history entry and opacity from another
  @Test func cards_revertModelChangeWithMovesInBetween() {
    let packCloses = Move([
      [
        // open-state model becomes hidden
        mock.coreMove(eid: "CardsPackOpen", opacity: 0.0),
        // closed-state model becomes visible
        mock.coreMove(eid: "CardsPackClosed", opacity: 1.0),
      ]
    ])
    let moveHistory: [Move] = [
      // pack opens
      Move([
        [
          mock.coreMove(eid: "CardsPackOpen", opacity: 1.0),
          mock.coreMove(eid: "CardsPackClosed", opacity: 0.0),
        ]
      ]),
      // pack moves to a new position
      mock.move(eid: "CardsPackOpen", target: .position([1, 1, 1])),
    ]

    let reverseMoves = MoveHistoryHelpers.moveToPreviousCoreMoves(
      packCloses,
      searchThrough: moveHistory
    )

    #expect(
      reverseMoves == [
        [
          mock.coreMove(eid: "CardsPackClosed", opacity: 0.0, revertToInitialState: true),
          mock.coreMove(
            eid: "CardsPackOpen",
            target: .position([1, 1, 1]),
            opacity: 1.0,
            revertToInitialState: true
          ),
        ]
      ]
    )
  }

  // Duration from the original move is propagated to the undo move
  @Test func cards_revertModelChangeWithDuration() {
    let cardsAppear = Move([
      [
        // 3 cards fade in together over 2 seconds
        mock.coreMove(eid: "Card1", opacity: 1.0, duration: .seconds(2)),
        mock.coreMove(eid: "Card2", opacity: 1.0, duration: .seconds(2)),
        mock.coreMove(eid: "Card3", opacity: 1.0, duration: .seconds(2)),
      ]
    ])
    let moveHistory: [Move] = []

    let reverseMoves = MoveHistoryHelpers.moveToPreviousCoreMoves(
      cardsAppear,
      searchThrough: moveHistory
    )

    #expect(
      reverseMoves == [
        [
          mock.coreMove(eid: "Card3", duration: .seconds(2), revertToInitialState: true),
          mock.coreMove(eid: "Card2", duration: .seconds(2), revertToInitialState: true),
          mock.coreMove(eid: "Card1", duration: .seconds(2), revertToInitialState: true),
        ]
      ]
    )
  }
}
