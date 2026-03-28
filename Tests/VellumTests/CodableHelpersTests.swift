import Foundation
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
  import simd
#endif
import Testing
import Vellum

// MARK: - Private wrappers to exercise the keyed-container API directly

private struct SIMD3Container: Codable {
  enum CodingKeys: String, CodingKey { case v }
  let v: SIMD3<Float>
  init(_ v: SIMD3<Float>) { self.v = v }
  init(from d: Decoder) throws {
    let c = try d.container(keyedBy: CodingKeys.self)
    v = try SIMD3FloatCodable.decode(from: c, forKey: .v)
  }
  func encode(to e: Encoder) throws {
    var c = e.container(keyedBy: CodingKeys.self)
    try SIMD3FloatCodable.encode(v, to: &c, forKey: .v)
  }
}

private struct SIMD3OptContainer: Codable {
  enum CodingKeys: String, CodingKey { case v }
  let v: SIMD3<Float>?
  init(_ v: SIMD3<Float>?) { self.v = v }
  init(from d: Decoder) throws {
    let c = try d.container(keyedBy: CodingKeys.self)
    v = try SIMD3FloatCodable.decodeIfPresent(from: c, forKey: .v)
  }
  func encode(to e: Encoder) throws {
    var c = e.container(keyedBy: CodingKeys.self)
    try SIMD3FloatCodable.encodeIfPresent(v, to: &c, forKey: .v)
  }
}

private struct SimdQuatContainer: Codable {
  enum CodingKeys: String, CodingKey { case v }
  let v: simd_quatf
  init(_ v: simd_quatf) { self.v = v }
  init(from d: Decoder) throws {
    let c = try d.container(keyedBy: CodingKeys.self)
    v = try SimdQuatfFloatCodable.decode(from: c, forKey: .v)
  }
  func encode(to e: Encoder) throws {
    var c = e.container(keyedBy: CodingKeys.self)
    try SimdQuatfFloatCodable.encode(v, to: &c, forKey: .v)
  }
}

private struct SimdQuatOptContainer: Codable {
  enum CodingKeys: String, CodingKey { case v }
  let v: simd_quatf?
  init(_ v: simd_quatf?) { self.v = v }
  init(from d: Decoder) throws {
    let c = try d.container(keyedBy: CodingKeys.self)
    v = try SimdQuatfFloatCodable.decodeIfPresent(from: c, forKey: .v)
  }
  func encode(to e: Encoder) throws {
    var c = e.container(keyedBy: CodingKeys.self)
    try SimdQuatfFloatCodable.encodeIfPresent(v, to: &c, forKey: .v)
  }
}

// MARK: - CodableHelpersTests · Helpers/CodableHelpers.swift

struct CodableHelpersTests {

  struct SIMD3Tests {
    @Test func encode_decode_roundTrip() throws {
      let original = SIMD3<Float>(1, 2, 3)
      let decoded = try JSONDecoder()
        .decode(SIMD3Container.self, from: JSONEncoder().encode(SIMD3Container(original))).v
      #expect(decoded == original)
    }

    // Boundary: decoding from an array with the wrong number of elements throws
    @Test func decode_wrongLength_throws() throws {
      #expect(throws: (any Error).self) {
        try JSONDecoder().decode(SIMD3Container.self, from: Data("{\"v\":[1.0,2.0]}".utf8))
      }
    }

    // Boundary: decodeIfPresent returns nil when the key is absent
    @Test func decodeIfPresent_missingKey_returnsNil() throws {
      let decoded = try JSONDecoder().decode(SIMD3OptContainer.self, from: Data("{}".utf8))
      #expect(decoded.v == nil)
    }

    // Boundary: encodeIfPresent with a nil value omits the key entirely
    @Test func encodeIfPresent_nil_omitsKey() throws {
      let data = try JSONEncoder().encode(SIMD3OptContainer(nil))
      let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
      #expect(json["v"] == nil)
    }
  }

  struct SimdQuatTests {
    @Test func encode_decode_roundTrip() throws {
      let original = simd_quatf.getNonRotated()
      let decoded = try JSONDecoder()
        .decode(SimdQuatContainer.self, from: JSONEncoder().encode(SimdQuatContainer(original))).v
      #expect(decoded.vector == original.vector)
    }

    // Boundary: decoding from an array with the wrong number of elements throws
    @Test func decode_wrongLength_throws() throws {
      #expect(throws: (any Error).self) {
        try JSONDecoder().decode(SimdQuatContainer.self, from: Data("{\"v\":[1.0,2.0,3.0]}".utf8))
      }
    }

    // Boundary: decodeIfPresent returns nil when the key is absent
    @Test func decodeIfPresent_missingKey_returnsNil() throws {
      let decoded = try JSONDecoder().decode(SimdQuatOptContainer.self, from: Data("{}".utf8))
      #expect(decoded.v == nil)
    }
  }
}
