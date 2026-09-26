import CoreGraphics
import Testing

@testable import ScopeUI

@Suite("strip mark layout")
struct StripMarkLayoutTests {
  static func place(
    prefixEnd: CGFloat?, prefixWidth: CGFloat = 170, cacheAt: CGFloat?, cacheWidth: CGFloat = 140,
    width: CGFloat = 1000
  ) -> StripMarkLayout {
    StripMarkLayout.place(
      width: width, prefixEnd: prefixEnd, prefixWidth: prefixWidth, cacheAt: cacheAt,
      cacheWidth: cacheWidth, inset: 6, line: 1, gap: 12)
  }

  static func apart(_ layout: StripMarkLayout, prefixWidth: CGFloat = 170) -> Bool {
    guard let prefix = layout.prefixLabel, let cache = layout.cacheLabel else { return true }
    return cache >= prefix + prefixWidth + 12 || cache + 140 + 12 <= prefix
  }

  @Test("a label that fits sits inside its bracket, and each mark keeps its label")
  func fits() {
    let layout = Self.place(prefixEnd: 257, cacheAt: 694)
    #expect(layout.prefixLabel == 6)
    #expect(layout.cacheLabel == 701)
    #expect(!layout.crossesBracketEdge)
    #expect(!layout.crossesCacheLine)
  }

  @Test("a narrow bracket keeps its width, and its closing edge starts under the label")
  func narrowBracket() {
    // A 1M window: 46.9k is 33 points of 700.
    let layout = Self.place(prefixEnd: 33, cacheAt: 400, width: 700)
    #expect(layout.prefixLabel == 6)
    #expect(layout.crossesBracketEdge)
    #expect(layout.cacheLabel == 407)
    #expect(!layout.crossesCacheLine)
  }

  @Test("when the cache label would meet the bracket's, it moves right past it")
  func collide() throws {
    let layout = Self.place(prefixEnd: 33, cacheAt: 97, width: 700)
    let cache = try #require(layout.cacheLabel)
    #expect(abs(cache - (6 + 170 + 12)) < 0.001)
    #expect(Self.apart(layout))
    #expect(layout.crossesCacheLine)
  }

  @Test("a cache label with no room on the right stands left of its line")
  func rightEdge() throws {
    let layout = Self.place(prefixEnd: 257, cacheAt: 950)
    let cache = try #require(layout.cacheLabel)
    #expect(cache + 140 <= 950)
    #expect(Self.apart(layout))
    #expect(!layout.crossesCacheLine)
  }

  @Test("across every position, the labels never overlap")
  func sweep() {
    for prefix in stride(from: CGFloat(2), through: 600, by: 7) {
      for cache in stride(from: CGFloat(0), through: 1000, by: 11) {
        let layout = Self.place(prefixEnd: prefix, cacheAt: cache)
        #expect(Self.apart(layout))
      }
    }
  }

  @Test("one mark alone")
  func alone() {
    #expect(Self.place(prefixEnd: nil, cacheAt: 100).cacheLabel == 107)
    #expect(Self.place(prefixEnd: 100, cacheAt: nil).cacheLabel == nil)
  }
}
