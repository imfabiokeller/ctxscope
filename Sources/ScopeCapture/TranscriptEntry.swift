internal import Foundation
internal import ScopeCore

struct TranscriptEntry: Sendable {
  let raw: JSONValue
  let range: EntryRange?

  init(_ raw: JSONValue, range: EntryRange? = nil) {
    self.raw = raw
    self.range = range
  }

  init(_ line: JSONLReader.Line) {
    self.init(line.value, range: line.range)
  }

  var kind: String { raw["type"]?.string ?? "" }
  var uuid: String? { raw["uuid"]?.string }
  var parentUUID: String? { raw["parentUuid"]?.string }
  var sessionID: String? { raw["sessionId"]?.string }

  var timestamp: Double? {
    guard let text = raw["timestamp"]?.string else { return nil }
    return TranscriptEntry.parseTimestamp(text)
  }

  var requestID: String? { raw["requestId"]?.string }

  var model: String? { raw["message"]?["model"]?.string }

  var stopReason: String? { raw["message"]?["stop_reason"]?.string }

  var usage: RequestUsage? {
    guard let usage = raw["message"]?["usage"] else { return nil }
    return RequestUsage(
      inputTokens: usage["input_tokens"]?.int ?? 0,
      cacheReadTokens: usage["cache_read_input_tokens"]?.int ?? 0,
      cacheCreationTokens: usage["cache_creation_input_tokens"]?.int ?? 0,
      outputTokens: usage["output_tokens"]?.int ?? 0,
      thinkingTokens: usage["output_tokens_details"]?["thinking_tokens"]?.int ?? 0,
      ephemeral1hTokens: usage["cache_creation"]?["ephemeral_1h_input_tokens"]?.int ?? 0,
      ephemeral5mTokens: usage["cache_creation"]?["ephemeral_5m_input_tokens"]?.int ?? 0,
      iterations: max(1, usage["iterations"]?.array?.count ?? 1),
      iterationModels: (usage["iterations"]?.array ?? []).compactMap { $0["model"]?.string }
    )
  }

  var blocks: [JSONValue] {
    guard let content = raw["message"]?["content"] else { return [] }
    if let list = content.array { return list }
    if let text = content.string {
      return [.object(["type": .string("text"), "text": .string(text)])]
    }
    return []
  }

  var attachmentType: String? { raw["attachment"]?["type"]?.string }
  var attachment: JSONValue? { raw["attachment"] }

  var renderedBlocks: [JSONValue]? { raw["rendered"]?.array }

  var systemSubtype: String? { raw["subtype"]?.string }
  var compactMetadata: JSONValue? { raw["compactMetadata"] }
  var isCompactSummary: Bool { raw["isCompactSummary"]?.bool ?? false }

  // Parsed by hand: a date formatter is slower and cannot be held by a Sendable type.
  static func parseTimestamp(_ text: String) -> Double? {
    let digits = Array(text.utf8)
    guard digits.count >= 19 else { return nil }
    func number(_ range: Range<Int>) -> Int? {
      var value = 0
      for index in range {
        let digit = Int(digits[index]) - 48
        guard (0...9).contains(digit) else { return nil }
        value = value * 10 + digit
      }
      return value
    }
    guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
      let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19)
    else { return nil }

    // Days from the civil calendar, Howard Hinnant's algorithm.
    let shifted = month <= 2 ? year - 1 : year
    let era = (shifted >= 0 ? shifted : shifted - 399) / 400
    let yearOfEra = shifted - era * 400
    let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    let days = era * 146_097 + dayOfEra - 719_468

    var seconds = Double(days * 86_400 + hour * 3600 + minute * 60 + second)
    if digits.count > 20, digits[19] == UInt8(ascii: "."), let milliseconds = number(20..<23) {
      seconds += Double(milliseconds) / 1000
    }
    return seconds
  }
}
