public import CoreGraphics

extension Metrics {
  public struct Popover: Sendable, Hashable {
    public let width: CGFloat = 360
    public let cornerRadius: CGFloat = 12
    public let footerButtons = Insets(vertical: 10, horizontal: 12)
    public let footerText = Insets(vertical: 10, horizontal: 16)
    public let gap: CGFloat = 8
    public let screenInset: CGFloat = 8

    public let titlePadding = Edges(top: 14, horizontal: 16, bottom: 12)
    public let titleGap: CGFloat = 3
    public let titleRowGap: CGFloat = 8
    public let sizePadding = Edges(top: 4, horizontal: 16, bottom: 16)
    public let sizeGap: CGFloat = 8
    public let figureGap: CGFloat = 6
    public let meterHeight: CGFloat = 10
    public let meterRadius: CGFloat = 3
    public let legendColumns = 3
    public let legendRowGap: CGFloat = 3
    public let legendColumnGap: CGFloat = 8
    public let section = Insets(vertical: 12, horizontal: 16)
    public let breakGap: CGFloat = 4
    public let sparkGap: CGFloat = 6
    public let sparkHeight: CGFloat = 40
    public let sparkBarGap: CGFloat = 1
    public let sparkMinBar: CGFloat = 1

    public let emptyPadding = Edges(top: 22, horizontal: 18, bottom: 18)
    public let emptyGap: CGFloat = 8
    public let listPadding = Insets(vertical: 10, horizontal: 8)
    public let listHeader = Edges(top: 0, horizontal: 10, bottom: 6)
    public let rowHeight: CGFloat = 44
    public let rowPadding: CGFloat = 10
    public let rowGap: CGFloat = 10
    public let rowTextGap: CGFloat = 1

    public var sparkCapacity: Int {
      Int((width - 2 * section.horizontal + sparkBarGap) / (sparkMinBar + sparkBarGap))
    }
  }

  // Only the snapshots draw the menu bar; in the app the system draws it.
  public struct MenuBar: Sendable, Hashable {
    public let height: CGFloat = 26
    public let itemHeight: CGFloat = 22
    public let itemPadding: CGFloat = 7
    public let itemGap: CGFloat = 5
  }
}
