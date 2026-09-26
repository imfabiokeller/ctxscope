internal import Foundation

/// A tolerant JSON value. Transcripts change shape between harness versions:
/// a field that is a string today is a list tomorrow, and new entry types
/// appear without warning. Decoding into fixed types would fail on the next
/// release, so the adapter reads values it recognises and ignores the rest.
enum JSONValue: Sendable, Hashable {
  case null
  case bool(Bool)
  case number(Double)
  case integer(Int)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  init(parsing data: Data) throws {
    let raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    self = JSONValue(any: raw)
  }

  init(any value: Any) {
    switch value {
    case let value as String:
      // JSONSerialization hands back bridged NSStrings. Every later read of
      // one goes through the slow foreign path, which was about a third of
      // the run time on a large session. Making it contiguous once here is
      // the whole fix.
      var contiguous = value
      contiguous.makeContiguousUTF8()
      self = .string(contiguous)
    case let value as [Any]: self = .array(value.map { JSONValue(any: $0) })
    case let value as [String: Any]:
      var object: [String: JSONValue] = [:]
      object.reserveCapacity(value.count)
      for (key, item) in value { object[key] = JSONValue(any: item) }
      self = .object(object)
    case let value as NSNumber:
      // NSNumber hides whether the literal was a bool, an int or a double.
      if CFGetTypeID(value) == CFBooleanGetTypeID() {
        self = .bool(value.boolValue)
      } else if value.doubleValue == value.doubleValue.rounded(),
        abs(value.doubleValue) < 9e15
      {
        self = .integer(value.intValue)
      } else {
        self = .number(value.doubleValue)
      }
    case is NSNull: self = .null
    default: self = .null
    }
  }

  subscript(key: String) -> JSONValue? {
    guard case .object(let object) = self else { return nil }
    return object[key]
  }

  var string: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  var int: Int? {
    switch self {
    case .integer(let value): value
    case .number(let value): Int(value)
    case .bool(let value): value ? 1 : 0
    default: nil
    }
  }

  var double: Double? {
    switch self {
    case .integer(let value): Double(value)
    case .number(let value): value
    default: nil
    }
  }

  var bool: Bool? {
    switch self {
    case .bool(let value): value
    case .integer(let value): value != 0
    default: nil
    }
  }

  var array: [JSONValue]? {
    if case .array(let value) = self { return value }
    return nil
  }

  var object: [String: JSONValue]? {
    if case .object(let value) = self { return value }
    return nil
  }

  /// Back to the Foundation shapes, for the one place that needs real JSON
  /// out again rather than a length or a field.
  var anyValue: Any {
    switch self {
    case .null: NSNull()
    case .bool(let value): value
    case .integer(let value): value
    case .number(let value): value
    case .string(let value): value
    case .array(let values): values.map(\.anyValue)
    case .object(let values): values.mapValues(\.anyValue)
    }
  }

  /// The value as JSON, re-rendered: keys in a fixed order, and indented when
  /// a person is going to read it.
  ///
  /// The order is alphabetical rather than the order the transcript wrote,
  /// because parsing an object into a dictionary loses that. Fixed is what
  /// matters: the same definition renders the same way every time it is read
  /// back, so the window, the estimator and the judge all see one text.
  func jsonText(pretty: Bool = true) -> String {
    var options: JSONSerialization.WritingOptions = [
      .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed,
    ]
    if pretty { options.insert(.prettyPrinted) }
    guard let data = try? JSONSerialization.data(withJSONObject: anyValue, options: options)
    else { return compactText }
    return String(decoding: data, as: UTF8.self)
  }

  /// Compact re-encoding, used to size tool call inputs the way the wire
  /// carries them.
  var compactText: String {
    switch self {
    case .null: "null"
    case .bool(let value): value ? "true" : "false"
    case .integer(let value): String(value)
    case .number(let value): String(value)
    case .string(let value): value
    case .array(let values): values.map(\.compactText).joined(separator: ",")
    case .object(let values):
      values.sorted { $0.key < $1.key }
        .map { "\($0.key):\($0.value.compactText)" }
        .joined(separator: ",")
    }
  }
}
