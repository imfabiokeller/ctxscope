public import SwiftUI

public struct KindSwatch: View {
  public enum Size: Sendable {
    case table
    case legend
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

public struct KindLegendItem: View {
  public enum Style: Sendable {
    case detailed
    case plain
    case compact
    case table
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
