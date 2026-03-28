import Foundation
import Testing
import Vellum

// MARK: - EIDTests · EID.swift

struct EIDTests {

  struct CodableTests {
    @Test func roundTrip_clone() throws {
      let original = EID.clone(name: "Pawn", cloneId: UUID())
      let decoded = try JSONDecoder().decode(EID.self, from: JSONEncoder().encode(original))
      #expect(decoded == original)
    }

    @Test func roundTrip_other() throws {
      let original = EID.other(name: "King")
      let decoded = try JSONDecoder().decode(EID.self, from: JSONEncoder().encode(original))
      #expect(decoded == original)
    }

    @Test func roundTrip_none() throws {
      let decoded = try JSONDecoder().decode(EID.self, from: JSONEncoder().encode(EID.none))
      #expect(decoded == .none)
    }

    // Boundary: decoding a malformed EID string throws a DecodingError
    @Test func decode_malformedString_throws() throws {
      #expect(throws: (any Error).self) {
        try JSONDecoder().decode(EID.self, from: Data("\"EID.garbage(xyz)\"".utf8))
      }
    }
  }
}
