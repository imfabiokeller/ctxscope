import Testing

@testable import ScopeCore

@Suite("ReferenceAnalyzer")
struct ReferenceAnalyzerTests {
  @Test("not assessable tokens are counted apart from unreferenced ones")
  func notAssessableIsItsOwnBucket() {
    let lane = SyntheticRecording.make().mainLane!
    let findings = lane.segments.map {
      ReferenceFinding(
        segment: $0.id,
        isAssessable: $0.isAssessable,
        referencedShare: $0.isAssessable ? 0.5 : nil,
        referenceRequests: $0.isAssessable ? [$0.born + 1] : []
      )
    }
    let report = ReferenceReport(
      method: LexicalJudge().method, findings: findings)
    let summary = ReferenceAnalyzer.run(lane, references: report, at: 30)
    #expect(summary.notAssessableTokens.value > 0)
    #expect(
      summary.assessedTokens.value + summary.notAssessableTokens.value
        == summary.totalTokens.value)
    #expect(abs(summary.ratio - 0.5) < 0.01)
    #expect(summary.interval.contains(summary.ratio))
    #expect(summary.positionalShare.count == 3)
    #expect(summary.referencedTokens.grade == .estimated)
  }

  @Test("the input side is reported on its own")
  func inputBandsAreReportedApart() {
    let lane = SyntheticRecording.make().mainLane!
    // Only what the model produced is referenced. The input ratio must not
    // pick any of that up.
    let findings = lane.segments.map {
      ReferenceFinding(
        segment: $0.id,
        isAssessable: $0.isAssessable,
        referencedShare: $0.isAssessable ? ($0.originRequest == nil ? 0 : 1) : nil,
        referenceRequests: $0.originRequest == nil ? [] : [$0.born]
      )
    }
    let summary = ReferenceAnalyzer.run(
      lane,
      references: ReferenceReport(method: LexicalJudge().method, findings: findings),
      at: 30
    )
    #expect(summary.inputAssessedTokens.value > 0)
    #expect(summary.inputAssessedTokens.value < summary.assessedTokens.value)
    #expect(summary.inputRatio == 0)
    #expect(summary.ratio > 0)
  }
}
