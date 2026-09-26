import Testing

@testable import ScopeCore

@Suite("Cache break causes")
struct CacheBreakTests {
  private static func segment(
    _ id: Int, _ band: Band, _ tokens: Int, born: Int, died: Int? = nil, label: String? = nil
  ) -> Segment {
    Segment(
      id: SegmentID(id), band: band, label: label ?? "\(band.rawValue) \(id)",
      tokens: Tokens(tokens, .estimated), characters: tokens * 3, contentClass: .prose,
      born: born, died: died, contentHash: UInt64(id))
  }

  private static func snapshot(
    _ index: Int, read: Int, written: Int, at time: Double? = nil
  ) -> Snapshot {
    Snapshot(
      index: index, requestID: nil, timestamp: time ?? Double(index), model: "m",
      usage: RequestUsage(cacheReadTokens: read, cacheCreationTokens: written))
  }

  private static func lane(extra: [Segment], at time: Double = 2, read: Int) -> Lane {
    let segments =
      [
        segment(0, .sys, 1000, born: 0),
        segment(1, .tools, 2000, born: 0, label: "Bash"),
        segment(2, .mem, 500, born: 0, died: extra.contains { $0.band == .mem } ? 2 : nil),
        segment(3, .user, 100, born: 1),
      ] + extra
    let total = segments.filter { $0.isLive(at: 2) }.reduce(0) { $0 + $1.tokens.value }
    return Lane(
      id: .main, window: .given(200_000), segments: segments,
      snapshots: [
        snapshot(0, read: 0, written: 3500),
        snapshot(1, read: 3500, written: 100),
        snapshot(2, read: read, written: total - read, at: time),
      ])
  }

  @Test("an edited memory file breaks the cache after the system prompt and tools")
  func memory() throws {
    let lane = Self.lane(
      extra: [Self.segment(4, .mem, 520, born: 2, label: "Memory CLAUDE.md")], read: 3000)
    let bust = try #require(CacheAnalyzer.run(lane).busts.first)
    #expect(bust.request == 2)
    #expect(bust.cause == .memoryChanged)
    #expect(bust.parentRequest == 1)
    #expect(bust.rewrittenTokens.value == 600)
    #expect(bust.readThrough == .tools)
    let change = try #require(bust.change)
    #expect(change.kind == .memory)
    #expect(change.first == SegmentID(2))
    #expect(change.added == [SegmentID(4)])
    #expect(change.removed == [SegmentID(2)])
    #expect(change.addedTokens.value == 520)
    #expect(change.servers.isEmpty)
  }

  @Test("a server that connects breaks the cache with its tools, and is named")
  func tools() throws {
    let lane = Self.lane(
      extra: [
        Self.segment(4, .mcp, 300, born: 2, label: "mcp__github__create_pull_request"),
        Self.segment(5, .mcp, 200, born: 2, label: "mcp__github__list_issues"),
      ],
      read: 3000)
    let bust = try #require(CacheAnalyzer.run(lane).busts.first)
    #expect(bust.cause == .toolsChanged)
    let change = try #require(bust.change)
    #expect(change.kind == .tools)
    #expect(change.added.count == 2)
    #expect(change.addedTokens.value == 500)
    #expect(change.servers == ["github"])
    #expect(change.firstLabel == "mcp__github__create_pull_request")
  }

  @Test("a changed system prompt block is named before a long pause")
  func system() throws {
    let lane = Self.lane(
      extra: [Self.segment(4, .sys, 50, born: 2)], at: 1 + 3600, read: 0)
    let bust = try #require(CacheAnalyzer.run(lane).busts.first)
    #expect(bust.cause == .systemChanged)
    #expect(bust.readThrough == nil)
    #expect(bust.gapSeconds == 3600)
  }

  @Test("a pause with nothing changed is an expired cache, with the gap to the request before")
  func idle() throws {
    let lane = Self.lane(extra: [], at: 1 + 600, read: 0)
    let bust = try #require(CacheAnalyzer.run(lane).busts.first)
    #expect(bust.cause == .idle)
    #expect(bust.gapSeconds == 600)
    #expect(bust.parentRequest == 1)
    #expect(bust.change == nil)
    #expect(bust.readThrough == nil)
  }

  @Test("nothing changed and no pause is unknown, and the first request cannot break")
  func unknown() throws {
    let lane = Self.lane(extra: [], read: 1000)
    let busts = CacheAnalyzer.run(lane).busts
    #expect(busts.map(\.request) == [2])
    #expect(busts.first?.cause == .unknown)
    #expect(busts.first?.readThrough == .system)
    let one = SyntheticRecording.make(.oneRequest).mainLane!
    #expect(CacheAnalyzer.run(one).busts.isEmpty)
  }

  @Test("a compaction is still named as one, whatever else moved with it")
  func compaction() throws {
    let lane = SyntheticRecording.make().mainLane!
    let at = try #require(lane.compactions.first?.atRequest)
    let bust = try #require(CacheAnalyzer.run(lane).busts.first { $0.request == at })
    #expect(bust.cause == .compaction)
    #expect(bust.readThrough == .memory)
  }
}
