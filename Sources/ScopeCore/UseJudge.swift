/// Referenced share, what the UI calls used. One protocol, several implementations:
/// lexical overlap is the local default, a cloud judge and ablation come
/// later and answer the same question.

/// Everything about a judge that changes its answer. The report carries it, so
/// a number can never be compared against one produced a different way.
public struct JudgeMethod: Sendable, Codable, Hashable {
  public let name: String
  public let version: Int
  /// Words per shingle.
  public let shingleWidth: Int
  /// How many shingles are kept per segment, and per consumer. `nil` means
  /// everything.
  public let segmentShingleCap: Int?
  public let consumerShingleCap: Int?
  /// How boilerplate is kept out of the score.
  public let boilerplateRule: String

  public init(
    name: String,
    version: Int,
    shingleWidth: Int,
    segmentShingleCap: Int?,
    consumerShingleCap: Int?,
    boilerplateRule: String
  ) {
    self.name = name
    self.version = version
    self.shingleWidth = shingleWidth
    self.segmentShingleCap = segmentShingleCap
    self.consumerShingleCap = consumerShingleCap
    self.boilerplateRule = boilerplateRule
  }

  public var summary: String {
    "\(name) v\(version), \(shingleWidth)-word shingles, "
      + "segment cap \(segmentShingleCap.map(String.init) ?? "none"), "
      + "consumer cap \(consumerShingleCap.map(String.init) ?? "none"), "
      + boilerplateRule
  }
}

/// What was reused of one segment.
public struct ReferenceFinding: Sendable, Codable, Hashable {
  public let segment: SegmentID
  /// False when reuse cannot be observed at all: rules, schemas, anything the
  /// transcript never shows. Such a segment is not unreferenced, it is not
  /// assessable.
  public let isAssessable: Bool
  /// Share of the segment's tokens that later output or tool inputs reuse.
  /// `nil` when not assessable.
  public let referencedShare: Double?
  /// The requests at which something of this segment was reused for the first
  /// time, in order. A request that quotes the same words again is not more
  /// reuse and does not appear.
  public let referenceRequests: [Int]
  /// How much of the segment had been reused by the end of each of those
  /// requests, as a running count of k-grams. Parallel to `referenceRequests`,
  /// and non-decreasing.
  ///
  /// This is what lets a view say how referenced a segment was at a request
  /// using only what had happened by then. Without it the only honest answer
  /// at any request was the share at the end of the lane, which is the future.
  public let matchedCounts: [Int]
  /// The k-grams the share is measured against, after boilerplate is dropped.
  /// Zero when the segment is not assessable.
  public let assessedShingles: Int

  public init(
    segment: SegmentID,
    isAssessable: Bool,
    referencedShare: Double?,
    referenceRequests: [Int],
    matchedCounts: [Int] = [],
    assessedShingles: Int = 0
  ) {
    self.segment = segment
    self.isAssessable = isAssessable
    self.referencedShare = referencedShare
    self.referenceRequests = referenceRequests
    self.matchedCounts = matchedCounts
    self.assessedShingles = assessedShingles
  }

  /// How much of the segment had been reused by the end of `request`, as a
  /// share. Monotone, and a function of the past only.
  public func share(at request: Int) -> Double? {
    guard isAssessable, assessedShingles > 0 else { return nil }
    var matched = 0
    for (slot, reference) in referenceRequests.enumerated() where reference <= request {
      matched = matchedCounts.indices.contains(slot) ? matchedCounts[slot] : matched
    }
    return Double(matched) / Double(assessedShingles)
  }

  public var firstReference: Int? { referenceRequests.first }
}

public struct ReferenceReport: Sendable, Codable {
  public let method: JudgeMethod
  public let findings: [ReferenceFinding]
  /// The boilerplate cutoff these findings were worked out with. It is the one
  /// thing that can change a share that was already settled, because it
  /// changes the denominator, so anything that caches a drawing of them has to
  /// notice when it moves.
  public let cutoff: Int

  public init(method: JudgeMethod, findings: [ReferenceFinding], cutoff: Int = 0) {
    self.method = method
    self.findings = findings
    self.cutoff = cutoff
  }

  /// Findings by segment, built once instead of searched linearly per lookup.
  public func bySegment() -> [SegmentID: ReferenceFinding] {
    var result: [SegmentID: ReferenceFinding] = [:]
    result.reserveCapacity(findings.count)
    for finding in findings { result[finding.segment] = finding }
    return result
  }
}

/// What a segment looks like to a judge: hashes, never text.
public struct JudgedSegment: Sendable {
  public let id: SegmentID
  public let born: Int
  public let isAssessable: Bool
  /// False for what the model wrote: its own text, its thinking, its tool
  /// calls. Only input-side segments count towards the boilerplate frequency,
  /// because a model quoting a file it read is the reuse being measured, not
  /// evidence that the quote is boilerplate.
  public let isInput: Bool
  public let shingles: [UInt64]

  public init(
    id: SegmentID,
    born: Int,
    isAssessable: Bool,
    isInput: Bool = true,
    shingles: [UInt64]
  ) {
    self.id = id
    self.born = born
    self.isAssessable = isAssessable
    self.isInput = isInput
    self.shingles = shingles
  }
}

/// Everything the model wrote at one request: text, thinking, and tool call
/// inputs. These are the consumers a segment can be referenced by.
public struct JudgedConsumer: Sendable {
  public let request: Int
  public let shingles: [UInt64]

  public init(request: Int, shingles: [UInt64]) {
    self.request = request
    self.shingles = shingles
  }
}

public struct JudgeInput: Sendable {
  public var segments: [JudgedSegment]
  public var consumers: [JudgedConsumer]

  public init(segments: [JudgedSegment] = [], consumers: [JudgedConsumer] = []) {
    self.segments = segments
    self.consumers = consumers
  }
}

/// A judge is fed, never handed a whole session.
///
/// A cloud judge may only ever see new output, and a 1M token window makes
/// the same demand of the local one: the work per request
/// has to be proportional to that request, not to the session so far. So this
/// is an append interface and a report, not a batch call.
public protocol UseJudge: Sendable {
  var method: JudgeMethod { get }
  /// A segment that just entered the context.
  mutating func add(segment: JudgedSegment)
  /// What the model wrote at one request. Only ever new output.
  mutating func add(consumer: JudgedConsumer)
  /// The findings as they stand. Mutating, because a judge is expected to
  /// keep what it has already worked out rather than do it again.
  mutating func report() -> ReferenceReport
}

extension UseJudge {
  /// Feeds a whole input at once, for callers that already have one.
  public mutating func add(_ input: JudgeInput) {
    for segment in input.segments { add(segment: segment) }
    for consumer in input.consumers { add(consumer: consumer) }
  }
}
