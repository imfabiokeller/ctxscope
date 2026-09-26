import AppKit
import CoreGraphics
import Testing

@testable import ScopeUI

/// No number over the timeline is drawn over another or cut through a glyph.
@Suite("chart labels")
struct ChartLabelTests {
  typealias Span = PromptLabels.Span

  static func place(_ spans: [Span], selected: Int? = nil) -> [PromptLabels.Place] {
    PromptLabels.place(
      spans, labels: spans.map { _ in 7 }, selected: selected, total: 200, inset: 2,
      chipInset: 6)
  }

  @Test("a band shows its number only when it fits with its inset")
  func fits() {
    let places = Self.place([Span(x: 0, width: 40), Span(x: 42, width: 10), Span(x: 54, width: 11)])
    #expect(places == [.inside, .hidden, .inside])
  }

  @Test("a narrow selected band shows its number on a chip, and the chip hides what it covers")
  func chip() {
    let spans = [Span(x: 0, width: 4), Span(x: 6, width: 12), Span(x: 20, width: 60)]
    let places = Self.place(spans, selected: 0)
    // 7 wide with 6 either side is 19, centered on the band and held inside
    // the chart.
    #expect(places[0] == .chip(x: 0, width: 19))
    #expect(places[1] == .hidden)
    #expect(places[2] == .inside)
    // A selected band with room shows its number inside it like any other.
    #expect(Self.place(spans, selected: 2)[2] == .inside)
  }

  @Test("the chip stays inside the chart at its right end")
  func rightEnd() {
    let places = Self.place([Span(x: 150, width: 46), Span(x: 197, width: 3)], selected: 1)
    #expect(places[1] == .chip(x: 181, width: 19))
    #expect(places[0] == .inside)
  }

  static func group(_ centers: [CGFloat]) -> [BreakBadges.Group] {
    BreakBadges.group(
      centers: centers, numbers: Array(1...centers.count), badge: 16, inset: 5, gap: 2,
      total: 400
    ) { CGFloat($0.count) * 6 }
  }

  @Test("badges that would touch share one, named by their first and last")
  func merge() {
    let groups = Self.group([20, 60, 70, 200])
    #expect(groups.map(\.label) == ["1", "2\u{2013}3", "4"])
    #expect(groups.map(\.breaks) == [0...0, 1...2, 3...3])
    // The shared badge stands where the first one's would, as wide as its
    // label needs.
    #expect(groups[1].x == 52)
    #expect(groups[1].width == 28)
  }

  @Test("across many breaks, no two badges overlap and every break is in one")
  func sweep() {
    for step in stride(from: CGFloat(1), through: 30, by: 1) {
      let centers = (0..<25).map { CGFloat($0) * step + 8 }
      let groups = Self.group(centers)
      for (left, right) in zip(groups, groups.dropFirst()) {
        #expect(left.x + left.width + 2 <= right.x)
      }
      #expect(groups.flatMap { Array($0.breaks) } == Array(0..<25))
      #expect(groups.allSatisfy { $0.x >= 0 && $0.x + $0.width <= 400 })
    }
  }

  /// The widths a layout reckons with are the system font's own, so a number
  /// said to fit does fit.
  @Test(
    "a number's width is what the system font sets it at",
    arguments: [(MeasuredRole.smallStrong, CGFloat(11)), (MeasuredRole.badge, CGFloat(10))])
  func measured(role: MeasuredRole, size: CGFloat) {
    let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
    for text in ["7", "23", "5\u{2013}6", "12\u{2013}14", "1,284"] {
      let set = (text as NSString).size(withAttributes: [.font: font]).width
      #expect(role.width(of: text) >= set)
      #expect(role.width(of: text) < set + 1)
    }
  }

  @Test("a badge's tooltip names its breaks and their requests from one")
  func tooltip() {
    let one = [TimelineChart.Break(column: 195, number: 3)]
    #expect(TimelineWords.breaks(one) == "Cache break 3 · request 196")
    let two = one + [TimelineChart.Break(column: 201, number: 4)]
    #expect(TimelineWords.breaks(two) == "Cache breaks 3\u{2013}4 · requests 196, 202")
  }
}
