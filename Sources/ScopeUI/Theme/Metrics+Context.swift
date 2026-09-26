public import CoreGraphics

/// The sizes of the Context page: its padding and the strip of every block,
/// with where its magnifier hangs.
extension Metrics {
  public var contextPage: ContextPage { ContextPage() }
  public var strip: Strip { Strip() }

  public struct ContextPage: Sendable, Hashable {
    public init() {}
    /// The main column's inset, and the gap between its three sections.
    public let padding = Insets(vertical: 24, horizontal: 28)
    public let sectionGap: CGFloat = 28
    /// The sidebar's inset, the gap between its groups, and the smaller gaps
    /// inside its title and its text.
    public let sidebarPadding = Insets(vertical: 24, horizontal: 22)
    public let sidebarGap: CGFloat = 20
    public let titleGap: CGFloat = 6
    public let textGap: CGFloat = 8
    /// Between the Blocks line and its table.
    public let blocksHeaderGap: CGFloat = 10
  }

  public struct Strip: Sendable, Hashable {
    public init() {}
    /// Between the section's line, the marks, the strip and the legend.
    public let gap: CGFloat = 10
    /// The row the two marks stand in, and the inset of their labels.
    public let markHeight: CGFloat = 22
    public let markLabelInset: CGFloat = 6
    /// The least room between the two marks' labels when one is moved past
    /// the other.
    public let markLabelGap: CGFloat = 12
    public let height: CGFloat = 40
    public let cornerRadius: CGFloat = 6
    /// A slice narrower than this is drawn without the rule after it, which
    /// would otherwise cover most of it.
    public let minimumGapped: CGFloat = 1.5
    /// The selected block's outline.
    public let selectionStroke: CGFloat = 2
    public let selectionRadius: CGFloat = 3
    public let selectionMinWidth: CGFloat = 3
    /// Between the kinds of the legend.
    public let legendGap: CGFloat = 22
    /// The magnifier hangs this far below the strip. The rest of its sizes
    /// are the timeline's magnifier's, `Metrics.magnifier`.
    public let magnifierOffset: CGFloat = 6
    /// The enlarged part of the strip across the magnifier's top.
    public let lensHeight: CGFloat = 24
  }
}
