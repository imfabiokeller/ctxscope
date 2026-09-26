public import SwiftUI

public struct DashedRule: View {
  private let color: ThemeColor
  @Environment(\.theme) private var theme

  public init(_ color: ThemeColor) {
    self.color = color
  }

  public var body: some View {
    let timeline = theme.metrics.timeline
    Canvas { context, size in
      var path = Path()
      path.move(to: CGPoint(x: size.width / 2, y: 0))
      path.addLine(to: CGPoint(x: size.width / 2, y: size.height))
      context.stroke(
        path, with: .color(color.color),
        style: StrokeStyle(
          lineWidth: timeline.markerWidth,
          dash: [timeline.markerDash, timeline.markerDashGap]))
    }
    .frame(width: timeline.markerWidth)
    .accessibilityHidden(true)
  }
}

#Preview {
  DashedRule(Theme.preview.chart.marker)
    .frame(height: 120)
    .padding()
    .environment(\.theme, Theme.preview)
}
