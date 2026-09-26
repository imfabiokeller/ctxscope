/// Tasks: what happened from one prompt the person typed to the next.
///
/// A task starts at the request a typed prompt entered at and runs up to the
/// request before the next one, or to the end of the lane. Requests before
/// the first typed prompt belong to no task: a subagent lane is given its
/// task by its parent, and a transcript can begin part way through one.

public struct Prompt: Sendable, Codable, Hashable {
  /// Counted from one, the way the window names it: "prompt 4".
  public let number: Int
  /// The block of the prompt's text.
  public let segment: SegmentID
  /// Request indices, from zero like everywhere in a recording, both ends
  /// included.
  public let requests: ClosedRange<Int>
  /// The measured context this task was added to: the total of the request
  /// its first one continued from, zero when there was none.
  public let startTokens: Int
  /// The measured context of its last request.
  public let endTokens: Int
  /// Exact context cost over its requests.
  public let cost: Double
  /// Cache breaks at any of its requests.
  public let cacheBreaks: Int
  /// The largest block that entered during the task, if any did.
  public let largestAdded: SegmentID?

  /// What the task added to the context. Negative when a compaction inside it
  /// dropped more than it added.
  public var addedTokens: Int { endTokens - startTokens }
  public var requestCount: Int { requests.count }
}

public struct PromptAnalysis: Sendable, Codable {
  /// In order, numbered from one.
  public let prompts: [Prompt]

  /// The task a request belongs to, or nil for a request before the first
  /// typed prompt.
  public func prompt(containing request: Int) -> Prompt? {
    var low = 0
    var high = prompts.count - 1
    while low <= high {
      let middle = (low + high) / 2
      let range = prompts[middle].requests
      if request < range.lowerBound {
        high = middle - 1
      } else if request > range.upperBound {
        low = middle + 1
      } else {
        return prompts[middle]
      }
    }
    return nil
  }
}

public enum PromptAnalyzer {
  public static func run(
    _ lane: Lane, costs: CostAnalysis, cache: CacheAnalysis
  ) -> PromptAnalysis {
    let count = lane.snapshots.count
    guard count > 0 else { return PromptAnalysis(prompts: []) }
    let byID = Dictionary(
      lane.segments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    // One task per request at most: two prompts that entered at the same
    // request were sent together, and the first of them names the task.
    var starts: [(request: Int, segment: SegmentID)] = []
    var taken: Set<Int> = []
    for id in lane.prompts {
      guard let segment = byID[id], segment.born < count, taken.insert(segment.born).inserted
      else { continue }
      starts.append((segment.born, id))
    }
    starts.sort { $0.request < $1.request }

    var largest: [Int: Segment] = [:]
    for segment in lane.segments where segment.born < count && segment.kind != nil {
      if let known = largest[segment.born], known.tokens.value >= segment.tokens.value {
        continue
      }
      largest[segment.born] = segment
    }
    let breaks = cache.busts.map(\.request)

    let prompts = starts.enumerated().map { index, start -> Prompt in
      let last = index + 1 < starts.count ? starts[index + 1].request - 1 : count - 1
      let requests = start.request...last
      let parent = lane.snapshots[start.request].parentRequest ?? (start.request - 1)
      let biggest = requests.compactMap { largest[$0] }.max { $0.tokens.value < $1.tokens.value }
      return Prompt(
        number: index + 1,
        segment: start.segment,
        requests: requests,
        startTokens: parent >= 0 && parent < count ? lane.snapshots[parent].usage.promptTotal : 0,
        endTokens: lane.snapshots[last].usage.promptTotal,
        cost: costs.context(in: requests),
        cacheBreaks: breaks.count { requests.contains($0) },
        largestAdded: biggest?.id
      )
    }
    return PromptAnalysis(prompts: prompts)
  }
}
