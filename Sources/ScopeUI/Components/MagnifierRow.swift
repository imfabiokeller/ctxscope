internal import ScopeCore
public import SwiftUI

/// The words both magnifiers write.
public enum MagnifierWords {
  /// The line above a magnifier's rows: "blocks 812–833 of 1,284", counted
  /// from one.
  public static func window(_ range: Range<Int>, of count: Int) -> String {
    "blocks \(UIFormat.count(range.lowerBound + 1))–\(UIFormat.count(range.upperBound)) "
      + "of \(UIFormat.count(count))"
  }

  /// A magnifier's title: "Request 60", for a request index from zero.
  public static func request(_ index: Int) -> String {
    "Request \(UIFormat.count(RequestNumber.of(index)))"
  }

  /// What stands beside the title: "142.6k · $0.058", the context's size and
  /// what the request cost to send.
  public static func figures(tokens: Int, dollars: Double) -> String {
    "\(TokenFormat.short(tokens)) · \(TokenFormat.dollars(dollars))"
  }
}

/// A magnifier's heading, the same in both: the request, its figures, and
/// the line saying which blocks the rows are.
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

/// One block in a magnifier's list: its kind's swatch, its label and its
/// size, marked when it is the one under the pointer. The timeline's column
/// magnifier and the context strip's both list their blocks with it.
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
