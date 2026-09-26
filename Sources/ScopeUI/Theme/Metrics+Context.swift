public import CoreGraphics

extension Metrics {
  public var contextPage: ContextPage { ContextPage() }
  public var strip: Strip { Strip() }

  public struct ContextPage: Sendable, Hashable {
    public init() {}
    public let padding = Insets(vertical: 24, horizontal: 28)
    public let sectionGap: CGFloat = 28
    public let sidebarPadding = Insets(vertical: 24, horizontal: 22)
    public let sidebarGap: CGFloat = 20
    public let titleGap: CGFloat = 6
    public let textGap: CGFloat = 8
    public let blocksHeaderGap: CGFloat = 10
  }

  public struct Strip: Sendable, Hashable {
    public init() {}
    public let gap: CGFloat = 10
    public let markHeight: CGFloat = 22
    public let markLabelInset: CGFloat = 6
    public let markLabelGap: CGFloat = 12
    public let height: CGFloat = 40
    public let cornerRadius: CGFloat = 6
    // Narrower slices skip the rule after them, which would cover most of the slice.
    public let minimumGapped: CGFloat = 1.5
    public let selectionStroke: CGFloat = 2
    public let selectionRadius: CGFloat = 3
    public let selectionMinWidth: CGFloat = 3
    public let legendGap: CGFloat = 22
    public let magnifierOffset: CGFloat = 6
    public let lensHeight: CGFloat = 24
  }
}
