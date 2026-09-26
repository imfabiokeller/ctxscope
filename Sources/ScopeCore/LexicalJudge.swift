public struct LexicalJudge: UseJudge {
  public static let boilerplateShare = 0.02
  public static let boilerplateFloor = 5

  public let method: JudgeMethod

  private var segments: [JudgedSegment] = []
  private var index: [UInt64: [Int]] = [:]
  private var inputFrequency: [UInt64: Int] = [:]
  private var inputSegments = 0
  private var matched: [[UInt64: Int]] = []
  private var references: [[Int]] = []
  private var findings: [ReferenceFinding] = []
  private var dirty: Set<Int> = []
  private var computedCutoff = -1

  public init(
    segmentShingleCap: Int? = nil,
    consumerShingleCap: Int? = nil,
    shingleWidth: Int = Shingler.width
  ) {
    method = JudgeMethod(
      name: "lexical-overlap",
      version: 2,
      shingleWidth: shingleWidth,
      segmentShingleCap: segmentShingleCap,
      consumerShingleCap: consumerShingleCap,
      boilerplateRule:
        "shingles in more than \(Int(Self.boilerplateShare * 100)) percent of input-side "
        + "segments dropped, never fewer than \(Self.boilerplateFloor)"
    )
  }

  public mutating func add(segment: JudgedSegment) {
    let slot = segments.count
    segments.append(segment)
    matched.append([:])
    references.append([])
    findings.append(Self.notAssessable(segment.id))
    dirty.insert(slot)
    guard segment.isAssessable else { return }
    if segment.isInput { inputSegments += 1 }
    let cutoff = boilerplateCutoff()
    for shingle in Set(segment.shingles) {
      index[shingle, default: []].append(slot)
      guard segment.isInput else { continue }
      let frequency = (inputFrequency[shingle] ?? 0) + 1
      inputFrequency[shingle] = frequency
      // A shingle that just became boilerplate changes every segment carrying it.
      if frequency == cutoff + 1 { dirty.formUnion(index[shingle] ?? []) }
    }
  }

  public mutating func add(consumer: JudgedConsumer) {
    for shingle in Set(consumer.shingles) {
      guard let slots = index[shingle] else { continue }
      for slot in slots {
        // `>=` on purpose: own output is born a request later, so nothing matches itself.
        guard consumer.request >= segments[slot].born else { continue }
        if matched[slot][shingle] == nil { matched[slot][shingle] = consumer.request }
        dirty.insert(slot)
        if references[slot].last != consumer.request {
          references[slot].append(consumer.request)
        }
      }
    }
  }

  public mutating func report() -> ReferenceReport {
    let cutoff = boilerplateCutoff()
    if cutoff != computedCutoff {
      computedCutoff = cutoff
      findings = segments.indices.map { finding(at: $0, cutoff: cutoff) }
    } else {
      for slot in dirty { findings[slot] = finding(at: slot, cutoff: cutoff) }
    }
    dirty.removeAll(keepingCapacity: true)
    return ReferenceReport(method: method, findings: findings, cutoff: cutoff)
  }

  private func finding(at slot: Int, cutoff: Int) -> ReferenceFinding {
    let segment = segments[slot]
    guard segment.isAssessable, !segment.shingles.isEmpty else {
      return Self.notAssessable(segment.id)
    }
    var total = 0
    var hits = 0
    var firstMatch: [Int: Int] = [:]
    for shingle in segment.shingles {
      guard (inputFrequency[shingle] ?? 0) <= cutoff else { continue }
      total += 1
      guard let request = matched[slot][shingle] else { continue }
      hits += 1
      firstMatch[request, default: 0] += 1
    }
    // Only boilerplate: nothing tells reuse from repetition, so not assessable rather than zero.
    guard total > 0 else { return Self.notAssessable(segment.id) }
    var requests: [Int] = []
    var counts: [Int] = []
    var running = 0
    for request in firstMatch.keys.sorted() {
      running += firstMatch[request] ?? 0
      requests.append(request)
      counts.append(running)
    }
    return ReferenceFinding(
      segment: segment.id,
      isAssessable: true,
      referencedShare: Double(hits) / Double(total),
      referenceRequests: requests,
      matchedCounts: counts,
      assessedShingles: total
    )
  }

  private static func notAssessable(_ id: SegmentID) -> ReferenceFinding {
    ReferenceFinding(
      segment: id, isAssessable: false, referencedShare: nil, referenceRequests: [])
  }

  private func boilerplateCutoff() -> Int {
    max(Self.boilerplateFloor, Int(Double(inputSegments) * Self.boilerplateShare))
  }
}
