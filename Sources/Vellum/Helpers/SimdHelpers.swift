#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
  import simd
#endif

// Inlined from github.com/craftingtablestudio/letsplay Illusionist/AngleHelpers — only what Vellum needs.

public enum Axis: Sendable, Codable {
  case x, y, z

  @inlinable public var vector: SIMD3<Float> {
    return switch self {
    case .x: SIMD3<Float>(1, 0, 0)
    case .y: SIMD3<Float>(0, 1, 0)
    case .z: SIMD3<Float>(0, 0, 1)
    }
  }
}

extension simd_quatf {
  /// Returns a quaternion with no rotation applied.
  @inlinable public static func getNonRotated() -> simd_quatf {
    return simd_quatf(real: 1, imag: SIMD3<Float>(0, 0, 0))
  }

  /// Transforms the given axis vector by the quaternion.
  public func act(on axis: Axis) -> SIMD3<Float> {
    let q = self
    let qConjugate = q.inverse
    let vQuat = simd_quatf(ix: axis.vector.x, iy: axis.vector.y, iz: axis.vector.z, r: 0)
    let resultQuat = q * vQuat * qConjugate
    return SIMD3<Float>(resultQuat.imag.x, resultQuat.imag.y, resultQuat.imag.z)
  }

  /// Returns true if both quaternions are facing the same direction along the given axis.
  public func facingSameDirection(as quaternion: simd_quatf, axis: Axis) -> Bool {
    let selfDirection = self.act(on: axis)
    let otherDirection = quaternion.act(on: axis)
    return (selfDirection * otherDirection).sum() > 0
  }
}
