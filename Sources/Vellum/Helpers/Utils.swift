// Inlined from github.com/mesqueeb/JustSugar — only the methods used in Vellum
import Foundation

extension Array {
  func at(_ index: Int) -> Element? {
    let i = index >= 0 ? index : count + index
    guard i >= 0, i < count else { return nil }
    return self[i]
  }

  func slice(_ start: Int, _ end: Int? = nil) -> [Element] {
    let startIndex = start >= 0 ? start : count + start
    let endIndex = end ?? count
    let adjustedEndIndex = endIndex >= 0 ? endIndex : count + endIndex
    let clampedStart = Swift.max(0, Swift.min(startIndex, count))
    let clampedEnd = Swift.max(0, Swift.min(adjustedEndIndex, count))
    guard clampedStart < clampedEnd else { return [] }
    return Array(self[clampedStart ..< clampedEnd])
  }
}

extension Array where Element == String {
  func join(_ separator: String) -> String { joined(separator: separator) }
}

extension String {
  func split(_ separator: Character) -> [String] {
    split(separator: separator, omittingEmptySubsequences: false).map(String.init)
  }

  func split(_ delimiter: String) -> [String] {
    components(separatedBy: delimiter)
  }
}
