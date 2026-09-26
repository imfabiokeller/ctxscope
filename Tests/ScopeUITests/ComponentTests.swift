import CoreGraphics
import Testing

@testable import ScopeUI

@Suite("Components")
struct ComponentTests {
  @Test("a count is grouped the way the window writes it")
  func count() {
    #expect(UIFormat.count(87) == "87")
    #expect(UIFormat.count(1284) == "1,284")
  }

  @Test("every glyph stays inside its frame")
  func glyphs() {
    let kinds: [Glyph.Kind] = [.chevronDown, .chevronLeft, .chevronRight, .magnifier, .ellipsis]
    for side in [CGFloat(10), 12, 24] {
      let frame = CGRect(x: 0, y: 0, width: side, height: side)
      for kind in kinds {
        let bounds = Glyph(kind).path(in: frame).boundingRect
        #expect(!bounds.isEmpty, "\(kind)")
        #expect(frame.contains(bounds), "\(kind) at \(side)")
      }
    }
  }

  @Test("the kinds are named with the UI's words, in reading order")
  func kindNames() {
    let names = Theme.preview.kind.named.map(\.name)
    #expect(names == ["system", "tools", "memory", "you", "agent", "results"])
  }

  @Test("the fact grid's rows")
  func factRows() {
    typealias Grid = FactGrid<FactData, FactTile>
    let wide: Set<Int> = [4, 5]
    #expect(Grid.rows(of: 6) { wide.contains($0) } == [[0, 1], [2, 3], [4], [5]])
    #expect(Grid.rows(of: 3) { $0 == 1 } == [[0], [1], [2]])
    #expect(Grid.rows(of: 3) { _ in false } == [[0, 1], [2]])
    #expect(Grid.rows(of: 0) { _ in false }.isEmpty)
  }
}
