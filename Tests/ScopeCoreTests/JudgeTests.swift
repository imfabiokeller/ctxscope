import Testing

@testable import ScopeCore

@Suite("Shingler")
struct ShinglerTests {
  @Test("words are lowercased runs of letters and digits")
  func words() {
    #expect(
      Shingler.words("Read(file_path: \"A/b.swift\")") == [
        "read", "file", "path", "a", "b", "swift",
      ])
  }

  @Test("the same text always shingles the same way")
  func stable() {
    let text = "the estimator is a predictor of token deltas not a tokenizer"
    #expect(Shingler.shingles(of: text) == Shingler.shingles(of: text))
    #expect(Shingler.shingles(of: text).count == Shingler.words(text).count - Shingler.width + 1)
  }

  @Test("short text still yields one shingle")
  func shortText() {
    #expect(Shingler.shingles(of: "two words").count == 1)
    #expect(Shingler.shingles(of: "").isEmpty)
  }

  @Test("sampling caps the count and keeps the ends")
  func sampling() {
    let text = (0..<2000).map { "word\($0)" }.joined(separator: " ")
    let sampled = Shingler.sampled(of: text, limit: 100)
    #expect(sampled.count == 100)
    #expect(sampled.first == Shingler.shingles(of: text).first)
  }
}

@Suite("LexicalJudge")
struct LexicalJudgeTests {
  private func shingles(_ text: String) -> [UInt64] {
    Shingler.shingles(of: text)
  }

  private func judge(_ input: JudgeInput) -> ReferenceReport {
    var judge = LexicalJudge()
    judge.add(input)
    return judge.report()
  }

  @Test("a segment quoted by later output is referenced")
  func referenced() {
    let quoted = "the request total is always measured and section sizes must sum to it"
    let input = JudgeInput(
      segments: [
        JudgedSegment(id: SegmentID(0), born: 1, isAssessable: true, shingles: shingles(quoted))
      ],
      consumers: [
        JudgedConsumer(request: 2, shingles: shingles("as it says, \(quoted), so we do that"))
      ]
    )
    let finding = judge(input).bySegment()[SegmentID(0)]
    #expect(finding?.referencedShare ?? 0 > 0.5)
    #expect(finding?.firstReference == 2)
  }

  @Test("output before the segment entered does not count as a reference")
  func onlyLaterOutputCounts() {
    let text = "cache read divided by cache read plus cache write plus uncached input"
    let input = JudgeInput(
      segments: [
        JudgedSegment(id: SegmentID(0), born: 5, isAssessable: true, shingles: shingles(text))
      ],
      consumers: [JudgedConsumer(request: 2, shingles: shingles(text))]
    )
    let finding = judge(input).bySegment()[SegmentID(0)]
    #expect(finding?.referencedShare == 0)
    #expect(finding?.firstReference == nil)
  }

  @Test("segments nothing can be said about report as not assessable, not as unreferenced")
  func notAssessable() {
    let input = JudgeInput(
      segments: [
        JudgedSegment(id: SegmentID(0), born: 0, isAssessable: false, shingles: [])
      ],
      consumers: [JudgedConsumer(request: 1, shingles: [1, 2, 3])]
    )
    let finding = judge(input).bySegment()[SegmentID(0)]
    #expect(finding?.isAssessable == false)
    #expect(finding?.referencedShare == nil)
  }

  @Test("the report names everything about the method that changes its answer")
  func method() {
    let report = judge(JudgeInput())
    #expect(report.method.name == "lexical-overlap")
    #expect(report.method.version == 2)
    #expect(report.method.shingleWidth == Shingler.width)
    #expect(report.method.consumerShingleCap == nil)
    #expect(report.method.summary.contains("boilerplate") || !report.method.boilerplateRule.isEmpty)
  }

  @Test("output at the request a segment entered counts as a reference")
  func sameRequestCounts() {
    let text = "the first request total minus the first user message is the prefix"
    let input = JudgeInput(
      segments: [
        JudgedSegment(id: SegmentID(0), born: 4, isAssessable: true, shingles: shingles(text))
      ],
      consumers: [JudgedConsumer(request: 4, shingles: shingles(text))]
    )
    #expect(judge(input).bySegment()[SegmentID(0)]?.referencedShare ?? 0 > 0.9)
  }

  @Test("a segment reports the requests that reused something of it first")
  func allReferences() throws {
    let whole = "segment sizes are assigned once when a segment enters the context"
    let half = "segment sizes are assigned once"
    let input = JudgeInput(
      segments: [
        JudgedSegment(id: SegmentID(0), born: 0, isAssessable: true, shingles: shingles(whole))
      ],
      consumers: [
        JudgedConsumer(request: 1, shingles: shingles(half)),
        JudgedConsumer(request: 2, shingles: []),
        // The same words again are not more reuse.
        JudgedConsumer(request: 3, shingles: shingles(half)),
        JudgedConsumer(request: 4, shingles: shingles(whole)),
      ]
    )
    let finding = try #require(judge(input).bySegment()[SegmentID(0)])
    #expect(finding.referenceRequests == [1, 4])
    #expect(finding.firstReference == 1)
    // The counts are cumulative, so the share only ever grows.
    #expect(finding.matchedCounts.count == 2)
    #expect(finding.matchedCounts[0] < finding.matchedCounts[1])
    #expect(finding.assessedShingles == shingles(whole).count)
  }

