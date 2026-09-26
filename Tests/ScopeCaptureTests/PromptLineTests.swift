import Foundation
import ScopeCore
import Testing

@testable import ScopeCapture

@Suite("prompt lines")
struct PromptLineTests {
  @Test("the first line with anything on it, white space made single")
  func firstLine() {
    #expect(
      PromptLine.first(of: "\n  \n  Fix   the\tflaky test\nmore detail") == "Fix the flaky test")
    #expect(PromptLine.first(of: "one line") == "one line")
    #expect(PromptLine.first(of: " \n\t\n") == nil)
    #expect(PromptLine.first(of: "") == nil)
  }

  @Test("the harness's tags are taken out, and a line of tags alone reads as its name")
  func markup() {
    #expect(
      PromptLine.first(of: "<command-message>next-iteration</command-message>\nmore")
        == "next-iteration")
    #expect(
      PromptLine.first(of: "<task-notification>\n<task-id>7</task-id>") == "task notification")
    #expect(PromptLine.first(of: "is a < b and <<EOF fine") == "is a < b and <<EOF fine")
    #expect(PromptLine.first(of: "<b>bold</b>", markup: false) == "<b>bold</b>")
    #expect(PromptLine.first(of: "## Context Usage\nrest") == "Context Usage")
    #expect(PromptLine.first(of: "#hashtag stays") == "#hashtag stays")
  }

  @Test("a long line is cut at a word, with an ellipsis, inside the limit")
  func cut() throws {
    let long = Array(repeating: "retry", count: 40).joined(separator: " ")
    let line = try #require(PromptLine.first(of: long, limit: 30))
    #expect(line.count <= 30)
    #expect(line.hasSuffix("retry\u{2026}"))
    let word = String(repeating: "x", count: 100)
    let cutWord = try #require(PromptLine.first(of: word, limit: 30))
    #expect(cutWord.count == 30)
  }

  @Test("a lane's prompts are read back through the same call a block's text uses")
  func fromTheTranscript() throws {
    let url = try #require(
      Bundle.module.url(forResource: "Fixtures/short-session", withExtension: "jsonl"))
    var builder = LaneBuilder(
      id: .main, agentType: nil, parentToolUseID: nil, window: nil, url: url)
    builder.append(try ClaudeCodeAdapter.entries(at: url))
    let lane = builder.finish().lane
    let lines = PromptLine.lines(of: lane) { builder.content(of: $0) }
    #expect(lane.prompts.count == 6)
    #expect(lines.count == lane.prompts.count)
    #expect(lines.values.allSatisfy { !$0.isEmpty && $0.count <= PromptLine.limit })
    #expect(lines.values.allSatisfy { !$0.contains("\n") })
  }

  @Test("a lane nobody typed in has no lines")
  func none() {
    let lane = Lane(id: .main, window: .given(200_000), segments: [], snapshots: [])
    #expect(PromptLine.lines(of: lane) { _ in nil }.isEmpty)
  }
}
