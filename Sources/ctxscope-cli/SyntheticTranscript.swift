import Foundation
import ScopeCore

enum SyntheticTranscript {
  struct Shape {
    var requests: Int
    var parallelEvery: Int
    var resultCharacters: Int
    var thinkingCharacters: Int
  }

  static let realistic = Shape(
    requests: 400, parallelEvery: 3, resultCharacters: 6000, thinkingCharacters: 1200)

  @discardableResult
  static func write(_ shape: Shape, to url: URL) throws -> Int {
    var lines: [Data] = []
    var parent = "root"
    var total = 40_000

    lines.append(
      try JSONLines.line([
        "type": "user", "uuid": "root", "parentUuid": NSNull(),
        "message": ["role": "user", "content": text(400)],
      ]))

    for request in 0..<shape.requests {
      let calls = request % shape.parallelEvery == 0 ? 3 : 1
      let output = 200 + calls * 60
      total += output + shape.resultCharacters * calls / 3
      let usage: [String: Any] = [
        "input_tokens": 2,
        "cache_read_input_tokens": total,
        "cache_creation_input_tokens": 0,
        "output_tokens": output,
        "output_tokens_details": ["thinking_tokens": 120],
      ]

      lines.append(
        try JSONLines.line(
          assistant(
            uuid: "t\(request)", parent: parent, request: "r\(request)", usage: usage,
            block: [
              "type": "thinking", "thinking": text(shape.thinkingCharacters),
              "signature": text(600),
            ])))
      parent = "t\(request)"

      var callIDs: [String] = []
      for call in 0..<calls {
        let id = "c\(request)_\(call)"
        callIDs.append(id)
        lines.append(
          try JSONLines.line(
            assistant(
              uuid: "u\(id)", parent: parent, request: "r\(request)", usage: usage,
              block: [
                "type": "tool_use", "id": id, "name": "Read",
                "input": ["file_path": "/a/b/File\(call).swift"],
              ])))
        parent = "u\(id)"
      }

      let last = parent
      for (index, id) in callIDs.enumerated() {
        let uuid = "res\(id)"
        let isLast = index == callIDs.count - 1
        lines.append(
          try JSONLines.line([
            "type": "user", "uuid": uuid, "parentUuid": isLast ? last : "u\(id)",
            "message": [
              "role": "user",
              "content": [
                ["type": "tool_result", "tool_use_id": id, "content": text(shape.resultCharacters)]
              ],
            ],
          ]))
        if isLast { parent = uuid }
      }
    }

    try JSONLines.file(lines).write(to: url)
    return lines.count
  }

  private static func assistant(
    uuid: String,
    parent: String,
    request: String,
    usage: [String: Any],
    block: [String: Any]
  ) -> [String: Any] {
    [
      "type": "assistant", "uuid": uuid, "parentUuid": parent, "requestId": request,
      "timestamp": "2026-01-01T00:00:00.000Z",
      "message": [
        "model": "synthetic", "role": "assistant", "content": [block], "usage": usage,
      ],
    ]
  }

  private static func text(_ count: Int) -> String {
    let unit = "alpha bravo charlie delta echo foxtrot golf hotel india juliet "
    var out = ""
    out.reserveCapacity(count + unit.count)
    while out.count < count { out += unit }
    return String(out.prefix(count))
  }
}
