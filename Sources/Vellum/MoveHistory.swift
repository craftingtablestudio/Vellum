import Foundation

// MARK: - Supporting types

/// A move index is a non-negative integer (>= 0) representing the index of a move in the history.
public struct MoveIndex: Sendable, Equatable, Codable, Hashable {
  public let rawValue: UInt
  public var value: Int { Int(rawValue) }

  public init(_ value: UInt) { self.rawValue = value }

  public init(clamping intValue: Int) { self.rawValue = UInt(clamping: intValue) }
}

/// A non `-1` moveNr, often used to represent which moveNr to jump to.
public struct ActualMoveNr: Sendable, Equatable, Codable, Hashable {
  public let rawValue: UInt
  public var value: Int { Int(rawValue) }

  public init(_ rawValue: UInt) { self.rawValue = rawValue }

  public init(clamping intValue: Int) { self.rawValue = UInt(clamping: intValue) }

  /// Returns `.lastMove` if the value equals `moves.count`, otherwise `.specific`.
  public func toMoveNr(history: MoveHistory) -> MoveNr {
    if self.value == history.moves.count { return .lastMove }
    return .specific(rawValue)
  }
}

/// - `.lastMove` encodes as `-1`
/// - `.specific` is a `UInt` (0 or higher)
public enum MoveNr: Sendable, Equatable, Codable, Hashable {
  case lastMove
  case specific(UInt)

  public var value: Int {
    return switch self {
    case .lastMove: -1
    case .specific(let val): Int(val)
    }
  }

  public init(clamping intValue: Int) {
    if intValue <= -1 { self = .lastMove } else { self = .specific(UInt(clamping: intValue)) }
  }

  public func toActualMoveNr(history: MoveHistory) -> ActualMoveNr {
    return switch self {
    case .lastMove: ActualMoveNr(clamping: history.moves.count)
    case .specific(let val): ActualMoveNr(val)
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let intValue = try container.decode(Int.self)
    if intValue <= -1 { self = .lastMove } else { self = .specific(UInt(clamping: intValue)) }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    let intValue: Int =
      switch self {
      case .lastMove: -1
      case .specific(let v): Int(v)
      }
    try container.encode(intValue)
  }
}

/// `addedAtIndex` — A new move was inserted at an index.
/// `browsedToIndex` — The move matched the next move in history (redo via exact replay).
public enum MoveAddOrBrowseIndex: Codable, Sendable {
  case addedAtIndex(MoveIndex)
  case browsedToIndex(MoveIndex)

  public var addedAtIndex: MoveIndex? {
    switch self {
    case .addedAtIndex(let i): return i
    case .browsedToIndex(_): return nil
    }
  }
  public var browsedToIndex: MoveIndex? {
    switch self {
    case .addedAtIndex(_): return nil
    case .browsedToIndex(let i): return i
    }
  }
}

/// Returns `nil` when no move was made; otherwise carries the insert metadata.
/// `newMoveNr` is `-1` when browsing stops. `backupForDivergence` is non-nil when
/// diverging from history (>1 move from end) and should be saved to `historyBackup`.
public typealias MoveResult = (
  addOrBrowseIndex: MoveAddOrBrowseIndex, newMoveNr: MoveNr, backupForDivergence: HistoryBackup?
)?

/// The action requested when browsing history.
public enum BrowseAction: Sendable {
  case undo
  case redo
  /// Navigate to a specific move. `.lastMove` stops browsing.
  case showMove(moveNr: MoveNr)
}

// MARK: - Internal

/// Result of comparing a candidate move against the current history state.
enum MoveComparisonResult {
  case matchesNextMoveInHistory
  case matchesCurrentState
  case isNew
}

// MARK: - MoveHistory extension

extension MoveHistory {
  public var moveNrSafe: MoveNr { MoveNr(clamping: self.moveNr) }

  /// The actual move number currently visible (resolves `-1` to `moves.count`).
  public var moveNrActual: ActualMoveNr { moveNrSafe.toActualMoveNr(history: self) }

  /// The index of the last visible move, or `nil` if at the initial board state.
  public var moveIndexActual: MoveIndex? {
    if moves.isEmpty { return nil }
    let actualMoveIndex = moveNrActual.value - 1
    return actualMoveIndex >= 0 ? MoveIndex(clamping: actualMoveIndex) : nil
  }

  /// True when there are no more moves to undo.
  public func cannotUndo(animatingTowards: ActualMoveNr?) -> Bool {
    let nr = animatingTowards ?? self.moveNrActual
    return self.moves.isEmpty || nr.value == 0
  }

