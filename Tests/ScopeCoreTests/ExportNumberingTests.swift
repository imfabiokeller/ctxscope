import Testing

@testable import ScopeCore

/// An export is read by a person, so its request numbers count from one like
/// everything else a person reads. `analyze --at 47` printed "request 47"
/// while the JSON beside it said 46, and a CSV `born` ran 0 to 194 where the
/// window showed 1 to 195.
@Suite("export numbering")
struct ExportNumberingTests {
  static var payload: ExportPayload {
    let recording = SyntheticRecording.make(SyntheticRecording.Options(requests: 6))
    let lane = recording.mainLane ?? Lane(id: .main, window: .given(1), segments: [], snapshots: [])
    let corpus = SyntheticJudge.corpus(for: lane)
    var judge = LexicalJudge()
    judge.add(corpus.input)
    return ExportPayload(
      sessionID: recording.sessionID, project: recording.project, title: recording.title,
      lane: lane, references: judge.report())
  }

  @Test("the JSON numbers every request from one")
  func json() throws {
    let payload = Self.payload
    let numbered = Export.numbered(payload)
    #expect(numbered.requestNumbersFrom == 1)
    #expect(numbered.lane.snapshots.map(\.index) == payload.lane.snapshots.map { $0.index + 1 })
    #expect(numbered.lane.segments.map(\.born) == payload.lane.segments.map { $0.born + 1 })
    for (before, after) in zip(payload.lane.segments, numbered.lane.segments) {
      #expect(after.died == before.died.map { $0 + 1 })
      #expect(after.tokens == before.tokens)
    }
    for (before, after) in zip(payload.references.findings, numbered.references.findings) {
      #expect(after.referenceRequests == before.referenceRequests.map { $0 + 1 })
    }
    #expect(Export.text(payload, format: .json).contains("\"requestNumbersFrom\" : 1"))
  }

  @Test("the CSV numbers every request from one")
  func csv() throws {
    let payload = Self.payload
    let rows = Export.csv(lane: payload.lane, references: payload.references)
      .split(separator: "\n").map(String.init)
    let header = try #require(rows.first).split(separator: ",").map(String.init)
    let born = try #require(header.firstIndex(of: "born"))
    let first = try #require(rows.dropFirst().first).split(separator: ",").map(String.init)
    // Every block of a lane is born at request 1 or later, never at 0.
    #expect(Int(first[born]) == payload.lane.segments[0].born + 1)
    // A label can hold a comma and is quoted when it does, which moves the
    // columns; those rows are skipped rather than mis-parsed here.
    var checked = 0
    for row in rows.dropFirst() where !row.contains("\"") {
      let cells = row.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
      guard cells.count == header.count else { continue }
      #expect(Int(cells[born]) ?? 0 >= 1)
      checked += 1
    }
    #expect(checked > 10)
  }
}
