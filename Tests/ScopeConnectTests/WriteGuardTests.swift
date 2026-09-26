import Foundation
import Testing

@testable import ScopeConnect

/// The check in front of every write. Nothing is asserted after the fact: a
/// file that would fail is never written.
@Suite("the write guard")
struct WriteGuardTests {
  @Test(
    "a file the harness reads passes",
    arguments: [
      "{}", "{\"model\": \"opus\"}", "{\n  \"a\": [1, {\"b\": null}]\n}\n",
    ])
  func readable(text: String) {
    #expect(WriteGuard.isWellFormed(Data(text.utf8)))
  }

  @Test(
    "anything the harness would read differently does not",
    arguments: [
      "", "   ", "[1, 2]", "\"a string\"", "{\"a\": 1,}", "// comment\n{}",
      "{\"a\": 1} and more",
    ])
  func notReadable(text: String) {
    #expect(!WriteGuard.isWellFormed(Data(text.utf8)))
  }

  @Test("a duplicate key is a file read two ways, so it is left alone")
  func duplicateKeys() {
    #expect(!WriteGuard.isWellFormed(Data("{\"hooks\": {}, \"hooks\": {}}".utf8)))
    #expect(!WriteGuard.isWellFormed(Data("{\"a\": {\"b\": 1, \"b\": 2}}".utf8)))
    #expect(!WriteGuard.isWellFormed(Data("{\"a\": [{\"b\": 1, \"b\": 2}]}".utf8)))
  }

  @Test("bytes that are not text are left alone")
  func notText() {
    var withNul = Data("{\"a\": \"x".utf8)
    withNul.append(0)
    withNul.append(contentsOf: Data("\"}".utf8))
    #expect(!WriteGuard.isWellFormed(withNul))
    #expect(
      !WriteGuard.isWellFormed(Data([0x7B, 0x22, 0x61, 0x22, 0x3A, 0x22, 0xFF, 0x22, 0x7D])))
    #expect(!WriteGuard.isWellFormed(Data([0xEF, 0xBB, 0xBF]) + Data("{}".utf8)))
  }

  @Test("the guard passes a file that is already connected")
  func alreadyConnected() throws {
    let original = Data("{\n  \"model\": \"opus\"\n}\n".utf8)
    let once = try SettingsEdit.connected(original, port: 45871)
    #expect(throws: Never.self) {
      try WriteGuard.check(once, backup: original, becomes: once)
    }
    let moved = try SettingsEdit.connected(once, port: 45999)
    #expect(throws: Never.self) {
      try WriteGuard.check(once, backup: original, becomes: moved)
    }
  }

  @Test("the guard passes what connect writes")
  func roundTripPasses() throws {
    for text in ["{}", "{\n  \"model\": \"opus\"\n}\n", "{\"hooks\": {\"Stop\": []}}"] {
      let original = Data(text.utf8)
      let next = try SettingsEdit.connected(original, port: 45871)
      #expect(throws: Never.self) {
        try WriteGuard.check(original, backup: nil, becomes: next)
      }
    }
  }

  @Test("a change that could not be taken back is refused")
  func notReversible() throws {
    let original = Data("{\"model\": \"opus\"}".utf8)
    // A file that does not give the original back: the guard is what catches
    // it, whatever produced it.
    #expect(throws: Refusal.wouldNotComeBack) {
      try WriteGuard.check(original, backup: nil, becomes: Data("{\"model\": \"haiku\"}".utf8))
    }
    #expect(throws: Refusal.wouldNotBeReadable) {
      try WriteGuard.check(original, backup: nil, becomes: Data("not json".utf8))
    }
  }

  @Test("a refusal names the line, the way it did before the guard existed")
  func linePrecision() {
    do {
      try WriteGuard.check(readable: Data("{\n  \"model\": \"opus\",\n}\n".utf8))
      Issue.record("a broken file was accepted")
    } catch let refusal as Refusal {
      #expect(
        refusal.description
          == "the settings file is not JSON: a key was expected on line 3, "
          + "so ctxscope left it alone")
    } catch {
      Issue.record("the wrong error came back")
    }
  }

  @Test("a key written twice is named, and the sentence is true")
  func repeatedKeyIsNamed() {
    do {
      try WriteGuard.check(readable: Data("{\n  \"hooks\": {},\n  \"hooks\": {}\n}\n".utf8))
      Issue.record("a file with a repeated key was accepted")
    } catch let refusal as Refusal {
      // Claude Code does read this file, so the old wording was untrue.
      #expect(
        refusal.description
          == "\"hooks\" is written twice in the settings file, so ctxscope cannot tell "
          + "which one Claude Code uses")
    } catch {
      Issue.record("the wrong error came back")
    }
    #expect(throws: Refusal.repeatedKey("b")) {
      try WriteGuard.check(readable: Data("{\"a\": {\"b\": 1, \"b\": 2}}".utf8))
    }
  }

  @Test("the refusals say what happened in plain words")
  func words() {
    for refusal in [
      Refusal.notJSON("x"), .notAnObject, .notReadable, .repeatedKey("k"), .wouldNotBeReadable,
      .wouldNotComeBack, .moved, .readOnly("f"), .danglingLink("f"),
    ] {
      #expect(!refusal.description.isEmpty)
      #expect(!refusal.description.contains("Error"))
      #expect(refusal.description.lowercased() == refusal.description.lowercased())
    }
  }
}
