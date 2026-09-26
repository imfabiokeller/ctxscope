public struct JudgeMethod: Sendable, Codable, Hashable {
  public let name: String
  public let version: Int
  public let shingleWidth: Int
  public let segmentShingleCap: Int?
  public let consumerShingleCap: Int?
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

public struct ReferenceFinding: Sendable, Codable, Hashable {
  public let segment: SegmentID
  public let isAssessable: Bool
  public let referencedShare: Double?
  public let referenceRequests: [Int]
  /// Parallel to `referenceRequests`, running and non-decreasing.
  public let matchedCounts: [Int]
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
  /// Changes the denominator of settled shares, so a cached drawing must notice when it moves.
  public let cutoff: Int

  public init(method: JudgeMethod, findings: [ReferenceFinding], cutoff: Int = 0) {
    self.method = method
    self.findings = findings
    self.cutoff = cutoff
  }

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
  /// Only input-side segments count towards boilerplate: a quoted file is the reuse measured.
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

/// A cloud judge may only ever see new output, so judges are fed incrementally.
public protocol UseJudge: Sendable {
  var method: JudgeMethod { get }
  mutating func add(segment: JudgedSegment)
  mutating func add(consumer: JudgedConsumer)
  mutating func report() -> ReferenceReport
}

extension UseJudge {
  public mutating func add(_ input: JudgeInput) {
    for segment in input.segments { add(segment: segment) }
    for consumer in input.consumers { add(consumer: consumer) }
  }
}
