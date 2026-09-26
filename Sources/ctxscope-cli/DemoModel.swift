import Foundation

/// The demo session as a story: what the person typed, what the harness put
/// around it, and what the model answered and called. `DemoLane` turns it into
/// transcript entries with usage numbers that add up.
///
/// Every word of it is made up for the demo. Nothing here is, or is taken
/// from, a real transcript or a real repository.

/// One API call, and what arrived in front of it.
struct DemoTurn {
  var inputs: [DemoInput] = []
  /// The summary the transcript stores, and what the thinking really cost.
  var thinking: String?
  var thinkingTokens = 0
  var text: String?
  var calls: [DemoCall] = []
  /// Seconds since the request before it.
  var gap: Double = 12
  var cache: DemoCache = .warm
}

/// What the cache read at a request.
enum DemoCache {
  /// Everything the request before it had cached.
  case warm
  /// The system prompt and the tools only: something after them changed.
  case prefix
  /// Nothing: the entry expired.
  case cold
}

/// A user or attachment entry in front of a request.
struct DemoInput {
  /// `type` and the fields that go with it.
  let fields: [String: Any]
  /// The texts a reader sizes this entry by.
  let sized: [String]

  /// True for a prompt the person typed.
  var isPrompt: Bool { (fields["origin"] as? [String: Any])?["kind"] as? String == "human" }

  static func prompt(_ text: String) -> DemoInput {
    DemoInput(
      fields: [
        "type": "user", "message": ["role": "user", "content": text],
        "origin": ["kind": "human"],
      ],
      sized: [text])
  }

  /// The task a subagent starts from, which the harness writes as its first
  /// user entry.
  static func task(_ text: String) -> DemoInput {
    DemoInput(
      fields: ["type": "user", "message": ["role": "user", "content": text]], sized: [text])
  }

  /// An attachment the harness recorded the rendering of.
  static func rendered(_ type: String, _ text: String, fields: [String: Any] = [:])
    -> DemoInput
  {
    var attachment = fields
    attachment["type"] = type
    return DemoInput(
      fields: ["type": "attachment", "attachment": attachment, "rendered": [["content": text]]],
      sized: [text])
  }

  /// Memory files, all of them in one `instructions` attachment.
  static func instructions(_ files: [DemoFile]) -> DemoInput {
    DemoInput(
      fields: [
        "type": "attachment",
        "attachment": ["type": "instructions", "files": files.map(\.record)],
      ],
      sized: files.map(\.content))
  }

  /// One memory file the harness attached again because it changed.
  static func nestedMemory(_ file: DemoFile) -> DemoInput {
    DemoInput(
      fields: [
        "type": "attachment",
        "attachment": ["type": "nested_memory", "path": file.path, "content": file.record],
      ],
      sized: [file.content])
  }

  /// Tool definitions that entered the context part way through.
  static func loadedTools(_ records: [[String: Any]]) -> DemoInput {
    DemoInput(
      fields: [
        "type": "attachment",
        "attachment": ["type": "deferred_tools_record", "entries": records],
      ],
      sized: records.map { JSONLines.text($0, pretty: true) })
  }
}

/// A memory file.
struct DemoFile {
  let path: String
  let type: String
  let content: String

  var record: [String: Any] { ["path": path, "type": type, "content": content] }
}

/// One tool call and what it returned.
struct DemoCall {
  let name: String
  let input: [String: Any]
  let result: String
  /// What the harness recorded about the result beside it.
  var record: [String: Any]?
  /// The subagent run a call to Agent started.
  var agent: DemoAgent?
}

/// A subagent run: its own lane, started by one call in the main lane.
struct DemoAgent {
  let id: String
  let type: String
  let prompt: String
  let turns: [DemoTurn]
}
