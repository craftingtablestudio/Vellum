import Foundation
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
  import simd
#endif
import Testing
@testable import Vellum

// MARK: - AppendMoveTests · appending moves and branching

struct AppendMoveTests {
  /// Appending to an empty history stores the move at index 0 and returns `.addedAtIndex`
  /// Boundary: empty collection — zero prior moves
  @Test func appendMove_addsFirstMove_toEmptyHistory() throws {
    let move = mock.move(eid: "E1", target: .position([1, 0, 0]))
    var history = MoveHistory()
    let result = try history.appendMove(move, initialStateDic: [:], atIndex: nil, setMoveNr: true)
    #expect(result?.addOrBrowseIndex.addedAtIndex == MoveIndex(0))
    #expect(history.moves.count == 1)
  }

  /// Average: appending an identical move returns nil — duplicate is ignored
  @Test func appendMove_duplicateMove_isIgnored() throws {
    let move = mock.move(eid: "E1", target: .position([1, 0, 0]))
    var history = MoveHistory()
    _ = try history.appendMove(move, initialStateDic: [:], atIndex: nil, setMoveNr: true)
    let result = try history.appendMove(move, initialStateDic: [:], atIndex: nil, setMoveNr: true)
    #expect(result == nil)
  }

  /// Average: while browsing, replaying the next move in history returns `.browsedToIndex` not `.addedAtIndex`
  @Test func appendMove_redoesMoveWhenMatchesNextInHistory() throws {
    let moveA = mock.move(eid: "E1", target: .position([1, 0, 0]))
    let moveB = mock.move(eid: "E1", target: .position([2, 0, 0]))
    var history = MoveHistory()
    history.moves = [moveA, moveB]
    history.moveNr = 1  // browsed back, currently seeing only moveA
    let result = try history.appendMove(moveB, initialStateDic: [:], atIndex: nil, setMoveNr: true)
    #expect(result?.addOrBrowseIndex.browsedToIndex == MoveIndex(1))
  }

  /// Complex: while browsing, appending a diverging move removes future moves
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

  /// Complex: when diverging removes more than one future move, a backup is returned
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

