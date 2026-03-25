import simd

public enum SIMD3FloatCodable {
  @inlinable public static func decode<CodingKeys: CodingKey>(
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) throws -> SIMD3<Float> {
    let array = try container.decode([Float].self, forKey: key)
    guard array.count == 3 else {
      throw DecodingError.dataCorruptedError(
        forKey: key,
        in: container,
        debugDescription: "Expected array of length 3"
      )
    }
    return SIMD3<Float>(array[0], array[1], array[2])
  }

  @inlinable public static func encode<CodingKeys: CodingKey>(
    _ value: SIMD3<Float>,
    to container: inout KeyedEncodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) throws { try container.encode([value.x, value.y, value.z], forKey: key) }

  @inlinable public static func decodeIfPresent<CodingKeys: CodingKey>(
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) throws -> SIMD3<Float>? {
    return container.contains(key) ? try decode(from: container, forKey: key) : nil
  }

  @inlinable public static func encodeIfPresent<CodingKeys: CodingKey>(
    _ value: SIMD3<Float>?,
    to container: inout KeyedEncodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) throws { if let value { try encode(value, to: &container, forKey: key) } }
}

public enum SimdQuatfFloatCodable {
  @inlinable public static func decode<CodingKeys: CodingKey>(
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) throws -> simd_quatf {
    let array = try container.decode([Float].self, forKey: key)
    guard array.count == 4 else {
      throw DecodingError.dataCorruptedError(
        forKey: key,
        in: container,
        debugDescription: "Expected array of length 4"
      )
    }
    return simd_quatf(ix: array[0], iy: array[1], iz: array[2], r: array[3])
  }

  @inlinable public static func encode<CodingKeys: CodingKey>(
    _ value: simd_quatf,
    to container: inout KeyedEncodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) throws {
    try container.encode(
      [value.vector.x, value.vector.y, value.vector.z, value.vector.w],
      forKey: key
    )
  }

  @inlinable public static func decodeIfPresent<CodingKeys: CodingKey>(
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) throws -> simd_quatf? {
    return container.contains(key) ? try decode(from: container, forKey: key) : nil
  }

  @inlinable public static func encodeIfPresent<CodingKeys: CodingKey>(
    _ value: simd_quatf?,
    to container: inout KeyedEncodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) throws { if let value { try encode(value, to: &container, forKey: key) } }
}
