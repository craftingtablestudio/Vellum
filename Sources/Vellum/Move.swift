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
    return chunks.compactMap { $0.first(where: { $0.eid != v0.EID.none }) }.first?.eid ?? v0.EID.none
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
        if eidsCovered.contains(coreMove.eid) {
          errors.append("Found duplicate EID in side effect DURING: \(coreMove.eid)")
        } else if coreMove.eid != v0.EID.none {
          eidsCovered.insert(coreMove.eid)
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
  }

  /// Nils out any property that is nil in the given reference CoreMove.
  public mutating func removePropsNillIn(_ otherCoreMove: v0.CoreMove) {
    if otherCoreMove.magnet == nil { self.magnet = nil }
    if otherCoreMove.position == nil { self.position = nil }
    if otherCoreMove.orientation == nil { self.orientation = nil }
    if otherCoreMove.scale == nil { self.scale = nil }
    if otherCoreMove.opacity == nil { self.opacity = nil }
    if otherCoreMove.modelMeta == nil { self.modelMeta = nil }
    if otherCoreMove.duration == nil { self.duration = nil }
    if otherCoreMove.sound == nil { self.sound = nil }
    if otherCoreMove.huggerIndex == nil { self.huggerIndex = nil }
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
    case .duration: m.duration = nil
    case .sound: m.sound = nil
    case .huggerIndex: m.huggerIndex = nil
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
    if let duration { arr.append("duration: \(duration)") }
    if let sound { arr.append("sound: \(sound)") }
    if let huggerIndex { arr.append("huggerIndex: \(huggerIndex)") }
    return arr.join(", ") + ")"
  }
  public var debugDescription: String { return description }
}
