#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
  import simd
#endif

public enum MoveHistoryHelpers {
  /// Finds the previous `CoreMove` for an `EID` by searching through the given moves in reverse.
  ///
  /// Collects the last known position/magnet, orientation, scale, opacity, modelMeta, and
  /// huggers — combining partial results if needed. After exhausting all history, fills
  /// remaining nil fields from `presetDic`. For clones not in `presetDic` with no target found,
  /// returns a CoreMove targeting `.magnet(.originalCloner)`.
  ///
  /// For magnet EIDs that have a `huggers` snapshot in history, the snapshot is collected and
  /// returned as a `huggers` field on the CoreMove.
  public static func findPreviousCoreMove(
    search targetEid: v0.EID,
    searchThrough: [v0.Move],
    presetDic: [v0.EID: v0.EntityState] = [:]
  ) -> v0.CoreMove {
    struct FoundMoves {
      let targetEid: v0.EID
      init(for targetEid: v0.EID) { self.targetEid = targetEid }

      var position: SIMD3<Float>? = nil
      var magnet: v0.EID? = nil
      var orientation: simd_quatf? = nil
      var scale: SIMD3<Float>? = nil
      var opacity: Float? = nil
      var modelMeta: v0.ModelMetaComponent? = nil
      var magneticField: v0.MagneticFieldMeta? = nil
      var huggers: [v0.EID]? = nil
      /// Tracks the coordinate space of the found position/orientation. Set from the same
      /// CoreMove that provided the position (or magnet), so the values and their space stay paired.
      var relativeTo: v0.EID? = nil

      mutating func updateMatches(coreMove: v0.CoreMove) {
        if coreMove.eid != targetEid { return }
        if self.position == nil && self.magnet == nil {
          self.position = coreMove.position
          self.magnet = coreMove.magnet
          // Capture relativeTo from the same move that provided the spatial target,
          // so position values and their coordinate space stay paired.
          self.relativeTo = coreMove.relativeTo
        }
        if self.orientation == nil { self.orientation = coreMove.orientation }
        if self.scale == nil { self.scale = coreMove.scale }
        if self.opacity == nil { self.opacity = coreMove.opacity }
        if self.modelMeta == nil { self.modelMeta = coreMove.modelMeta }
        if self.magneticField == nil { self.magneticField = coreMove.magneticField }
        if self.huggers == nil { self.huggers = coreMove.huggers }
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

    // Resolve remaining nil fields from presetDic
    if let preset = presetDic[targetEid] {
      if found.position == nil && found.magnet == nil {
        if let hugs = preset.magneticHugs, let magnet = hugs.hugging {
          found.magnet = magnet
          // Magnet moves are resolved in root-space by the animation pipeline — the stacking
          // position is computed from the magnet's root-space position, not from a stored coordinate.
          // Explicitly nil so the relativeTo from the preset (which may be .parent for entities
          // that were nested before reparenting) doesn't leak into the returned CoreMove.
          found.relativeTo = nil
        } else {
          found.position = preset.position
          // Keep position and relativeTo paired — the preset position is in whatever
          // coordinate space the preset was captured in (e.g. .parent for nested entities).
          found.relativeTo = preset.relativeTo
        }
      }
      if found.orientation == nil { found.orientation = preset.orientation }
      if found.scale == nil { found.scale = preset.scale }
      if found.opacity == nil { found.opacity = preset.opacity }
      if found.modelMeta == nil { found.modelMeta = preset.modelMeta }
      if found.magneticField == nil { found.magneticField = preset.magneticField }
    }

    let target: v0.CoreMoveTarget =
      if let magnet = found.magnet {
        .magnet(magnet)
      } else if let position = found.position { .position(position) } else if targetEid.isClone {
        .magnet(.originalCloner)
      } else { .unset }

    return v0.CoreMove(
      eid: targetEid,
      target: target,
      orientation: found.orientation,
      scale: found.scale,
      opacity: found.opacity,
      modelMeta: found.modelMeta,
      magneticField: found.magneticField,
      huggers: found.huggers,
      relativeTo: found.relativeTo
    )
  }

  /// Converts a `Move` into its reverse CoreMoves by looking up each entity's previous state.
  ///
  /// Returns `[[CoreMove]]` — a chunked array matching the undo direction.
  static func moveToPreviousCoreMoves(
    _ moveToUndo: v0.Move,
    searchThrough: [v0.Move],
    presetDic: [v0.EID: v0.EntityState] = [:]
  ) -> [[v0.CoreMove]] {
    var result: [[v0.CoreMove]] = []
    var chunksToUndo: [[v0.CoreMove]] = moveToUndo.chunks

    while !chunksToUndo.isEmpty {
      var chunkToUndo: [v0.CoreMove] = chunksToUndo.removeLast()
      var chunkUndone: [v0.CoreMove] = []

      while !chunkToUndo.isEmpty {
        let coreMoveToUndo = chunkToUndo.removeLast()

        // Pure snapshot CoreMoves (huggers ordering, no position/magnet) are metadata about
        // a magnet's huggedBy ordering. They are not entity movements and should not be undone
        // as such — the correct huggers snapshot is derived from the PREVIOUS state in history.
        if coreMoveToUndo.huggers != nil && coreMoveToUndo.magnet == nil && coreMoveToUndo.position == nil {
          // Find this magnet's previous huggers snapshot from history
          let previousSnapshot = Self.findPreviousCoreMove(
            search: coreMoveToUndo.eid,
            searchThrough: searchThrough,
            presetDic: presetDic
          )
          if let prevHuggers = previousSnapshot.huggers {
            chunkUndone.append(v0.CoreMove(eid: coreMoveToUndo.eid, huggers: prevHuggers))
          } else {
            // Entity had no huggers before this move — emit empty snapshot to clear them
            chunkUndone.append(v0.CoreMove(eid: coreMoveToUndo.eid, huggers: []))
          }
          continue
        }

        if !chunksToUndo.isEmpty {
          let appearsInEarlierChunks = chunksToUndo.contains {
            $0.contains { $0.eid == coreMoveToUndo.eid }
          }
          if appearsInEarlierChunks {
            let previousChunks = v0.Move(chunksToUndo)
            var previousMove1 = Self.findPreviousCoreMove(
              search: coreMoveToUndo.eid,
              searchThrough: [previousChunks]
            )
            if !previousMove1.hasNoTarget {
              if let d = coreMoveToUndo.duration { previousMove1.duration = d }
              if let s = coreMoveToUndo.sound { previousMove1.sound = s }
              chunkUndone.append(previousMove1)
              continue
            }
          }
        }

        var previousMove2 = Self.findPreviousCoreMove(
          search: coreMoveToUndo.eid,
          searchThrough: searchThrough,
          presetDic: presetDic
        )
        if let d = coreMoveToUndo.duration { previousMove2.duration = d }
        if let s = coreMoveToUndo.sound { previousMove2.sound = s }
        chunkUndone.append(previousMove2)
      }
      result.append(chunkUndone)
    }

    return result
  }

  private static func sameMagnetSameSideUp(_ lhs: v0.CoreMove, _ rhs: v0.CoreMove?) -> Bool {
    guard let rhs else { return false }
    let allOk =
      lhs.position == rhs.position && lhs.magnet == rhs.magnet && lhs.eid == rhs.eid
      && lhs.modelMeta == rhs.modelMeta && lhs.magneticField == rhs.magneticField
      && lhs.opacity == rhs.opacity && lhs.scale == rhs.scale
      && lhs.huggers == rhs.huggers
    if !allOk { return false }
    if let o1 = lhs.orientation, let o2 = rhs.orientation {
      return o1.facingSameDirection(as: o2, axis: .y)
    }
    return lhs.orientation == nil && rhs.orientation == nil
  }

  static func coreMoveUnchanged(
    coreMove: v0.CoreMove,
    movesToCompareWith: [v0.Move],
    initialStateDic: [v0.EID: v0.EntityState]
  ) -> Bool {
    let eid = coreMove.eid
    if eid == v0.EID.none { return false }
    var coreMoveToCompare = coreMove
    var lastPlayedCoreMove = MoveHistoryHelpers.findPreviousCoreMove(
      search: eid,
      searchThrough: movesToCompareWith
    )
    if let initialState = initialStateDic[coreMove.eid] {
      lastPlayedCoreMove.fillInEmptyParts(with: initialState)
      coreMoveToCompare.fillInEmptyParts(with: initialState)
    } else {
      lastPlayedCoreMove.removePropsNillIn(coreMoveToCompare)
    }
    let result =
      lastPlayedCoreMove == coreMoveToCompare
      || Self.sameMagnetSameSideUp(lastPlayedCoreMove, coreMoveToCompare)

    if DEBUGGING_VELLUM {
      print(
        """
        👀==============
          eid  →\(eid)
          coreMove →\(coreMove)
          coreMoveToCompare →\(coreMoveToCompare)
          lastPlayedCoreMove →\(lastPlayedCoreMove)
          sameMagnetSameSideUp →\(Self.sameMagnetSameSideUp(lastPlayedCoreMove, coreMoveToCompare))
          sameAsLast →\(result)
        ==============👀
        """
      )
    }
    return result
  }
}
