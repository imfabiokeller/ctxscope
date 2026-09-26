package import Foundation

/// A JSON value that remembers where in the source it was written.
///
/// A settings file belongs to the person who wrote it. Decoding one and
/// encoding it again would reorder its keys, rewrite its indentation and touch
/// lines nobody asked to change, so ctxscope parses the bytes, keeps the range
/// of every value, and edits the file by splicing text into it.
package struct JSONSpan: Sendable {
  package indirect enum Kind: Sendable {
    case object([Member])
    case array([JSONSpan])
    case string(String)
    case number
    case bool(Bool)
    case null
  }

  /// One key and its value. The range runs from the opening quote of the name
  /// to the last byte of the value, which is what a member costs in the file.
  package struct Member: Sendable {
    package let name: String
    package let range: Range<Int>
    package let value: JSONSpan
  }

  package let kind: Kind
  /// Byte offsets into the data this was parsed from.
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

  /// What is wrong with a file ctxscope refuses to touch. The message names
  /// the line, because a person who has to fix it needs to find it.
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

  /// How deep a document may nest. A settings file is three or four levels;
  /// anything near this is either a mistake or an attempt to run the parser
  /// out of stack, and a refusal is the answer to both.
  package static let depthLimit = 200

  /// Parses one JSON document. Comments are not JSON and are not accepted:
  /// a file with one is refused rather than rewritten without it.
  ///
  /// It never traps. A settings file is somebody else's bytes, and every shape
  /// they can take has to come back as a refusal rather than as a crash: a
  /// file this throws on is a file ctxscope leaves alone.
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
