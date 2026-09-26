public import CoreGraphics

extension Metrics {
  public var connect: Connect { Connect() }

  public struct Connect: Sendable, Hashable {
    public init() {}
    public let size = CGSize(width: 520, height: 460)
    public let padding: CGFloat = 16
    public let gap: CGFloat = 12
    public let noteGap: CGFloat = 4
  }
}
