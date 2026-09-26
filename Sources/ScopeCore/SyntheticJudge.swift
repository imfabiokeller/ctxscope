public enum SyntheticJudge {
  public static let outputShingles = 200
  public static let tokensPerShingle = 12

  public static func input(for lane: Lane, seed: UInt64 = 0x5bf0_3635_1f2c_a19b) -> JudgeInput {
    var random = SyntheticRecording.Random(seed: seed)
    let pool = (0..<200_000).map { _ in random.next() }
    func draw(_ count: Int) -> [UInt64] {
      (0..<count).map { _ in pool[Int(random.next() % UInt64(pool.count))] }
    }
    let segments = lane.segments.map { segment in
      JudgedSegment(
        id: segment.id,
        born: segment.born,
        isAssessable: segment.isAssessable,
        isInput: segment.originRequest == nil,
        shingles: draw(min(400, max(1, segment.tokens.value / tokensPerShingle)))
      )
    }
    let consumers = lane.snapshots.map {
      JudgedConsumer(request: $0.index, shingles: draw(outputShingles))
    }
    return JudgeInput(segments: segments, consumers: consumers)
  }

  public static func corpus(
    for lane: Lane,
    seed: UInt64 = 0x51ed_2701_7b3a_0c4d
  ) -> (input: JudgeInput, texts: [SegmentID: String]) {
    var random = SyntheticRecording.Random(seed: seed)
    var texts: [SegmentID: String] = [:]
    var segments: [JudgedSegment] = []
    var quoted: [Int: [String]] = [:]

    for segment in lane.segments {
      guard segment.isAssessable, segment.characters > 0 else {
        segments.append(
          JudgedSegment(
            id: segment.id, born: segment.born, isAssessable: false,
            isInput: segment.originRequest == nil, shingles: []))
        continue
      }
      let text = sentences(
        words: max(Shingler.width, min(240, segment.tokens.value / 2)), random: &random)
      texts[segment.id] = text
      segments.append(
        JudgedSegment(
          id: segment.id,
          born: segment.born,
          isAssessable: true,
          isInput: segment.originRequest == nil,
          shingles: Shingler.sampled(of: text, limit: 400)
        )
      )
      guard random.unit() < 0.55 else { continue }
      let words = Shingler.words(text)
      let take = max(Shingler.width, Int(Double(words.count) * (0.1 + random.unit() * 0.5)))
      let start = words.count > take ? Int(random.next() % UInt64(words.count - take + 1)) : 0
      let at = min(lane.snapshots.count - 1, segment.born + 1 + Int(random.next() % 4))
      quoted[at, default: []].append(
        words[start..<min(words.count, start + take)]
          .joined(separator: " "))
    }

    let consumers = lane.snapshots.map { snapshot in
      JudgedConsumer(
        request: snapshot.index,
        shingles: Shingler.shingles(of: (quoted[snapshot.index] ?? []).joined(separator: "\n"))
      )
    }
    return (JudgeInput(segments: segments, consumers: consumers), texts)
  }

  /// Stands for content: no transcript text ever reaches a fixture or a snapshot.
  private static func sentences(words count: Int, random: inout SyntheticRecording.Random)
    -> String
  {
    var text = ""
    var sinceBreak = 0
    for index in 0..<max(Shingler.width, count) {
      let word = vocabulary[Int(random.next() % UInt64(vocabulary.count))]
      text += index == 0 ? word : " " + word
      sinceBreak += 1
      if sinceBreak > 9, random.unit() < 0.3 {
        text += random.unit() < 0.4 ? ".\n" : ", "
        sinceBreak = 0
      }
    }
    return text
  }

  private static let vocabulary = [
    "segment", "request", "token", "context", "window", "prefix", "band", "family", "cache",
    "read", "write", "measured", "derived", "estimated", "residual", "compaction", "lane",
    "subagent", "carry", "cost", "reference", "ratio", "interval", "shingle", "judge",
    "transcript", "adapter", "analyzer", "recording", "snapshot", "usage", "prompt", "output",
    "thinking", "result", "schema", "memory", "instruction", "boundary", "retirement",
    "hypothesis", "overshoot", "calibration", "sample", "delta", "grade", "provenance",
    "duplication", "position", "share", "zone", "threshold", "bound", "peak", "model",
  ]
}
