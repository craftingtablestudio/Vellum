import Foundation
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
  import simd
#endif

public enum v0 {

  // MARK: - EID

  public enum EIDCustomDecodingError: Error { case BadClone, BadOther }

  /// Entity Identifier — the stable, serialisable identity of an entity across moves and saves.
  ///
  /// - `.other(name)`: a static, unique entity. Name alone is sufficient because only one instance
  ///   ever exists. Should have an entry in `initialStateDic` so its state can be restored on undo.
  /// - `.clone(name, cloneId)`: a dynamically created entity minted by an `EntityCloner`. Multiple
  ///   copies of the same template can exist simultaneously (e.g. black stones on a Go board), so a
  ///   UUID distinguishes instances. `name` is the template; `cloneId` is the specific instance.
  /// - `.clonableGroupChild(group, child, cloneId)`: a child of a `ClonableGroupComponent` container.
  ///   It rides its container's spawn (sharing the container's `cloneId`) and, on undo, rests at its
  ///   template child's authored pose rather than returning to a cloner. `name` reconstructs the
  ///   scene-side `"group__groupclone__child"` convention so entity lookups keep working.
  /// - `.none`: absence of an entity.
  public enum EID: Codable, Equatable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
  {
    case clone(name: String, cloneId: UUID)
    case clonableGroupChild(group: String, child: String, cloneId: UUID)
    case other(name: String)
    case none

    // ╔═══════════════════════════╗
    // ║ CUSTOM STRING CONVERTABLE ║
    // ╚═══════════════════════════╝

    public var description: String {
      switch self {
      case .clone(let name, let uuid):
        let shortUUID = "\(uuid.uuidString.prefix(3))...\(uuid.uuidString.suffix(3))"
        return "EID.clone(\(name):\(shortUUID))"
      case .clonableGroupChild(let group, let child, let uuid):
        let shortUUID = "\(uuid.uuidString.prefix(3))...\(uuid.uuidString.suffix(3))"
        return "EID.clonableGroupChild(\(group)\(GROUP_CLONE_DIVIDER)\(child):\(shortUUID))"
      case .other(let name): return "EID.other(\(name))"
      case .none: return "EID.none"
      }
    }

    public var debugDescription: String { return self.description }

    // ╔═════════╗
    // ║ CODABLE ║
    // ╚═════════╝

    public var toStringValue: String {
      switch self {
      case .clone(let name, let uuid): return "EID.clone(\(name):\(uuid))"
      case .clonableGroupChild(let group, let child, let uuid):
        return "EID.clonableGroupChild(\(group)\(GROUP_CLONE_DIVIDER)\(child):\(uuid))"
      case .other(let name): return "EID.other(\(name))"
      case .none: return "EID.none"
      }
    }

    public static func fromStringValue(_ stringRepresentation: String) throws -> EID {
      if stringRepresentation == "EID.none" { return EID.none }
      if stringRepresentation.starts(with: "EID.clonableGroupChild(") {
        let trimmed = String(
          stringRepresentation.dropFirst("EID.clonableGroupChild(".count).dropLast()
        )
        let components = trimmed.split(":")
        guard components.count == 2, let fullName = components.at(0),
          let cloneIdString = components.at(1), let cloneId = UUID(uuidString: cloneIdString)
        else { throw EIDCustomDecodingError.BadClone }
        let parts = fullName.components(separatedBy: GROUP_CLONE_DIVIDER)
        guard parts.count == 2, let group = parts.first, let child = parts.last else {
          throw EIDCustomDecodingError.BadClone
        }
        return .clonableGroupChild(group: group, child: child, cloneId: cloneId)
      }
      if stringRepresentation.starts(with: "EID.clone(") {
        let trimmed = String(stringRepresentation.dropFirst("EID.clone(".count).dropLast())
        let components = trimmed.split(":")
        guard components.count == 2, let name = components.at(0),
          let cloneIdString = components.at(1), let cloneId = UUID(uuidString: cloneIdString)
        else { throw EIDCustomDecodingError.BadClone }
        return .clone(name: name, cloneId: cloneId)
      } else if stringRepresentation.starts(with: "EID.other(") {
        let name = String(stringRepresentation.dropFirst("EID.other(".count).dropLast())
        return .other(name: name)
      } else {
        throw EIDCustomDecodingError.BadOther
      }
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(self.toStringValue)
    }

    private enum CodingKeys: String, CodingKey { case kind, name, cloneId }
    private enum Kind: String, Codable { case clone, other }

