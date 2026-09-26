public import CoreGraphics

extension Metrics {
  public var tile: Tile { Tile() }

  public struct Tile: Sendable, Hashable {
    public init() {}
    public let padding = Insets(vertical: 10, horizontal: 12)
    public let radius: CGFloat = 8
    public let gap: CGFloat = 8
    public let labelGap: CGFloat = 3
    public let detailGap: CGFloat = 1
    public let valueGap: CGFloat = 8
    public let chipHeight: CGFloat = 22
    public let chipInset: CGFloat = 8
    public let headerGap: CGFloat = 8
    public let promptLines = 3
  }
}
