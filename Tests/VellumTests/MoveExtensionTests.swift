import Foundation
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
  import simd
#endif
import Testing
@testable import Vellum

// MARK: - MoveExtensionTests · Move.swift

struct MoveExtensionTests {

  struct WithSideEffectsTests {
    @Test func during_appendsToChunk0() {
      let base = mock.move(eid: "A", target: .position([0, 0, 0]))
      let side = mock.coreMove(eid: "B", target: .position([1, 0, 0]))
      #expect(base.withSideEffects(during: [side], after: []).chunks[0].count == 2)
    }

    @Test func after_appendsToChunk1() {
      let base = mock.move(eid: "A", target: .position([0, 0, 0]))
      let side = mock.coreMove(eid: "B", target: .position([1, 0, 0]))
      #expect(base.withSideEffects(during: [], after: [side]).chunks.count == 2)
    }

    // Boundary: both arrays empty returns the move unchanged
    @Test func bothEmpty_moveIsUnchanged() {
      let base = mock.move(eid: "A", target: .position([0, 0, 0]))
      #expect(base.withSideEffects(during: [], after: []) == base)
    }
  }

  struct OmitTests {
    @Test func position_clearsAllPositions() {
      let move = mock.move(eid: "A", target: .position([1, 0, 0]))
      #expect(move.omit(.position).chunks[0][0].position == nil)
    }
  }

  struct ValidateTests {
    // Boundary: validate catches duplicate EIDs within a single chunk
    @Test func duplicateEID_inChunk_returnsError() {
      let cm = mock.coreMove(eid: "A", target: .position([0, 0, 0]))
      #expect(!Move([[cm, cm]]).validate().isEmpty)
    }

    // Boundary: validate allows the same EID to appear in different chunks (resets between chunks)
    @Test func sameEID_inDifferentChunks_isAllowed() {
      let cm = mock.coreMove(eid: "A", target: .position([0, 0, 0]))
      #expect(Move([[cm], [cm]]).validate().isEmpty)
    }
  }

  struct CoreMoveTests {

    struct ValidateTests {
      // Boundary: returns an error when both position and magnet are set
      @Test func positionAndMagnet_returnsError() {
        var cm = mock.coreMove(eid: "A", target: .position([0, 0, 0]))
        cm.magnet = .other(name: "B")
        #expect(!cm.validate().isEmpty)
      }

      // Boundary: returns an error when magnet == eid (self-approach)
      @Test func magnetEqualsEID_returnsError() {
        let cm = mock.coreMove(eid: "A", target: .magnet("A"))
        #expect(!cm.validate().isEmpty)
      }
    }

    struct OmitTests {
      // Complex: clears the correct field for each CodingKey case
      @Test func eachField_clearsCorrectly() {
        let cm = CoreMove(
          eid: .other(name: "A"), target: .position([1, 0, 0]),
          orientation: .getNonRotated(), scale: [1, 1, 1], opacity: 0.5,
          modelMeta: ModelMetaComponent(name: "M", pathTextureDic: [:]),
          duration: .seconds(1), sound: .drop
        )
        let cmMagnet = CoreMove(eid: .other(name: "A"), target: .magnet(.other(name: "B"), 1))
        #expect(cm.omit(.eid).eid == .none)
        #expect(cm.omit(.position).position == nil)
        #expect(cm.omit(.orientation).orientation == nil)
        #expect(cm.omit(.scale).scale == nil)
        #expect(cm.omit(.opacity).opacity == nil)
        #expect(cm.omit(.modelMeta).modelMeta == nil)
        #expect(cm.omit(.duration).duration == nil)
        #expect(cm.omit(.sound).sound == nil)
        #expect(cmMagnet.omit(.magnet).magnet == nil)
        #expect(cmMagnet.omit(.huggerIndex).huggerIndex == nil)
        #expect(CoreMove(eid: .other(name: "A"), revertToInitialState: true).omit(.revertToInitialState).revertToInitialState == false)
      }
    }

    struct ShouldRevertEntireStateTests {
      // Boundary: true when revertToInitialState=true and all positional fields are nil
      @Test func allNil_isTrue() {
        #expect(CoreMove(eid: .other(name: "A"), revertToInitialState: true).shouldRevertEntireState)
      }

      // Boundary: false when revertToInitialState=true but position is set
      @Test func withPosition_isFalse() {
        #expect(!mock.coreMove(eid: "A", target: .position([1, 0, 0]), revertToInitialState: true).shouldRevertEntireState)
      }
    }

    struct FillInEmptyPartsTests {
      @Test func fillsPositionFromInitialState() {
        var cm = CoreMove(eid: .other(name: "A"))
        cm.fillInEmptyParts(with: EntityState(eid: .other(name: "A"), position: [5, 0, 0]))
        #expect(cm.position == [5, 0, 0])
      }

      // Complex: fills magnet from initialState.magneticHugs when entity is hugging another
      @Test func fillsMagnetFromInitialState() {
        var cm = CoreMove(eid: .other(name: "A"))
        cm.fillInEmptyParts(with: EntityState(
          eid: .other(name: "A"),
          magneticHugs: MagneticHugsComponent(hugging: .other(name: "B"), huggedBy: [])
        ))
        #expect(cm.magnet == .other(name: "B"))
      }

      // Boundary: does not overwrite fields that are already set
      @Test func doesNotOverwriteExistingFields() {
        var cm = mock.coreMove(eid: "A", target: .position([1, 0, 0]))
        cm.fillInEmptyParts(with: EntityState(eid: .other(name: "A"), position: [99, 0, 0]))
        #expect(cm.position == [1, 0, 0])
      }
    }

    struct RemovePropsNillInTests {
      @Test func clearsMatchingFields() {
        var cm = mock.coreMove(eid: "A", target: .position([1, 0, 0]))
        cm.scale = [1, 1, 1]
        cm.removePropsNillIn(mock.coreMove(eid: "A"))
        #expect(cm.position == nil)
        #expect(cm.scale == nil)
      }
    }
  }
}
