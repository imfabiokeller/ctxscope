/// The smallest addressable piece of a request: one system block, one tool
/// schema, one memory file, one message content block, one tool result.

public struct SegmentID: Hashable, Sendable, Codable, Comparable {
  public let rawValue: Int

  public init(_ rawValue: Int) {
    self.rawValue = rawValue
  }

  public static func < (lhs: SegmentID, rhs: SegmentID) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// Content classes the estimator fits separate rates for.
public enum ContentClass: String, Sendable, Codable, CaseIterable {
  case prose
  case code
  case json
  /// Base64 payload of an inline image. Its characters say almost nothing
  /// about its tokens, so it gets its own rate.
  case image
}

/// Why a segment left the context, and therefore how much the claim that it
/// left is worth.
public enum DeathCause: String, Sendable, Codable, CaseIterable {
  /// Its entry left the parent chain: a rewind, or an edited prompt.
  case chain
  /// A compaction the harness recorded.
  case compaction
  /// Nothing in the transcript says it left. The measured total does, so
  /// which segments went is a hypothesis, not an observation.
  case inferred

  public var grade: Grade {
    switch self {
    case .chain, .compaction: .derived
    case .inferred: .estimated
    }
  }
}

public struct Segment: Sendable, Identifiable, Codable, Hashable {
  /// The smallest size a block with content can be given. A segment at the
  /// floor is one the measured delta could not pay for, not one that is
  /// genuinely that small.
  public static let floor = 1

  public let id: SegmentID
  public let band: Band
  /// Short, neutral name for the UI. Never the content itself.
  public let label: String
  /// Size in the prompt, fixed when the segment enters the context.
  public var tokens: Tokens
  public let characters: Int
  public let contentClass: ContentClass
  /// Request index where the segment entered the context.
  public let born: Int
  /// Request index where it left, exclusive. `nil` means it is still there at
  /// the end of the recording.
  public var died: Int?
  /// Why it left, and with what confidence.
  public var deathCause: DeathCause?
  /// Hash of the content, for duplication. Never the content.
  public let contentHash: UInt64
  /// For content the model produced: the request whose output carried it.
  public let originRequest: Int?

  public init(
    id: SegmentID,
    band: Band,
    label: String,
    tokens: Tokens,
    characters: Int,
    contentClass: ContentClass,
    born: Int,
    died: Int? = nil,
    deathCause: DeathCause? = nil,
    contentHash: UInt64,
    originRequest: Int? = nil
  ) {
    self.id = id
    self.band = band
    self.label = label
    self.tokens = tokens
    self.characters = characters
    self.contentClass = contentClass
    self.born = born
    self.died = died
    self.deathCause = deathCause
    self.contentHash = contentHash
    self.originRequest = originRequest
  }

  public var family: Family { BandRegistry.family(of: band) }
  /// The kind the block is shown as. Nil for unattributed tokens.
  public var kind: Kind? { BandRegistry.kind(of: band) }
  public var source: Source { BandRegistry.source(of: band) }
  public var isAssessable: Bool { BandRegistry.isAssessable(band) }

  public func isLive(at request: Int) -> Bool {
    born <= request && request < (died ?? Int.max)
  }
}
