import Foundation
import ScopeCore

@testable import ScopeUI

/// Small lanes made by hand for the Timeline presenter's tests: a prefix, a
/// prompt, and one block per request, with the cache read back in full at
/// every request unless a break says how much was read.
enum TimelineLanes {
  struct Block {
    let band: Band
    let label: String
    let tokens: Int
    let born: Int
    var died: Int?
  }

  /// `reads` is what a request read from the cache when it is not all of the
  /// request before it; `gaps` the seconds before a request, 10 otherwise.
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

  /// The page for a lane, with every prompt's line its block's label.
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
