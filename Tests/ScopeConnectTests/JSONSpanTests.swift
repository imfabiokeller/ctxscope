import Foundation
import Testing

@testable import ScopeConnect

@Suite("the span parser")
struct JSONSpanTests {
  private func parse(_ text: String) throws -> JSONSpan {
    try JSONSpan.parse(Data(text.utf8))
  }

  @Test("ranges point at the bytes the value was written with")
  func ranges() throws {
    let text = "{\n  \"a\": 1,\n  \"b\": [true, null]\n}\n"
    let root = try parse(text)
    let bytes = [UInt8](text.utf8)
    #expect(String(decoding: bytes[root.range], as: UTF8.self).hasPrefix("{"))
    let member = try #require(root.members?.first)
    #expect(String(decoding: bytes[member.range], as: UTF8.self) == "\"a\": 1")
    let array = try #require(root["b"])
    #expect(String(decoding: bytes[array.range], as: UTF8.self) == "[true, null]")
  }

  @Test("escapes come out as the characters they stand for")
  func escapes() throws {
    let root = try parse(#"{"a\nb": "x\ty\\z\"q\/r\b\f"}"#)
    #expect(root.members?.first?.name == "a\nb")
    #expect(root["a\nb"]?.text == "x\ty\\z\"q/r\u{08}\u{0C}")
  }

  @Test("a surrogate pair is one character")
  func surrogatePair() throws {
    #expect(try parse(#"{"k": "\uD83D\uDE00"}"#)["k"]?.text == "\u{1F600}")
    #expect(try parse(#"{"k": "\u0041\u00e9"}"#)["k"]?.text == "Aé")
    #expect(try parse(#"{"k": "\uDBFF\uDFFF"}"#)["k"]?.text == "\u{10FFFF}")
  }

  @Test(
    "a surrogate that stands alone or comes in the wrong order is replaced, not trapped",
    arguments: [
      #"{"k": "\uD800\u0041"}"#,
      #"{"k": "\uD800"}"#,
      #"{"k": "\uDC00\uD800"}"#,
      #"{"k": "\uDFFF"}"#,
      #"{"k": "\uD800\uD800"}"#,
      #"{"k": "\uD800\uDBFF"}"#,
      #"{"k": "\uDC00abc"}"#,
    ])
  func loneSurrogate(text: String) throws {
    let value = try #require(try parse(text)["k"]?.text)
    #expect(value.unicodeScalars.contains("\u{FFFD}"))
  }

  @Test("a lone high surrogate does not swallow what follows it")
  func loneSurrogateKeepsTheRest() throws {
    #expect(try parse(#"{"k": "\uD800\u0041"}"#)["k"]?.text == "\u{FFFD}A")
    #expect(try parse(#"{"k": "\uD800\uD83D\uDE00"}"#)["k"]?.text == "\u{FFFD}\u{1F600}")
  }

  @Test(
    "numbers are spans, whatever they are written as",
    arguments: [
      "0", "-0", "1.5", "-2.25e-3", "1E+10", "123456789012345678901234567890",
    ])
  func numbers(text: String) throws {
    let root = try parse("{\"n\": \(text)}")
    guard case .number = root["n"]?.kind else {
      Issue.record("\(text) was not read as a number")
      return
    }
  }

  @Test("nesting past the cap is refused rather than run off the stack")
  func deepNesting() throws {
    let fine = String(repeating: "[", count: 100) + String(repeating: "]", count: 100)
    #expect(throws: Never.self) { try parse(fine) }
    let deep = String(repeating: "[", count: 20_000) + String(repeating: "]", count: 20_000)
    #expect(throws: JSONSpan.Invalid.self) { try parse(deep) }
    let objects =
      String(repeating: "{\"a\":", count: 20_000) + "1" + String(repeating: "}", count: 20_000)
    #expect(throws: JSONSpan.Invalid.self) { try parse(objects) }
    do {
      _ = try parse(deep)
    } catch let invalid as JSONSpan.Invalid {
      #expect(invalid.description.contains("\(JSONSpan.depthLimit) levels of nesting"))
    }
  }

  @Test(
    "what is not JSON is refused",
    arguments: [
      "", "   \n ", "{", "}", "[", "{\"a\"}", "{\"a\": }", "{'a': 1}", "{\"a\": 1,}",
      "// comment\n{}", "{\"a\": 1} trailing", "{\"a\": tru}", "{\"a\": 1} {\"b\": 2}",
      "{\"a\": \"unclosed", "{\"a\": \"\\u12\"}", "nan", "{\"a\": \"x\"",
    ])
  func refused(text: String) {
    #expect(throws: (any Error).self) { try parse(text) }
  }

  @Test(
    "a number this reads and the harness does not is caught by the guard",
    arguments: [
      "{\"a\": +1}", "{\"a\": .5}", "{\"a\": 1-2e+.}", "{\"a\": 1.2.3}",
    ])
  func lenientNumbers(text: String) {
    // The scanner accepts it on purpose; the write guard refuses it, as JSONSerialization does.
    #expect(!WriteGuard.isWellFormed(Data(text.utf8)))
  }

  @Test("bytes that are not text come back rather than crash")
  func notText() {
    var withNul = Data("{\"a\": \"x".utf8)
    withNul.append(0)
    withNul.append(contentsOf: Data("\"}".utf8))
    // The parser reads it on purpose; the write guard refuses it, since the harness would read
    // it differently.
    #expect(throws: Never.self) { try JSONSpan.parse(withNul) }
    #expect(!WriteGuard.isWellFormed(withNul))

    let invalidUTF8 = Data([0x7B, 0x22, 0x61, 0x22, 0x3A, 0x22, 0xFF, 0xFE, 0x22, 0x7D])
    #expect(throws: Never.self) { try JSONSpan.parse(invalidUTF8) }
    #expect(!WriteGuard.isWellFormed(invalidUTF8))

    let bom = Data([0xEF, 0xBB, 0xBF]) + Data("{}".utf8)
    #expect(throws: (any Error).self) { try JSONSpan.parse(bom) }
  }

  @Test("the line a refusal names is the line the trouble is on")
  func lineNumbers() {
    do {
      _ = try parse("{\n  \"a\": 1,\n\n  \"b\": @\n}\n")
      Issue.record("a broken file was accepted")
    } catch let invalid as JSONSpan.Invalid {
      #expect(invalid.description == "a value was expected on line 4")
    } catch {
      Issue.record("the wrong error came back")
    }
  }

  @Test("a large file is read in a time somebody would wait for")
  func size() throws {
    let entries = (0..<20_000).map { "    \"key\($0)\": \"value \($0)\"" }
    let text = "{\n" + entries.joined(separator: ",\n") + "\n}\n"
    let started = Date()
    let root = try parse(text)
    #expect(root.members?.count == 20_000)
    #expect(Date().timeIntervalSince(started) < 2)
  }
}
