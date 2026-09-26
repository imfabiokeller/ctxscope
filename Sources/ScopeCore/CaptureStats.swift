public struct CaptureStats: Sendable, Codable, Hashable {
  public var skippedLines: Int
  public var chainRestarts: Int
  public var toolCalls: Int
  public var toolCallsWithResult: Int
  public var inferredRetirements: Int
  public var inferredRetirementTokens: Int
  public var inferredRetirementOvershoot: Int
  public var rejectedMeasurements: Int
  public var heldEntries: Int
  public var unattributedTokens: Int
  public var unfinishedResponses: Int
  public var contextReports: Int

  public init(
    skippedLines: Int = 0,
    chainRestarts: Int = 0,
    toolCalls: Int = 0,
    toolCallsWithResult: Int = 0,
    inferredRetirements: Int = 0,
    inferredRetirementTokens: Int = 0,
    inferredRetirementOvershoot: Int = 0,
    rejectedMeasurements: Int = 0,
    heldEntries: Int = 0,
    unfinishedResponses: Int = 0,
    unattributedTokens: Int = 0,
    contextReports: Int = 0
  ) {
    self.skippedLines = skippedLines
    self.chainRestarts = chainRestarts
    self.toolCalls = toolCalls
    self.toolCallsWithResult = toolCallsWithResult
    self.inferredRetirements = inferredRetirements
    self.inferredRetirementTokens = inferredRetirementTokens
    self.inferredRetirementOvershoot = inferredRetirementOvershoot
    self.rejectedMeasurements = rejectedMeasurements
    self.heldEntries = heldEntries
    self.unfinishedResponses = unfinishedResponses
    self.unattributedTokens = unattributedTokens
    self.contextReports = contextReports
  }

  public var toolCallsWithoutResult: Int { max(0, toolCalls - toolCallsWithResult) }
}
