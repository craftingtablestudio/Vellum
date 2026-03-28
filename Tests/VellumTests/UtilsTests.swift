import Foundation
import Testing
import Vellum

// MARK: - UtilsTests · Utils.swift

struct UtilsTests {

  struct AtTests {
    // Boundary: at(-1) returns the last element
    @Test func negativeOne_returnsLastElement() {
      #expect([1, 2, 3].at(-1) == 3)
    }

    // Boundary: at(-n) counts from the end for larger negative offsets
    @Test func negativeOffset_countsFromEnd() {
      #expect([1, 2, 3].at(-2) == 2)
    }

    // Boundary: positive index out of bounds returns nil
    @Test func positiveOutOfBounds_returnsNil() {
      #expect([1, 2, 3].at(10) == nil)
    }

    // Boundary: negative index out of bounds returns nil
    @Test func negativeOutOfBounds_returnsNil() {
      #expect([1, 2, 3].at(-10) == nil)
    }
  }

  struct SliceTests {
    @Test func noEnd_returnsToEndOfArray() {
      #expect([1, 2, 3].slice(1) == [2, 3])
    }

    // Boundary: negative end counts from the end of the array
    @Test func negativeEnd_countsFromEnd() {
      #expect([1, 2, 3].slice(0, -1) == [1, 2])
    }

    // Boundary: start >= end returns an empty array
    @Test func startBeyondEnd_returnsEmpty() {
      #expect([1, 2, 3].slice(5) == [])
    }

    // Boundary: out-of-range negative start clamps to 0
    @Test func outOfRangeStart_clampsToZero() {
      #expect([1, 2, 3].slice(-10) == [1, 2, 3])
    }
  }

  struct StringSplitTests {
    // Boundary: split(Character) preserves empty components between adjacent separators
    @Test func character_preservesEmptyComponents() {
      #expect("a::b".split(":") == ["a", "", "b"])
    }

    @Test func string_splitsOnDelimiter() {
      #expect("a::b".split("::") == ["a", "b"])
    }
  }
}
