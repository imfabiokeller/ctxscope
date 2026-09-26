import Foundation
import Testing

@testable import ScopeConnect

@Suite("the diff shown before a write")
struct TextDiffTests {
  @Test("no change is no diff")
  func nothing() {
    let text = Data("{\n  \"a\": 1\n}\n".utf8)
    #expect(TextDiff.lines(from: text, to: text).isEmpty)
    #expect(TextDiff.text(from: text, to: text).isEmpty)
  }

  @Test("added lines are marked and the kept ones around them are shown")
  func added() {
    let before = Data("{\n  \"a\": 1\n}\n".utf8)
    let after = Data("{\n  \"a\": 1,\n  \"b\": 2\n}\n".utf8)
    let lines = TextDiff.lines(from: before, to: after)
    #expect(lines.filter { $0.mark == .added }.map(\.text) == ["  \"a\": 1,", "  \"b\": 2"])
    #expect(lines.filter { $0.mark == .removed }.map(\.text) == ["  \"a\": 1"])
    #expect(lines.contains { $0.mark == .kept && $0.text == "{" })
  }

  @Test("long runs of unchanged lines are counted rather than printed")
  func skipped() {
    let filler = (1...20).map { "  \"k\($0)\": \($0)," }.joined(separator: "\n")
    let before = Data("{\n\(filler)\n  \"z\": 0\n}\n".utf8)
    let after = Data("{\n\(filler)\n  \"z\": 1\n}\n".utf8)
    let lines = TextDiff.lines(from: before, to: after)
    #expect(lines.contains { $0.mark == .skipped })
    #expect(lines.count < 12)
  }

  @Test("what connecting would write reads as one block of added lines")
  func connectDiff() throws {
    let before = Data("{\n  \"model\": \"opus\"\n}\n".utf8)
    let after = try SettingsEdit.connected(before, port: 45871)
    let text = TextDiff.text(from: before, to: after)
    #expect(text.contains("+     \"SessionEnd\": ["))
    #expect(text.contains("+             \"url\": \"http://127.0.0.1:45871/ctxscope/hook\","))
    #expect(!text.contains("- {"))
  }

  @Test("a big file is diffed in a time somebody would wait for")
  func size() throws {
    let before = Data(
      ("{\n" + (0..<200_000).map { "  \"k\($0)\": \($0)," }.joined(separator: "\n")
        + "\n  \"last\": 0\n}\n").utf8)
    var after = String(decoding: before, as: UTF8.self)
    after = after.replacingOccurrences(of: "  \"k100000\": 100000,", with: "  \"k100000\": 1,")
    let started = Date()
    let lines = TextDiff.lines(from: before, to: Data(after.utf8))
    let took = Date().timeIntervalSince(started)
    #expect(took < 5, "a 200,000 line file took \(took) s")
    #expect(lines.filter { $0.mark == .added }.map(\.text) == ["  \"k100000\": 1,"])
    #expect(lines.filter { $0.mark == .removed }.map(\.text) == ["  \"k100000\": 100000,"])
    #expect(lines.count < 10)
  }

  @Test("a diff nobody could read is cut off and says how much it cut")
  func capped() {
    let before = Data((0..<2_000).map { "line \($0)" }.joined(separator: "\n").utf8)
    let after = Data((0..<2_000).map { "other \($0)" }.joined(separator: "\n").utf8)
    let lines = TextDiff.lines(from: before, to: after)
    #expect(lines.count == TextDiff.maxLines + 1)
    #expect(lines.last?.mark == .skipped)
    #expect(lines.last?.text.hasSuffix("more lines") == true)
  }

  @Test("a plan works its own diff out, and does not carry one around")
  func planDiff() throws {
    let before = Data("{\n  \"model\": \"opus\"\n}\n".utf8)
    let after = try SettingsEdit.connected(before, port: 45871)
    #expect(TextDiff.text(from: before, to: after).contains("+   \"hooks\": {"))
  }
}
