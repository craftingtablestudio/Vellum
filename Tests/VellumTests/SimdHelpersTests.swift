import Foundation
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
  import simd
#endif
import Testing
import Vellum

// MARK: - SimdHelpersTests · Helpers/SimdHelpers.swift

struct SimdHelpersTests {

  struct QuaternionTests {
    @Test func getNonRotated_isIdentityQuaternion() {
      let q = simd_quatf.getNonRotated()
      #expect(q.real == 1.0 && q.imag == SIMD3<Float>(0, 0, 0))
    }

    // Boundary: act(on:) with an identity quaternion returns the axis vector unchanged
    @Test func act_identityQuaternion_returnsAxisVector() {
      #expect(simd_quatf.getNonRotated().act(on: .x) == SIMD3<Float>(1, 0, 0))
    }

    @Test func facingSameDirection_sameOrientation_isTrue() {
      let q = simd_quatf.getNonRotated()
      #expect(q.facingSameDirection(as: q, axis: .y))
    }

    // Boundary: facingSameDirection returns false when quaternions point opposite ways
    @Test func facingSameDirection_oppositeOrientation_isFalse() {
      let q = simd_quatf.getNonRotated()
      let flipped = simd_quatf(angle: Float.pi, axis: SIMD3<Float>(1, 0, 0))
      #expect(!flipped.facingSameDirection(as: q, axis: .y))
    }
  }
}
