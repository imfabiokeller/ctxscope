internal import Foundation

// Untyped on purpose: transcript shapes change between harness versions.
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
      // JSONSerialization returns bridged NSStrings; making them native once avoids
      // the slow foreign path on every later read.
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
      // NSNumber hides whether the literal was a bool, an int or a double. 9e15 keeps
      // the integer inside the range a Double holds exactly.
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

  func jsonText(pretty: Bool = true) -> String {
    var options: JSONSerialization.WritingOptions = [
      .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed,
    ]
    if pretty { options.insert(.prettyPrinted) }
    guard let data = try? JSONSerialization.data(withJSONObject: anyValue, options: options)
    else { return compactText }
    return String(decoding: data, as: UTF8.self)
  }

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
