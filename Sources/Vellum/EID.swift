import Foundation

public let GROUP_CLONE_DIVIDER = "__groupclone__"

extension v0.EID {
  /// For `.clonableGroupChild`, deliberately re-encodes the scene-side `"group__groupclone__child"`
  /// convention so entity-name lookups and the template preset key keep resolving.
  public var name: String {
    switch self {
    case .clone(let name, _): return name
    case .clonableGroupChild(let group, let child, _):
      return "\(group)\(GROUP_CLONE_DIVIDER)\(child)"
    case .other(let name): return name
    case .none: return ""
    }
  }

  public func cloneId() -> UUID? {
    switch self {
    case .clone(_, let cloneId): return cloneId
    case .clonableGroupChild(_, _, let cloneId): return cloneId
    case .other, .none: return nil
    }
  }

  /// A runtime clone minted by an `EntityCloner` (NOT a `ClonableGroup` child). Multiple instances of
  /// the same template coexist, distinguished by `cloneId`; on undo one returns to its cloner.
  public var isPureClone: Bool {
    if case .clone = self { return true }
    return false
  }

  /// A child of a `ClonableGroupComponent` container. Shares its container's `cloneId` and rides the
  /// container's spawn; on undo it rests at its template child's authored pose rather than a cloner.
  public var isClonableGroupChild: Bool {
    if case .clonableGroupChild = self { return true }
    return false
  }

  /// The group name portion, e.g. `"PlayerSet"` for `.clonableGroupChild(group: "PlayerSet", …)`.
  /// Returns `nil` unless this is a group child.
  public var clonableGroupName: String? {
    if case .clonableGroupChild(let group, _, _) = self { return group }
    return nil
  }

  /// The preset key of a group child's TEMPLATE child. Template children are renamed at scene load to
  /// `"group__groupclone__child"` and registered under `.other`, so the template's preset entry shares
  /// this child's full name — and its parent-local pose is the child's authored resting spot. Returns
  /// `nil` unless this is a group child.
  public var clonableGroupTemplateEID: v0.EID? {
    guard isClonableGroupChild else { return nil }
    return .other(name: name)
  }
}
