import Foundation

/// Transcript lines the way the harness writes them: one JSON object per
/// line, slashes left alone. Shared by everything the CLI writes a transcript
/// with, the bench's synthetic session and the demo.
enum JSONLines {
  static func line(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
  }

  /// Lines joined into the bytes of a file, each one ending in a newline.
  static func file(_ lines: [Data]) -> Data {
    var file = Data()
    for item in lines {
      file.append(item)
      file.append(0x0a)
    }
    return file
  }

  /// A value as the JSON text a reader re-renders it to: sorted keys, and
  /// indented when `pretty`.
  static func text(_ value: Any, pretty: Bool) -> String {
    var options: JSONSerialization.WritingOptions = [
      .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed,
    ]
    if pretty { options.insert(.prettyPrinted) }
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: options) else {
      return ""
    }
    return String(decoding: data, as: UTF8.self)
  }
}
