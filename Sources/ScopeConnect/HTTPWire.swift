package import Foundation

package struct HookRequest: Sendable, Equatable {
  package let method: String
  package let path: String
  package let headers: [String: String]
  package let body: Data
}

package enum HTTPStatus: Int, Sendable {
  case ok = 200
  case badRequest = 400
  case forbidden = 403
  case notFound = 404
  case methodNotAllowed = 405
  case tooLarge = 413

  var reason: String {
    switch self {
    case .ok: "OK"
    case .badRequest: "Bad Request"
    case .forbidden: "Forbidden"
    case .notFound: "Not Found"
    case .methodNotAllowed: "Method Not Allowed"
    case .tooLarge: "Payload Too Large"
    }
  }
}

package enum HTTPRead: Sendable, Equatable {
  case incomplete
  case request(HookRequest)
  case refuse(HTTPStatus)
}

package enum HTTPWire {
  package static let bodyCap = 64 * 1024
  package static let headerCap = 8 * 1024

  package static func read(_ buffer: Data, cap: Int = bodyCap) -> HTTPRead {
    guard let split = range(of: Data("\r\n\r\n".utf8), in: buffer) else {
      return buffer.count > headerCap ? .refuse(.tooLarge) : .incomplete
    }
    let head = String(decoding: buffer[buffer.startIndex..<split.lowerBound], as: UTF8.self)
    let lines = head.components(separatedBy: "\r\n")
    let start = lines.first?.split(separator: " ", omittingEmptySubsequences: true) ?? []
    guard start.count >= 2 else { return .refuse(.badRequest) }
    let fields = headers(lines.dropFirst())
    guard let length = contentLength(fields) else { return .refuse(.badRequest) }
    guard length <= cap else { return .refuse(.tooLarge) }
    let bodyStart = split.upperBound
    guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= length else {
      return .incomplete
    }
    let end = buffer.index(bodyStart, offsetBy: length)
    return .request(
      HookRequest(
        method: String(start[0]).uppercased(),
        path: String(start[1].prefix(while: { $0 != "?" })),
        headers: fields,
        body: Data(buffer[bodyStart..<end])
      ))
  }

  // An empty JSON object is the documented 2xx body that asks for nothing.
  package static func response(_ status: HTTPStatus) -> Data {
    let body = status == .ok ? "{}" : ""
    return Data(
      ("HTTP/1.1 \(status.rawValue) \(status.reason)\r\n"
        + "Content-Type: application/json\r\n"
        + "Content-Length: \(body.utf8.count)\r\n"
        + "Connection: close\r\n\r\n" + body).utf8)
  }

  private static func headers(_ lines: some Sequence<String>) -> [String: String] {
    var fields: [String: String] = [:]
    for line in lines {
      guard let colon = line.firstIndex(of: ":") else { continue }
      let name = line[line.startIndex..<colon].lowercased()
      fields[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }
    return fields
  }

  private static func contentLength(_ fields: [String: String]) -> Int? {
    guard fields["transfer-encoding"] == nil else { return nil }
    guard let value = fields["content-length"] else { return 0 }
    guard let parsed = Int(value), parsed >= 0 else { return nil }
    return parsed
  }

  private static func range(of needle: Data, in haystack: Data) -> Range<Data.Index>? {
    guard needle.count <= haystack.count else { return nil }
    var start = haystack.startIndex
    let last = haystack.index(haystack.endIndex, offsetBy: -needle.count)
    while start <= last {
      let end = haystack.index(start, offsetBy: needle.count)
      if haystack[start..<end].elementsEqual(needle) { return start..<end }
      start = haystack.index(after: start)
    }
    return nil
  }
}
