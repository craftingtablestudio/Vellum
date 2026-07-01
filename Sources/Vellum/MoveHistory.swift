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
  public func toMoveNr(history: v0.MoveHistory) -> MoveNr {
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

  public func toActualMoveNr(history: v0.MoveHistory) -> ActualMoveNr {
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
  addOrBrowseIndex: MoveAddOrBrowseIndex, newMoveNr: MoveNr, backupForDivergence: v0.HistoryBackup?
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

extension v0.MoveHistory {
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
  public var playedMoves: [v0.Move] { return self.moves.slice(0, self.moveNrActual.value) }

  // MARK: materializeEntityStateDic

  /// Forward-folds the played history onto `presetDic` to reconstruct the materialised
  /// `[EID: EntityState]` for the currently-visible `moveNr`.
  ///
  /// This is the replacement for the (removed) persisted `entityDic` "snapshot truth":
  /// instead of storing the materialised state, it is recomputed on demand from the two
  /// things that ARE persisted — `presetDic` (the move-0 baseline) and `history.moves`.
  ///
  /// For each entity that exists at the current `moveNr` (every key in `presetDic` plus every
  /// EID that ever appears in a played move), the last-known state is resolved via
  /// `MoveHistoryHelpers.findPreviousCoreMove` — the same primitive the undo system already
  /// trusts — and converted into an `EntityState`.
  ///
  /// `physicsMode` is carried from `presetDic` (no `CoreMove` field changes it). A clone spawned
  /// *mid-history* has no `presetDic` entry, so its `physicsMode` resolves to `nil` — which is
  /// harmless: no load path applies `entityDic.physicsMode`. Clones inherit their template's
  /// physics mode at creation, `CoreMove`s carry no physics, and the only consumer of
  /// `EntityState.physicsMode` (`upsertProgramatically`) runs for peer live-sync, fed by a wire
  /// capture rather than this dictionary.
  ///
  /// Destruction is folded too: an entity whose resolved magnet is a `.destroy` magnet (a Go
  /// bowl, a Solitaire/Innovation sink) is dropped from the result, mirroring the live scene
  /// where capturing an entity deletes it. Dangling references to dropped entities are stripped
  /// from every surviving magnet's `huggedBy`.
  ///
  /// Complexity is O(eids × playedMoves) worst case via the per-EID reverse search; for realistic
  /// games this is well within budget (see the Vellum perf test). Pass an explicit `upTo` to
  /// materialise a specific move number (defaults to the history's current `moveNr`).
  public func materializeEntityStateDic(
    presetDic: [v0.EID: v0.EntityState],
    upTo: ActualMoveNr? = nil
  ) -> [v0.EID: v0.EntityState] {
    let visibleCount = (upTo ?? self.moveNrActual).value
    let playedMoves = self.moves.slice(0, visibleCount)

    // The set of entities that exist at this move number: the preset baseline plus every EID
    // that authored a played move, plus every EID referenced as a `magnet` target. Today every
    // real magnet is either preset scenery or a fan/tower host that authors its own `huggers`
    // snapshot (so it already shows up as `coreMove.eid`); including the target defensively keeps
    // the result self-consistent if a future plugin adds a magnet referenced only as a target —
    // otherwise a hugger would point at a magnet missing from the dic (violating `validateEntityDic`
    // rule 5). `.none` / `.originalCloner` are not real entities and are skipped.
    var candidateEids = Set(presetDic.keys)
    for move in playedMoves {
      for chunk in move.chunks {
        for coreMove in chunk where coreMove.eid != v0.EID.none {
          candidateEids.insert(coreMove.eid)
          if let magnet = coreMove.magnet, magnet != .none, magnet != .originalCloner {
            candidateEids.insert(magnet)
          }
        }
      }
    }

    // Resolve each candidate's last-known state by folding history onto the preset baseline.
    var resolved: [v0.EID: v0.CoreMove] = [:]
    for eid in candidateEids {
      resolved[eid] = MoveHistoryHelpers.findPreviousCoreMove(
        search: eid,
        searchThrough: playedMoves,
        presetDic: presetDic
      )
    }

    // A ClonableGroup child clone (e.g. a PlayerSet magnet) never authors its own move — it's spawned
    // nested when its container clone is — so `findPreviousCoreMove` falls back to `.magnet(.originalCloner)`
    // with no transform. Its authoritative resting pose is its template child's parent-relative transform,
    // captured in `presetDic` under `EID.other(<sameChildName>)`. Inherit that (mirroring what
    // `resolveOriginalCloner` does live, but from pure preset data) so the child materialises with the
    // right parent-local pose instead of pose-less — otherwise the canonical-load default fills identity
    // and wipes the template-authored orientation.
    for eid in candidateEids where eid.isGroupClone && resolved[eid]?.magnet == .originalCloner {
      guard let template = presetDic[v0.EID.other(name: eid.name)] else { continue }
      var coreMove = resolved[eid]!
      coreMove.magnet = nil
      coreMove.position = coreMove.position ?? template.position
      coreMove.orientation = coreMove.orientation ?? template.orientation
      coreMove.scale = coreMove.scale ?? template.scale
      resolved[eid] = coreMove
    }

    /// True when `eid`'s resolved magnetic field is a destroyer. `findPreviousCoreMove` already
    /// folds the preset's `magneticField` into the resolved CoreMove, so checking `resolved` is
    /// sufficient — and every magnet referenced as a target is a `candidateEids` member, hence
    /// always present in `resolved`.
    func isDestroyer(_ eid: v0.EID) -> Bool { resolved[eid]?.magneticField?.hugEffect == .destroy }

    // Entities whose final resting magnet destroys them are gone from the materialised scene.
    let destroyed = Set(
      candidateEids.filter { eid in
        if let magnet = resolved[eid]?.magnet { return isDestroyer(magnet) }
        return false
      }
    )

    // The authoritative `hugging` relationship per surviving entity. `huggedBy` is reconciled
    // against THIS map below so the two stay bidirectionally consistent — a stale `huggers`
    // snapshot can't leave a magnet claiming a hugger that has since moved (or been destroyed).
    //
    // `.originalCloner` / `.none` are NOT real magnets: `findPreviousCoreMove` returns
    // `.magnet(.originalCloner)` as a fallback for any clone with no position/magnet of its own —
    // in practice a clone magnet HOST (e.g. a ClonableGroup `Hand`) that only ever appears in
    // history via its own `huggers` snapshot. Such a host isn't hugging anything; it carries its
    // huggers below. Treating the sentinel as a hug would point it at a non-existent entity.
    var huggingByEid: [v0.EID: v0.EID] = [:]
    for eid in candidateEids where !destroyed.contains(eid) {
      if let magnet = resolved[eid]?.magnet, magnet != .originalCloner, magnet != .none,
        !destroyed.contains(magnet)
      {
        huggingByEid[eid] = magnet
      }
    }

    var dic: [v0.EID: v0.EntityState] = [:]
    for eid in candidateEids where !destroyed.contains(eid) {
      guard let coreMove = resolved[eid] else { continue }
      let hugging = huggingByEid[eid]
      // Reconcile huggedBy: keep the snapshot's ordering but only for entities that actually hug
      // this magnet now, then append any current huggers the snapshot missed (deterministic order).
      let actualHuggers = Set(huggingByEid.filter { $0.value == eid }.map { $0.key })
      let ordered = (coreMove.huggers ?? []).filter { actualHuggers.contains($0) }
      let stragglers = actualHuggers.subtracting(ordered).sorted { $0.description < $1.description }
      let huggedBy = ordered + stragglers
      // Keep a present-but-empty `MagneticHugsComponent` for any entity that participates in the
      // magnet system — a magnet whose last hugger just left still carries an (empty) component
      // in the live scene, and `validateEntityDic` relies on a magnet's component being present to
      // confirm the bidirectional hug. The proxy: it hugs/is-hugged now, history snapshotted its
      // huggers, or it carried the component at the preset baseline.
      let participatesInMagnetism =
        hugging != nil || !huggedBy.isEmpty || coreMove.huggers != nil
        || presetDic[eid]?.magneticHugs != nil
      let magneticHugs: v0.MagneticHugsComponent? =
        participatesInMagnetism
        ? v0.MagneticHugsComponent(hugging: hugging, huggedBy: huggedBy) : nil
      dic[eid] = v0.EntityState(
        eid: eid,
        position: coreMove.position,
        orientation: coreMove.orientation,
        scale: coreMove.scale,
        physicsMode: presetDic[eid]?.physicsMode,
        magneticHugs: magneticHugs,
        modelMeta: coreMove.modelMeta,
        magneticField: coreMove.magneticField,
        opacity: coreMove.opacity
      )
    }
    return dic
  }

  private var lastVisibleMove: v0.Move? { return self.playedMoves.at(-1) }

  // MARK: compareMove

  private func compareMove(
    moveToAppend: v0.Move,
    initialStateDic: [v0.EID: v0.EntityState]
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
      let unchanged = MoveHistoryHelpers.coreMoveUnchanged(
        coreMove: coreMove,
        movesToCompareWith: playedMoves,
        initialStateDic: initialStateDic
      )
      if DEBUGGING_VELLUM { print("[compareMove] \(coreMove.eid) unchanged:", unchanged) }
      return unchanged
    }
    if DEBUGGING_VELLUM {
      print("[compareMove] moveSameAsLast:", moveSameAsLast, "chunks:", moveToAppend.chunks.count)
    }
    return moveSameAsLast ? .matchesCurrentState : .isNew
  }

  // MARK: appendMove

  /// Appends a move to the history ledger.
  ///
  /// - Parameters:
  ///   - initialStateDic: The initial state of all entities, used to detect duplicate moves.
  ///   - atIndex: When non-nil, inserts the move at exactly that index and skips all
  ///     duplicate-detection logic. Intended for multiplayer sync: a remote participant's move
  ///     arrives with the index it was assigned on their device, and must land at the same
  ///     position in every participant's history to keep ledgers identical.
  ///   - setMoveNr: When `true`, resets `moveNr` to `-1` (latest) after inserting. Must be
  ///     `true` whenever `atIndex` is nil.
  /// - Returns: `MoveResult` — nil if the move was a no-op.
  @discardableResult public mutating func appendMove(
    _ move: v0.Move,
    initialStateDic: [v0.EID: v0.EntityState],
    atIndex: MoveIndex?,
    setMoveNr: Bool
  ) throws -> MoveResult {
    let errors = move.validate()
    if !errors.isEmpty {
      print("❗️[appendMove] Move not added because there are errors")
      for e in errors { print("  - \(e)") }
      throw VellumError.invalidState
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

    var backupForDivergence: v0.HistoryBackup? = nil

    if self.moveNr > -1 {
      let divergenceMoveNr = self.moveNrActual.value
      let movesToTruncate = self.moves.count - divergenceMoveNr

      if movesToTruncate > 1 {
        backupForDivergence = v0.HistoryBackup(
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
    case animateMoves(
      movesAndNrs: [(move: v0.Move, oldMoveNr: ActualMoveNr, newMoveNr: ActualMoveNr)]
    )
    case stopAnimating(stopAt: ActualMoveNr)
  }

  /// Returns the moves to animate for a given browse action.
  ///
  /// Call sites should:
  /// 1. Immediately save `animatingTowardsMoveNr` to the history.
  /// 2. After each animation completes, save the new `moveNr`.
  ///
  /// - Parameter presetDic: Initial entity states used to resolve undo moves eagerly.
  ///   Clones not in `presetDic` with no target in history get `.magnet(.originalCloner)`.
  public func browseHistory(
    action: BrowseAction,
    animatingTowards: ActualMoveNr?,
    currentlyAnimating: ActualMoveNr?,
    presetDic: [v0.EID: v0.EntityState] = [:]
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
      var movesToAnimate: [(move: v0.Move, oldMoveNr: ActualMoveNr, newMoveNr: ActualMoveNr)] = []
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

      var movesToAnimate: [(move: v0.Move, oldMoveNr: ActualMoveNr, newMoveNr: ActualMoveNr)] = []
      for (moveToUndoIndex, moveToUndo) in movesToUndo.enumerated() {
        let originalMoveIndex = wasAimingFor.value - moveToUndoIndex - 1
        let movesToSearchThrough = self.moves.slice(0, originalMoveIndex)
        let chunks = MoveHistoryHelpers.moveToPreviousCoreMoves(
          moveToUndo,
          searchThrough: movesToSearchThrough,
          presetDic: presetDic
        )
        let moveToUndo = v0.Move(chunks)
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