  /// True when there are no more moves to redo.
  public func cannotRedo(animatingTowards: ActualMoveNr?) -> Bool {
    let nr = animatingTowards ?? self.moveNrActual
    return self.moves.isEmpty || nr.value >= self.moves.count
  }

  /// The signed offset between where we are and where we are animating towards.
  public func animatingTowardsOffset(animatingTowards: ActualMoveNr?) -> Int {
    guard let animatingTowards = animatingTowards else { return 0 }
    return animatingTowards.value - self.moveNrActual.value
  }

  /// All moves up to and including the current `moveNr`.
  public var playedMoves: [Move] { return self.moves.slice(0, self.moveNrActual.value) }

  private var lastVisibleMove: Move? { return self.playedMoves.at(-1) }

  // MARK: compareMove

  private func compareMove(
    moveToAppend: Move,
    initialStateDic: [EID: EntityState]
  ) -> MoveComparisonResult {
    if moveNr != -1 && moveNr < moves.count {
      let movesToCompareWith = moves.slice(0, moveNr + 1)
      if let nextMove = movesToCompareWith.last {
        let moveSameAsNext =
          moveToAppend.chunks.count == nextMove.chunks.count
          && moveToAppend.chunks.enumerated()
            .allSatisfy { (chunkIndex, chunk) in
              let nextMoveChunk = nextMove.chunks[chunkIndex]
              return chunk.count == nextMoveChunk.count
                && chunk.enumerated()
                  .allSatisfy { (i, coreMove) in
                    coreMove.eid == nextMoveChunk[i].eid
                      && MoveHistoryHelpers.coreMoveUnchanged(
                        coreMove: coreMove,
                        movesToCompareWith: movesToCompareWith,
                        initialStateDic: initialStateDic
                      )
                  }
            }
        if moveSameAsNext { return .matchesNextMoveInHistory }
      }
    }

    if playedMoves.last == moveToAppend { return .matchesCurrentState }

    guard let chunkToCheck = moveToAppend.chunks.at(0) else { return .matchesCurrentState }

    let moveSameAsLast = chunkToCheck.allSatisfy { coreMove in
      MoveHistoryHelpers.coreMoveUnchanged(
        coreMove: coreMove,
        movesToCompareWith: playedMoves,
        initialStateDic: initialStateDic
      )
    }
    return moveSameAsLast ? .matchesCurrentState : .isNew
  }

  // MARK: appendMove

  /// Appends a move to the history ledger.
  ///
  /// - Returns: `MoveResult` — nil if the move was a no-op.
  @discardableResult public mutating func appendMove(
    _ move: Move,
    initialStateDic: [EID: EntityState],
    atIndex: MoveIndex?,
    setMoveNr: Bool
  ) throws -> MoveResult {
    let errors = move.validate()
    if !errors.isEmpty {
      print("❗️[appendMove] Move not added because there are errors")
      for e in errors { print("  - \(e)") }
      throw SaveStateError.invalidState
    }

    // Insert at a specific index
    if let atIndex {
      let validIndex = atIndex.value < self.moves.count
      if validIndex {
        self.moves.removeSubrange(atIndex.value...)
        self.moves.append(move)
      } else {
        self.moves.append(move)
      }
      if setMoveNr { self.moveNr = -1 }
      return (
        addOrBrowseIndex: .addedAtIndex(atIndex), newMoveNr: .specific(atIndex.rawValue + 1),
        backupForDivergence: nil
      )
    }

    if !setMoveNr {
      fatalError(
        "Not setting the moveNr is only for moves that had a specific index set when appended."
      )
    }

    switch compareMove(moveToAppend: move, initialStateDic: initialStateDic) {
    case .matchesNextMoveInHistory:
      self.moveNr += 1
      return (
        addOrBrowseIndex: .browsedToIndex(MoveIndex(clamping: self.moveNr - 1)),
        newMoveNr: MoveNr(clamping: self.moveNr), backupForDivergence: nil
      )
    case .matchesCurrentState: return nil
    case .isNew: break
    }

    var backupForDivergence: HistoryBackup? = nil

    if self.moveNr > -1 {
      let divergenceMoveNr = self.moveNrActual.value
      let movesToTruncate = self.moves.count - divergenceMoveNr

      if movesToTruncate > 1 {
        backupForDivergence = HistoryBackup(
          divergenceMoveNr: divergenceMoveNr,
          moves: self.moves.slice(divergenceMoveNr)
        )
      }

      if let moveIndexActual {
        self.moves.removeSubrange((moveIndexActual.value + 1)...)
      } else if self.moveNr == 0 {
        self.moves = []
      }
      self.moveNr = -1
    }

    let addedAtIndex = MoveIndex(clamping: self.moves.count)
    self.moves.append(move)

    return (
      addOrBrowseIndex: .addedAtIndex(addedAtIndex), newMoveNr: MoveNr(clamping: self.moveNr),
      backupForDivergence: backupForDivergence
    )
  }

