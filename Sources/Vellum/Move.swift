#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
  import simd
#endif

// MARK: - Move extensions

extension v0.Move {
  /// Convenience init from a single CoreMove.
  public init(_ coreMove: v0.CoreMove) { self.chunks = [[coreMove]] }

  /// The first CoreMove in the first chunk that has a valid EID.
  public var firstCore: v0.CoreMove? {
    return chunks.compactMap { $0.first(where: { $0.eid != v0.EID.none }) }.first
  }

  public var firstEid: v0.EID {
    return chunks.compactMap { $0.first(where: { $0.eid != v0.EID.none }) }.first?.eid
      ?? v0.EID.none
  }

  /// The union of every EID this Move relates to: `coreMove.eid` plus `coreMove.magnet`
  /// (when non-nil) plus each EID in `coreMove.huggers ?? []`, across every CoreMove in
  /// every chunk.
  ///
  /// `v0.EID.none` is excluded so placeholder CoreMoves don't pollute matching.
  public var relatedEids: Set<v0.EID> {
    var result: Set<v0.EID> = []
    for chunk in chunks {
      for coreMove in chunk {
        if coreMove.eid != v0.EID.none { result.insert(coreMove.eid) }
        if let magnet = coreMove.magnet, magnet != v0.EID.none { result.insert(magnet) }
        if let huggers = coreMove.huggers {
          for hugger in huggers where hugger != v0.EID.none { result.insert(hugger) }
        }
      }
    }
    return result
  }

  /// Returns a copy of this move with additional side-effect CoreMoves added.
  /// - `during`: merged into chunk 0 (parallel with main move)
  /// - `after`: merged into chunk 1 (sequential after)
  public func withSideEffects(during: [v0.CoreMove], after: [v0.CoreMove]) -> v0.Move {
    var move = self
    if !during.isEmpty {
      var chunk1: [v0.CoreMove] = move.chunks.at(0) ?? []
      chunk1.append(contentsOf: during)
      if move.chunks.count <= 0 { move.chunks.append(chunk1) } else { move.chunks[0] = chunk1 }
    }
    if !after.isEmpty {
      var chunk2: [v0.CoreMove] = move.chunks.at(1) ?? []
      chunk2.append(contentsOf: after)
      if move.chunks.count <= 1 { move.chunks.append(chunk2) } else { move.chunks[1] = chunk2 }
    }
    return move
  }

  /// Returns a copy with the given field omitted from all CoreMoves.
  public func omit(_ key: v0.CoreMove.CodingKeys) -> v0.Move {
    var m = self
    m.chunks = self.chunks.map { chunk in chunk.map { m in m.omit(key) } }
    return m
  }

  // MARK: Validation

  public func validate() -> [String] {
    var errors: [String] = []
    var eidsCovered: Set<v0.EID> = Set()
    for chunk in chunks {
      for coreMove in chunk {
        // Snapshot CoreMoves (huggers only, no position/magnet) use the magnet's EID as a
        // metadata key — they don't represent entity movement and are allowed to share an EID
        // with the entity's own CoreMove in the same chunk.
        let isSnapshot =
          coreMove.huggers != nil && coreMove.position == nil && coreMove.magnet == nil
        if !isSnapshot {
          if eidsCovered.contains(coreMove.eid) {
            errors.append("Found duplicate EID in side effect DURING: \(coreMove.eid)")
          } else if coreMove.eid != v0.EID.none {
            eidsCovered.insert(coreMove.eid)
          }
        }
        errors.append(contentsOf: coreMove.validate())
      }
      if !errors.isEmpty { break }
      eidsCovered.removeAll()
    }
    return errors
  }
}

// MARK: - CoreMove extensions

extension v0.CoreMove {
  /// True when this CoreMove has no target (neither position nor magnet).
  var hasNoTarget: Bool { return magnet == nil && position == nil }

  /// Fills in any nil fields using the entity's saved initial state.
  /// Used to reconstruct a full undo CoreMove from minimal context.
  public mutating func fillInEmptyParts(with initialState: v0.EntityState) {
    if position == nil && magnet == nil {
      if let hugs = initialState.magneticHugs, let magnet = hugs.hugging {
        self.magnet = magnet
      } else {
        self.position = initialState.position
      }
    }
    if orientation == nil {
      self.orientation = initialState.orientation ?? simd_quatf.getNonRotated()
    }
    if scale == nil { self.scale = initialState.scale ?? [1, 1, 1] }
    if opacity == nil { self.opacity = initialState.opacity ?? 1.0 }
    if modelMeta == nil { self.modelMeta = initialState.modelMeta ?? nil }
    if magneticField == nil { self.magneticField = initialState.magneticField ?? nil }
    if huggers == nil { self.huggers = initialState.magneticHugs?.huggedBy }
  }

