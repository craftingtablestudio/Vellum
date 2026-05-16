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
      if found.huggers == nil { found.huggers = preset.magneticHugs?.huggedBy }
    }

    let target: v0.CoreMoveTarget =
      if let magnet = found.magnet { .magnet(magnet) } else if let position = found.position {
        .position(position)
      } else if targetEid.isClone { .magnet(.originalCloner) } else { .unset }

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
  /// For each CoreMove, the entity's previous state is found by searching earlier chunks of the
  /// same move first (for multi-part moves like captures), then falling back to history/presets.
  /// The original move's animation timing and sound are preserved on the reverse.
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
      let chunkToUndo = chunksToUndo.removeLast()
      var chunkUndone: [v0.CoreMove] = []

      // Pre-scan: collect EIDs that have non-snapshot (movement) CoreMoves in this chunk.
      // When an EID has both a pure snapshot and a movement CoreMove, the snapshot revert
      // is redundant — buildHuggersSnapshots in the animation pipeline will recompute the
      // hugger ordering from the movement data. Skipping the snapshot avoids producing two
      // CoreMoves with the same EID, which causes magnetWillBeAtPosition lookups to find
      // the snapshot (no position) instead of the movement CoreMove.
      let eidsWithMovement = Set(chunkToUndo.filter { cm in
        cm.position != nil || cm.magnet != nil || cm.orientation != nil
          || cm.scale != nil || cm.opacity != nil
          || cm.modelMeta != nil || cm.magneticField != nil
      }.map { $0.eid })

      for coreMoveToUndo in chunkToUndo.reversed() {
        let isPureSnapshot =
          coreMoveToUndo.huggers != nil && coreMoveToUndo.magnet == nil
          && coreMoveToUndo.position == nil && coreMoveToUndo.orientation == nil
          && coreMoveToUndo.scale == nil && coreMoveToUndo.opacity == nil
          && coreMoveToUndo.modelMeta == nil && coreMoveToUndo.magneticField == nil
        if isPureSnapshot {
          // Skip snapshot reverts for EIDs that also have a movement CoreMove — the
          // animation pipeline's buildHuggersSnapshots will recompute the ordering.
          if eidsWithMovement.contains(coreMoveToUndo.eid) { continue }
          let previousSnapshot = Self.findPreviousCoreMove(
            search: coreMoveToUndo.eid,
            searchThrough: searchThrough,
            presetDic: presetDic
          )
          chunkUndone.append(
            v0.CoreMove(eid: coreMoveToUndo.eid, huggers: previousSnapshot.huggers ?? []))
          continue
        }

        // When the same entity appears in an earlier chunk of this move (e.g. a capture
        // where the attacker is placed in chunk 0, then re-placed in chunk 1), that earlier
        // chunk provides the target. Otherwise falls back to history/presets.
        var prev =
          Self.findInEarlierChunks(eid: coreMoveToUndo.eid, chunks: chunksToUndo)
          ?? Self.findPreviousCoreMove(
            search: coreMoveToUndo.eid,
            searchThrough: searchThrough,
            presetDic: presetDic
          )
        if let d = coreMoveToUndo.duration { prev.duration = d }
        if let s = coreMoveToUndo.sound { prev.sound = s }
        // EntityState stores opacity nil when 1.0, but CoreMove nil means "no change".
        // When the forward move explicitly set opacity and history/preset returned nil,
        // the entity was at default 1.0 — make that explicit so undo restores visibility.
        if coreMoveToUndo.opacity != nil && prev.opacity == nil { prev.opacity = 1.0 }
        chunkUndone.append(prev)
      }
      result.append(chunkUndone)
    }

    return result
  }

  /// Searches earlier (not yet processed) chunks for a movement CoreMove with the given EID.
  /// Returns `nil` if the entity isn't found or only appears as metadata (no movement target).
  private static func findInEarlierChunks(eid: v0.EID, chunks: [[v0.CoreMove]]) -> v0.CoreMove? {
    guard !chunks.isEmpty else { return nil }
    guard chunks.contains(where: { $0.contains { $0.eid == eid } }) else { return nil }
    let found = Self.findPreviousCoreMove(search: eid, searchThrough: [v0.Move(chunks)])
    return found.hasNoTarget ? nil : found
  }

  private static func sameMagnetSameSideUp(_ lhs: v0.CoreMove, _ rhs: v0.CoreMove?) -> Bool {
    guard let rhs else { return false }
    let allOk =
      lhs.position == rhs.position && lhs.magnet == rhs.magnet && lhs.eid == rhs.eid
      && lhs.modelMeta == rhs.modelMeta && lhs.magneticField == rhs.magneticField
      && lhs.opacity == rhs.opacity && lhs.scale == rhs.scale && lhs.huggers == rhs.huggers
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
