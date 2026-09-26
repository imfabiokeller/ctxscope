/// What a compaction did, as an analysis rather than something the adapter
/// worked out on the way past. The harness records the totals, so most of this
/// is measured; which segments survived is a fact about the reconstruction.
public struct CompactionSummary: Sendable, Codable, Hashable {
  public let event: CompactionEvent
  public let survivingSegments: Int
  public let survivingTokens: Tokens
  public let droppedSegments: Int
  public let droppedTokens: Tokens
  /// Tokens that entered at the compaction, which is the summary it wrote.
  public let summaryTokens: Tokens
  /// What the harness said it dropped, against what the reconstruction says,
  /// once the summary that arrived in its place is accounted for. A large
  /// disagreement means the reconstruction lost the thread.
  public let disagreement: Int
}

public struct CompactionAnalysis: Sendable, Codable {
  public let compactions: [CompactionSummary]
  public var count: Int { compactions.count }
}

public enum CompactionAnalyzer {
  public static func run(_ lane: Lane) -> CompactionAnalysis {
    var summaries: [CompactionSummary] = []
    for event in lane.compactions {
      var surviving = 0
      var survivingGrade = Grade.measured
      var dropped = 0
      var droppedGrade = Grade.measured
      var survivors = 0
      var casualties = 0
      var entered = 0
      var enteredGrade = Grade.measured
      for segment in lane.segments {
        if segment.born == event.atRequest {
          entered += segment.tokens.value
          enteredGrade = max(enteredGrade, segment.tokens.grade)
        }
        if segment.isLive(at: event.atRequest) {
          survivors += 1
          surviving += segment.tokens.value
          survivingGrade = max(survivingGrade, segment.tokens.grade)
        } else if segment.died == event.atRequest {
          casualties += 1
          dropped += segment.tokens.value
          droppedGrade = max(droppedGrade, segment.tokens.grade)
        }
      }
      summaries.append(
        CompactionSummary(
          event: event,
          survivingSegments: survivors,
          survivingTokens: Tokens(surviving, survivingGrade),
          droppedSegments: casualties,
          droppedTokens: Tokens(dropped, droppedGrade),
          summaryTokens: Tokens(entered, enteredGrade),
          // The context fell by what left minus what the summary put back, so
          // that is what the harness number has to be compared against.
          disagreement: abs((event.preTokens - event.postTokens + entered) - dropped)
        )
      )
    }
    return CompactionAnalysis(compactions: summaries)
  }
}
