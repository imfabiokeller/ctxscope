import Foundation
import ScopeCore

/// A small argument reader. No third-party packages in phases 1 to 3, and the
/// CLI has four commands, so this is all it needs.
struct Arguments {
  /// Flags that take a value. Everything else is a switch, so `validate
  /// --json <id>` reads the id as the id rather than as the value of --json.
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

  /// A request number a person typed, which counts from one. Anything else is
  /// said out loud rather than quietly clamped: `--at 0` used to mean the
  /// first request and `--at fish` used to mean the last.
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

/// stdout and stderr, kept in one place so nothing prints from a library.
enum Console {
  static func out(_ text: String) {
    print(text)
  }

  static func error(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
  }
}
