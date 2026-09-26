public import ScopeCapture
public import ScopeCore

// Transcript text: shown, never stored anywhere else.
public struct BlockNames: Sendable, Equatable {
  public let details: [SegmentID: BlockDetail]

  public init(_ details: [SegmentID: BlockDetail] = [:]) {
    self.details = details
  }

  public func name(of segment: Segment) -> String {
    guard let detail = details[segment.id] else { return segment.label }
    return "\(detail.head) · \(detail.detail)"
  }
}
