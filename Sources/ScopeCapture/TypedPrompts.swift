internal import Foundation
internal import ScopeCore

// The harness writes one prompt as several entries sharing a `promptId` (the
// prompt, then an interruption notice); only the first starts a task.
struct TypedPrompts {
  // Where no `origin` is written, the `<task-notification>` block gives it away.
  static let taskNotification = "task-notification"
  static let notificationTag = "<task-notification>"
  // Older transcripts write it without a `promptId`, so the text gives it away.
  static let interruption = "[Request interrupted by user"

  private var lastPromptID: String?

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