  @Test("the share at a request is monotone and made only of the past")
  func shareOverTime() throws {
    let whole = "the estimator predicts a derived delta and never tokenizes anything at all"
    let part = "the estimator predicts a derived delta"
    var judge = LexicalJudge()
    judge.add(
      segment: JudgedSegment(
        id: SegmentID(0), born: 0, isAssessable: true, shingles: shingles(whole)))
    judge.add(consumer: JudgedConsumer(request: 2, shingles: shingles(part)))
    let early = try #require(judge.report().bySegment()[SegmentID(0)])

    // Nothing had happened before request 2, and what had happened by 2 is
    // what the view shows at 2 and at everything after it, until more happens.
    #expect(early.share(at: 0) == 0)
    #expect(early.share(at: 1) == 0)
    let atTwo = try #require(early.share(at: 2))
    #expect(atTwo > 0)
    #expect(atTwo < 1)
    #expect(early.share(at: 9) == atTwo)

    // A later reference must not move what the earlier requests showed.
    judge.add(consumer: JudgedConsumer(request: 6, shingles: shingles(whole)))
    let later = try #require(judge.report().bySegment()[SegmentID(0)])
    #expect(later.share(at: 2) == atTwo)
    #expect(later.share(at: 5) == atTwo)
    #expect((later.share(at: 6) ?? 0) > atTwo)
    // Monotone the whole way.
    var last = 0.0
    for request in 0...10 {
      let share = later.share(at: request) ?? 0
      #expect(share >= last)
      last = share
    }
  }

  @Test("feeding a judge one request at a time gives the same answer")
  func incrementalMatchesBatch() {
    var segments: [JudgedSegment] = []
    var consumers: [JudgedConsumer] = []
    for request in 0..<40 {
      segments.append(
        JudgedSegment(
          id: SegmentID(request), born: request, isAssessable: true,
          shingles: shingles("segment number \(request) holding some content to match on")))
      consumers.append(
        JudgedConsumer(
          request: request,
          shingles: shingles("segment number \(max(0, request - 1)) holding some content")))
    }
    var batch = LexicalJudge()
    batch.add(JudgeInput(segments: segments, consumers: consumers))

    var streamed = LexicalJudge()
    for index in 0..<40 {
      streamed.add(segment: segments[index])
      streamed.add(consumer: consumers[index])
    }
    #expect(batch.report().findings == streamed.report().findings)

    // Asking for a report as the lane grows must not change the answer: only
    // the segments that moved are recomputed, so a stale one would show here.
    var asked = LexicalJudge()
    for index in 0..<40 {
      asked.add(segment: segments[index])
      asked.add(consumer: consumers[index])
      _ = asked.report()
    }
    #expect(asked.report().findings == batch.report().findings)
  }

  @Test("boilerplate that is in everything is not evidence of reuse")
  func boilerplateIsDropped() {
    let common = shingles("users someone developer product source file path prefix common")
    var segments: [JudgedSegment] = []
    for index in 0..<80 {
      segments.append(
        JudgedSegment(
          id: SegmentID(index), born: 0, isAssessable: true,
          shingles: common + shingles("distinct body number \(index) with its own words here")))
    }
    var judge = LexicalJudge()
    judge.add(
      JudgeInput(
        segments: segments,
        consumers: [
          JudgedConsumer(request: 1, shingles: common)
        ]))
    // Every segment was hit, but only on the boilerplate, so nothing counts.
    #expect(judge.report().findings.allSatisfy { ($0.referencedShare ?? 0) == 0 })
  }

  @Test("the model quoting a segment does not make that segment boilerplate")
  func modelOutputDoesNotRaiseTheFrequency() {
    let text = "the estimator predicts the derived token delta between two requests"
    var judge = LexicalJudge()
    judge.add(
      segment: JudgedSegment(
        id: SegmentID(0), born: 0, isAssessable: true, isInput: true, shingles: shingles(text)))
    // Sixty responses that all quote it. Counting those towards the document
    // frequency put the shingle over the cutoff and the one thing it proves,
    // that the segment was reused, was thrown away as boilerplate.
    for index in 1...60 {
      judge.add(
        segment: JudgedSegment(
          id: SegmentID(index), born: index, isAssessable: true, isInput: false,
          shingles: shingles(text)))
    }
    judge.add(consumer: JudgedConsumer(request: 61, shingles: shingles(text)))
    #expect(judge.report().bySegment()[SegmentID(0)]?.referencedShare ?? 0 > 0.9)
  }
}
