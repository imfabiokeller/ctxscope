public import CoreGraphics

extension Metrics {
  /// The menu bar popover's panel and everything in it.
  public struct Popover: Sendable, Hashable {
    public let width: CGFloat = 360
    public let cornerRadius: CGFloat = 12
    /// The footer's inset when it holds buttons, and when it holds text.
    public let footerButtons = Insets(vertical: 10, horizontal: 12)
    public let footerText = Insets(vertical: 10, horizontal: 16)
    /// Below the menu bar, from its bottom edge to the panel's top.
    public let gap: CGFloat = 8
    /// The least room kept between the panel and the edges of the screen.
    public let screenInset: CGFloat = 8

    /// The session's name, its lane and its status, and the line under them.
    public let titlePadding = Edges(top: 14, horizontal: 16, bottom: 12)
    public let titleGap: CGFloat = 3
    public let titleRowGap: CGFloat = 8
    /// The size, its meter and the legend under it.
    public let sizePadding = Edges(top: 4, horizontal: 16, bottom: 16)
    public let sizeGap: CGFloat = 8
    public let figureGap: CGFloat = 6
    public let meterHeight: CGFloat = 10
    public let meterRadius: CGFloat = 3
    public let legendColumns = 3
    public let legendRowGap: CGFloat = 3
    public let legendColumnGap: CGFloat = 8
    /// The figures, the last cache break and the chart, each in a section
    /// of its own.
    public let section = Insets(vertical: 12, horizontal: 16)
    public let breakGap: CGFloat = 4
    public let sparkGap: CGFloat = 6
    public let sparkHeight: CGFloat = 40
    /// Between two bars of the chart, and the narrowest a bar may be before
    /// requests share one.
    public let sparkBarGap: CGFloat = 1
    public let sparkMinBar: CGFloat = 1

    /// The panel shown when no session is in focus.
    public let emptyPadding = Edges(top: 22, horizontal: 18, bottom: 18)
    public let emptyGap: CGFloat = 8
    public let listPadding = Insets(vertical: 10, horizontal: 8)
    public let listHeader = Edges(top: 0, horizontal: 10, bottom: 6)
    public let rowHeight: CGFloat = 44
    public let rowPadding: CGFloat = 10
    public let rowGap: CGFloat = 10
    public let rowTextGap: CGFloat = 1

    /// How many bars the chart can hold at one request each: the room there
    /// is, at the narrowest bar and one gap apart.
    public var sparkCapacity: Int {
      Int((width - 2 * section.horizontal + sparkBarGap) / (sparkMinBar + sparkBarGap))
    }
  }

  /// The menu bar and the item in it. The system draws both in the app;
  /// only the snapshots do, so a picture of the item shows it on a bar.
  public struct MenuBar: Sendable, Hashable {
    public let height: CGFloat = 26
    /// The item's box, and its inset either side of what is inside it.
    public let itemHeight: CGFloat = 22
    public let itemPadding: CGFloat = 7
    /// Between the mark and the number.
    public let itemGap: CGFloat = 5
  }
}
