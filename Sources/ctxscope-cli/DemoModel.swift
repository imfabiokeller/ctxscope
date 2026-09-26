import Foundation

// Everything in the demo is invented: never put real transcript or repository text here.

struct DemoTurn {
  var inputs: [DemoInput] = []
  var thinking: String?
  var thinkingTokens = 0
  var text: String?
  var calls: [DemoCall] = []
  var gap: Double = 12
  var cache: DemoCache = .warm
}

enum DemoCache {
  case warm
  case prefix
  case cold
}

struct DemoInput {
  let fields: [String: Any]
  let sized: [String]

  var isPrompt: Bool { (fields["origin"] as? [String: Any])?["kind"] as? String == "human" }

  static func prompt(_ text: String) -> DemoInput {
    DemoInput(
      fields: [
        "type": "user", "message": ["role": "user", "content": text],
        "origin": ["kind": "human"],
      ],
      sized: [text])
  }

  static func task(_ text: String) -> DemoInput {
    DemoInput(
      fields: ["type": "user", "message": ["role": "user", "content": text]], sized: [text])
  }

  static func rendered(_ type: String, _ text: String, fields: [String: Any] = [:])
    -> DemoInput
  {
    var attachment = fields
    attachment["type"] = type
    return DemoInput(
      fields: ["type": "attachment", "attachment": attachment, "rendered": [["content": text]]],
      sized: [text])
  }

  static func instructions(_ files: [DemoFile]) -> DemoInput {
    DemoInput(
      fields: [
        "type": "attachment",
        "attachment": ["type": "instructions", "files": files.map(\.record)],
      ],
      sized: files.map(\.content))
  }

  static func nestedMemory(_ file: DemoFile) -> DemoInput {
    DemoInput(
      fields: [
        "type": "attachment",
        "attachment": ["type": "nested_memory", "path": file.path, "content": file.record],
      ],
      sized: [file.content])
  }

  static func loadedTools(_ records: [[String: Any]]) -> DemoInput {
    DemoInput(
      fields: [
        "type": "attachment",
        "attachment": ["type": "deferred_tools_record", "entries": records],
      ],
      sized: records.map { JSONLines.text($0, pretty: true) })
  }
}

struct DemoFile {
  let path: String
  let type: String
  let content: String

  var record: [String: Any] { ["path": path, "type": type, "content": content] }
}

struct DemoCall {
  let name: String
  let input: [String: Any]
  let result: String
  var record: [String: Any]?
  var agent: DemoAgent?
}

struct DemoAgent {
  let id: String
  let type: String
  let prompt: String
  let turns: [DemoTurn]
}