  /// When a move targets the same magnet but with a different huggers snapshot (reordering),
  /// it must NOT be deduplicated — the huggers ordering changed.
  @Test func appendMove_sameMagnetDifferentHuggersOrder_isNotDeduplicated() throws {
    let E1 = EID.other(name: "E1")
    let WK = EID.other(name: "WK")
    let WQ = EID.other(name: "WQ")

    // Move 1: WK joins E1, snapshot says E1.huggedBy = [WK]
    let move1 = Move([[CoreMove(eid: WK, target: .magnet(E1)), CoreMove(eid: E1, huggers: [WK])]])
    // Move 2: WQ joins E1 on top, snapshot says E1.huggedBy = [WK, WQ]
    let move2 = Move([
      [CoreMove(eid: WQ, target: .magnet(E1)), CoreMove(eid: E1, huggers: [WK, WQ])]
    ])
    // Move 3: WK moves to E1 again (same magnet), but now on top — snapshot says E1.huggedBy = [WQ, WK]
    let move3 = Move([
      [CoreMove(eid: WK, target: .magnet(E1)), CoreMove(eid: E1, huggers: [WQ, WK])]
    ])

    var history = MoveHistory()
    _ = try history.appendMove(move1, initialStateDic: [:], atIndex: nil, setMoveNr: true)
    _ = try history.appendMove(move2, initialStateDic: [:], atIndex: nil, setMoveNr: true)
    let result = try history.appendMove(move3, initialStateDic: [:], atIndex: nil, setMoveNr: true)

    #expect(
      history.moves.count == 3,
      "Move with different huggers order should not be deduplicated"
    )
    #expect(result != nil, "appendMove should return a result for a reorder move")
  }

  /// Placing a piece back on its starting magnet with a different Y rotation and the same
  /// huggers snapshot should be deduplicated — nothing meaningful changed. The initial state
  /// already records the magnet's huggedBy, so the huggers snapshot in the move matches.
  /// Regression: fillInEmptyParts didn't fill huggers from initialState, so the comparison
  /// saw nil vs [WK] and treated it as a new move.
  @Test func appendMove_sameMagnetSameHuggers_withInitialState_isDeduplicated() throws {
    let E1 = EID.other(name: "E1")
    let WK = EID.other(name: "WK")
    let YAW = simd_quatf(angle: 0.5, axis: [0, 1, 0])

    // WK starts on E1 — initial state records the hug relationship from both sides
    let initialStateDic: [EID: EntityState] = [
      WK: EntityState(eid: WK, magneticHugs: MagneticHugsComponent(hugging: E1, huggedBy: [])),
      E1: EntityState(eid: E1, magneticHugs: MagneticHugsComponent(hugging: nil, huggedBy: [WK])),
    ]

    // Piece dropped back on same magnet with a Y rotation + huggers snapshot
    let move = Move([
      [CoreMove(eid: WK, target: .magnet(E1), orientation: YAW), CoreMove(eid: E1, huggers: [WK])]
    ])

    var history = MoveHistory()
    let result = try history.appendMove(
      move,
      initialStateDic: initialStateDic,
      atIndex: nil,
      setMoveNr: true
    )

    #expect(result == nil, "Same magnet + same huggers + Y rotation only should be deduplicated")
    #expect(history.moves.count == 0)
  }

  /// A huggers-only snapshot CoreMove (no position/magnet) that matches the previous snapshot
  /// SHOULD be deduplicated — nothing changed.
  @Test func appendMove_sameHuggersOrder_isDeduplicated() throws {
    let E1 = EID.other(name: "E1")
    let WK = EID.other(name: "WK")
    let WQ = EID.other(name: "WQ")

    let move1 = Move([[CoreMove(eid: WK, target: .magnet(E1)), CoreMove(eid: E1, huggers: [WK])]])
    let move2 = Move([
      [CoreMove(eid: WQ, target: .magnet(E1)), CoreMove(eid: E1, huggers: [WK, WQ])]
    ])
    // Move 3: WQ to E1 again with SAME huggers order — should be deduplicated
    let move3 = Move([
      [CoreMove(eid: WQ, target: .magnet(E1)), CoreMove(eid: E1, huggers: [WK, WQ])]
    ])

    var history = MoveHistory()
    _ = try history.appendMove(move1, initialStateDic: [:], atIndex: nil, setMoveNr: true)
    _ = try history.appendMove(move2, initialStateDic: [:], atIndex: nil, setMoveNr: true)
    let result = try history.appendMove(move3, initialStateDic: [:], atIndex: nil, setMoveNr: true)

    #expect(history.moves.count == 2, "Move with same huggers order should be deduplicated")
    #expect(result == nil, "appendMove should return nil for a duplicate move")
  }
}

// MARK: - RestoreHistoryTests

