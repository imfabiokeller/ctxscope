public import ScopeCore

public struct SegmentContent: Sendable, Hashable {
  public let segment: SegmentID
  public let band: Band
  public let label: String
  public let text: String

  public init(segment: SegmentID, band: Band, label: String, text: String) {
    self.segment = segment
    self.band = band
    self.label = label
    self.text = text
  }
}
