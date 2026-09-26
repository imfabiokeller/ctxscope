public import ScopeCore

public struct SelectedText: Sendable, Hashable {
  public let segment: SegmentID
  public let text: String?

  public init(segment: SegmentID, text: String?) {
    self.segment = segment
    self.text = text
  }
}