struct RestoreHistoryTests {
  /// Complex: trimming to divergence point and appending backup.moves restores the full original history
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
  /// Undo from the latest move returns one reversed move with `newMoveNr` decremented by 1
  /// Boundary: history of exactly 1 move — minimum non-empty case
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
      // ActualMoveNr is the resolved integer: MoveNr's -1 sentinel is replaced with the real count
      #expect(movesAndNrs[0].oldMoveNr == ActualMoveNr(1))
      #expect(movesAndNrs[0].newMoveNr == ActualMoveNr(0))
    } else {
      #expect(Bool(false), "Expected .animateMoves result from undo")
    }
  }

  /// Redo while browsing returns the next forward move with `newMoveNr` incremented by 1
  /// Boundary: moveNr is at 0, nothing visible yet — the redo floor
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
      // ActualMoveNr is the resolved integer: MoveNr's -1 sentinel is replaced with the real count
      #expect(movesAndNrs[0].oldMoveNr == ActualMoveNr(0))
      #expect(movesAndNrs[0].newMoveNr == ActualMoveNr(1))
    } else {
      #expect(Bool(false), "Expected .animateMoves result from redo")
    }
  }

  /// Complex: `.stopAnimating` fires when the user acts mid-animation and the new target falls between
  /// `currentlyAnimating` and `animatingTowards`
  /// e.g. showMove 5→0 in progress (animatingTowards=0, currentlyAnimating=2), user taps redo
  ///      → newMoveNr = 0+1 = 1, which is between 2 and 0 → stopAt=1
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

  /// Complex: `showMove(.specific(0))` from the end of a 3-move history returns 3 reverse moves in order
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
  /// Undoing a capture where neither piece has prior history reverts both to their initial states
  /// Boundary: affected pieces appear for the first time in this move — no history to search
  @Test func chess_revertCaptureBackToInitialState() {
    let history = MoveHistory(moves: [
      // unrelated prior move — confirms WP1 doesn't pollute the BP1/WR1 lookup
      mock.move(eid: "WP1", target: .magnet("A4")),
      Move([
        [
          // black pawn moves to A1 (WR1's home square), displacing the rook
          mock.coreMove(eid: "BP1", target: .magnet("A1")),
          // white rook is captured (side-effect: pushed just off the board edge)
          mock.coreMove(eid: "WR1", target: .position([0.22, 0, 0.18])),
        ]
      ]),
    ])

    let browseResult = history.browseHistory(
      action: .undo,
      animatingTowards: nil,
      currentlyAnimating: nil,
      presetDic: CHESS_PRESET_DIC
    )
    let reverseMoves: [Move] =
      switch browseResult {
      case .animateMoves(let movesAndNrs): movesAndNrs.map(\.move)
      default: []
      }

    #expect(
      reverseMoves == [
        Move([
          [
            mock.coreMove(eid: "WR1", target: .magnet("A1"), huggers: []),
            mock.coreMove(eid: "BP1", target: .magnet("A7"), huggers: []),
          ]
        ])
      ]
    )
  }

  /// Complex: undoing a move that followed a capture reverts the piece to its post-capture position
  @Test func chess_revertPawnBackToStateAfterCapture() {
    let history = MoveHistory(moves: [
      // white pawn advances two squares, vacating A2
      mock.move(eid: "WP1", target: .magnet("A4")),
      // black pawn captures at A2 (side-effect: rook is displaced to captured area)
      Move([
        [
          mock.coreMove(eid: "BP1", target: .magnet("A2")),
          mock.coreMove(eid: "WR1", target: .position([0.22, 0, 0.18])),
        ]
      ]),
      // black pawn advances to A1
      mock.move(eid: "BP1", target: .magnet("A1")),
    ])

    let browseResult = history.browseHistory(
      action: .undo,
      animatingTowards: nil,
      currentlyAnimating: nil,
      presetDic: CHESS_PRESET_DIC
    )
    let reverseMoves: [Move] =
      switch browseResult {
      case .animateMoves(let movesAndNrs): movesAndNrs.map(\.move)
      default: []
      }

    #expect(
      reverseMoves == [Move([[mock.coreMove(eid: "BP1", target: .magnet("A2"), huggers: [])]])]
    )
  }

  /// Complex: undoing a subsequent move of a captured piece reverts it to the position it was moved to on capture
  @Test func chess_revertCapturedPieceBackToStateAfterCapture() {
    let ROOK_POSITION: SIMD3<Float> = [0.22, 0, 0.18]  // just off the board edge after being displaced
    let history = MoveHistory(moves: [
      // unrelated black queen maneuver
      mock.move(eid: "BQ", target: .magnet("D5")),
      // black pawn advances to A5; white rook is captured (side-effect: pushed off the board)
      Move([
        [
          mock.coreMove(eid: "BP1", target: .magnet("A5")),
          mock.coreMove(eid: "WR1", target: .position(ROOK_POSITION)),
        ]
      ]), mock.move(eid: "WR1", target: .position([0.22, 0, 0.127])),
    ])

    let browseResult = history.browseHistory(
      action: .undo,
      animatingTowards: nil,
      currentlyAnimating: nil,
      presetDic: CHESS_PRESET_DIC
    )
    let reverseMoves: [Move] =
      switch browseResult {
      case .animateMoves(let movesAndNrs): movesAndNrs.map(\.move)
      default: []
      }

    #expect(
      reverseMoves == [
        Move([[mock.coreMove(eid: "WR1", target: .position(ROOK_POSITION), huggers: [])]])
      ]
    )
  }

  /// Complex: undoing a corner Go capture — white stone clones return to their board positions;
  /// the freshly placed black stone (a clone with no prior history) returns to its original cloner
  /// (its bowl, via `clonePresetDic`). Captures undo first (reverse chunk order), then the placement.
  @Test func go_revertCaptureMove_stonesAreClones() {
    let history = MoveHistory(moves: [
      // corner setup: 3 white stones form a group at the bottom-left corner (A1, B1, A2),
      // 2 black stones already block two of the three external liberties (C1 and A3)
      Move([
        [
          mock.coreMove(eidClone: "white1", target: .magnet("A1")),  // white in the corner
          mock.coreMove(eidClone: "white2", target: .magnet("B1")),  // white right of corner
          mock.coreMove(eidClone: "white3", target: .magnet("A2")),  // white above corner
          mock.coreMove(eidClone: "blackA", target: .magnet("C1")),  // black blocking B1's right liberty
          mock.coreMove(eidClone: "blackB", target: .magnet("A3")),  // black blocking A2's top liberty
        ]
      ]),
      // unrelated move elsewhere on the board — confirms black5 doesn't pollute the white-stone lookup
      Move([[mock.coreMove(eidClone: "black5", target: .magnet("Q10"))]]),
      Move([
        [
          // black fills the last liberty at B2, completing the surround of the three white stones
          mock.coreMove(eidClone: "black1", target: .magnet("B2"))
        ],
        [
          // surrounded white stones are captured — all go to the black player's bowl
          mock.coreMove(eidClone: "white1", target: .magnet("BowlLidBlack")),
          mock.coreMove(eidClone: "white2", target: .magnet("BowlLidBlack")),
          mock.coreMove(eidClone: "white3", target: .magnet("BowlLidBlack")),
        ],
      ]),
    ])

    let browseResult = history.browseHistory(
      action: .undo,
      animatingTowards: nil,
      currentlyAnimating: nil,
      clonePresetDic: ["black1": ClonePreset(originalClonerEid: EID.other(name: "BowlBlack"))]
    )
    let reverseMoves: [Move] =
      switch browseResult {
      case .animateMoves(let movesAndNrs): movesAndNrs.map(\.move)
      default: []
      }

    #expect(
      reverseMoves == [
        Move([
          [
            mock.coreMove(eidClone: "white3", target: .magnet("A2")),  // returns above corner
            mock.coreMove(eidClone: "white2", target: .magnet("B1")),  // returns right of corner
            mock.coreMove(eidClone: "white1", target: .magnet("A1")),  // returns to corner
          ],
          [
            mock.coreMove(eidClone: "black1", target: .magnet("BowlBlack"))  // fresh clone — returns to its bowl
          ],
        ])
      ]
    )
  }

  /// Complex: undoing a Go capture — whites with a known prior position carry that last known target
  /// when reverting, rather than falling back to `.unset`
  @Test func go_revertCaptureMove_whitesHavePriorPosition() {
    let history = MoveHistory(moves: [
      Move([
        [
          mock.coreMove(eidClone: "white1", target: .magnet("A1")),
          mock.coreMove(eidClone: "white2", target: .magnet("A2")),
          mock.coreMove(eidClone: "white3", target: .magnet("A3")),
        ]
      ]),
      Move([
        [
          // black stone places on the board
          mock.coreMove(eidClone: "black", target: .position([1, 0, 0]))
        ],
        [
          // surrounded white stones are captured — all go to the black player's bowl
          mock.coreMove(eidClone: "white1", target: .magnet("BowlLidBlack")),
          mock.coreMove(eidClone: "white2", target: .magnet("BowlLidBlack")),
          mock.coreMove(eidClone: "white3", target: .magnet("BowlLidBlack")),
        ],
      ]),
    ])

    let browseResult = history.browseHistory(
      action: .undo,
      animatingTowards: nil,
      currentlyAnimating: nil,
      clonePresetDic: ["black": ClonePreset(originalClonerEid: EID.other(name: "BowlBlack"))]
    )
    let reverseMoves: [Move] =
      switch browseResult {
      case .animateMoves(let movesAndNrs): movesAndNrs.map(\.move)
      default: []
      }

    #expect(
      reverseMoves == [
        Move([
          [
            mock.coreMove(eidClone: "white3", target: .magnet("A3")),
            mock.coreMove(eidClone: "white2", target: .magnet("A2")),
            mock.coreMove(eidClone: "white1", target: .magnet("A1")),
          ], [mock.coreMove(eidClone: "black", target: .magnet("BowlBlack"))],
        ])
      ]
    )
  }

  /// Complex: undoing a chess capture where the same piece appears across multiple parts of the move
  @Test func chess_revertCaptureMoveAndSideEffects() {
    let history = MoveHistory(moves: [
      Move([
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
    ])

    let browseResult = history.browseHistory(
      action: .undo,
      animatingTowards: nil,
      currentlyAnimating: nil,
      presetDic: CHESS_PRESET_DIC
    )
    let reverseMoves: [Move] =
      switch browseResult {
      case .animateMoves(let movesAndNrs): movesAndNrs.map(\.move)
      default: []
      }

    #expect(
      reverseMoves == [
        Move([
          [
            mock.coreMove(eid: "WP1", target: .magnet("A7")),
            mock.coreMove(eid: "BP1", target: .magnet("A7"), huggers: []),
          ], [mock.coreMove(eid: "WP1", target: .magnet("A2"), huggers: [])],
        ])
      ]
    )
  }

  /// Complex: undoing a move that carried a stack of cards reverts all stacked cards to their initial state
  @Test func cards_revertMove_andCarriedStack() {
    let INITIAL_POSITION: SIMD3<Float> = [0, 0, 0]
    // Card:UUID1 started at INITIAL_POSITION with A, B, C already stacked on it
    let presetDic: [EID: EntityState] = [
      .other(name: "Card:UUID1"): EntityState(
        eid: .other(name: "Card:UUID1"),
        position: INITIAL_POSITION
      ),
      .other(name: "Card:UUIDA"): EntityState(
        eid: .other(name: "Card:UUIDA"),
        magneticHugs: MagneticHugsComponent(hugging: .other(name: "Card:UUID1"), huggedBy: [])
      ),
      .other(name: "Card:UUIDB"): EntityState(
        eid: .other(name: "Card:UUIDB"),
        magneticHugs: MagneticHugsComponent(hugging: .other(name: "Card:UUID1"), huggedBy: [])
      ),
      .other(name: "Card:UUIDC"): EntityState(
        eid: .other(name: "Card:UUIDC"),
        magneticHugs: MagneticHugsComponent(hugging: .other(name: "Card:UUID1"), huggedBy: [])
      ),
    ]
    let history = MoveHistory(moves: [
      // some other card move that happened earlier
      mock.move(eid: "Card:UUID0", target: .position([1, 0, 0])),
      Move([
        [
          // card 1 moves, carrying A, B, C stacked on top of it
          mock.coreMove(eid: "Card:UUID1", target: .position([1, 0, 0])),
          mock.coreMove(eid: "Card:UUIDA", target: .magnet("Card:UUID1")),
          mock.coreMove(eid: "Card:UUIDB", target: .magnet("Card:UUID1")),
          mock.coreMove(eid: "Card:UUIDC", target: .magnet("Card:UUID1")),
        ]
      ]),
    ])

    let browseResult = history.browseHistory(
      action: .undo,
      animatingTowards: nil,
      currentlyAnimating: nil,
      presetDic: presetDic
    )
    let reverseMoves: [Move] =
      switch browseResult {
      case .animateMoves(let movesAndNrs): movesAndNrs.map(\.move)
      default: []
      }

    #expect(
      reverseMoves == [
        Move([
          [
            mock.coreMove(eid: "Card:UUIDC", target: .magnet("Card:UUID1"), huggers: []),
            mock.coreMove(eid: "Card:UUIDB", target: .magnet("Card:UUID1"), huggers: []),
            mock.coreMove(eid: "Card:UUIDA", target: .magnet("Card:UUID1"), huggers: []),
            mock.coreMove(eid: "Card:UUID1", target: .position(INITIAL_POSITION)),
          ]
        ])
      ]
    )
  }

  /// Complex: undoing a stack merge reverts all cards to their positions before the merge
  @Test func cards_revertStackMerge() {
    let POS_CARD1: SIMD3<Float> = [5, 0, 0]
    let history = MoveHistory(moves: [
      // card A stacks on card 1
      mock.move(eid: "Card:UUIDA", target: .magnet("Card:UUID1")),
      // card B stacks on card 1
      mock.move(eid: "Card:UUIDB", target: .magnet("Card:UUID1")),
      // card 2 moves somewhere
      mock.move(eid: "Card:UUID2", target: .position([1, 0, 0])),
      // card 1 (with A+B stacked) moves to POS_CARD1
      mock.move(eid: "Card:UUID1", target: .position(POS_CARD1)),
      Move([
        [
          // card 1 (with A+B stacked) merges onto card 2
          mock.coreMove(eid: "Card:UUID1", target: .magnet("Card:UUID2")),
          mock.coreMove(eid: "Card:UUIDA", target: .magnet("Card:UUID2")),
          mock.coreMove(eid: "Card:UUIDB", target: .magnet("Card:UUID2")),
        ]
      ]),
    ])

    let browseResult = history.browseHistory(
      action: .undo,
      animatingTowards: nil,
      currentlyAnimating: nil
    )
    let reverseMoves: [Move] =
      switch browseResult {
      case .animateMoves(let movesAndNrs): movesAndNrs.map(\.move)
      default: []
      }

    #expect(
      reverseMoves == [
        Move([
          [
            mock.coreMove(eid: "Card:UUIDB", target: .magnet("Card:UUID1"), ),
            mock.coreMove(eid: "Card:UUIDA", target: .magnet("Card:UUID1"), ),
            mock.coreMove(eid: "Card:UUID1", target: .position(POS_CARD1), ),
          ]
        ])
      ]
    )
  }

  /// Complex: splitting a tower and undoing restores each card to its pre-split stack position
  @Test func cards_revertTowerSplit() {
    let POS_CARD1: SIMD3<Float> = [5, 0, 0]
    let history = MoveHistory(moves: [
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
      Move([
        [
          // card A splits off from the tower and moves to a new location
          mock.coreMove(eid: "Card:UUIDA", target: .position([1, 0, 0])),
          // card B rides on top of card A as it splits off
          mock.coreMove(eid: "Card:UUIDB", target: .magnet("Card:UUIDA")),
        ]
      ]),
    ])

    let browseResult = history.browseHistory(
      action: .undo,
      animatingTowards: nil,
      currentlyAnimating: nil
    )
    let reverseMoves: [Move] =
      switch browseResult {
      case .animateMoves(let movesAndNrs): movesAndNrs.map(\.move)
      default: []
      }

    #expect(
      reverseMoves == [
        Move([
          [
            mock.coreMove(eid: "Card:UUIDB", target: .magnet("Card:UUID2"), ),
            mock.coreMove(eid: "Card:UUIDA", target: .magnet("Card:UUID2"), ),
          ]
        ])
      ]
    )
  }

  /// Undoing an opacity-only move with no prior history reverts to initial state
  /// Boundary: first and only move — no history to search, falls back to preset opacity
  @Test func cards_revertModelChangeAsInitialMove() {
    // pack starts closed: closed model visible, open model hidden
    let presetDic: [EID: EntityState] = [
      .other(name: "CardsPackClosed"): EntityState(
        eid: .other(name: "CardsPackClosed"),
        opacity: 1.0
      ),
      .other(name: "CardsPackOpen"): EntityState(eid: .other(name: "CardsPackOpen"), opacity: 0.0),
    ]
    let history = MoveHistory(moves: [
      Move([
        [
          // open-state model becomes visible
          mock.coreMove(eid: "CardsPackOpen", opacity: 1.0),
          // closed-state model becomes hidden
          mock.coreMove(eid: "CardsPackClosed", opacity: 0.0),
        ]
      ])
    ])

    let browseResult = history.browseHistory(
      action: .undo,
      animatingTowards: nil,
      currentlyAnimating: nil,
      presetDic: presetDic
    )
    let reverseMoves: [Move] =
      switch browseResult {
      case .animateMoves(let movesAndNrs): movesAndNrs.map(\.move)
      default: []
      }

    #expect(
      reverseMoves == [
        Move([
          [
            mock.coreMove(eid: "CardsPackClosed", opacity: 1.0),
            mock.coreMove(eid: "CardsPackOpen", opacity: 0.0),
          ]
        ])
      ]
    )
  }

  /// Complex: undoing an opacity-only move when a prior matching move exists restores the prior opacity
  @Test func cards_revertModelChangeAsSubsequentMove() {
    let history = MoveHistory(moves: [
      // pack opens
      Move([
        [
          mock.coreMove(eid: "CardsPackOpen", opacity: 1.0),
          mock.coreMove(eid: "CardsPackClosed", opacity: 0.0),
        ]
      ]),
      // pack closes — this is the prior state that should be restored on undo
      Move([
        [
          mock.coreMove(eid: "CardsPackOpen", opacity: 0.0),
          mock.coreMove(eid: "CardsPackClosed", opacity: 1.0),
        ]
      ]),
      // pack opens again — this is the move being undone
      Move([
        [
          mock.coreMove(eid: "CardsPackOpen", opacity: 1.0),
          mock.coreMove(eid: "CardsPackClosed", opacity: 0.0),
        ]
      ]),
    ])

    let browseResult = history.browseHistory(
      action: .undo,
      animatingTowards: nil,
      currentlyAnimating: nil
    )
    let reverseMoves: [Move] =
      switch browseResult {
      case .animateMoves(let movesAndNrs): movesAndNrs.map(\.move)
      default: []
      }

    #expect(
      reverseMoves == [
        Move([
          [
            mock.coreMove(eid: "CardsPackClosed", opacity: 1.0),
            mock.coreMove(eid: "CardsPackOpen", opacity: 0.0),
          ]
        ])
      ]
    )
  }

  /// Complex: undoing an opacity change preserves the entity's position from a prior move
  @Test func cards_moveThenOpenPack() {
    let POS: SIMD3<Float> = [5, 0, 0]
    let history = MoveHistory(moves: [
      // both pack variants move together to POS
      Move([
        [
          mock.coreMove(eid: "CardsPackClosed", target: .position(POS)),
          mock.coreMove(eid: "CardsPackOpen", target: .position(POS)),
        ]
      ]),
      Move([
        [
          // open-state model becomes visible
          mock.coreMove(eid: "CardsPackOpen", opacity: 1.0),
          // closed-state model becomes hidden
          mock.coreMove(eid: "CardsPackClosed", opacity: 0.0),
        ]
      ]),
    ])

    let browseResult = history.browseHistory(
      action: .undo,
      animatingTowards: nil,
      currentlyAnimating: nil
    )
    let reverseMoves: [Move] =
      switch browseResult {
      case .animateMoves(let movesAndNrs): movesAndNrs.map(\.move)
      default: []
      }

    #expect(
      reverseMoves == [
        Move([
          [
            mock.coreMove(eid: "CardsPackClosed", target: .position(POS), opacity: 1.0),
            mock.coreMove(eid: "CardsPackOpen", target: .position(POS), opacity: 1.0),
          ]
        ])
      ]
    )
  }

  /// Boundary: clone has no prior history and no preset entry — its baseline comes from
  /// `clonePresetDic`: undoing its first move sends it back to its original cloner (the bowl),
  /// oriented as it spawned.
  @Test func go_undoCloneFirstMove_returnsToItsCloner() {
    let history = MoveHistory(moves: [
      Move([[mock.coreMove(eidClone: "black", target: .magnet("D4"))]])
    ])
    let spawnOrientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])

    let browseResult = history.browseHistory(
      action: .undo,
      animatingTowards: nil,
      currentlyAnimating: nil,
      clonePresetDic: [
        "black": ClonePreset(
          originalClonerEid: EID.other(name: "BowlBlack"),
          initialOrientation: spawnOrientation
        )
      ]
    )
    let reverseMoves: [Move] =
      switch browseResult {
      case .animateMoves(let movesAndNrs): movesAndNrs.map(\.move)
      default: []
      }

    #expect(
      reverseMoves == [
        Move([
          [
            mock.coreMove(
              eidClone: "black",
              target: .magnet("BowlBlack"),
              orientation: spawnOrientation
            )
          ]
        ])
      ]
    )
  }

  /// Boundary: clone has no baseline ANYWHERE — no history, no preset entry, no clonePresetDic
  /// entry. It has nowhere to return to, so the reverse move fades it out in place.
  @Test func go_undoCloneFirstMove_noClonePreset_fadesOut() {
    let history = MoveHistory(moves: [
      Move([[mock.coreMove(eidClone: "black", target: .magnet("D4"))]])
    ])

    let browseResult = history.browseHistory(
      action: .undo,
      animatingTowards: nil,
      currentlyAnimating: nil
    )
    let reverseMoves: [Move] =
      switch browseResult {
      case .animateMoves(let movesAndNrs): movesAndNrs.map(\.move)
      default: []
      }

    #expect(reverseMoves == [Move([[mock.coreMove(eidClone: "black", opacity: 0)]])])
  }

  /// Complex: undoing an opacity change correctly combines position from one history entry and opacity from another
  @Test func cards_revertModelChangeWithMovesInBetween() {
    let history = MoveHistory(moves: [
      // pack opens
      Move([
        [
          mock.coreMove(eid: "CardsPackOpen", opacity: 1.0),
          mock.coreMove(eid: "CardsPackClosed", opacity: 0.0),
        ]
      ]),
      // pack moves to a new position
      mock.move(eid: "CardsPackOpen", target: .position([1, 1, 1])),
      Move([
        [
          // open-state model becomes hidden
          mock.coreMove(eid: "CardsPackOpen", opacity: 0.0),
          // closed-state model becomes visible
          mock.coreMove(eid: "CardsPackClosed", opacity: 1.0),
        ]
      ]),
    ])

    let browseResult = history.browseHistory(
      action: .undo,
      animatingTowards: nil,
      currentlyAnimating: nil
    )
    let reverseMoves: [Move] =
      switch browseResult {
      case .animateMoves(let movesAndNrs): movesAndNrs.map(\.move)
      default: []
      }

    #expect(
      reverseMoves == [
        Move([
          [
            mock.coreMove(eid: "CardsPackClosed", opacity: 0.0),
            mock.coreMove(eid: "CardsPackOpen", target: .position([1, 1, 1]), opacity: 1.0, ),
          ]
        ])
      ]
    )
  }

  /// Undoing a move that changed a magnet's stackOffset must revert the magneticField,
  /// even when the magneticField CoreMove was merged with a huggers snapshot (e.g. by
  /// `withSideEffects`). The huggers-only undo path must carry the previous magneticField
  /// through, not drop it.
  @Test func undo_magneticFieldStackOffset_revertsWhenMergedWithHuggers() {
    let M = EID.other(name: "M")
    let Card = EID.other(name: "Card")
    let INITIAL_FIELD = MagneticFieldPartial(stackOffset: [0, 0, 0])
    let CHANGED_FIELD = MagneticFieldPartial(stackOffset: [0, 0, -0.026])

    let presetDic: [EID: EntityState] = [
      M: EntityState(eid: M, position: [0, 0, 0], magneticField: INITIAL_FIELD),
      Card: EntityState(eid: Card, magneticHugs: MagneticHugsComponent(hugging: M, huggedBy: [])),
    ]

    // Simulates what withSideEffects produces when a huggers snapshot and a magneticField
    // side effect share the same EID — they get merged into one CoreMove.
    let history = MoveHistory(moves: [
      Move([
        [
          mock.coreMove(eid: "Card", target: .magnet("M")),
          CoreMove(eid: M, magneticField: CHANGED_FIELD, huggers: [Card]),
        ]
      ])
    ])

    let browseResult = history.browseHistory(
      action: .undo,
      animatingTowards: nil,
      currentlyAnimating: nil,
      presetDic: presetDic
    )
    let reverseMoves: [Move] =
      switch browseResult {
      case .animateMoves(let movesAndNrs): movesAndNrs.map(\.move)
      default: []
      }

    let allReverseCores = reverseMoves.flatMap { $0.chunks.flatMap { $0 } }
    let mReverse = allReverseCores.first { $0.eid == M }
    #expect(
      mReverse?.magneticField == INITIAL_FIELD,
      "Undo must revert magneticField.stackOffset to its initial value, not drop it"
    )
  }

  /// Complex: duration from the original move is propagated to the undo move
  @Test func cards_revertModelChangeWithDuration() {
    // cards start invisible before the fade-in
    let presetDic: [EID: EntityState] = [
      .other(name: "Card1"): EntityState(eid: .other(name: "Card1"), opacity: 0.0),
      .other(name: "Card2"): EntityState(eid: .other(name: "Card2"), opacity: 0.0),
      .other(name: "Card3"): EntityState(eid: .other(name: "Card3"), opacity: 0.0),
    ]
    let history = MoveHistory(moves: [
      Move([
        [
          // 3 cards fade in together over 2 seconds
          mock.coreMove(eid: "Card1", opacity: 1.0, duration: .seconds(2)),
          mock.coreMove(eid: "Card2", opacity: 1.0, duration: .seconds(2)),
          mock.coreMove(eid: "Card3", opacity: 1.0, duration: .seconds(2)),
        ]
      ])
    ])

    let browseResult = history.browseHistory(
      action: .undo,
      animatingTowards: nil,
      currentlyAnimating: nil,
      presetDic: presetDic
    )
    let reverseMoves: [Move] =
      switch browseResult {
      case .animateMoves(let movesAndNrs): movesAndNrs.map(\.move)
      default: []
      }

    #expect(
      reverseMoves == [
        Move([
          [
            mock.coreMove(eid: "Card3", opacity: 0.0, duration: .seconds(2)),
            mock.coreMove(eid: "Card2", opacity: 0.0, duration: .seconds(2)),
            mock.coreMove(eid: "Card1", opacity: 0.0, duration: .seconds(2)),
          ]
        ])
      ]
    )
  }
}
