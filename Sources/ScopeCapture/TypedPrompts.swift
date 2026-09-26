internal import Foundation
internal import ScopeCore

/// Tells a prompt the person typed apart from everything else the `user`
/// role carries: tool results, the harness's own notes, a compaction summary,
/// a background task reporting back, the marker an interruption leaves.
///
/// A task runs from one typed prompt to the next, so this decides where every
/// task starts. It is stateful because the harness writes one prompt as
/// several entries sharing a `promptId`: the prompt, and after it the notice
/// that the person interrupted the answer. Only the first starts a task.
struct TypedPrompts {
  /// What the harness writes as the `origin.kind` of a user turn that a
  /// background task produced. Such a turn carries a `<task-notification>`
  /// block, which is also what gives it away where no origin is written.
  static let taskNotification = "task-notification"
  static let notificationTag = "<task-notification>"
  /// The text an interruption leaves in the user role. Older transcripts
  /// write it without a `promptId`, so the text is what gives it away.
  static let interruption = "[Request interrupted by user"

  private var lastPromptID: String?

  /// Whether an entry, met in file order, is a new prompt the person typed.
  mutating func isNewPrompt(_ entry: TranscriptEntry) -> Bool {
    guard Self.isTyped(entry) else { return false }
    guard let id = entry.raw["promptId"]?.string else { return true }
    defer { lastPromptID = id }
    return id != lastPromptID
  }

  static func isTyped(_ entry: TranscriptEntry) -> Bool {
    guard entry.kind == "user", !entry.isCompactSummary,
      entry.raw["isMeta"]?.bool != true,
      entry.raw["origin"]?["kind"]?.string != taskNotification
    else { return false }
    let blocks = entry.blocks
    guard !blocks.contains(where: { $0["type"]?.string == "tool_result" }),
      let text = blocks.first(where: { $0["type"]?.string == "text" })?["text"]?.string
    else { return false }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && !trimmed.hasPrefix(notificationTag)
      && !trimmed.hasPrefix(interruption)
  }
}
