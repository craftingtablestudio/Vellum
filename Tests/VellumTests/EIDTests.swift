import Foundation
import Testing
import Vellum

struct EIDTests {
  /// `.none` encodes to the fixed JSON string "EID.none" and round-trips.
  @Test func none_roundTripsStringFormat() throws {
    let data = try JSONEncoder().encode(EID.none)
    #expect(String(data: data, encoding: .utf8) == "\"EID.none\"")
    #expect(try JSONDecoder().decode(EID.self, from: data) == .none)
  }

  /// A group-clone child's template preset key: `.other` under the same full name.
  @Test func groupCloneTemplateEID_mapsToOtherWithSameName() {
    let child = EID.clone(name: "PlayerSet__groupclone__Hand", cloneId: UUID())
    #expect(child.groupCloneTemplateEID == EID.other(name: "PlayerSet__groupclone__Hand"))
  }

  /// Standalone clones and `.other` entities have no template preset key.
  @Test func groupCloneTemplateEID_nilForNonGroupClones() {
    #expect(EID.clone(name: "GoStoneBlack", cloneId: UUID()).groupCloneTemplateEID == nil)
    #expect(EID.other(name: "PlayerSet__groupclone__Hand").groupCloneTemplateEID == nil)
  }
}
