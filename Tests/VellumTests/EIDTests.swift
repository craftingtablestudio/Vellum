import Foundation
import Testing
import Vellum

struct EIDTests {
  /// Average: `.originalCloner` encodes to the fixed JSON string "EID.originalCloner"
  @Test func originalCloner_encodesToStringFormat() throws {
    let encoder = JSONEncoder()
    let data = try encoder.encode(EID.originalCloner)
    let string = String(data: data, encoding: .utf8)!
    #expect(string == "\"EID.originalCloner\"")
  }

  /// Average: the JSON string "EID.originalCloner" decodes back to `.originalCloner`
  @Test func originalCloner_decodesFromStringFormat() throws {
    let json = "\"EID.originalCloner\""
    let decoder = JSONDecoder()
    let eid = try decoder.decode(EID.self, from: json.data(using: .utf8)!)
    #expect(eid == .originalCloner)
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

  // MARK: - EID.parent

  /// `.parent` encodes to the fixed JSON string "EID.parent"
  @Test func parent_encodesToStringFormat() throws {
    let encoder = JSONEncoder()
    let data = try encoder.encode(EID.parent)
    let string = String(data: data, encoding: .utf8)!
    #expect(string == "\"EID.parent\"")
  }

  /// The JSON string "EID.parent" decodes back to `.parent`
  @Test func parent_decodesFromStringFormat() throws {
    let json = "\"EID.parent\""
    let decoder = JSONDecoder()
    let eid = try decoder.decode(EID.self, from: json.data(using: .utf8)!)
    #expect(eid == .parent)
  }

  /// `.parent` round-trips through encode/decode
  @Test func parent_codableRoundTrip() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(EID.parent)
    let decoded = try decoder.decode(EID.self, from: data)
    #expect(decoded == .parent)
  }

  /// `.parent` is not treated as a clone
  @Test func parent_isNotClone() { #expect(EID.parent.isClone == false) }

  /// `.parent` has an empty name
  @Test func parent_hasEmptyName() { #expect(EID.parent.name == "") }

  /// `.parent` has no clone ID
  @Test func parent_hasNoCloneId() { #expect(EID.parent.cloneId() == nil) }

  /// `.parent` is equal to itself (reflexive equality)
  @Test func parent_equalsItself() { #expect(EID.parent == EID.parent) }

  /// `.parent` is distinct from `.none` and `.originalCloner`
  @Test func parent_notEqualToOtherSentinels() {
    #expect(EID.parent != EID.none)
    #expect(EID.parent != EID.originalCloner)
  }
}
