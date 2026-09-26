/// What the capture had to cope with. These are statements about the input,
/// not measurements of the context, and `validate` reports them so a lane
/// that was reconstructed from damaged or unusual material says so.
public struct CaptureStats: Sendable, Codable, Hashable {
  /// Lines that were not valid JSON. A transcript being appended to can end in
  /// half a line, which is normal.
  public var skippedLines: Int
  /// Chains that started at an entry whose parent is not in the file. Every
  /// segment of the previous chain leaves at such a point, so a lane with many
  /// of these is one whose history is missing.
  public var chainRestarts: Int
  /// Tool calls that entered the context.
  public var toolCalls: Int
  /// How many of them brought their result with them. Parallel calls put
  /// every sibling result off the parent chain, so this is the check that the
  /// chain expansion is doing its job.
  public var toolCallsWithResult: Int
  /// Segments retired because the measured total said they were gone, with no
  /// entry in the transcript saying so.
  public var inferredRetirements: Int
  public var inferredRetirementTokens: Int
  /// Tokens retired beyond what the overhang asked for. A greedy retirement
  /// can only stop on a segment boundary.
  public var inferredRetirementOvershoot: Int
  /// Measured response totals the sizer refused because they cannot be right
  /// for the content they would have had to cover.
  public var rejectedMeasurements: Int
  /// Parsed entries still held in memory. Everything else is served by reading
  /// its bytes again, so this is what a lane costs beyond its own structure.
  public var heldEntries: Int
  /// Tokens that entered a request but belong to no observed block: room a
  /// retirement freed beyond what was needed, and a prefix change nothing
  /// accounted for. Graded E and named "Unattributed" wherever it is drawn.
  public var unattributedTokens: Int
  /// Responses with no `stop_reason`, whose output total is a count taken
  /// while the stream was still running. Their blocks are estimated instead.
  public var unfinishedResponses: Int
  /// `/context` runs the harness recorded in this lane. The first usable one
  /// sets the prefix split; the count says whether there were others that
  /// could have disagreed with it.
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