  /// Returns a copy with non-nil fields from `other` applied on top of self.
  public func merging(_ other: v0.CoreMove) -> v0.CoreMove {
    var result = self
    if other.position != nil { result.position = other.position }
    if other.magnet != nil { result.magnet = other.magnet }
    if other.orientation != nil { result.orientation = other.orientation }
    if other.scale != nil { result.scale = other.scale }
    if other.opacity != nil { result.opacity = other.opacity }
    if other.modelMeta != nil { result.modelMeta = other.modelMeta }
    if other.magneticField != nil { result.magneticField = other.magneticField }
    if other.duration != nil { result.duration = other.duration }
    if other.delay != nil { result.delay = other.delay }
    if other.force != nil { result.force = other.force }
    if other.sound != nil { result.sound = other.sound }
    if other.huggers != nil { result.huggers = other.huggers }
    return result
  }

  /// Nils out any property that is nil in the given reference CoreMove.
  public mutating func removePropsNillIn(_ otherCoreMove: v0.CoreMove) {
    if otherCoreMove.magnet == nil { self.magnet = nil }
    if otherCoreMove.position == nil { self.position = nil }
    if otherCoreMove.orientation == nil { self.orientation = nil }
    if otherCoreMove.scale == nil { self.scale = nil }
    if otherCoreMove.opacity == nil { self.opacity = nil }
    if otherCoreMove.modelMeta == nil { self.modelMeta = nil }
    if otherCoreMove.magneticField == nil { self.magneticField = nil }
    if otherCoreMove.duration == nil { self.duration = nil }
    if otherCoreMove.delay == nil { self.delay = nil }
    if otherCoreMove.force == nil { self.force = nil }
    if otherCoreMove.sound == nil { self.sound = nil }
    if otherCoreMove.huggers == nil { self.huggers = nil }
  }

  /// Returns a copy of this CoreMove with the given field cleared.
  public func omit(_ key: CodingKeys) -> v0.CoreMove {
    var m = self
    switch key {
    case .eid: m.eid = v0.EID.none
    case .magnet: m.magnet = nil
    case .position: m.position = nil
    case .orientation: m.orientation = nil
    case .scale: m.scale = nil
    case .opacity: m.opacity = nil
    case .modelMeta: m.modelMeta = nil
    case .magneticField: m.magneticField = nil
    case .duration: m.duration = nil
    case .delay: m.delay = nil
    case .force: m.force = nil
    case .sound: m.sound = nil
    case .huggers: m.huggers = nil
    }
    return m
  }

  // MARK: Validation

  public func validate() -> [String] {
    var errors: [String] = []
    if position != nil && magnet != nil {
      errors.append("A move can only have a `position` OR `magnet`, not both!")
    }
    if let magnet, eid == magnet { errors.append("Cannot approach one's self in a magnet move!") }
    return errors
  }
}

// MARK: - EntityState ← CoreMove

extension v0.EntityState {
  /// Snapshot-style EntityState carrying the CoreMove's authored target fields.
  /// `magneticHugs.hugging` is derived from `coreMove.magnet` (nil for position-only moves).
  public init(from coreMove: v0.CoreMove) {
    self.init(
      eid: coreMove.eid,
      position: coreMove.position,
      orientation: coreMove.orientation,
      scale: coreMove.scale,
      magneticHugs: coreMove.magnet.map { v0.MagneticHugsComponent(hugging: $0, huggedBy: []) },
      modelMeta: coreMove.modelMeta,
      magneticField: coreMove.magneticField,
      opacity: coreMove.opacity
    )
  }
}

// MARK: - CoreMove: CustomStringConvertible

extension v0.CoreMove: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    var arr = ["CoreMove(eid: \(eid)"]
    if let magnet { arr.append("magnet: \(magnet)") }
    if let position { arr.append("position: \(position)") }
    if let orientation { arr.append("orientation: \(orientation)") }
    if let scale { arr.append("scale: \(scale)") }
    if let opacity { arr.append("opacity: \(opacity)") }
    if let modelMeta { arr.append("modelMeta: \(modelMeta)") }
    if let magneticField { arr.append("magneticField: \(magneticField)") }
    if let duration { arr.append("duration: \(duration)") }
    if let delay { arr.append("delay: \(delay)") }
    if let sound { arr.append("sound: \(sound)") }
    if let huggers { arr.append("huggers: \(huggers)") }
    return arr.join(", ") + ")"
  }
  public var debugDescription: String { return description }
}
