internal import Foundation
internal import ScopeCore

/// What a transcript records about the prefix, and where it sits.
///
/// All of it arrives after the prefix it describes. The system prompt snapshot
/// is written before the first response, the tool list before the second, and
/// a `/context` run wherever somebody typed it, which on a real session was
/// request 152. The prefix is derived once, at the first request, so evidence
/// that turns up after that request was stepped describes a lane that has
/// already been built: `SessionCapture` builds it again rather than patching
/// it, which is what makes a lane the same however the file was read.
///
/// Nothing here holds text. The system prompt is kept as block lengths and the
/// uuid of the entry that holds them, so the words are read back out of the
/// file when they are asked for.
struct PrefixEvidence: Sendable {
  /// Characters per recorded system prompt block, in order.
  private(set) var systemLengths: [Int] = []
  private(set) var systemEntry: String?
  private(set) var tools: [ContextReport.Tool] = []
  private(set) var toolsEntry: String?
  private(set) var report: ContextReport?

  var hasSnapshot: Bool { systemEntry != nil || toolsEntry != nil }

  var source: PrefixSplit.Source {
    .of(snapshot: hasSnapshot, report: report != nil)
  }

  /// Takes what an entry records about the prefix. True when it said something
  /// this did not already know, which is what makes a lane worth building
  /// again.
  ///
  /// Only the first of each is taken. A session's snapshots are byte identical
  /// wherever they sit, and a second `/context` run describes the same prompt.
  @discardableResult
  mutating func learn(from entry: TranscriptEntry, at request: Int = 0) -> Bool {
    if var found = ContextUsage.report(of: entry) {
      guard report == nil else { return false }
      found.request = request
      report = found
      return true
    }
    guard entry.attachmentType == EntryReader.snapshotType,
      let attachment = entry.attachment, let uuid = entry.uuid
    else { return false }
    var learned = false
    let blocks = EntryReader.systemBlocks(attachment)
    if systemEntry == nil, !blocks.isEmpty {
      systemLengths = blocks.map(\.unicodeScalars.count)
      systemEntry = uuid
      learned = true
    }
    if toolsEntry == nil {
      let tools = EntryReader.snapshotTools(attachment)
      if !tools.isEmpty {
        self.tools = tools
        toolsEntry = uuid
        learned = true
      }
    }
    return learned
  }

  /// The blocks of the unobserved prefix, and what each is worth.
  ///
  /// `observed` names the prefix bands the transcript already put in the
  /// context as content of their own, such as memory files injected as
  /// attachments. Splitting for one of those would count it twice.
  func plan(observed: Set<Band>) -> PrefixSplit.Plan {
    if let report {
      let plan = PrefixSplit.plan(
        from: ContextUsage.joined(report, tools: tools),
        systemLengths: observed.contains(.sys) ? [] : systemLengths,
        observed: observed)
      if !plan.isEmpty { return plan }
    }
    return PrefixSplit.priorPlan(
      observed: observed,
      systemLengths: observed.contains(.sys) ? [] : systemLengths,
      tools: tools)
  }
}
