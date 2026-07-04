#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
  import simd
#endif

/// A clone's runtime baseline: the cloner it returns to when history holds no earlier state for
/// it, and the orientation it spawned with. Not persisted — the caller (Magisterium) derives it
/// from live cloner state and passes it alongside `presetDic`. What happens on arrival (e.g. a
/// `.destroy` magnet recycling the clone) is the magnet's own property, not Vellum's concern.
public struct ClonePreset: Sendable, Equatable {
  public let originalClonerEid: v0.EID
  public let initialOrientation: simd_quatf?

  public init(originalClonerEid: v0.EID, initialOrientation: simd_quatf? = nil) {
    self.originalClonerEid = originalClonerEid
    self.initialOrientation = initialOrientation
  }
}

public enum MoveHistoryHelpers {
  /// Finds the previous `CoreMove` for an `EID` by searching through the given moves in reverse.
  ///
  /// Collects the last known position/magnet, orientation, scale, opacity, modelMeta, and
  /// huggers — combining partial results if needed. After exhausting all history, fills the
  /// remaining nil fields from the entity's baseline:
  /// - a preset entity → its own `presetDic` entry
  /// - a ClonableGroup child → POSE fields from its template child's preset entry
  ///   (`groupCloneTemplateEID`) — its authored resting spot inside the container
  /// - a standalone clone → its `clonePresetDic` entry: target its original cloner, oriented as
  ///   it spawned. A clone with no baseline anywhere fades out in place (`opacity: 0`).
  ///
  /// The baselines run in that order and each fills only still-nil fields, so an earlier source
  /// that supplied a field wins over a later one.
  ///
  /// For magnet EIDs that have a `huggers` snapshot in history, the snapshot is collected and
  /// returned as a `huggers` field on the CoreMove.
  public static func findPreviousCoreMove(
    search targetEid: v0.EID,
    searchThrough: [v0.Move],
    presetDic: [v0.EID: v0.EntityState] = [:],
    clonePresetDic: [String: ClonePreset] = [:]
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
      var magneticField: v0.MagneticFieldPartial? = nil
      var huggers: [v0.EID]? = nil

      mutating func updateMatches(coreMove: v0.CoreMove) {
        if coreMove.eid != targetEid { return }
        if self.position == nil && self.magnet == nil {
          self.position = coreMove.position
          self.magnet = coreMove.magnet
        }
        if self.orientation == nil { self.orientation = coreMove.orientation }
        if self.scale == nil { self.scale = coreMove.scale }
        if self.opacity == nil { self.opacity = coreMove.opacity }
        if self.modelMeta == nil { self.modelMeta = coreMove.modelMeta }
        if let incoming = coreMove.magneticField {
          if self.magneticField == nil {
            self.magneticField = incoming
          } else {
            self.magneticField!.fillInEmptyParts(from: incoming)
          }
        }
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
        } else {
          // The preset position is in whatever coordinate space the entity lives in (parent-local
          // for nested entities, root-space otherwise). That space is no longer stored — it's
          // derived live from the entity's `ParentLocalComponent` marker at apply time.
          found.position = preset.position
        }
      }
      if found.orientation == nil { found.orientation = preset.orientation }
      if found.scale == nil { found.scale = preset.scale }
      if found.opacity == nil { found.opacity = preset.opacity }
      if found.modelMeta == nil { found.modelMeta = preset.modelMeta }
      if let presetField = preset.magneticField {
        if found.magneticField == nil {
          found.magneticField = presetField
        } else {
          found.magneticField!.fillInEmptyParts(from: presetField)
        }
      }
      if found.huggers == nil { found.huggers = preset.magneticHugs?.huggedBy }
    }

    // A ClonableGroup child is keyed `.clone` but its authored resting pose lives on its TEMPLATE
    // child's preset entry (`.other`, same full name). Fill POSE fields only: templates are
    // invisible, so opacity/modelMeta must not be inherited. A child that resolved to a real
    // magnet keeps it — its pose is owned by that magnet.
    if let templateEid = targetEid.groupCloneTemplateEID, let template = presetDic[templateEid] {
      if found.position == nil && found.magnet == nil { found.position = template.position }
      if found.orientation == nil { found.orientation = template.orientation }
      if found.scale == nil { found.scale = template.scale }
    }

    // A standalone clone's baseline is its cloner: with no earlier target anywhere it returns to
    // its original cloner, and an orientation it never authored is the one it spawned with —
    // mirroring how the preset/template fills above treat their baselines.
    if targetEid.isClone, let clonePreset = clonePresetDic[targetEid.name] {
      if found.position == nil && found.magnet == nil {
        found.magnet = clonePreset.originalClonerEid
      }
      if found.orientation == nil { found.orientation = clonePreset.initialOrientation }
    }

    // A clone COMPLETELY unknown — no history, no preset/template entry, no cloner — has nowhere
    // to return to: fade it out in place. A clone that IS known but positionless (e.g. a spawned
    // container whose preset entry deliberately drops its position) simply rests where it is.
    let knownToPresets =
      presetDic[targetEid] != nil
      || targetEid.groupCloneTemplateEID.flatMap { presetDic[$0] } != nil
    if targetEid.isClone && found.position == nil && found.magnet == nil && !knownToPresets {
      return v0.CoreMove(eid: targetEid, opacity: 0, huggers: found.huggers)
    }

    let target: v0.CoreMoveTarget =
      if let magnet = found.magnet { .magnet(magnet) } else if let position = found.position {
        .position(position)
      } else { .unset }

    return v0.CoreMove(
      eid: targetEid,
      target: target,
      orientation: found.orientation,
      scale: found.scale,
      opacity: found.opacity,
      modelMeta: found.modelMeta,
      magneticField: found.magneticField,
      huggers: found.huggers
    )
  }

  /// Converts a `Move` into its reverse CoreMoves by looking up each entity's previous state.
  ///
  /// For each CoreMove, the entity's previous state is found by searching earlier chunks of the
  /// same move first (for multi-part moves like captures), then falling back to history/variants.
  /// The original move's animation timing and sound are preserved on the reverse.
  ///
  /// Returns `[[CoreMove]]` — a chunked array matching the undo direction.
  static func moveToPreviousCoreMoves(
    _ moveToUndo: v0.Move,
    searchThrough: [v0.Move],
    presetDic: [v0.EID: v0.EntityState] = [:],
    clonePresetDic: [String: ClonePreset] = [:]
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
      let eidsWithMovement = Set(
        chunkToUndo.filter { cm in
          cm.position != nil || cm.magnet != nil || cm.orientation != nil || cm.scale != nil
            || cm.opacity != nil || cm.modelMeta != nil || cm.magneticField != nil
        }
        .map { $0.eid }
      )

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
            presetDic: presetDic,
            clonePresetDic: clonePresetDic
          )
          chunkUndone.append(
            v0.CoreMove(eid: coreMoveToUndo.eid, huggers: previousSnapshot.huggers ?? [])
          )
          continue
        }

        // When the same entity appears in an earlier chunk of this move (e.g. a capture
        // where the attacker is placed in chunk 0, then re-placed in chunk 1), that earlier
        // chunk provides the target. Otherwise falls back to history/variants.
        var prev =
          Self.findInEarlierChunks(eid: coreMoveToUndo.eid, chunks: chunksToUndo)
          ?? Self.findPreviousCoreMove(
            search: coreMoveToUndo.eid,
            searchThrough: searchThrough,
            presetDic: presetDic,
            clonePresetDic: clonePresetDic
          )
        if let d = coreMoveToUndo.duration { prev.duration = d }
        if let s = coreMoveToUndo.sound { prev.sound = s }
        // EntityState stores opacity nil when 1.0, but CoreMove nil means "no change".
        // When the forward move explicitly set opacity and history/preset returned nil,
        // the entity was at default 1.0 — make that explicit so undo restores visibility.
        if coreMoveToUndo.opacity != nil && prev.opacity == nil { prev.opacity = 1.0 }
        // Same for magneticField: if the forward move changed a field but history/preset
        // had no previous value for it, fall back to the MagneticFieldComponent default.
        if let changed = coreMoveToUndo.magneticField {
          let d = v0.MagneticFieldPartial.componentDefaults
          var f = prev.magneticField ?? v0.MagneticFieldPartial()
          if changed.hugEffect != nil && f.hugEffect == nil { f.hugEffect = d.hugEffect }
          if changed.fieldRadius != nil && f.fieldRadius == nil { f.fieldRadius = d.fieldRadius }
          if changed.stackOffset != nil && f.stackOffset == nil { f.stackOffset = d.stackOffset }
          if changed.collisionSound != nil && f.collisionSound == nil {
            f.collisionSound = d.collisionSound
          }
          if changed.entityLimit != nil && f.entityLimit == nil { f.entityLimit = d.entityLimit }
          if changed.forwardTo != nil && f.forwardTo == nil { f.forwardTo = d.forwardTo }
          if changed.overflowTo != nil && f.overflowTo == nil { f.overflowTo = d.overflowTo }
          if changed.yAlignmentTolerance != nil && f.yAlignmentTolerance == nil {
            f.yAlignmentTolerance = d.yAlignmentTolerance
          }
          prev.magneticField = f
        }
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
