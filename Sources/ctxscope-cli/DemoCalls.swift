import Foundation

struct DemoProject {
  let home: String
  let cwd: String
  let today: String

  func path(_ relative: String) -> String { cwd + "/" + relative }

  func read(_ relative: String, _ content: String) -> DemoCall {
    let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
    let count = content.hasSuffix("\n") ? lines.count - 1 : lines.count
    return DemoCall(
      name: "Read", input: ["file_path": path(relative)],
      result: Self.numbered(content),
      record: [
        "type": "text",
        "file": [
          "filePath": path(relative), "content": content, "numLines": count,
          "startLine": 1, "totalLines": count,
        ],
      ])
  }

  func bash(_ command: String, _ description: String, _ output: String, failed: Bool = false)
    -> DemoCall
  {
    DemoCall(
      name: "Bash", input: ["command": command, "description": description],
      result: failed ? "Error: Exit code 1\n" + output : output,
      record: [
        "stdout": output, "stderr": "", "interrupted": false, "isImage": false,
      ])
  }

  func grep(_ pattern: String, _ output: String, files: Int) -> DemoCall {
    let lines = output.split(separator: "\n").count
    return DemoCall(
      name: "Grep",
      input: ["pattern": pattern, "output_mode": "content", "-n": true],
      result: output,
      record: ["mode": "content", "numFiles": files, "numLines": lines, "content": output])
  }

  func edit(_ relative: String, _ old: String, _ new: String) -> DemoCall {
    let snippet = Self.numbered(new, from: 12)
    return DemoCall(
      name: "Edit",
      input: ["file_path": path(relative), "old_string": old, "new_string": new],
      result: "The file \(path(relative)) has been updated. Here's the result of running "
        + "`cat -n` on a snippet of the edited file:\n" + snippet,
      record: ["filePath": path(relative), "oldString": old, "newString": new])
  }

  func write(_ relative: String, _ content: String) -> DemoCall {
    DemoCall(
      name: "Write", input: ["file_path": path(relative), "content": content],
      result: "File created successfully at: \(path(relative))",
      record: ["type": "create", "filePath": path(relative), "content": content])
  }

  func fetch(_ url: String, _ prompt: String, _ answer: String) -> DemoCall {
    DemoCall(
      name: "WebFetch", input: ["url": url, "prompt": prompt], result: answer,
      record: [
        "bytes": answer.utf8.count * 9, "code": 200, "codeText": "OK", "result": answer,
        "durationMs": 1840, "url": url,
      ])
  }

  func todo(_ items: [(String, String)]) -> DemoCall {
    DemoCall(
      name: "TodoWrite",
      input: [
        "todos": items.map { ["content": $0.0, "status": $0.1, "activeForm": $0.0] }
      ],
      result: "Todos have been modified successfully. Ensure that you continue to use the "
        + "todo list to track your progress. Please proceed with the current tasks if "
        + "applicable")
  }

  func mcp(_ verb: String, _ input: [String: Any], _ result: String) -> DemoCall {
    DemoCall(name: "mcp__github__" + verb, input: input, result: result)
  }

  func agent(_ run: DemoAgent, description: String, report: String) -> DemoCall {
    DemoCall(
      name: "Agent",
      input: ["description": description, "prompt": run.prompt, "subagent_type": run.type],
      result: report,
      record: [
        "status": "completed", "agentId": run.id, "prompt": run.prompt,
        "totalToolUseCount": run.turns.reduce(0) { $0 + $1.calls.count },
        "content": [["type": "text", "text": report]],
      ],
      agent: run)
  }

  static func numbered(_ content: String, from first: Int = 1) -> String {
    var lines = content.split(separator: "\n", omittingEmptySubsequences: false)
    if content.hasSuffix("\n") { lines.removeLast() }
    return lines.enumerated().map { index, line in
      let number = String(first + index)
      return String(repeating: " ", count: max(0, 6 - number.count)) + number + "\t" + line
    }.joined(separator: "\n")
  }
}
