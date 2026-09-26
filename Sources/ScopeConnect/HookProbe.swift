internal import Darwin
internal import Foundation

/// Asks whether ctxscope's listener is answering on a port.
///
/// A connection that opens is not enough: another program could be sitting on
/// the port. The probe sends a GET to the hook path, which the listener
/// answers with 405 and nothing else does, so the answer is about ctxscope
/// rather than about the port.
///
/// A plain socket with a timeout rather than a framework and a callback: this
/// is asked once, from a command that has nothing else to do while it waits.
package enum HookProbe {
  package enum Answer: String, Sendable, Equatable {
    case listening
    case refused
    /// Something is there, but it is not ctxscope.
    case foreign
  }

  package static func ask(port: UInt16, seconds: Double = 1) -> Answer {
    let handle = socket(AF_INET, SOCK_STREAM, 0)
    guard handle >= 0 else { return .refused }
    defer { close(handle) }
    var limit = timeval(
      tv_sec: Int(seconds), tv_usec: Int32((seconds - seconds.rounded(.down)) * 1_000_000))
    setsockopt(handle, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(handle, SOL_SOCKET, SO_SNDTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
    let connected = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(handle, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard connected == 0 else { return .refused }

    let request = Array(
      ("GET \(HookWiring.path) HTTP/1.1\r\nHost: \(HookWiring.host):\(port)\r\n"
        + "Connection: close\r\n\r\n").utf8)
    guard request.withUnsafeBytes({ send(handle, $0.baseAddress, $0.count, 0) }) == request.count
    else { return .foreign }

    var answer = [UInt8](repeating: 0, count: 64)
    let read = recv(handle, &answer, answer.count, 0)
    guard read > 0 else { return .foreign }
    let head = String(decoding: answer[0..<read], as: UTF8.self)
    return head.hasPrefix("HTTP/1.1 \(HTTPStatus.methodNotAllowed.rawValue) ")
      ? .listening : .foreign
  }
}
