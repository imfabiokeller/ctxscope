public import CoreGraphics

/// Every size, gap and radius the window uses, by what it is for. A view
/// writes `theme.metrics.header.height`, never 52, so a change to a size is
/// a change here.
///
/// In points.
public struct Metrics: Sendable, Hashable {
  public static let standard = Metrics()

  /// One point: every border and rule.
  public let hairline: CGFloat = 1

  public let window = Window()
  public let header = Header()
  public let control = Control()
  public let segmented = Segmented()
  public let pill = Pill()
  public let search = Search()
  public let card = Card()
  public let table = Table()
  public let swatch = Swatch()
  public let list = DefinitionList()
  public let code = Code()
  public let badge: CGFloat = 16
  public let popover = Popover()
  public let menuBar = MenuBar()
  public let timeline = Timeline()
  public let magnifier = Magnifier()

  public struct Window: Sendable, Hashable {
    /// The window's size when it opens, and the snapshots' size.
    public let size = CGSize(width: 1440, height: 900)
    public let cornerRadius: CGFloat = 10
    public let sidebarWidth: CGFloat = 340
    /// The traffic lights, which only a snapshot draws.
    public let trafficLight: CGFloat = 12
    public let trafficLightGap: CGFloat = 8
  }

  public struct Header: Sendable, Hashable {
    public let height: CGFloat = 52
    /// The bar's inset from the window edges, and the gap between its items.
    public let padding: CGFloat = 16
    public let gap: CGFloat = 16
    /// Room left for the system's traffic lights.
    public let trafficLightReserve: CGFloat = 60
    /// The extra room before the view picker, which sets it apart from the
    /// two pop-up buttons that choose what it shows.
    public let pickerLeading: CGFloat = 24
  }

  public struct Control: Sendable, Hashable {
    /// A push button, a pop-up button and a stepper's arrows.
    public let height: CGFloat = 28
    /// The taller button beside a command in the popover.
    public let tallHeight: CGFloat = 30
    public let cornerRadius: CGFloat = 6
    public let buttonPadding: CGFloat = 12
    public let popUpPadding: CGFloat = 10
    /// Between the parts of a pop-up button's label.
    public let popUpGap: CGFloat = 8
    public let chevron: CGFloat = 10
    public let chevronStroke: CGFloat = 1.5
    public let stepperArrow: CGFloat = 12
    public let stepperArrowStroke: CGFloat = 1.6
    public let stepperGap: CGFloat = 4
    public let stepperLabelWidth: CGFloat = 120
    public let ellipsis: CGFloat = 12
    /// Between two buttons that stand side by side.
    public let buttonGap: CGFloat = 8
    public let focusRingWidth: CGFloat = 3
  }

  public struct Segmented: Sendable, Hashable {
    public let trackPadding: CGFloat = 2
    public let trackRadius: CGFloat = 7
    public let thumbRadius: CGFloat = 5
    /// The window's view picker.
    public let toolbarHeight: CGFloat = 24
    public let toolbarPadding: CGFloat = 14
    /// A filter above a table.
    public let filterHeight: CGFloat = 22
    public let filterPadding: CGFloat = 12
  }

  public struct Pill: Sendable, Hashable {
    public let height: CGFloat = 24
    public let padding: CGFloat = 10
    public let gap: CGFloat = 6
    public let dot: CGFloat = 7
    /// The popover's smaller dot and label.
    public let statusDot: CGFloat = 6
    public let statusGap: CGFloat = 5
  }

  public struct Search: Sendable, Hashable {
    public let width: CGFloat = 180
    public let height: CGFloat = 26
    public let glass: CGFloat = 12
    public let glassStroke: CGFloat = 1.5
    public let glassInset: CGFloat = 8
    /// Where the text starts, clear of the glass.
    public let textInset: CGFloat = 26
    public let trailingInset: CGFloat = 8
  }

  public struct Card: Sendable, Hashable {
    /// A summary card on the window.
    public let statPadding = Insets(vertical: 14, horizontal: 16)
    public let statRadius: CGFloat = 10
    public let statGap: CGFloat = 4
    /// A card in the sidebar, such as a cache break's.
    public let infoPadding = Insets(vertical: 12, horizontal: 14)
    public let infoRadius: CGFloat = 8
    public let infoGap: CGFloat = 5
    /// Between a card's badge, its place and its figure.
    public let infoHeaderGap: CGFloat = 8
    /// Between the cards of a row or a column.
    public let gap: CGFloat = 12
  }

  public struct Table: Sendable, Hashable {
    public let headerHeight: CGFloat = 28
    public let rowHeight: CGFloat = 30
    public let compactHeaderHeight: CGFloat = 26
    public let compactRowHeight: CGFloat = 28
    /// A row's inset from the table's edges, and the gap between its cells.
    public let cellPadding: CGFloat = 10
    public let columnGap: CGFloat = 12
    /// The fixed columns of the blocks table; the block's name takes the
    /// rest.
    public let blocks = BlockColumns()
    /// The fixed columns of the prompts table; the prompt takes the rest.
    public let prompts = PromptColumns()
  }

  public struct BlockColumns: Sendable, Hashable {
    public let kind: CGFloat = 104
    public let size: CGFloat = 80
    public let carried: CGFloat = 84
    public let used: CGFloat = 72
    public let cost: CGFloat = 96
  }

  public struct PromptColumns: Sendable, Hashable {
    public let number: CGFloat = 28
    public let requests: CGFloat = 90
    public let added: CGFloat = 110
    public let cost: CGFloat = 80
    public let breaks: CGFloat = 96
  }

