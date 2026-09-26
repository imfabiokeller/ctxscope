import Foundation
import ScopeCore

@testable import ScopeUI

enum TimelineLanes {
  struct Block {
    let band: Band
    let label: String
    let tokens: Int
    let born: Int
    var died: Int?
  }

  /// `reads` overrides what a request read from the cache (by default all of the request
  /// before it); `gaps` the seconds before a request, 10 otherwise.
  static func lane(
    requests: Int, extra: [Block] = [], prompts: [Int] = [0], reads: [Int: Int] = [:],
    gaps: [Int: Double] = [:], models: [Int: String] = [:]
  ) -> Lane {
    var blocks = [
      Block(band: .sys, label: "System prompt", tokens: 3000, born: 0),
      Block(band: .tools, label: "Read", tokens: 8000, born: 0),
      Block(band: .mem, label: "CLAUDE.md", tokens: 2000, born: 0),
    ]
    for request in 0..<requests {
      if prompts.contains(request) {
        blocks.append(Block(band: .user, label: "Prompt at \(request)", tokens: 200, born: request))
      }
      blocks.append(Block(band: .read, label: "file\(request).swift", tokens: 1000, born: request))
    }
    blocks += extra
    let segments = blocks.enumerated().map { index, block in
      Segment(
        id: SegmentID(index), band: block.band, label: block.label,
        tokens: Tokens(block.tokens, .estimated), characters: block.tokens * 3,
        contentClass: .prose, born: block.born, died: block.died, contentHash: UInt64(index))
    }
    var snapshots: [Snapshot] = []
    var time = 0.0
    var previous = 0
    for request in 0..<requests {
      let total = segments.filter { $0.isLive(at: request) }.reduce(0) { $0 + $1.tokens.value }
      let read = reads[request] ?? previous
      time += gaps[request] ?? 10
      snapshots.append(
        Snapshot(
          index: request, requestID: "r\(request)", timestamp: time,
          model: models[request] ?? "model",
          usage: RequestUsage(cacheReadTokens: read, cacheCreationTokens: total - read)))
      previous = total
    }
    return Lane(
      id: .main, window: .given(200_000), segments: segments, snapshots: snapshots,
      prompts: segments.filter { $0.band == .user }.map(\.id))
  }

  static func present(_ lane: Lane, selected: Int? = nil) -> TimelineData {
    let costs = CostAnalyzer.run(lane)
    let cache = CacheAnalyzer.run(lane)
    let lines = Dictionary(
      uniqueKeysWithValues: lane.segments.filter { $0.band == .user }.map { ($0.id, $0.label) })
    return TimelinePresenter.present(
      lane: lane, costs: costs, cache: cache,
      prompts: PromptAnalyzer.run(lane, costs: costs, cache: cache),
      order: ReadingOrder(lane), promptLines: lines, selectedPrompt: selected)
  }
}
