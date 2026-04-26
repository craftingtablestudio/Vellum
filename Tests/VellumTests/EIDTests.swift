import Foundation
import Testing
import Vellum

struct EIDTests {
  @Test func originalCloner_encodesToStringFormat() throws {
    let encoder = JSONEncoder()
    let data = try encoder.encode(EID.originalCloner)
    let string = String(data: data, encoding: .utf8)!
    #expect(string == "\"EID.originalCloner\"")
  }

  @Test func originalCloner_decodesFromStringFormat() throws {
    let json = "\"EID.originalCloner\""
    let decoder = JSONDecoder()
    let eid = try decoder.decode(EID.self, from: json.data(using: .utf8)!)
    #expect(eid == .originalCloner)
  }

  @Test func originalCloner_roundTrips() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(EID.self, from: try encoder.encode(EID.originalCloner))
    #expect(decoded == .originalCloner)
  }

  @Test func originalCloner_isNotClone() { #expect(EID.originalCloner.isClone == false) }

  @Test func originalCloner_hasEmptyName() { #expect(EID.originalCloner.name == "") }

  @Test func originalCloner_hasNoCloneId() { #expect(EID.originalCloner.cloneId() == nil) }

  @Test func originalCloner_equalsItself() { #expect(EID.originalCloner == EID.originalCloner) }

  @Test func originalCloner_notEqualToNone() { #expect(EID.originalCloner != EID.none) }
}
