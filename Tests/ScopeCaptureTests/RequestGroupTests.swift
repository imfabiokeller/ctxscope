import Foundation
import ScopeCore
import Testing

@testable import ScopeCapture

/// One API call written as several entries is the normal case, not the edge
/// case: 6937 requests of this machine's transcripts are written as three.
@Suite("Request groups")
struct RequestGroupTests {
  static func entry(_ json: String) throws -> TranscriptEntry {
    TranscriptEntry(try JSONValue(parsing: Data(json.utf8)))
  }

  /// The requests a list of entries makes, the way the live build groups them.
  static func requests(in entries: [TranscriptEntry]) -> [LaneBuilder.RequestGroup] {
    var log = RequestLog()
    for entry in entries where entry.kind == "assistant" && entry.usage != nil {
      log.ingest(entry)
    }
    _ = log.advance(final: true)
    return log.requests
  }

  static func streamedThinkingResponse() throws -> [TranscriptEntry] {
    [
      try entry(
        """
        {"type":"assistant","uuid":"a1","parentUuid":"u0","requestId":"r1",
         "message":{"model":"m","content":[{"type":"thinking","thinking":"aaaa","signature":"s"}],
         "usage":{"input_tokens":10,"cache_read_input_tokens":90,
         "cache_creation_input_tokens":0,"output_tokens":500,
         "output_tokens_details":{"thinking_tokens":400}}}}
        """),
      try entry(
        """
        {"type":"assistant","uuid":"a2","parentUuid":"a1","requestId":"r1",
         "message":{"model":"m","stop_reason":"end_turn",
         "content":[{"type":"text","text":"bbbb"}],
         "usage":{"input_tokens":10,"cache_read_input_tokens":90,
         "cache_creation_input_tokens":0,"output_tokens":500,
         "output_tokens_details":{"thinking_tokens":400}}}}
        """),
    ]
  }

  @Test("a response streamed as several entries counts its thinking once")
  func thinkingIsNotCountedTwice() throws {
    let entries = try Self.streamedThinkingResponse()
    let requests = Self.requests(in: entries)
    #expect(requests.count == 1)
    let request = try #require(requests.first)
    #expect(request.entryCount == 2)
    #expect(request.hasThinking)

    var totals: [Int: Int] = [:]
    let reader = EntryReader()
    for entry in entries {
      let pieces = reader.pieces(of: entry)
      _ = LaneBuilder.groups(
        for: entry, pieces: pieces, origin: request, originIndex: 0, complete: true,
        totals: &totals)
    }
    // Thinking 400, the rest of the output 100. Not 400 plus 500.
    #expect(totals[0] == 400)
    #expect(totals[1] == 100)
    #expect(totals.values.reduce(0, +) == request.usage.outputTokens)
  }

  @Test("the second entry of a response does not reset the output group")
  func secondEntryDoesNotReset() throws {
    let entries = try Self.streamedThinkingResponse()
    let request = try #require(Self.requests(in: entries).first)
    var totals: [Int: Int] = [:]
    let reader = EntryReader()
    // The entry without a thinking block, on its own. It must still know that
    // the response it belongs to had thinking.
    let pieces = reader.pieces(of: entries[1])
    _ = LaneBuilder.groups(
      for: entries[1], pieces: pieces, origin: request, originIndex: 0, complete: true,
      totals: &totals)
    #expect(totals[1] == 100)
  }

  @Test("a response without thinking uses the whole output")
  func noThinking() throws {
    let entries = [
      try Self.entry(
        """
        {"type":"assistant","uuid":"a1","parentUuid":"u0","requestId":"r1",
         "message":{"model":"m","stop_reason":"end_turn",
         "content":[{"type":"text","text":"bbbb"}],
         "usage":{"input_tokens":10,"cache_read_input_tokens":90,
         "cache_creation_input_tokens":0,"output_tokens":120}}}
        """)
    ]
    let request = try #require(Self.requests(in: entries).first)
    #expect(!request.hasThinking)
    var totals: [Int: Int] = [:]
    let reader = EntryReader()
    _ = LaneBuilder.groups(
      for: entries[0], pieces: reader.pieces(of: entries[0]), origin: request, originIndex: 0,
      complete: true, totals: &totals)
    #expect(totals[0] == nil)
    #expect(totals[1] == 120)
  }

  @Test("a response that never finished is estimated, not measured")
  func unfinishedResponsesAreNotMeasured() throws {
    let entries = [
      try Self.entry(
        """
        {"type":"assistant","uuid":"a1","parentUuid":"u0","requestId":"r1",
         "message":{"model":"m","content":[{"type":"text","text":"bbbb"}],
         "usage":{"input_tokens":10,"cache_read_input_tokens":90,
         "cache_creation_input_tokens":0,"output_tokens":3}}}
        """)
    ]
    let request = try #require(Self.requests(in: entries).first)
    #expect(!request.isFinished)
    var totals: [Int: Int] = [:]
    let reader = EntryReader()
    let groups = LaneBuilder.groups(
      for: entries[0], pieces: reader.pieces(of: entries[0]), origin: request, originIndex: 0,
      complete: true, totals: &totals)
    #expect(totals.isEmpty)
    #expect(groups == [nil])
  }

  @Test("output tokens are taken from the finished entry of the group")
  func outputTakesTheMaximum() throws {
    let entries = [
      try Self.entry(
        """
        {"type":"assistant","uuid":"a1","parentUuid":"u0","requestId":"r1",
         "message":{"model":"m","content":[{"type":"text","text":"a"}],
         "usage":{"input_tokens":1,"cache_read_input_tokens":99,
         "cache_creation_input_tokens":0,"output_tokens":7}}}
        """),
      try Self.entry(
        """
        {"type":"assistant","uuid":"a2","parentUuid":"a1","requestId":"r1",
         "message":{"model":"m","content":[{"type":"text","text":"b"}],
         "usage":{"input_tokens":1,"cache_read_input_tokens":99,
         "cache_creation_input_tokens":0,"output_tokens":220}}}
        """),
    ]
    let request = try #require(Self.requests(in: entries).first)
    #expect(request.usage.outputTokens == 220)
    #expect(request.usage.promptTotal == 100)
  }

  @Test("a request with no prompt at all is not a call")
  func emptyRequestsAreSkipped() throws {
    let entries = [
      try Self.entry(
        """
        {"type":"assistant","uuid":"a1","parentUuid":"u0","requestId":"r1",
         "message":{"model":"m","content":[],"usage":{"input_tokens":0,
         "cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":0}}}
        """)
    ]
    #expect(Self.requests(in: entries).isEmpty)
  }

  @Test("entries without a request id stand alone")
  func missingRequestID() throws {
    let entries = [
      try Self.entry(
        """
        {"type":"assistant","uuid":"a1","parentUuid":"u0",
         "message":{"model":"m","content":[{"type":"text","text":"a"}],
         "usage":{"input_tokens":1,"cache_read_input_tokens":9,
         "cache_creation_input_tokens":0,"output_tokens":3}}}
        """),
      try Self.entry(
        """
        {"type":"assistant","uuid":"a2","parentUuid":"a1",
         "message":{"model":"m","content":[{"type":"text","text":"b"}],
         "usage":{"input_tokens":1,"cache_read_input_tokens":19,
         "cache_creation_input_tokens":0,"output_tokens":3}}}
        """),
    ]
    #expect(Self.requests(in: entries).count == 2)
  }
}
