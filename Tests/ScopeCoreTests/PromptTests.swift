import Testing

@testable import ScopeCore

@Suite("Prompts")
struct PromptTests {
  private static func analyzed(_ lane: Lane) -> PromptAnalysis {
    PromptAnalyzer.run(lane, costs: CostAnalyzer.run(lane), cache: CacheAnalyzer.run(lane))
  }

  @Test("tasks run from one typed prompt to the next and cover the rest of the lane")
  func coverage() throws {
    let lane = SyntheticRecording.make().mainLane!
    let analysis = Self.analyzed(lane)
    let prompts = analysis.prompts
    #expect(prompts.count == lane.prompts.count)
    #expect(prompts.map(\.number) == Array(1...prompts.count))
    #expect(prompts.first?.requests.lowerBound == 1)
    #expect(prompts.last?.requests.upperBound == lane.snapshots.count - 1)
    for (earlier, later) in zip(prompts, prompts.dropFirst()) {
      #expect(earlier.requests.upperBound + 1 == later.requests.lowerBound)
      #expect(earlier.endTokens == later.startTokens)
    }
    #expect(analysis.prompt(containing: 0) == nil)
    for request in 1..<lane.snapshots.count {
      #expect(analysis.prompt(containing: request)?.requests.contains(request) == true)
    }
  }

  @Test("a task's cost, breaks and largest block are those of its own requests")
  func figures() throws {
    let lane = SyntheticRecording.make().mainLane!
    let costs = CostAnalyzer.run(lane)
    let cache = CacheAnalyzer.run(lane)
    let analysis = PromptAnalyzer.run(lane, costs: costs, cache: cache)
    let total = analysis.prompts.reduce(0) { $0 + $1.cost }
    let expected = costs.context(through: lane.snapshots.count - 1) - costs.context(through: 0)
    #expect(abs(total - expected) < 1e-9)
    #expect(analysis.prompts.reduce(0) { $0 + $1.cacheBreaks } == cache.busts.count)

    let bust = try #require(cache.busts.first)
    let broken = try #require(analysis.prompt(containing: bust.request))
    #expect(broken.cacheBreaks >= 1)

    let task = try #require(analysis.prompts.first)
    let largest = try #require(task.largestAdded)
    let entered = lane.segments.filter { task.requests.contains($0.born) }
    #expect(entered.allSatisfy { $0.tokens.value <= lane.segments[largest.rawValue].tokens.value })
    #expect(task.startTokens == lane.snapshots[0].usage.promptTotal)
    #expect(task.addedTokens == task.endTokens - task.startTokens)
  }

  @Test("a compaction inside a task can make what it added negative")
  func compaction() throws {
    let lane = Self.lane(totals: [400, 500, 150], prompts: [0, 1])
    let task = try #require(Self.analyzed(lane).prompt(containing: 2))
    #expect(task.startTokens == 400)
    #expect(task.addedTokens == -250)
  }

  @Test("a prompt at request 0 has nothing before it, and a rewind starts from its parent")
  func firstAndRewind() throws {
    // The second prompt was typed after rewinding to request 0.
    let lane = Self.lane(totals: [100, 300, 500], prompts: [0, 2], parents: [2: 0])
    let prompts = Self.analyzed(lane).prompts
    #expect(prompts.map(\.requests) == [0...1, 2...2])
    #expect(prompts[0].startTokens == 0)
    #expect(prompts[1].startTokens == 100)
    #expect(prompts[1].addedTokens == 400)
  }

  private static func lane(
    totals: [Int], prompts born: [Int], parents: [Int: Int] = [:]
  ) -> Lane {
    let segments = born.enumerated().map { index, born in
      Segment(
        id: SegmentID(index), band: .user, label: "User prompt", tokens: Tokens(10, .estimated),
        characters: 30, contentClass: .prose, born: born, contentHash: UInt64(index))
    }
    return Lane(
      id: .main, window: .given(200_000), segments: segments,
      snapshots: totals.enumerated().map { index, total in
        Snapshot(
          index: index, requestID: nil, timestamp: Double(index), model: "m",
          usage: RequestUsage(cacheReadTokens: total), parentRequest: parents[index])
      },
      prompts: segments.map(\.id))
  }

  @Test("an empty lane and a lane nobody typed in have no tasks")
  func none() {
    let empty = Lane(id: .main, window: .given(200_000), segments: [], snapshots: [])
    #expect(Self.analyzed(empty).prompts.isEmpty)
    #expect(Self.analyzed(empty).prompt(containing: 0) == nil)
    let one = SyntheticRecording.make(.oneRequest).mainLane!
    #expect(Self.analyzed(one).prompts.isEmpty)
  }
}
