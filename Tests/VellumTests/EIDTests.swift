import Foundation
import Testing
import Vellum

struct EIDTests {
  /// `.originalCloner` encodes to the fixed JSON string "EID.originalCloner"
  @Test func originalCloner_encodesToStringFormat() throws {
    let encoder = JSONEncoder()
    let data = try encoder.encode(EID.originalCloner)
    let string = String(data: data, encoding: .utf8)!
    #expect(string == "\"EID.originalCloner\"")
  }

  /// The JSON string "EID.originalCloner" decodes back to `.originalCloner`
  @Test func originalCloner_decodesFromStringFormat() throws {
    let json = "\"EID.originalCloner\""
    let decoder = JSONDecoder()
    let eid = try decoder.decode(EID.self, from: json.data(using: .utf8)!)
    #expect(eid == .originalCloner)
  }

  /// JSON-encoding then decoding `.originalCloner` gives back the same value
  @Test func originalCloner_roundTrips() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(EID.self, from: try encoder.encode(EID.originalCloner))
    #expect(decoded == .originalCloner)
  }

  /// `.originalCloner` is not treated as a clone — it is the original source
  @Test func originalCloner_isNotClone() { #expect(EID.originalCloner.isClone == false) }

  /// `.originalCloner` has an empty name, unlike regular named entities
  @Test func originalCloner_hasEmptyName() { #expect(EID.originalCloner.name == "") }

  /// `.originalCloner` has no clone ID — it was never cloned from anything
  @Test func originalCloner_hasNoCloneId() { #expect(EID.originalCloner.cloneId() == nil) }

  /// `.originalCloner` is equal to itself (reflexive equality holds)
  @Test func originalCloner_equalsItself() { #expect(EID.originalCloner == EID.originalCloner) }

  /// `.originalCloner` is a distinct value — it does not equal `.none`
  @Test func originalCloner_notEqualToNone() { #expect(EID.originalCloner != EID.none) }
}
