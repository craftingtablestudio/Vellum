#if !os(macOS) && !os(iOS) && !os(watchOS) && !os(tvOS) && !os(visionOS)
  // Linux-compatible simd_quatf — mirrors the Apple simd.framework API surface used by Vellum.
  // SIMD3<Float> and SIMD4<Float> are part of the Swift standard library on all platforms.

  public struct simd_quatf: Sendable, Equatable {
    /// Storage: (ix, iy, iz, r) → (.x, .y, .z, .w), matching Apple's layout.
    public var vector: SIMD4<Float>

    public init(ix: Float, iy: Float, iz: Float, r: Float) { vector = SIMD4<Float>(ix, iy, iz, r) }

    public init(real: Float, imag: SIMD3<Float>) {
      vector = SIMD4<Float>(imag.x, imag.y, imag.z, real)
    }

    /// Imaginary (vector) part.
    public var imag: SIMD3<Float> { SIMD3<Float>(vector.x, vector.y, vector.z) }

    /// Real (scalar) part.
    public var real: Float { vector.w }

    /// Multiplicative inverse (assumes non-zero norm).
    public var inverse: simd_quatf {
      let lenSq = (vector * vector).sum()
      return simd_quatf(
        ix: -vector.x / lenSq,
        iy: -vector.y / lenSq,
        iz: -vector.z / lenSq,
        r: vector.w / lenSq
      )
    }

    public static func * (lhs: simd_quatf, rhs: simd_quatf) -> simd_quatf {
      let lv = lhs.imag, rv = rhs.imag
      let lw = lhs.real, rw = rhs.real
      return simd_quatf(
        ix: lw * rv.x + rw * lv.x + lv.y * rv.z - lv.z * rv.y,
        iy: lw * rv.y + rw * lv.y + lv.z * rv.x - lv.x * rv.z,
        iz: lw * rv.z + rw * lv.z + lv.x * rv.y - lv.y * rv.x,
        r: lw * rw - (lv * rv).sum()
      )
    }
  }
#endif