  public struct Swatch: Sendable, Hashable {
    public let table: CGFloat = 8
    public let legend: CGFloat = 10
    public let compact: CGFloat = 7
    public let cornerRadius: CGFloat = 2
    /// From a swatch to its name, in a table, a legend and the popover.
    public let tableGap: CGFloat = 7
    public let legendGap: CGFloat = 6
    public let compactGap: CGFloat = 5
  }

  public struct DefinitionList: Sendable, Hashable {
    public let popoverRowGap: CGFloat = 9
    public let columnGap: CGFloat = 12
  }

  public struct Code: Sendable, Hashable {
    public let padding: CGFloat = 12
    public let cornerRadius: CGFloat = 8
    public let maxHeight: CGFloat = 250
    /// A command on its own line in the popover.
    public let inlinePadding = Insets(vertical: 7, horizontal: 10)
  }

  /// The Timeline page and its chart.
  public struct Timeline: Sendable, Hashable {
    /// The main column's inset, and the room between its two sections.
    public let padding = Insets(vertical: 22, horizontal: 28)
    public let sectionGap: CGFloat = 22
    /// Between the rows of the chart section.
    public let chartGap: CGFloat = 10
    /// The sidebar's inset and the room between its groups.
    public let sidebarPadding: CGFloat = 22
    public let sidebarGap: CGFloat = 22
    /// Between the lines of the selected prompt's detail.
    public let detailGap: CGFloat = 10
    /// Under the "By prompt" heading.
    public let headingGap: CGFloat = 8
    /// The axis labels' column left of the plot, and the gap after it.
    public let axisWidth: CGFloat = 36
    public let axisGap: CGFloat = 8
    /// The "cost" label's drop from the top of its row.
    public let costLabelInset: CGFloat = 2
    public let bandHeight: CGFloat = 26
    public let bandRadius: CGFloat = 4
    /// The least room either side of a band's number; a band with less shows
    /// none.
    public let bandLabelInset: CGFloat = 2
    /// Either side of the selected prompt's number on its chip, when its band
    /// is too narrow for it.
    public let bandChipInset: CGFloat = 6
    /// Either side of a badge's label when several breaks share it, and the
    /// least room between two badges.
    public let badgeInset: CGFloat = 5
    public let badgeGap: CGFloat = 2
    public let plotHeight: CGFloat = 280
    public let costHeight: CGFloat = 56
    public let costRadius: CGFloat = 1
    /// The shortest cost bar, so a cheap request still shows.
    public let costMinimum: CGFloat = 2
    /// Between two columns, and the most of a column's pitch a gap may take
    /// when there are too many columns for the full gap.
    public let columnGap: CGFloat = 2
    public let columnGapShare: CGFloat = 0.18
    /// The rule between two blocks of a column.
    public let blockGap: CGFloat = 0.5
    /// The shortest block, in device pixels as a 2x display draws it, that a
    /// rule is drawn beside. A rule between two short blocks tells nobody
    /// anything, and hundreds of them line up across the columns as stripes.
    public let blockGapMinimumPixels: CGFloat = 12

    /// Whether the rule between two neighbouring blocks, `below` and `above`
    /// pixels tall, is drawn: only where both are tall enough to be read as
    /// blocks of their own.
    public func separates(below: CGFloat, above: CGFloat) -> Bool {
      min(below, above) >= blockGapMinimumPixels
    }
    /// A cache break's dashed line: its width, dash and gap, how far it rises
    /// above the plot, and how far above the plot its badge sits.
    public let markerWidth: CGFloat = 1.5
    public let markerDash: CGFloat = 3
    public let markerDashGap: CGFloat = 1.5
    public let markerOverhang: CGFloat = 4
    public let badgeRise: CGFloat = 12
    /// The dashed line in the legend.
    public let legendMarkerHeight: CGFloat = 12
    /// Rows of one line of text, set to the heights in `Typography.lines`
    /// rather than SwiftUI's, which are a point taller. A heading alone; the
    /// chart's heading, whose legend shares its baseline; and the request
    /// numbers under the chart.
    public let headingHeight: CGFloat = 15
    public let legendHeight: CGFloat = 15.5
    public let axisLineHeight: CGFloat = 11.5
  }

  /// The magnifier over a hovered column: the column at height beside a
  /// window of its blocks.
  public struct Magnifier: Sendable, Hashable {
    public let width: CGFloat = 340
    public let padding = Insets(vertical: 10, horizontal: 12)
    public let cornerRadius: CGFloat = 10
    public let columnWidth: CGFloat = 30
    public let columnHeight: CGFloat = 352
    public let columnRadius: CGFloat = 3
    /// Between the column and the rows.
    public let gap: CGFloat = 10
    /// Between a row's swatch, label and size.
    public let rowGap: CGFloat = 8
    public let rows = 22
    public let rowHeight: CGFloat = 16
    public let rowPadding: CGFloat = 6
    public let rowRadius: CGFloat = 4
    /// Under the title, and under the line below it.
    public let titleGap: CGFloat = 2
    public let subtitleGap: CGFloat = 8
    /// From the pointer to the magnifier's near edge.
    public let offset: CGFloat = 16
  }

  /// Vertical and horizontal padding.
  public struct Insets: Sendable, Hashable {
    public let vertical: CGFloat
    public let horizontal: CGFloat
  }

  /// Padding whose top and bottom differ: "14px 16px 12px".
  public struct Edges: Sendable, Hashable {
    public let top: CGFloat
    public let horizontal: CGFloat
    public let bottom: CGFloat
  }
}
