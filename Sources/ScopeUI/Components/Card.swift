public import SwiftUI

/// A bordered box that groups what belongs together.
public struct Card<Content: View>: View {
  public enum Style: Sendable {
    /// A summary card on the window: a border, no face of its own, the
    /// larger radius.
    case outlined
    /// A card in the sidebar, such as a cache break's: a raised face.
    case raised
  }

  private let style: Style
  private let fillsHeight: Bool
  private let content: Content
  @Environment(\.theme) private var theme

  /// `fillsHeight` stretches the card to the height it is offered, the way
  /// the cards of one row all take the height of the tallest.
  public init(
    _ style: Style = .raised, fillsHeight: Bool = false, @ViewBuilder content: () -> Content
  ) {
    self.style = style
    self.fillsHeight = fillsHeight
    self.content = content()
  }

  public var body: some View {
    let card = theme.metrics.card
    let shape = RoundedRectangle(
      cornerRadius: style == .outlined ? card.statRadius : card.infoRadius)
    VStack(alignment: .leading, spacing: style == .outlined ? card.statGap : card.infoGap) {
      content
    }
    .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
    .padding(style == .outlined ? card.statPadding : card.infoPadding)
    // The padding is inside the border.
    .padding(theme.metrics.hairline)
    .background {
      if style == .raised {
        shape.fill(theme.surface.raised.color)
      }
    }
    .overlay {
      shape.strokeBorder(theme.line.card.color, lineWidth: theme.metrics.hairline)
    }
  }
}

/// One of the summary cards: what it counts, the figure, and a line that
/// says what the figure is made of.
public struct StatCard: View {
  private let label: String
  private let figure: String
  private let unit: String?
  private let detail: String
  private let fillsHeight: Bool
  @Environment(\.theme) private var theme

  /// `fillsHeight` is the card's: set it on a row of cards that should all
  /// be as tall as the tallest.
  public init(
    label: String, figure: String, unit: String? = nil, detail: String, fillsHeight: Bool = false
  ) {
    self.label = label
    self.figure = figure
    self.unit = unit
    self.detail = detail
    self.fillsHeight = fillsHeight
  }

  public var body: some View {
    let type = theme.type
    let secondary = theme.text.secondary.color
    Card(.outlined, fillsHeight: fillsHeight) {
      Text(label).font(type.caption).foregroundStyle(secondary).line(type.lines.caption)
      figureLine.tracking(type.figureTracking)
        .foregroundStyle(theme.text.primary.color)
        .lineLimit(1)
      // The detail can wrap, so it cannot be framed to one line's height;
      // the card gives the point back below it instead.
      Text(detail).font(type.caption).foregroundStyle(secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, -type.captionExcess)
    }
    .accessibilityElement(children: .combine)
  }

  /// The figure and its unit as one run of text, so they share a baseline.
  private var figureLine: Text {
    let figure = Text(self.figure + (unit == nil ? "" : " ")).font(theme.type.figure)
    guard let unit else { return figure }
    let note = Text(unit).font(theme.type.figureUnit)
      .foregroundStyle(theme.text.secondary.color)
    return Text("\(figure)\(note)")
  }
}

/// A number in a small dark circle, which ties a mark on a chart to the card
/// that explains it.
public struct NumberBadge: View {
  private let label: String
  private let width: CGFloat?
  @Environment(\.theme) private var theme

  public init(_ number: Int) {
    label = UIFormat.count(number)
    width = nil
  }

  /// A badge several numbers share, "3–4", as wide as `width`: a circle
  /// stretched into a capsule.
  public init(_ label: String, width: CGFloat) {
    self.label = label
    self.width = width
  }

  public var body: some View {
    Text(label)
      .font(theme.type.badge)
      .foregroundStyle(theme.status.onBadge.color)
      .frame(width: width ?? theme.metrics.badge, height: theme.metrics.badge)
      .background {
        // A circle where the badge is round, which Core Graphics edges
        // differently from a capsule of the same size.
        if (width ?? theme.metrics.badge) > theme.metrics.badge {
          Capsule().fill(theme.status.badge.color)
        } else {
          Circle().fill(theme.status.badge.color)
        }
      }
  }
}

#Preview {
  VStack(alignment: .leading, spacing: 12) {
    StatCard(
      label: "Context", figure: "142.6k", unit: "of 200k",
      detail: "71% full · +3.7k this request")
    Card {
      HStack {
        NumberBadge(1)
        Text("Request 23 · prompt 4")
      }
    }
  }
  .frame(width: 340)
  .padding()
  .environment(\.theme, Theme.preview)
}
