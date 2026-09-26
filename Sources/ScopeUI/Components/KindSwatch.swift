public import SwiftUI

/// The small rounded square that stands for a kind wherever its name is
/// written.
public struct KindSwatch: View {
  public enum Size: Sendable {
    /// In a table row and above the sidebar's title.
    case table
    /// In the legend under a chart.
    case legend
    /// In the popover's legend.
    case compact
  }

  private let color: ThemeColor
  private let size: Size
  @Environment(\.theme) private var theme

  public init(_ color: ThemeColor, size: Size = .table) {
    self.color = color
    self.size = size
  }

  public var body: some View {
    let swatch = theme.metrics.swatch
    let side =
      switch size {
      case .table: swatch.table
      case .legend: swatch.legend
      case .compact: swatch.compact
      }
    RoundedRectangle(cornerRadius: swatch.cornerRadius)
      .fill(color.color)
      .frame(width: side, height: side)
      .accessibilityHidden(true)
  }
}

/// A kind's swatch with its name, and a size or share beside it.
public struct KindLegendItem: View {
  public enum Style: Sendable {
    /// Under the context bar: the name in medium weight, the detail quieter.
    case detailed
    /// Above the timeline: the name alone.
    case plain
    /// In the popover: small type, name and detail as one run.
    case compact
    /// A table's Kind cell.
    case table
    /// Above the sidebar's title, in secondary size.
    case caption
  }

  private let color: ThemeColor
  private let name: String
  private let detail: String?
  private let style: Style
  @Environment(\.theme) private var theme

  public init(color: ThemeColor, name: String, detail: String? = nil, style: Style = .detailed) {
    self.color = color
    self.name = name
    self.detail = detail
    self.style = style
  }

  public var body: some View {
    let swatch = theme.metrics.swatch
    let type = theme.type
    let text = theme.text
    HStack(spacing: gap(swatch)) {
      KindSwatch(color, size: swatchSize)
      switch style {
      case .detailed:
        Text(name).font(type.captionMedium).foregroundStyle(text.primary.color)
        if let detail {
          Text(detail).font(type.caption).foregroundStyle(text.secondary.color)
        }
      case .plain:
        Text(name).font(type.caption).foregroundStyle(text.primary.color)
      case .compact:
        Text([name, detail].compactMap { $0 }.joined(separator: " "))
          .font(type.small).foregroundStyle(text.supporting.color)
      case .table:
        Text(name).font(type.body).foregroundStyle(text.primary.color)
      case .caption:
        Text(name).font(type.caption).foregroundStyle(text.supporting.color)
      }
    }
    // A legend names every kind, so an item keeps its size and never cuts
    // its name short.
    .fixedSize()
    .line(
      style == .compact
        ? theme.type.lines.small
        : style == .table ? theme.type.lines.body : theme.type.lines.caption
    )
    .accessibilityElement(children: .combine)
  }

  private var swatchSize: KindSwatch.Size {
    switch style {
    case .detailed, .plain: .legend
    case .compact: .compact
    case .table, .caption: .table
    }
  }

  private func gap(_ swatch: Metrics.Swatch) -> CGFloat {
    switch style {
    case .detailed, .plain: swatch.legendGap
    case .compact: swatch.compactGap
    case .table, .caption: swatch.tableGap
    }
  }
}

#Preview {
  VStack(alignment: .leading, spacing: 8) {
    ForEach(Theme.preview.kind.named, id: \.name) { kind in
      KindLegendItem(color: kind.color, name: kind.name, detail: "3.1k · 2%")
    }
  }
  .padding()
  .environment(\.theme, Theme.preview)
}
