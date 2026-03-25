import simd

public enum MoveHistoryHelpers {
  /// Finds the previous `CoreMove` for an `EID` by searching through the given moves in reverse.
  ///
  /// Collects the last known position/magnet, orientation, scale, opacity, modelMeta, and
  /// huggerIndex — combining partial results if needed. If nothing is found, returns a
  /// `CoreMove` with `revertToInitialState: true` so the caller can fall back to preset state.
  public static func findPreviousCoreMove(search targetEid: EID, searchThrough: [Move]) -> CoreMove
  {
    struct FoundMoves {
      let targetEid: EID
      init(for targetEid: EID) { self.targetEid = targetEid }

      var position: SIMD3<Float>? = nil
      var magnet: EID? = nil
      var orientation: simd_quatf? = nil
      var scale: SIMD3<Float>? = nil
      var opacity: Float? = nil
      var modelMeta: ModelMetaComponent? = nil
      var huggerIndex: Int? = nil

      mutating func updateMatches(coreMove: CoreMove) {
        if coreMove.eid != targetEid { return }
        if self.position == nil && self.magnet == nil {
          self.position = coreMove.position
          self.magnet = coreMove.magnet
        }
        if self.orientation == nil { self.orientation = coreMove.orientation }
        if self.scale == nil { self.scale = coreMove.scale }
        if self.opacity == nil { self.opacity = coreMove.opacity }
        if self.modelMeta == nil { self.modelMeta = coreMove.modelMeta }
        if self.huggerIndex == nil { self.huggerIndex = coreMove.huggerIndex }
      }

      var allFound: Bool {
        (position != nil || magnet != nil) && orientation != nil && scale != nil
      }
    }

    var found = FoundMoves(for: targetEid)

    searching: for move in searchThrough.reversed() {
      for chunk in move.chunks.reversed() {
        for coreMove in chunk.reversed() {
          found.updateMatches(coreMove: coreMove)
          if found.allFound { break searching }
        }
      }
    }

    let target: CoreMoveTarget =
      if let magnet = found.magnet {
        .magnet(magnet, found.huggerIndex)
      } else if let position = found.position {
        .position(position)
      } else {
        .unset
      }

    return CoreMove(
      eid: targetEid,
      target: target,
      orientation: found.orientation,
      scale: found.scale,
      opacity: found.opacity,
      modelMeta: found.modelMeta,
      duration: nil,
      revertToInitialState: true
    )
  }

  /// Converts a `Move` into its reverse CoreMoves by looking up each entity's previous state.
  ///
  /// Returns `[[CoreMove]]` — a chunked array matching the undo direction.
  public static func moveToPreviousCoreMoves(
    _ moveToUndo: Move,
    searchThrough: [Move]
  ) -> [[CoreMove]] {
    var result: [[CoreMove]] = []
    var chunksToUndo: [[CoreMove]] = moveToUndo.chunks

    while !chunksToUndo.isEmpty {
      var chunkToUndo: [CoreMove] = chunksToUndo.removeLast()
      var chunkUndone: [CoreMove] = []

      while !chunkToUndo.isEmpty {
        let coreMoveToUndo = chunkToUndo.removeLast()

        if !chunksToUndo.isEmpty {
          let previousChunks = Move(chunksToUndo)
          var previousMove1 = Self.findPreviousCoreMove(
            search: coreMoveToUndo.eid,
            searchThrough: [previousChunks]
          )
          if !previousMove1.shouldRevertEntireState {
            if let d = coreMoveToUndo.duration { previousMove1.duration = d }
            if let s = coreMoveToUndo.sound { previousMove1.sound = s }
            chunkUndone.append(previousMove1)
            continue
          }
        }

        var previousMove2 = Self.findPreviousCoreMove(
          search: coreMoveToUndo.eid,
          searchThrough: searchThrough
        )
        if let d = coreMoveToUndo.duration { previousMove2.duration = d }
        if let s = coreMoveToUndo.sound { previousMove2.sound = s }
        chunkUndone.append(previousMove2)
      }
      result.append(chunkUndone)
    }

    return result
  }

  private static func sameMagnetSameSideUpSameIndex(_ lhs: CoreMove, _ rhs: CoreMove?) -> Bool {
    guard let rhs else { return false }
    let allOk =
      lhs.position == rhs.position && lhs.magnet == rhs.magnet && lhs.eid == rhs.eid
      && lhs.modelMeta == rhs.modelMeta && lhs.opacity == rhs.opacity && lhs.scale == rhs.scale
      && lhs.huggerIndex == rhs.huggerIndex
    if !allOk { return false }
    if let o1 = lhs.orientation, let o2 = rhs.orientation {
      return o1.facingSameDirection(as: o2, axis: .y)
    }
    return lhs.orientation == nil && rhs.orientation == nil
  }

  public static func coreMoveUnchanged(
    coreMove: CoreMove,
    movesToCompareWith: [Move],
    initialStateDic: [EID: EntityState]
  ) -> Bool {
    let eid = coreMove.eid
    if eid == EID.none { return false }
    var coreMoveToCompare = coreMove
    var lastPlayedCoreMove = MoveHistoryHelpers.findPreviousCoreMove(
      search: eid,
      searchThrough: movesToCompareWith
    )
    if let initialState = initialStateDic[coreMove.eid] {
      lastPlayedCoreMove.fillInEmptyParts(with: initialState)
      coreMoveToCompare.fillInEmptyParts(with: initialState)
      if lastPlayedCoreMove.magnet != nil, lastPlayedCoreMove.huggerIndex == nil,
        let magnet = initialState.magneticHugs?.hugging, let magnetState = initialStateDic[magnet],
        let magnetHuggedBy = magnetState.magneticHugs?.huggedBy
      {
        lastPlayedCoreMove.huggerIndex = magnetHuggedBy.firstIndex(of: lastPlayedCoreMove.eid)
      }
    } else {
      lastPlayedCoreMove.removePropsNillIn(coreMoveToCompare)
    }
    let result =
      lastPlayedCoreMove == coreMoveToCompare
      || Self.sameMagnetSameSideUpSameIndex(lastPlayedCoreMove, coreMoveToCompare)

    if DEBUGGING_VELLUM {
      print(
        """
        👀==============
          eid  →\(eid)
          coreMove →\(coreMove)
          coreMoveToCompare →\(coreMoveToCompare)
          lastPlayedCoreMove →\(lastPlayedCoreMove)
          sameMagnetSameSideUpSameIndex →\(Self.sameMagnetSameSideUpSameIndex(lastPlayedCoreMove, coreMoveToCompare))
          sameAsLast →\(result)
        ==============👀
        """
      )
    }
    return result
  }
}
