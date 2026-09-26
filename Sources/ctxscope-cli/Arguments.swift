import Foundation
import ScopeCore

struct Arguments {
  static let valued: Set<String> = [
    "lane", "at", "format", "out", "window", "limit", "project", "requests", "seed",
    "capture-requests", "port", "claude-home", "home", "live", "start",
  ]

  let command: String
  let positional: [String]
  private let flags: [String: String]
  private let switches: Set<String>

  init(_ raw: [String]) {
    var positional: [String] = []
    var flags: [String: String] = [:]
    var switches: Set<String> = []
    var index = 0
    while index < raw.count {
      let item = raw[index]
      if item.hasPrefix("--") {
        let name = String(item.dropFirst(2))
        if let equals = name.firstIndex(of: "=") {
          flags[String(name[name.startIndex..<equals])] = String(name[name.index(after: equals)...])
        } else if Self.valued.contains(name), index + 1 < raw.count,
          !raw[index + 1].hasPrefix("--")
        {
          flags[name] = raw[index + 1]
          index += 1
        } else {
          switches.insert(name)
        }
      } else {
        positional.append(item)
      }
      index += 1
    }
    command = positional.first ?? "help"
    self.positional = Array(positional.dropFirst())
    self.flags = flags
    self.switches = switches
  }

  func value(_ name: String) -> String? { flags[name] }

  func integer(_ name: String) -> Int? { flags[name].flatMap(Int.init) }

  func requestNumber(_ name: String) throws -> Int? {
    guard let text = flags[name] else { return nil }
    guard let value = Int(text), value >= 1 else {
      throw CLIError.usage(
        "--\(name) takes a request number counting from 1, not \"\(text)\"")
    }
    return RequestNumber.index(value)
  }

  func has(_ name: String) -> Bool { switches.contains(name) || flags[name] != nil }

  var first: String? { positional.first }
}

enum CLIError: Error, CustomStringConvertible {
  case usage(String)

  var description: String {
    switch self {
    case .usage(let text): text
    }
  }
}

enum Console {
  static func out(_ text: String) {
    print(text)
  }

  static func error(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
  }
}
