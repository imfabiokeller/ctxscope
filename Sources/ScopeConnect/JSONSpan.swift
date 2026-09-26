package import Foundation

// Settings files are edited by splicing bytes, never decoded and re-encoded,
// so key order, indentation and untouched lines stay as written.
package struct JSONSpan: Sendable {
  package indirect enum Kind: Sendable {
    case object([Member])
    case array([JSONSpan])
    case string(String)
    case number
    case bool(Bool)
    case null
  }

  package struct Member: Sendable {
    package let name: String
    package let range: Range<Int>
    package let value: JSONSpan
  }

  package let kind: Kind
  package let range: Range<Int>

  package subscript(key: String) -> JSONSpan? {
    members?.first { $0.name == key }?.value
  }

  package var members: [Member]? {
    guard case .object(let members) = kind else { return nil }
    return members
  }

  package var elements: [JSONSpan]? {
    guard case .array(let elements) = kind else { return nil }
    return elements
  }

  package var text: String? {
    guard case .string(let value) = kind else { return nil }
    return value
  }

  package var flag: Bool? {
    guard case .bool(let value) = kind else { return nil }
    return value
  }

  package enum Invalid: Error, CustomStringConvertible, Equatable {
    case empty
    case unexpected(String, line: Int)

    package var description: String {
      switch self {
      case .empty: "the file is empty"
      case .unexpected(let what, let line): "\(what) on line \(line)"
      }
    }
  }

  // A settings file nests three or four levels; this refuses input meant to
  // exhaust the parser's stack.
  package static let depthLimit = 200

  // Safety: never traps. Any bytes, comments included, come back as a refusal,
  // and a file it refuses is left alone.
  package static func parse(_ data: Data) throws -> JSONSpan {
    var reader = JSONReader(bytes: [UInt8](data))
    reader.skipSpace()
    guard reader.at < reader.bytes.count else { throw Invalid.empty }
    let value = try reader.value()
    reader.skipSpace()
    guard reader.at == reader.bytes.count else {
      throw reader.fail("text after the end of the document")
    }
    return value
  }
}
