import CoreGraphics
import Testing

@testable import ScopeUI

@Suite("the menu bar mark")
struct StatusGlyphTests {
  private typealias Part = StatusGlyph.Part

  private func track() -> Part {
    Part(rect: CGRect(x: 1, y: 5, width: 12, height: 6), cornerRadius: 1, alpha: 0.3)
  }

  private func slice(_ left: CGFloat, _ right: CGFloat) -> Part {
    Part(rect: CGRect(x: left, y: 5, width: right - left, height: 6), cornerRadius: 0.5, alpha: 1)
  }

  private func bar(_ x: CGFloat, _ top: CGFloat, _ bottom: CGFloat) -> Part {
    Part(
      rect: CGRect(x: x, y: top, width: 1.5, height: bottom - top), cornerRadius: 0.75, alpha: 1)
  }

  @Test("a 16 point square with the track inside it")
  func frame() {
    #expect(StatusGlyph.size == CGSize(width: 16, height: 16))
    let box = CGRect(origin: .zero, size: StatusGlyph.size)
    for state in StatusGlyph.State.allCases {
      for part in StatusGlyph.parts(fill: 1, state: state) {
        #expect(box.contains(part.rect))
      }
    }
  }

  @Test("empty, the track and the cursor at its start")
  func empty() {
    #expect(StatusGlyph.parts(fill: 0, state: .idle) == [track(), bar(1, 2, 14)])
  }

  @Test("at 0.44 the cursor snaps to 6.5 and the second slice stops half a point before it")
  func fortyFour() {
    #expect(
      StatusGlyph.parts(fill: 0.44, state: .idle) == [
        track(), slice(1, 3.5), slice(4, 6), bar(6.5, 2, 14),
      ])
  }

  @Test("at half, two whole slices and the cursor at 7")
  func half() {
    #expect(
      StatusGlyph.parts(fill: 0.5, state: .idle) == [
        track(), slice(1, 3.5), slice(4, 6.5), bar(7, 2, 14),
      ])
  }

  @Test("full, every slice and the cursor at the track's end")
  func full() {
    #expect(
      StatusGlyph.parts(fill: 1, state: .idle) == [
        track(), slice(1, 3.5), slice(4, 6.5), slice(7, 11), slice(11.5, 12.5), bar(13, 2, 14),
      ])
  }

  @Test("the kit's half and full pictures are fills of 6.5 and 10.5 twelfths")
  func kit() {
    #expect(
      StatusGlyph.parts(fill: 6.5 / 12, state: .idle) == [
        track(), slice(1, 3.5), slice(4, 6.5), bar(7.5, 2, 14),
      ])
    #expect(
      StatusGlyph.parts(fill: 10.5 / 12, state: .idle) == [
        track(), slice(1, 3.5), slice(4, 6.5), slice(7, 11), bar(11.5, 2, 14),
      ])
  }

  @Test("the fill snaps to half points and stays inside 0 to 1")
  func snapping() {
    #expect(StatusGlyph.end(fill: 0.02) == 1)
    #expect(StatusGlyph.end(fill: 0.03) == 1.5)
    #expect(StatusGlyph.end(fill: -1) == 1)
    #expect(StatusGlyph.end(fill: 2) == 13)
    #expect(StatusGlyph.snapped(0.713) == 17.0 / 24)
    for step in 0...1000 {
      let fill = Double(step) / 1000
      #expect(StatusGlyph.snapped(StatusGlyph.snapped(fill)) == StatusGlyph.snapped(fill))
      for part in StatusGlyph.parts(fill: fill, state: .live) {
        for edge in [part.rect.minX, part.rect.maxX, part.rect.minY, part.rect.maxY] {
          #expect((edge * 4).rounded() == edge * 4)
        }
      }
    }
  }

  @Test("live puts a 3.5 point dot on a shorter cursor")
  func live() {
    let parts = StatusGlyph.parts(fill: 0.5, state: .live)
    let dot = Part(rect: CGRect(x: 6, y: 1, width: 3.5, height: 3.5), cornerRadius: 1.75, alpha: 1)
    #expect(parts.suffix(2) == [bar(7, 3.5, 14), dot])
    #expect(parts.dropLast(2) == StatusGlyph.parts(fill: 0.5, state: .idle).dropLast())
    #expect(StatusGlyph.opacity(.live) == 1)
  }

  @Test("a cache break splits the cursor into two stubs")
  func cacheBreak() {
    let parts = StatusGlyph.parts(fill: 0.5, state: .cacheBreak)
    #expect(parts.suffix(2) == [bar(7, 1, 4), bar(7, 12, 15)])
    #expect(StatusGlyph.opacity(.cacheBreak) == 1)
  }

  @Test("idle is drawn at 35 percent, the other states in full")
  func idle() {
    #expect(StatusGlyph.opacity(.idle) == 0.35)
    #expect(StatusGlyph.opacity(.live) == 1)
  }
}
