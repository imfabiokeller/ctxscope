public import ScopeCore

/// The text one segment was built from, for the sidebar's text box.
///
/// It is read back out of the transcript on demand rather than held, so a
/// session that is open costs its structure and not its bytes. It is also the
/// text the judge shingled, so what is shown is what was judged.
public struct SegmentContent: Sendable, Hashable {
  public let segment: SegmentID
  public let band: Band
  /// The short neutral name, the same one the segment carries.
  public let label: String
  public let text: String

  public init(segment: SegmentID, band: Band, label: String, text: String) {
    self.segment = segment
    self.band = band
    self.label = label
    self.text = text
  }
}