    public init(from decoder: Decoder) throws {
      do {
        let container = try decoder.singleValueContainer()
        let stringRepresentation = try container.decode(String.self)
        do { self = try EID.fromStringValue(stringRepresentation) } catch {
          switch error {
          case EIDCustomDecodingError.BadClone:
            throw DecodingError.dataCorruptedError(
              in: container,
              debugDescription: "Invalid format for clone"
            )
          case EIDCustomDecodingError.BadOther:
            throw DecodingError.dataCorruptedError(
              in: container,
              debugDescription: "Unknown prefix for EID"
            )
          default: throw error
          }
        }
      } catch {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .clone:
          let name = try container.decode(String.self, forKey: .name)
          let cloneId = try container.decode(UUID.self, forKey: .cloneId)
          self = .clone(name: name, cloneId: cloneId)
        case .other:
          let name = try container.decode(String.self, forKey: .name)
          self = .other(name: name)
        }
      }
    }
  }

  // MARK: - SoundGroup

  public enum SoundGroup: String, Codable, CaseIterable, Sendable {
    case none
    case drop
    case grab
    case pickup
    case place
    case stow
    case shuffle
  }

  // MARK: - PhysicsBodyMode

  public enum PhysicsBodyMode: String, Codable, Sendable, Equatable {
    case `static` = "static"
    case kinematic = "kinematic"
    case dynamic = "dynamic"
  }

  // MARK: - MagneticHugsComponent

  public struct MagneticHugsComponent: Codable, Sendable, Equatable {
    public var hugging: EID?
    public var huggedBy: [EID]

    public init() {
      self.hugging = nil
      self.huggedBy = []
    }

    public init(hugging: EID?, huggedBy: [EID]) {
      self.hugging = hugging
      self.huggedBy = huggedBy
    }
  }

  // MARK: - ModelMetaComponent

  /// Stores the logical identity and texture overrides for an entity whose visual appearance can
  /// change at runtime (e.g. a playing card that shows a specific face).
  public struct ModelMetaComponent: Codable, Sendable, Equatable {
    /// The logical name of this model variant (e.g. `"Ace of Spades"`). Identifies what the
    /// entity conceptually *is*, independent of which texture is currently applied.
    public var name: String
    /// Maps entity-relative scene paths to locally cached texture filenames.
    /// The key is a slash-separated path into the entity's child hierarchy; the value is a
    /// filename (e.g. `"AS.png"`) that the caller resolves to a file on disk — typically
    /// downloaded from a remote source and cached locally before being applied.
    ///
    /// Example:
    /// ```swift
    /// ModelMetaComponent(
    ///   name: "Ace of Spades",
    ///   pathTextureDic: ["Front/Front": "AS.png"]
    /// )
    /// ```
    public var pathTextureDic: [String: String]

    public init(name: String, pathTextureDic: [String: String]) {
      self.name = name
      self.pathTextureDic = pathTextureDic
    }
  }

  // MARK: - HugEffect

  /// Determines the physics applied after an entity starts sticking to a magnet.
  public enum HugEffect: String, Codable, CaseIterable, Sendable {
    case none
    case tower
    case fan
    case pile
    case destroy
  }

  // MARK: - FaceDirectionAlignment

  public enum FaceDirectionAlignment: String, Codable, CaseIterable, Sendable {
    case none
    case magnet
    case firstHugger
  }

  public enum GrabHuggers: String, Codable, CaseIterable, Sendable {
    case birdView
    case individually
    case bringUpperSiblings
    case lastOrAll
  }

  // MARK: - MagneticFieldPartial

  /// Serialisable snapshot of a magnet's field configuration, used to record field
  /// changes in moves, sync them over SharePlay, persist them in save data, and
  /// replay them during undo/redo.
  ///
  /// Platform-agnostic representation of `MagneticFieldComponent` properties that
  /// can change at runtime via a `CoreMove`. All fields are optional — `nil` means
  /// no override (the entity keeps its current value for that field).
  public struct MagneticFieldPartial: Codable, Sendable, Equatable {
    public var hugEffect: HugEffect?
    public var fieldRadius: Float?
    /// An offset to apply to entities being stacked on this magnet.
    public var stackOffset: SIMD3<Float>?
    public var collisionSound: SoundGroup?
    public var entityLimit: Int?
    public var forwardTo: String?
    public var overflowTo: String?
    public var yAlignmentTolerance: Float?
    public var faceDirectionAlignment: FaceDirectionAlignment?
    public var grabHuggers: GrabHuggers?

    public init(
      hugEffect: HugEffect? = nil,
      fieldRadius: Float? = nil,
      stackOffset: SIMD3<Float>? = nil,
      collisionSound: SoundGroup? = nil,
      entityLimit: Int? = nil,
      forwardTo: String? = nil,
      overflowTo: String? = nil,
      yAlignmentTolerance: Float? = nil,
      faceDirectionAlignment: FaceDirectionAlignment? = nil,
      grabHuggers: GrabHuggers? = nil
    ) {
      self.hugEffect = hugEffect
      self.fieldRadius = fieldRadius
      self.stackOffset = stackOffset
      self.collisionSound = collisionSound
      self.entityLimit = entityLimit
      self.forwardTo = forwardTo
      self.overflowTo = overflowTo
      self.yAlignmentTolerance = yAlignmentTolerance
      self.faceDirectionAlignment = faceDirectionAlignment
      self.grabHuggers = grabHuggers
    }

    // ╔═════════╗
    // ║ CODABLE ║
    // ╚═════════╝

    private enum CodingKeys: String, CodingKey {
      case hugEffect, fieldRadius, stackOffset, collisionSound, entityLimit, forwardTo, overflowTo
      case yAlignmentTolerance, faceDirectionAlignment, grabHuggers
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.hugEffect = try container.decodeIfPresent(HugEffect.self, forKey: .hugEffect)
      self.fieldRadius = try container.decodeIfPresent(Float.self, forKey: .fieldRadius)
      self.stackOffset = try SIMD3FloatCodable.decodeIfPresent(
        from: container,
        forKey: .stackOffset
      )
      self.collisionSound = try container.decodeIfPresent(SoundGroup.self, forKey: .collisionSound)
      self.entityLimit = try container.decodeIfPresent(Int.self, forKey: .entityLimit)
      self.forwardTo = try container.decodeIfPresent(String.self, forKey: .forwardTo)
      self.overflowTo = try container.decodeIfPresent(String.self, forKey: .overflowTo)
      self.yAlignmentTolerance = try container.decodeIfPresent(
        Float.self,
        forKey: .yAlignmentTolerance
      )
      self.faceDirectionAlignment = try container.decodeIfPresent(
        FaceDirectionAlignment.self,
        forKey: .faceDirectionAlignment
      )
      self.grabHuggers = try container.decodeIfPresent(GrabHuggers.self, forKey: .grabHuggers)
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encodeIfPresent(self.hugEffect, forKey: .hugEffect)
      try container.encodeIfPresent(self.fieldRadius, forKey: .fieldRadius)
      try SIMD3FloatCodable.encodeIfPresent(self.stackOffset, to: &container, forKey: .stackOffset)
      try container.encodeIfPresent(self.collisionSound, forKey: .collisionSound)
      try container.encodeIfPresent(self.entityLimit, forKey: .entityLimit)
      try container.encodeIfPresent(self.forwardTo, forKey: .forwardTo)
      try container.encodeIfPresent(self.overflowTo, forKey: .overflowTo)
      try container.encodeIfPresent(self.yAlignmentTolerance, forKey: .yAlignmentTolerance)
      try container.encodeIfPresent(self.faceDirectionAlignment, forKey: .faceDirectionAlignment)
      try container.encodeIfPresent(self.grabHuggers, forKey: .grabHuggers)
    }

    /// Fills in any nil fields from `other`, preserving any already-set fields.
    public mutating func fillInEmptyParts(from other: MagneticFieldPartial) {
      if self.hugEffect == nil { self.hugEffect = other.hugEffect }
      if self.fieldRadius == nil { self.fieldRadius = other.fieldRadius }
      if self.stackOffset == nil { self.stackOffset = other.stackOffset }
      if self.collisionSound == nil { self.collisionSound = other.collisionSound }
      if self.entityLimit == nil { self.entityLimit = other.entityLimit }
      if self.forwardTo == nil { self.forwardTo = other.forwardTo }
      if self.overflowTo == nil { self.overflowTo = other.overflowTo }
      if self.yAlignmentTolerance == nil { self.yAlignmentTolerance = other.yAlignmentTolerance }
      if self.faceDirectionAlignment == nil {
        self.faceDirectionAlignment = other.faceDirectionAlignment
      }
      if self.grabHuggers == nil { self.grabHuggers = other.grabHuggers }
    }

    /// MagneticFieldComponent default values.
    public static let componentDefaults = MagneticFieldPartial(
      hugEffect: HugEffect.none,
      fieldRadius: 0.08,
      stackOffset: .zero,
      collisionSound: SoundGroup.none,
      entityLimit: -1,
      forwardTo: "",
      overflowTo: "",
      yAlignmentTolerance: 360,
      faceDirectionAlignment: FaceDirectionAlignment.none,
      grabHuggers: GrabHuggers.individually
    )
  }

  // MARK: - EntityState

  /// Represents the saved state of one entity in the scene.
  public struct EntityState: Codable, Sendable, Equatable {
    public let eid: EID
    /// Position is saved only for dynamic/draggable entities; nil otherwise.
    public var position: SIMD3<Float>?
    /// Orientation is saved only when non-default; nil otherwise.
    public var orientation: simd_quatf?
    /// Scale is saved only when not [1, 1, 1]; nil otherwise.
    public var scale: SIMD3<Float>?
    public var physicsMode: PhysicsBodyMode?
    public var magneticHugs: MagneticHugsComponent?
    public var modelMeta: ModelMetaComponent?
    /// Snapshot of the entity's magnetic field configuration (e.g. stackOffset for splay direction).
    /// nil means no override — the entity keeps its authored MagneticFieldComponent as-is.
    public var magneticField: MagneticFieldPartial?
    /// nil represents no opacity override (i.e. fully opaque / 1.0).
    public var opacity: Float?

    public init(
      eid: EID,
      position: SIMD3<Float>? = nil,
      orientation: simd_quatf? = nil,
      scale: SIMD3<Float>? = nil,
      physicsMode: PhysicsBodyMode? = nil,
      magneticHugs: MagneticHugsComponent? = nil,
      modelMeta: ModelMetaComponent? = nil,
      magneticField: MagneticFieldPartial? = nil,
      opacity: Float? = nil
    ) {
      self.eid = eid
      self.position = position
      self.orientation = orientation
      self.scale = scale
      self.physicsMode = physicsMode
      self.magneticHugs = magneticHugs
      self.modelMeta = modelMeta
      self.magneticField = magneticField
      self.opacity = opacity
    }

    // ╔═════════╗
    // ║ CODABLE ║
    // ╚═════════╝

    enum CodingKeys: String, CodingKey {
      case eid, position, orientation, scale, physicsMode, magneticHugs, modelMeta, magneticField,
        opacity
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.eid = try container.decode(EID.self, forKey: .eid)
      self.position = try SIMD3FloatCodable.decodeIfPresent(from: container, forKey: .position)
      self.orientation = try SimdQuatfFloatCodable.decodeIfPresent(
        from: container,
        forKey: .orientation
      )
      self.scale = try SIMD3FloatCodable.decodeIfPresent(from: container, forKey: .scale)
      self.physicsMode = try container.decodeIfPresent(PhysicsBodyMode.self, forKey: .physicsMode)
      self.magneticHugs = try container.decodeIfPresent(
        MagneticHugsComponent.self,
        forKey: .magneticHugs
      )
      self.modelMeta = try container.decodeIfPresent(ModelMetaComponent.self, forKey: .modelMeta)
      self.magneticField = try container.decodeIfPresent(
        MagneticFieldPartial.self,
        forKey: .magneticField
      )
      self.opacity = try container.decodeIfPresent(Float.self, forKey: .opacity)
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(self.eid, forKey: .eid)
      try SIMD3FloatCodable.encodeIfPresent(self.position, to: &container, forKey: .position)
      try SimdQuatfFloatCodable.encodeIfPresent(
        self.orientation,
        to: &container,
        forKey: .orientation
      )
      try SIMD3FloatCodable.encodeIfPresent(self.scale, to: &container, forKey: .scale)
      try container.encodeIfPresent(self.physicsMode, forKey: .physicsMode)
      try container.encodeIfPresent(self.magneticHugs, forKey: .magneticHugs)
      try container.encodeIfPresent(self.modelMeta, forKey: .modelMeta)
      try container.encodeIfPresent(self.magneticField, forKey: .magneticField)
      try container.encodeIfPresent(self.opacity, forKey: .opacity)
    }
  }

  // MARK: - CoreMoveTarget

  /// Convenience enum for the CoreMove initialiser — not stored directly.
  /// `unset` represents a CoreMove being built and is not valid to insert or animate.
  public enum CoreMoveTarget: Equatable, Sendable {
    case position(SIMD3<Float>)
    case magnet(EID)
    case unset
  }

  // MARK: - CoreMove

  /// A Core Move is a move without any side effects — it represents changes to one entity.
  public struct CoreMove: Equatable, Codable, Sendable {
    public var eid: EID
    public var magnet: EID?
    public var position: SIMD3<Float>?
    public var orientation: simd_quatf?
    public var scale: SIMD3<Float>?
    /// Opacity override; nil means fully opaque (1.0).
    public var opacity: Float?
    public var modelMeta: ModelMetaComponent?
    /// Snapshot of the target entity's magnetic field configuration to apply (e.g. stackOffset
    /// for splay direction changes). nil means no change to the entity's MagneticFieldComponent.
    public var magneticField: MagneticFieldPartial?
    /// When nil, defaults to the initiating action's animation duration.
    public var duration: Duration?
    /// Optional delay before the animation starts. Used for staggered animations
    /// where multiple CoreMoves in the same chunk start at different times.
    public var delay: Duration?
    /// Initial velocity impulse applied via physics before the main animation.
    /// When set, the entity is made dynamic with gravity, given this linear velocity,
    /// and after 2 seconds physics is disabled and the normal position/magnet animation begins
    /// from wherever the entity ended up.
    public var force: SIMD3<Float>?
    /// Custom sound to play
    public var sound: SoundGroup?
    /// Snapshot of the desired `huggedBy` ordering for the magnet identified by `eid`.
    /// When present, the pipeline expands this into individual per-hugger CoreMoves
    /// (each targeting the magnet with a `huggerIndex` derived from their array position).
    public var huggers: [EID]?
    public init(
      eid: EID,
      target: CoreMoveTarget = .unset,
      orientation: simd_quatf? = nil,
      scale: SIMD3<Float>? = nil,
      opacity: Float? = nil,
      modelMeta: ModelMetaComponent? = nil,
      magneticField: MagneticFieldPartial? = nil,
      duration: Duration? = nil,
      delay: Duration? = nil,
      force: SIMD3<Float>? = nil,
      sound: SoundGroup? = nil,
      huggers: [EID]? = nil,
    ) {
      self.eid = eid
      self.orientation = orientation
      self.scale = scale
      self.opacity = opacity
      self.modelMeta = modelMeta
      self.magneticField = magneticField
      self.duration = duration
      self.delay = delay
      self.force = force
      self.sound = sound
      self.huggers = huggers
      switch target {
      case .position(let position):
        self.position = position
        self.magnet = nil
      case .magnet(let magnet):
        self.magnet = magnet
        self.position = nil
      case .unset:
        self.position = nil
        self.magnet = nil
      }
    }

    // ╔═════════╗
    // ║ CODABLE ║
    // ╚═════════╝

    public enum CodingKeys: String, CodingKey {
      case eid, magnet, position, orientation, scale, opacity, modelMeta, magneticField, duration,
        delay, force, sound, huggers
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.eid = try container.decode(EID.self, forKey: .eid)
      self.magnet = try container.decodeIfPresent(EID.self, forKey: .magnet)
      self.position = try SIMD3FloatCodable.decodeIfPresent(from: container, forKey: .position)
      self.orientation = try SimdQuatfFloatCodable.decodeIfPresent(
        from: container,
        forKey: .orientation
      )
      self.scale = try SIMD3FloatCodable.decodeIfPresent(from: container, forKey: .scale)
      self.opacity = try container.decodeIfPresent(Float.self, forKey: .opacity)
      self.modelMeta = try container.decodeIfPresent(ModelMetaComponent.self, forKey: .modelMeta)
      self.magneticField = try container.decodeIfPresent(
        MagneticFieldPartial.self,
        forKey: .magneticField
      )
      self.duration = try container.decodeIfPresent(Duration.self, forKey: .duration)
      self.delay = try container.decodeIfPresent(Duration.self, forKey: .delay)
      self.force = try SIMD3FloatCodable.decodeIfPresent(from: container, forKey: .force)
      self.sound = try container.decodeIfPresent(SoundGroup.self, forKey: .sound)
      self.huggers = try container.decodeIfPresent([EID].self, forKey: .huggers)
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(self.eid, forKey: .eid)
      try container.encodeIfPresent(self.magnet, forKey: .magnet)
      try SIMD3FloatCodable.encodeIfPresent(self.position, to: &container, forKey: .position)
      try SimdQuatfFloatCodable.encodeIfPresent(
        self.orientation,
        to: &container,
        forKey: .orientation
      )
      try SIMD3FloatCodable.encodeIfPresent(self.scale, to: &container, forKey: .scale)
      try container.encodeIfPresent(self.opacity, forKey: .opacity)
      try container.encodeIfPresent(self.modelMeta, forKey: .modelMeta)
      try container.encodeIfPresent(self.magneticField, forKey: .magneticField)
      try container.encodeIfPresent(self.duration, forKey: .duration)
      try container.encodeIfPresent(self.delay, forKey: .delay)
      try SIMD3FloatCodable.encodeIfPresent(self.force, to: &container, forKey: .force)
      try container.encodeIfPresent(self.sound, forKey: .sound)
      try container.encodeIfPresent(self.huggers, forKey: .huggers)
    }
  }

  // MARK: - Move

  /// A Move groups CoreMoves into parallel chunks.
  /// All CoreMoves in one chunk animate simultaneously.
  public struct Move: Equatable, Codable, Sendable {
    public var chunks: [[CoreMove]]

    public init(_ chunks: [[CoreMove]]) { self.chunks = chunks }
  }

  // MARK: - HistoryBackup

  /// Backup of original history when in alternate history mode.
  /// When browsing history and making a diverging change, the original
  /// moves are backed up here so the user can restore or keep their changes.
  public struct HistoryBackup: Codable, Sendable, Equatable {
    /// The moveNr at which divergence happened (where the backup starts).
    public var divergenceMoveNr: Int
    /// The original moves that were truncated from divergenceMoveNr onward.
    public var moves: [Move]

    public var hasBackup: Bool { !moves.isEmpty }

    public init(divergenceMoveNr: Int = -1, moves: [Move] = []) {
      self.divergenceMoveNr = divergenceMoveNr
      self.moves = moves
    }
  }

  // MARK: - MoveHistory

  /// The history of moves of a game.
  public struct MoveHistory: Codable, Sendable {
    /// A ledger of all moves played.
    public var moves: [Move]

    /// The last played move that is currently visible.
    /// - `-1` means not browsing — showing the latest played state.
    /// - `0` means showing the initial board state.
    /// - `N` means showing after move N.
    public var moveNr: Int

    public init(moves: [Move] = [], moveNr: Int = -1) {
      self.moves = moves
      self.moveNr = moveNr
    }

    // ╔═════════╗
    // ║ CODABLE ║
    // ╚═════════╝

    /// `moves` is encoded as `[String: Move]` (keyed `"_0"`, `"_1"`, …) rather than `[Move]`
    /// to work around confirmed SwiftData bugs affecting `Codable` structs with optional fields:
    ///
    /// - **`init(from:)` bypassed + `Optional<Any>` crash**: SwiftData uses its own
    ///   composite-attribute decoder instead of `JSONDecoder`, ignoring any custom `init(from:)`.
    ///   That decoder throws when it encounters `Optional<Any>`, crashing even when your struct
    ///   handles optionals correctly.
    ///   https://developer.apple.com/forums/thread/739282
    ///
    /// - **All-optional struct collapses to nil**: If a struct stored via SwiftData has all
    ///   optional fields and every field is nil, SwiftData treats the entire struct as nil.
    ///   When the parent property is non-optional this produces a fatal crash:
    ///   `"Passed nil for a non-optional keypath"`. Workarounds: make the property optional, or
    ///   add one non-optional field to the struct.
    ///   https://developer.apple.com/forums/thread/762562
    ///
    /// Further reading:
    /// - https://wadetregaskis.com/swiftdata-pitfalls/
    /// - https://fatbobman.com/en/posts/considerations-for-using-codable-and-enums-in-swiftdata-models/
    private enum CodingKeys: String, CodingKey { case moves, moveNr }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.moveNr = try container.decodeIfPresent(Int.self, forKey: .moveNr) ?? -1
      // Moves are encoded as [String: Move] to survive SwiftData dictionary encoding quirks.
      let movesDic = try container.decodeIfPresent([String: Move].self, forKey: .moves) ?? [:]
      let movesArray =
        movesDic.sorted(by: {
          guard let intKey0 = Int($0.key.trimmingCharacters(in: CharacterSet(charactersIn: "_"))),
            let intKey1 = Int($1.key.trimmingCharacters(in: CharacterSet(charactersIn: "_")))
          else { return false }
          return intKey0 < intKey1
        })
        .map { $0.value }
      self.moves = movesArray
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(self.moveNr, forKey: .moveNr)
      var movesDic: [String: Move] = [:]
      for (index, move) in self.moves.enumerated() { movesDic["_\(index)"] = move }
      try container.encode(movesDic, forKey: .moves)
    }
  }
}
