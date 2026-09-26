/// Span-level overlap between a segment and everything the model wrote after
/// it entered the context.
///
/// Incremental and indexed, never pairwise. A segment is indexed by its
/// shingles when it arrives; a consumer looks its own shingles up in that
/// index and marks the segments it hits. The work per request is proportional
/// to the output of that request, which is what a 1M token window needs.
public struct LexicalJudge: UseJudge {
  /// A shingle that occurs in more than this share of the input-side segments
  /// is boilerplate: a path prefix, a command head, a line of framing every
  /// tool result carries. It matches everything, so it says nothing about
  /// reuse.
  ///
  /// The frequency is counted over input-side segments only. Counting the
  /// model's own output in it made every genuine reuse raise the frequency of
  /// the shingle it matched, so in a lane of a hundred segments content quoted
  /// once was already at the cutoff and was dropped as boilerplate.
  public static let boilerplateShare = 0.02
  /// The smallest a cutoff can be. A shingle in five separate inputs is
  /// common; a shingle in two is a quotation.
  public static let boilerplateFloor = 5

  public let method: JudgeMethod

  private var segments: [JudgedSegment] = []
  /// Shingle to the segments that contain it.
  private var index: [UInt64: [Int]] = [:]
  /// How many input-side segments carry a shingle, which is the frequency the
  /// boilerplate rule reads.
  private var inputFrequency: [UInt64: Int] = [:]
  private var inputSegments = 0
  /// Per segment, each reused shingle and the first request that reused it.
  /// The request matters: without it the only share a view could show at a
  /// request was the one at the end of the lane, which is the future.
  private var matched: [[UInt64: Int]] = []
  private var references: [[Int]] = []
  /// The findings as they stand, and the slots that have moved since they were
  /// last computed. Recomputing all of them cost 61 ms on a lane of 7,479
  /// segments, every time anything asked for a report.
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
      // A shingle that has just become boilerplate stops counting towards
      // every segment that carries it, so all of them have to be worked out
      // again. Nothing else can change a finding while the cutoff stands
      // still, and a cutoff that moves rebuilds everything anyway.
      if frequency == cutoff + 1 { dirty.formUnion(index[shingle] ?? []) }
    }
  }

  public mutating func add(consumer: JudgedConsumer) {
    for shingle in Set(consumer.shingles) {
      guard let slots = index[shingle] else { continue }
      for slot in slots {
        // A segment can be referenced by the request it entered at: the model
        // writes a tool call in the same response that reads the previous
        // result, and its own output is born one request later, so no segment
        // can match itself.
        guard consumer.request >= segments[slot].born else { continue }
        // The first request that reused a shingle is the one that counts: a
        // second look at the same words is not more reuse.
        if matched[slot][shingle] == nil { matched[slot][shingle] = consumer.request }
        dirty.insert(slot)
        if references[slot].last != consumer.request {
          references[slot].append(consumer.request)
        }
      }
    }
  }

  /// The findings as they stand.
  ///
  /// Only the segments that moved since the last report are recomputed. The
  /// exception is the boilerplate cutoff: it is a step function of how many
  /// input-side segments have been seen, and when it moves every finding moves
  /// with it, so that case rebuilds all of them. Either way the answer is the
  /// one a judge fed the same input from scratch would give.
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
    // How many k-grams had been reused by the end of each request that reused
    // any. Counted here, because which shingles count depends on the cutoff.
    var firstMatch: [Int: Int] = [:]
    for shingle in segment.shingles {
      guard (inputFrequency[shingle] ?? 0) <= cutoff else { continue }
      total += 1
      guard let request = matched[slot][shingle] else { continue }
      hits += 1
      firstMatch[request, default: 0] += 1
    }
    // A segment made only of boilerplate has nothing that could tell reuse
    // apart from repetition, so it is not assessable rather than zero.
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