  // MARK: browseHistory

  public enum BrowseResult {
    case animateMoves(movesAndNrs: [(move: Move, oldMoveNr: ActualMoveNr, newMoveNr: ActualMoveNr)])
    case stopAnimating(stopAt: ActualMoveNr)
  }

  /// Returns the moves to animate for a given browse action.
  ///
  /// Call sites should:
  /// 1. Immediately save `animatingTowardsMoveNr` to the history.
  /// 2. After each animation completes, save the new `moveNr`.
  public func browseHistory(
    action: BrowseAction,
    animatingTowards: ActualMoveNr?,
    currentlyAnimating: ActualMoveNr?
  ) -> BrowseResult {
    if DEBUGGING_VELLUM { print("👀 [browseHistory]", action) }

    let newMoveNr: ActualMoveNr =
      switch action {
      case .undo: ActualMoveNr(clamping: (animatingTowards ?? moveNrActual).value - 1)
      case .redo: ActualMoveNr(clamping: (animatingTowards ?? moveNrActual).value + 1)
      case .showMove(let moveNr):
        switch moveNr {
        case .lastMove: ActualMoveNr(clamping: self.moves.count)
        case .specific(let val): ActualMoveNr(val)
        }
      }

    if let to = animatingTowards?.rawValue, let from = currentlyAnimating?.rawValue {
      let isBetween: Bool =
        if to > from { newMoveNr.rawValue <= to && newMoveNr.rawValue > from } else if from > to {
          newMoveNr.rawValue < from && newMoveNr.rawValue >= to
        } else { false }
      if isBetween { return .stopAnimating(stopAt: newMoveNr) }
    }

    let willAimFor = newMoveNr
    let wasAimingFor = animatingTowards ?? moveNrActual

    // REDOing
    if willAimFor.rawValue > wasAimingFor.rawValue {
      var movesToAnimate: [(move: Move, oldMoveNr: ActualMoveNr, newMoveNr: ActualMoveNr)] = []
      let moves = self.moves.slice(wasAimingFor.value, willAimFor.value)
      for (moveToRedoIndex, moveToRedo) in moves.enumerated() {
        let oldMoveNr = ActualMoveNr(clamping: wasAimingFor.value + moveToRedoIndex)
        let newMoveNr = ActualMoveNr(clamping: wasAimingFor.value + moveToRedoIndex + 1)
        movesToAnimate.append((moveToRedo, oldMoveNr, newMoveNr))
      }
      return .animateMoves(movesAndNrs: movesToAnimate)
    }

    // UNDOing
    if willAimFor.rawValue < wasAimingFor.rawValue {
      let movesToUndo = self.moves.slice(willAimFor.value, wasAimingFor.value).reversed()

      if DEBUGGING_VELLUM {
        print("movesToUndo: moves.slice(\(willAimFor.value), \(wasAimingFor.value)) →", movesToUndo)
      }

      var movesToAnimate: [(move: Move, oldMoveNr: ActualMoveNr, newMoveNr: ActualMoveNr)] = []
      for (moveToUndoIndex, moveToUndo) in movesToUndo.enumerated() {
        let originalMoveIndex = wasAimingFor.value - moveToUndoIndex - 1
        let movesToSearchThrough = self.moves.slice(0, originalMoveIndex)
        let chunks = MoveHistoryHelpers.moveToPreviousCoreMoves(
          moveToUndo,
          searchThrough: movesToSearchThrough
        )
        let moveToUndo = Move(chunks)
        let oldMoveNr = ActualMoveNr(clamping: originalMoveIndex + 1)
        let newMoveNr = ActualMoveNr(clamping: originalMoveIndex)
        movesToAnimate.append((moveToUndo, oldMoveNr, newMoveNr))
      }

      if DEBUGGING_VELLUM { print("movesToAnimate →", movesToAnimate) }
      return .animateMoves(movesAndNrs: movesToAnimate)
    }

    return .animateMoves(movesAndNrs: [])
  }
}
