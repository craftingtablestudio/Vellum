import Foundation

public let GROUP_CLONE_DIVIDER = "__groupclone__"

extension v0.EID {
  public var name: String {
    switch self {
    case .clone(let name, _): return name
    case .other(let name): return name
    case .none: return ""
    case .originalCloner: return ""
    }
  }

  public func cloneId() -> UUID? {
    switch self {
    case .clone(_, let cloneId): return cloneId
    default: return nil
    }
  }

  public var isClone: Bool {
    switch self {
    case .clone: return true
    default: return false
    }
  }

  /// True when this is a clone EID whose name uses the "GroupName__groupclone__ChildName" format,
  /// indicating it originated from a `ClonableGroupComponent` rather than an `EntityCloner`.
  public var isGroupClone: Bool { isClone && name.contains(GROUP_CLONE_DIVIDER) }

  /// The group name portion of a group-clone EID, e.g. `"PlayerSet"` from `"PlayerSet__groupclone__Red"`.
  /// Returns `nil` for non-group-clone EIDs.
  public var groupCloneName: String? {
    guard isGroupClone else { return nil }
    return name.components(separatedBy: GROUP_CLONE_DIVIDER).first
  }

  /// The child name portion of a group-clone EID, e.g. `"Red"` from `"PlayerSet__groupclone__Red"`.
  /// Returns `nil` for non-group-clone EIDs.
  public var groupCloneChildName: String? {
    guard isGroupClone else { return nil }
    return name.components(separatedBy: GROUP_CLONE_DIVIDER).last
  }
}
