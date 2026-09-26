public import ScopeCapture
public import ScopeCore

/// What a block is called wherever the window names one: its tool and what
/// it did, "Read · src/api/client.ts", when the transcript says, and its
/// label otherwise.
///
/// The details are transcript text read back off the main actor by
/// `SessionHost.blockDetails`. They are shown and never kept anywhere else.
public struct BlockNames: Sendable, Equatable {
  public let details: [SegmentID: BlockDetail]

  public init(_ details: [SegmentID: BlockDetail] = [:]) {
    self.details = details
  }

  /// "Bash · npm test", or the block's label when nothing more is known.
  public func name(of segment: Segment) -> String {
    guard let detail = details[segment.id] else { return segment.label }
    return "\(detail.head) · \(detail.detail)"
  }
}
