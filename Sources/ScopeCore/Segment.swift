public struct SegmentID: Hashable, Sendable, Codable, Comparable {
  public let rawValue: Int

  public init(_ rawValue: Int) {
    self.rawValue = rawValue
  }

  public static func < (lhs: SegmentID, rhs: SegmentID) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public enum ContentClass: String, Sendable, Codable, CaseIterable {
  case prose
  case code
  case json
  case image
}

public enum DeathCause: String, Sendable, Codable, CaseIterable {
  case chain
  case compaction
  case inferred

  public var grade: Grade {
    switch self {
    case .chain, .compaction: .derived
    case .inferred: .estimated
    }
  }
}

public struct Segment: Sendable, Identifiable, Codable, Hashable {
  public static let floor = 1

  public let id: SegmentID
  public let band: Band
  /// Short, neutral name for the UI. Never the content itself.
  public let label: String
  public var tokens: Tokens
  public let characters: Int
  public let contentClass: ContentClass
  public let born: Int
  public var died: Int?
  public var deathCause: DeathCause?
  public let contentHash: UInt64
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
  public var kind: Kind? { BandRegistry.kind(of: band) }
  public var source: Source { BandRegistry.source(of: band) }
  public var isAssessable: Bool { BandRegistry.isAssessable(band) }

  public func isLive(at request: Int) -> Bool {
    born <= request && request < (died ?? Int.max)
  }
}
