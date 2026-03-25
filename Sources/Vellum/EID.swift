import Foundation

extension EID {
  public var name: String {
    switch self {
    case .clone(let name, _): return name
    case .other(let name): return name
    case .none: return ""
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
}
