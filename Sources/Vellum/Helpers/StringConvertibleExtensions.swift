extension v0.MagneticHugsComponent: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    let _hugging: String? = if let hugging { "hugging: \(hugging)" } else { nil }
    let _huggedBy: String? =
      if !huggedBy.isEmpty { "huggedBy: [\(huggedBy.map { "\($0)" }.join(", "))]" } else { nil }
    return "MagneticHugsComponent(\([_hugging, _huggedBy].compactMap{$0}.join(", "))"
  }

  public var debugDescription: String { return self.description }
}

extension v0.ModelMetaComponent: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    return "ModelMetaComponent(name: \"\(name)\", pathTextureDic: \(pathTextureDic))"
  }
  public var debugDescription: String { return description }
}
