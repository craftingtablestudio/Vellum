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
    let child = EID.clonableGroupChild(group: "PlayerSet", child: "Hand", cloneId: UUID())
    #expect(child.groupCloneTemplateEID == EID.other(name: "PlayerSet__groupclone__Hand"))
  }

  /// Standalone clones and `.other` entities have no template preset key.
  @Test func groupCloneTemplateEID_nilForNonGroupClones() {
    #expect(EID.clone(name: "GoStoneBlack", cloneId: UUID()).groupCloneTemplateEID == nil)
    #expect(EID.other(name: "PlayerSet__groupclone__Hand").groupCloneTemplateEID == nil)
  }

  /// `.clonableGroupChild` survives the custom single-string Codable round-trip, and the parsed
  /// case reports its group/child/cloneId — distinct from a `.clone` sharing the same full name.
  @Test func clonableGroupChild_roundTripsStringFormat() throws {
    let cloneId = UUID()
    let child = EID.clonableGroupChild(group: "PlayerSet", child: "Hand", cloneId: cloneId)
    let data = try JSONEncoder().encode(child)
    let decoded = try JSONDecoder().decode(EID.self, from: data)
    #expect(decoded == child)
    #expect(decoded.isGroupClone)
    #expect(!decoded.isPureClone)
    #expect(decoded.groupCloneName == "PlayerSet")
    #expect(decoded.cloneId() == cloneId)
    #expect(decoded.name == "PlayerSet__groupclone__Hand")
  }

  /// `.clone` and `.clonableGroupChild` are distinct even when their `name` collides, and each
  /// reports only its own flavor.
  @Test func pureCloneAndGroupChild_areDistinctFlavors() {
    let cloneId = UUID()
    let pure = EID.clone(name: "PlayerSet__groupclone__Hand", cloneId: cloneId)
    let group = EID.clonableGroupChild(group: "PlayerSet", child: "Hand", cloneId: cloneId)
    #expect(pure != group)
    #expect(pure.isPureClone && !pure.isGroupClone)
    #expect(group.isGroupClone && !group.isPureClone)
    #expect(pure.groupCloneName == nil)
  }
}
