public struct CompactionSummary: Sendable, Codable, Hashable {
  public let event: CompactionEvent
  public let survivingSegments: Int
  public let survivingTokens: Tokens
  public let droppedSegments: Int
  public let droppedTokens: Tokens
  public let summaryTokens: Tokens
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
      let droppedNetOfSummary = event.preTokens - event.postTokens + entered
      summaries.append(
        CompactionSummary(
          event: event,
          survivingSegments: survivors,
          survivingTokens: Tokens(surviving, survivingGrade),
          droppedSegments: casualties,
          droppedTokens: Tokens(dropped, droppedGrade),
          summaryTokens: Tokens(entered, enteredGrade),
          disagreement: abs(droppedNetOfSummary - dropped)
        )
      )
    }
    return CompactionAnalysis(compactions: summaries)
  }
}
