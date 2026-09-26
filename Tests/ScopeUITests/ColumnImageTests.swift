import CoreGraphics
import Foundation
import ScopeCore
import Testing

@testable import ScopeUI

@Suite("Timeline columns image")
struct ColumnImageTests {
  private let theme = ThemeLoader.pick(ThemeLoader.bundled(), for: .light)
  private let metrics = Metrics.standard.timeline

  private func draw(_ data: TimelineData, width: Int = 400, height: Int = 280) -> CGImage? {
    let layout = ColumnLayout(
      width: CGFloat(width), count: data.chart.columns.count, metrics: metrics)
    let key = ColumnImage.Key(
      chart: data.chart.identity, width: width, height: height, scale: 1, theme: 1,
      highlighted: data.chart.highlighted)
    return ColumnImage.make(
      chart: data.chart, layout: layout, key: key, theme: theme, metrics: metrics)
  }

  /// The alpha of one pixel, counted from the image's bottom left.
  private func alpha(_ image: CGImage, x: Int, y: Int) throws -> UInt8 {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = try #require(
      CGContext(
        data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(
      image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
    return pixel[3]
  }

  @Test("columns outside the selected prompt fade, the selected ones do not")
  func dimming() throws {
    let data = TimelineLanes.present(TimelineLanes.lane(requests: 4, prompts: [0, 2]), selected: 2)
    let image = try #require(draw(data))
    let layout = ColumnLayout(width: 400, count: 4, metrics: metrics)
    let dimmed = try alpha(image, x: Int(layout.center(0)), y: 2)
    let full = try alpha(image, x: Int(layout.center(3)), y: 2)
    #expect(full == 255)
    #expect(abs(Double(dimmed) - 255 * theme.chart.dimmedOpacity) < 2)
    // Above the tallest column there is nothing.
    #expect(try alpha(image, x: Int(layout.center(3)), y: 270) == 0)
  }

  @Test("a column stands as tall as its tokens")
  func height() throws {
    let data = TimelineLanes.present(TimelineLanes.lane(requests: 1))
    let image = try #require(draw(data, width: 40, height: 200))
    // 14,200 tokens of a 200k window is 14.2 pixels of 200.
    #expect(try alpha(image, x: 20, y: 13) == 255)
    #expect(try alpha(image, x: 20, y: 15) == 0)
  }

  @Test("columns keep the full gap until there are too many for it")
  func columnLayout() {
    let few = ColumnLayout(width: 998, count: 87, metrics: metrics)
    #expect(few.gap == 2)
    #expect(abs(few.x(86) + few.columnWidth - 998) < 0.001)
    #expect(few.column(atX: 0) == 0)
    #expect(few.column(atX: few.x(40) + 1) == 40)
    #expect(few.column(atX: 998) == nil)
    let many = ColumnLayout(width: 998, count: 800, metrics: metrics)
    #expect(many.gap < 1)
    #expect(many.columnWidth > 0)
    #expect(many.column(atX: 997.9) == 799)
  }

  @Test("the magnifier stands beside the pointer on the side with room, inside the plot")
  func magnifierPlace() {
    #expect(ContextPlot.magnifierX(100, width: 340, offset: 16, room: 1000) == 116)
    #expect(ContextPlot.magnifierX(900, width: 340, offset: 16, room: 1000) == 544)
    // Too narrow for either side: against the right end, never past the left.
    #expect(ContextPlot.magnifierX(300, width: 340, offset: 16, room: 500) == 160)
    #expect(ContextPlot.magnifierX(100, width: 340, offset: 16, room: 300) == 0)
  }

  /// Hundreds of small blocks drew a rule each, and the rules lined up across
  /// the columns as stripes. A rule stands only between two blocks that are
  /// both tall enough to be read.
  @Test("a rule stands between two blocks only when both are tall enough")
  func rules() {
    let tall = metrics.blockGapMinimumPixels
    #expect(metrics.separates(below: tall, above: tall))
    #expect(!metrics.separates(below: tall - 1, above: 400))
    #expect(!metrics.separates(below: 400, above: tall - 1))
    #expect(!metrics.separates(below: 3, above: 3))
  }

  @Test("the dark appearance dims a column less, so its kinds keep their colors")
  func darkDimming() {
    let dark = ThemeLoader.pick(ThemeLoader.bundled(), for: .dark)
    #expect(dark.chart.dimmedOpacity > theme.chart.dimmedOpacity)
    #expect(dark.chart.dimmedOpacity < 1)
  }
}
