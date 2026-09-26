public struct Prompt: Sendable, Codable, Hashable {
  public let number: Int
  public let segment: SegmentID
  public let requests: ClosedRange<Int>
  public let startTokens: Int
  public let endTokens: Int
  public let cost: Double
  public let cacheBreaks: Int
  public let largestAdded: SegmentID?

  public var addedTokens: Int { endTokens - startTokens }
  public var requestCount: Int { requests.count }
}

public struct PromptAnalysis: Sendable, Codable {
  public let prompts: [Prompt]

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
