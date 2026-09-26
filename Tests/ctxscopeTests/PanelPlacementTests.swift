import CoreGraphics
import Testing

@testable import ctxscope

@Suite("where the panel goes")
struct PanelPlacementTests {
  /// 1440 points wide, with a 24 point menu bar.
  private let screen = CGRect(x: 0, y: 0, width: 1440, height: 876)
  private let reach = PanelPlacement.Margins(top: 20, side: 32, bottom: 44)
  private let size = CGSize(width: 362, height: 450)

  private func place(itemX: CGFloat, on screen: CGRect? = nil) -> PanelPlacement {
    let screen = screen ?? self.screen
    return PanelPlacement.place(
      size, under: CGRect(x: itemX, y: screen.maxY, width: 60, height: 24), on: screen,
      margins: PanelPlacement.margins(reach: reach, gap: 8), gap: 8, inset: 8)
  }

  @Test("centered under the item, a gap below the bar")
  func centered() {
    let placement = place(itemX: 900)
    #expect(placement.panel.midX == 930)
    #expect(placement.panel.maxY == screen.maxY - 8)
    #expect(placement.panel.size == size)
  }

  @Test("kept inside the screen near either edge")
  func edges() {
    #expect(place(itemX: 1400).panel.maxX == screen.maxX - 8)
    #expect(place(itemX: 0).panel.minX == screen.minX + 8)
    let left = CGRect(x: -1280, y: 0, width: 1280, height: 776)
    #expect(place(itemX: -40, on: left).panel.maxX == left.maxX - 8)
  }

  @Test("the window leaves the shadow its room, and stops at the bar")
  func window() {
    let placement = place(itemX: 900)
    #expect(placement.margins == PanelPlacement.Margins(top: 8, side: 32, bottom: 44))
    #expect(placement.window.maxY == screen.maxY)
    #expect(placement.window.minY == placement.panel.minY - 44)
    #expect(placement.window.minX == placement.panel.minX - 32)
    #expect(placement.window.width == size.width + 64)
  }

  @Test("a shadow that reaches less than the gap keeps its own reach above")
  func shortReach() {
    let margins = PanelPlacement.margins(
      reach: PanelPlacement.Margins(top: 4, side: 10, bottom: 10), gap: 8)
    #expect(margins.top == 4)
  }

  @Test("a panel wider than the screen still starts at its inset")
  func tooWide() {
    let narrow = CGRect(x: 0, y: 0, width: 300, height: 700)
    #expect(place(itemX: 100, on: narrow).panel.minX == 8)
  }
}
