public import SwiftUI

/// A bar split into parts, each a share of the whole, on a track that shows
/// what is left: the popover's context by kind against the window.
///
/// Every edge is put on a whole device pixel, so two parts never share a
/// pixel and blur.
public struct Meter: View {
  public struct Part: Sendable, Equatable {
    public let color: ThemeColor
    /// A share of the whole bar, from zero to one.
    public let share: Double

    public init(color: ThemeColor, share: Double) {
      self.color = color
      self.share = share
    }
  }

  private let parts: [Part]
  @Environment(\.theme) private var theme
  @Environment(\.displayScale) private var scale

  public init(_ parts: [Part]) {
    self.parts = parts
  }

  public var body: some View {
    let popover = theme.metrics.popover
    let parts = parts
    let scale = scale
    Canvas(opaque: false, rendersAsynchronously: false) { context, size in
      var start = 0.0
      for part in parts where part.share > 0 {
        let end = min(1, start + part.share)
        let left = Pixels.snap(start * size.width, scale: scale)
        let right = Pixels.snap(end * size.width, scale: scale)
        context.fill(
          Path(CGRect(x: left, y: 0, width: right - left, height: size.height)),
          with: .color(part.color.color))
        start = end
      }
    }
    .frame(height: popover.meterHeight)
    .background(theme.chart.meterTrack.color)
    .clipShape(RoundedRectangle(cornerRadius: popover.meterRadius))
    .accessibilityHidden(true)
  }
}

/// A row of thin bars standing on a common base, one per request, with some
/// of them marked: the popover's context per request, with its cache breaks.
public struct Sparkline: View {
  public struct Bar: Sendable, Equatable {
    /// A share of the chart's height, from zero to one.
    public let height: Double
    public let isMarked: Bool

    public init(height: Double, isMarked: Bool) {
      self.height = height
      self.isMarked = isMarked
    }
  }

  private let bars: [Bar]
  @Environment(\.theme) private var theme
  @Environment(\.displayScale) private var scale

  public init(_ bars: [Bar]) {
    self.bars = bars
  }

  public var body: some View {
    let popover = theme.metrics.popover
    let bars = bars
    let scale = scale
    let gap = popover.sparkBarGap
    let plain = theme.chart.spark.color
    let marked = theme.chart.sparkBreak.color
    Canvas(opaque: false, rendersAsynchronously: false) { context, size in
      guard !bars.isEmpty else { return }
      let count = CGFloat(bars.count)
      let width = (size.width - gap * (count - 1)) / count
      for (slot, bar) in bars.enumerated() {
        let x = CGFloat(slot) * (width + gap)
        let left = Pixels.snap(x, scale: scale)
        let right = Pixels.snap(x + width, scale: scale)
        let top = Pixels.snap(size.height * (1 - CGFloat(bar.height)), scale: scale)
        context.fill(
          Path(CGRect(x: left, y: top, width: right - left, height: size.height - top)),
          with: .color(bar.isMarked ? marked : plain))
      }
    }
    .frame(height: popover.sparkHeight)
    .accessibilityHidden(true)
  }
}

/// Where an edge goes: on the nearest device pixel.
enum Pixels {
  static func snap(_ value: CGFloat, scale: CGFloat) -> CGFloat {
    let scale = max(1, scale)
    return (value * scale).rounded() / scale
  }
}

#Preview {
  let theme = Theme.preview
  VStack(spacing: 16) {
    Meter(
      theme.kind.inReadingOrder.enumerated().map {
        Meter.Part(color: $0.element, share: 0.02 + Double($0.offset) * 0.05)
      })
    Sparkline((1...87).map { Sparkline.Bar(height: Double($0) / 120, isMarked: $0 == 64) })
  }
  .frame(width: 328)
  .padding()
  .environment(\.theme, theme)
}
