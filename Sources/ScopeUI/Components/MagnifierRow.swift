internal import ScopeCore
public import SwiftUI

public enum MagnifierWords {
  public static func window(_ range: Range<Int>, of count: Int) -> String {
    "blocks \(UIFormat.count(range.lowerBound + 1))–\(UIFormat.count(range.upperBound)) "
      + "of \(UIFormat.count(count))"
  }

  public static func request(_ index: Int) -> String {
    "Request \(UIFormat.count(RequestNumber.of(index)))"
  }

  public static func figures(tokens: Int, dollars: Double) -> String {
    "\(TokenFormat.short(tokens)) · \(TokenFormat.dollars(dollars))"
  }
}

public struct MagnifierHeader: View {
  private let title: String
  private let figures: String
  private let window: String?
  @Environment(\.theme) private var theme

  public init(title: String, figures: String, window: String?) {
    self.title = title
    self.figures = figures
    self.window = window
  }

  public var body: some View {
    let metrics = theme.metrics.magnifier
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        Text(title).font(theme.type.captionStrong)
          .foregroundStyle(theme.text.primary.color)
        Spacer(minLength: 0)
        Text(figures).font(theme.type.small).foregroundStyle(theme.text.secondary.color)
      }
      .padding(.bottom, metrics.titleGap)
      if let window {
        Text(window)
          .font(theme.type.small).foregroundStyle(theme.text.secondary.color)
          .padding(.bottom, metrics.subtitleGap)
      }
    }
  }
}

public struct MagnifierRow: View {
  private let color: ThemeColor
  private let label: String
  private let size: String
  private let isHovered: Bool
  @Environment(\.theme) private var theme

  public init(color: ThemeColor, label: String, size: String, isHovered: Bool) {
    self.color = color
    self.label = label
    self.size = size
    self.isHovered = isHovered
  }

  public var body: some View {
    let metrics = theme.metrics.magnifier
    HStack(spacing: metrics.rowGap) {
      KindSwatch(color, size: .compact)
      Text(label).font(theme.type.small).lineLimit(1).truncationMode(.middle)
      Spacer(minLength: 0)
      Text(size).font(theme.type.smallMedium)
        .foregroundStyle(theme.text.secondary.color)
    }
    .foregroundStyle(theme.text.primary.color)
    .padding(.horizontal, metrics.rowPadding)
    .frame(height: metrics.rowHeight)
    .background {
      if isHovered {
        RoundedRectangle(cornerRadius: metrics.rowRadius).fill(theme.surface.selection.color)
      }
    }
  }
}
