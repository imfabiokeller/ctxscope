import Foundation

enum JSONLines {
  static func line(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
  }

  static func file(_ lines: [Data]) -> Data {
    var file = Data()
    for item in lines {
      file.append(item)
      file.append(0x0a)
    }
    return file
  }

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
