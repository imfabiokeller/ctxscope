public import ScopeCore

/// The selected block's recorded text, read from the transcript off the main
/// actor when the selection changes. Nil text is a block the transcript
/// recorded no text for, or one whose text has not arrived yet.
public struct SelectedText: Sendable, Hashable {
  public let segment: SegmentID
  public let text: String?

  public init(segment: SegmentID, text: String?) {
    self.segment = segment
    self.text = text
  }
}
