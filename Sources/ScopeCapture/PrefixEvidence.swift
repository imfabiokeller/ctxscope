internal import Foundation
internal import ScopeCore

// Holds no text: system blocks are kept as lengths and the uuid of their entry.
struct PrefixEvidence: Sendable {
  private(set) var systemLengths: [Int] = []
  private(set) var systemEntry: String?
  private(set) var tools: [ContextReport.Tool] = []
  private(set) var toolsEntry: String?
  private(set) var report: ContextReport?

  var hasSnapshot: Bool { systemEntry != nil || toolsEntry != nil }

  var source: PrefixSplit.Source {
    .of(snapshot: hasSnapshot, report: report != nil)
  }

  // Only the first of each counts: snapshots are byte identical, and a second
  // `/context` run describes the same prompt.
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
