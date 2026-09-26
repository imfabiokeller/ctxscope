import Foundation
import ScopeCore
import Testing

@testable import ScopeCapture

@Suite("tools loaded mid-session")
struct LoadedToolTests {
  static func entry(_ names: [String], uuid: String = UUID().uuidString, parent: String? = nil)
    throws -> TranscriptEntry
  {
    var object: [String: Any] = [
      "type": "attachment",
      "uuid": uuid,
      "attachment": [
        "type": "deferred_tools_record",
        "entries": names.map { name in
          [
            "name": name, "description": "a tool", "defer_loading": true,
            "input_schema": ["type": "object", "properties": [:]],
          ] as [String: Any]
        },
      ],
    ]
    if let parent { object["parentUuid"] = parent }
    let data = try JSONSerialization.data(withJSONObject: object)
    return TranscriptEntry(try JSONValue(parsing: data))
  }

  static func text(_ entry: TranscriptEntry) throws -> String {
    String(
      decoding: try JSONSerialization.data(withJSONObject: entry.raw.anyValue), as: UTF8.self)
  }

  @Test("one block per loaded tool, banded by what the name says")
  func oneBlockPerTool() throws {
    let reader = EntryReader()
    let pieces = reader.pieces(of: try Self.entry(["Read", "mcp__srv__verb"]))
    #expect(pieces.count == 2)
    #expect(pieces.map(\.band) == [.tools, .mcp])
    #expect(pieces.map(\.label) == ["Read", "mcp__srv__verb"])
    #expect(pieces.allSatisfy { $0.contentClass == .json })
    #expect(pieces.allSatisfy { !$0.text.isEmpty })
    #expect(pieces.map(\.toolName) == ["Read", "mcp__srv__verb"])
  }

  @Test("a loaded tool is a block of the request it arrived at")
  func bornAtTheRequestThatLoadedIt() throws {
    // Spliced in the way the harness writes one: the record takes the next entry's parent, and
    // the next entry takes the record's place.
    let lines = try PrefixParityTests.lines("short-session")
    let cut = try #require(
      lines.indices.dropFirst(lines.count / 2).first { index in
        let value = try? JSONValue(parsing: Data(lines[index].utf8))
        return value?["parentUuid"]?.string != nil
      })
    let next = try JSONValue(parsing: Data(lines[cut].utf8))
    let uuid = UUID().uuidString
    let record = try Self.entry(
      ["mcp__srv__late"], uuid: uuid, parent: next["parentUuid"]?.string)
    var rewritten = next.object ?? [:]
    rewritten["parentUuid"] = .string(uuid)
    let spliced =
      Array(lines[0..<cut]) + [try Self.text(record)]
      + [try Self.text(TranscriptEntry(.object(rewritten)))] + Array(lines[(cut + 1)...])

    let directory = FileManager.default.temporaryDirectory
      .appending(path: "ctxscope-loaded-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "session.jsonl")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    try IncrementalTests.append(spliced, to: url)

    var capture = SessionCapture(
      session: IncrementalTests.reference(url), includeSubagents: false, window: nil)
    try capture.refresh()
    let lane = try #require(capture.finish().recording.mainLane)
    let late = try #require(lane.segments.first { $0.label == "mcp__srv__late" })
    #expect(late.band == .mcp)
    #expect(late.born > 0)
    #expect(late.tokens.value > 0)
    #expect(Validator.run(lane).mismatches.isEmpty)
  }
}
