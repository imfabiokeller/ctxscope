import Foundation
import Network
import Testing

@testable import ScopeConnect

@Suite("what arrives on the wire")
struct HTTPWireTests {
  static let port: UInt16 = 45871

  private func post(
    _ body: String, path: String = "/ctxscope/hook", method: String = "POST",
    host: String = "127.0.0.1:45871", extra: String = ""
  ) -> Data {
    Data(
      ("\(method) \(path) HTTP/1.1\r\nHost: \(host)\r\nContent-Type: application/json\r\n"
        + extra + "Content-Length: \(body.utf8.count)\r\n\r\n" + body).utf8)
  }

  @Test("a well formed post is read whole")
  func wellFormed() {
    let body = #"{"hook_event_name":"Stop","session_id":"abc"}"#
    guard case .request(let request) = HTTPWire.read(post(body)) else {
      Issue.record("a complete request was not read")
      return
    }
    #expect(request.method == "POST")
    #expect(request.path == "/ctxscope/hook")
    #expect(request.body == Data(body.utf8))
    #expect(HookRouter.status(for: request, port: Self.port) == .ok)
    #expect(request.headers["content-type"] == "application/json")
  }

  @Test("half a request waits for the rest")
  func incomplete() {
    let whole = post(#"{"hook_event_name":"Stop","session_id":"abc"}"#)
    #expect(HTTPWire.read(whole.prefix(20)) == .incomplete)
    #expect(HTTPWire.read(whole.dropLast(4)) == .incomplete)
  }

  @Test("a body over the cap is refused rather than buffered")
  func tooLarge() {
    let body = String(repeating: "x", count: HTTPWire.bodyCap + 1)
    #expect(HTTPWire.read(post(body)) == .refuse(.tooLarge))
    #expect(
      HTTPWire.read(Data(String(repeating: "h", count: HTTPWire.headerCap + 1).utf8))
        == .refuse(.tooLarge))
  }

  @Test("a body whose length is not stated is refused")
  func noLength() {
    let raw = Data("POST /ctxscope/hook HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)
    #expect(HTTPWire.read(raw) == .refuse(.badRequest))
  }

  @Test("another method and another path are turned away")
  func routing() {
    guard case .request(let get) = HTTPWire.read(post("", method: "GET")) else {
      Issue.record("a complete request was not read")
      return
    }
    #expect(HookRouter.status(for: get, port: Self.port) == .methodNotAllowed)
    guard case .request(let elsewhere) = HTTPWire.read(post("{}", path: "/something")) else {
      Issue.record("a complete request was not read")
      return
    }
    #expect(HookRouter.status(for: elsewhere, port: Self.port) == .notFound)
  }

  @Test("a request a browser could have sent is refused")
  func origin() {
    guard
      case .request(let fromAPage) = HTTPWire.read(
        post("{}", extra: "Origin: https://example.com\r\n"))
    else {
      Issue.record("a complete request was not read")
      return
    }
    #expect(HookRouter.status(for: fromAPage, port: Self.port) == .forbidden)

    // A browser page cannot set Host, so an unpublished host is refused the same way.
    for host in ["example.com", "127.0.0.1:1", "127.0.0.1", "evil.local:45871", ""] {
      guard case .request(let elsewhere) = HTTPWire.read(post("{}", host: host)) else {
        Issue.record("a complete request was not read")
        return
      }
      #expect(HookRouter.status(for: elsewhere, port: Self.port) == .forbidden, "host \(host)")
    }
    for host in ["127.0.0.1:45871", "localhost:45871", "LocalHost:45871"] {
      guard case .request(let ours) = HTTPWire.read(post("{}", host: host)) else {
        Issue.record("a complete request was not read")
        return
      }
      #expect(HookRouter.status(for: ours, port: Self.port) == .ok, "host \(host)")
    }
  }

  @Test("a query string is not part of the path")
  func query() {
    guard case .request(let request) = HTTPWire.read(post("{}", path: "/ctxscope/hook?a=1")) else {
      Issue.record("a complete request was not read")
      return
    }
    #expect(request.path == "/ctxscope/hook")
  }

  @Test("the answer is a 200 with an empty JSON object")
  func answer() {
    let text = String(decoding: HTTPWire.response(.ok), as: UTF8.self)
    #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
    #expect(text.contains("Content-Type: application/json\r\n"))
    #expect(text.contains("Content-Length: 2\r\n"))
    #expect(text.hasSuffix("\r\n\r\n{}"))
  }
}

@Suite("hook payloads")
struct HookEventTests {
  @Test("the documented fields are read")
  func fields() {
    let body = Data(
      """
      {"session_id":"abc123","transcript_path":"/Users/x/.claude/projects/p/abc123.jsonl",
      "cwd":"/Users/x/code","reason":"clear","hook_event_name":"SessionEnd"}
      """.utf8)
    let event = HookEvent.decode(body)
    #expect(event?.kind == .sessionEnd)
    #expect(event?.sessionID == "abc123")
  }

  @Test("fields ctxscope does not use are read past")
  func extras() {
    // Every other field is ignored, so transcript text never enters through a hook.
    let end = HookEvent.decode(
      Data(#"{"session_id":"s","hook_event_name":"SessionEnd","reason":"clear"}"#.utf8))
    #expect(end == HookEvent(kind: .sessionEnd, sessionID: "s"))
  }

  @Test("an event ctxscope does not listen for is not one")
  func unknown() {
    for name in ["PreToolUse", "UserPromptSubmit", "Stop", "SubagentStart", "PostModelSwitch"] {
      let body = Data(#"{"session_id":"s","hook_event_name":"\#(name)"}"#.utf8)
      #expect(HookEvent.decode(body) == nil, "\(name) decoded")
    }
    #expect(HookEvent.decode(Data(#"{"hook_event_name":"SessionEnd"}"#.utf8)) == nil)
    #expect(
      HookEvent.decode(Data(#"{"session_id":"","hook_event_name":"SessionEnd"}"#.utf8)) == nil)
    #expect(HookEvent.decode(Data("not json".utf8)) == nil)
    #expect(HookEvent.decode(Data()) == nil)
  }

  @Test("every event ctxscope writes into the settings file can be decoded")
  func everyEvent() {
    for name in HookWiring.events {
      let body = Data(#"{"session_id":"s","hook_event_name":"\#(name)"}"#.utf8)
      #expect(HookEvent.decode(body)?.kind.rawValue == name)
    }
    #expect(HookEvent.Kind.allCases.map(\.rawValue) == HookWiring.events)
  }
}

@Suite("a listener that is actually bound")
struct HookListenerTests {
  @MainActor
  @Test("it binds the loopback, answers a post and reports the event")
  func roundTrip() async throws {
    let listener = HookListener()
    let seen = Collected()
    listener.onEvent = { seen.add($0) }
    guard let port = await listener.start() else {
      Issue.record("no port could be bound")
      return
    }
    defer { listener.stop() }
    #expect(listener.port == port)

    let body = Data(#"{"session_id":"abc123","hook_event_name":"SessionEnd"}"#.utf8)
    let (data, response) = try await post(body, to: port, path: HookWiring.path)
    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    #expect(String(decoding: data, as: UTF8.self) == "{}")
    // The answer goes out before the event reaches the main actor, so wait for the event.
    for _ in 0..<200 where seen.events.isEmpty { await Task.yield() }
    #expect(seen.events.map(\.sessionID) == ["abc123"])

    let other = Data(#"{"session_id":"abc123","hook_event_name":"UserPromptSubmit"}"#.utf8)
    let (_, second) = try await post(other, to: port, path: HookWiring.path)
    #expect((second as? HTTPURLResponse)?.statusCode == 200)
    #expect(seen.events.count == 1)

    let (_, elsewhere) = try await post(body, to: port, path: "/elsewhere")
    #expect((elsewhere as? HTTPURLResponse)?.statusCode == 404)
    let huge = Data(repeating: UInt8(ascii: "x"), count: HTTPWire.bodyCap + 1)
    let (_, refused) = try await post(huge, to: port, path: HookWiring.path)
    #expect((refused as? HTTPURLResponse)?.statusCode == 413)
    #expect(seen.events.count == 1)

    let (_, fromAPage) = try await post(
      body, to: port, path: HookWiring.path, origin: "https://example.com")
    #expect((fromAPage as? HTTPURLResponse)?.statusCode == 403)
    #expect(seen.events.count == 1)

    #expect(HookProbe.ask(port: port) == .listening)
  }

  @MainActor
  @Test("a second listener takes the next port, and the probe finds nothing on a free one")
  func portFallback() async throws {
    let first = HookListener()
    guard let taken = await first.start() else {
      Issue.record("no port could be bound")
      return
    }
    defer { first.stop() }
    let second = HookListener()
    let next = await second.start(preferring: taken)
    defer { second.stop() }
    #expect(next != nil)
    #expect(next != taken)
  }

  @MainActor
  @Test("a connection that says nothing is let go")
  func idleTimeout() async throws {
    let listener = HookListener(idleSeconds: 0.3)
    guard let port = await listener.start() else {
      Issue.record("no port could be bound")
      return
    }
    defer { listener.stop() }

    let held = NWConnection(
      host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    let states = AsyncStream<Bool> { yield in
      held.stateUpdateHandler = { state in
        switch state {
        case .ready: yield.yield(true)
        case .failed, .cancelled: yield.yield(false)
        default: break
        }
      }
      held.start(queue: .global(qos: .utility))
    }
    for await ready in states {
      #expect(ready)
      break
    }
    let closed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      held.receive(minimumIncompleteLength: 1, maximumLength: 16) { data, _, isComplete, error in
        continuation.resume(returning: isComplete || error != nil || (data?.isEmpty ?? true))
      }
    }
    #expect(closed)
    held.cancel()
  }

  @Test("only the loopback is taken")
  func onlyLocal() {
    #expect(HookListener.isLocal(.hostPort(host: .ipv4(.loopback), port: 1)))
    #expect(HookListener.isLocal(.hostPort(host: .ipv6(.loopback), port: 1)))
    #expect(!HookListener.isLocal(.hostPort(host: .ipv4(.broadcast), port: 1)))
    #expect(!HookListener.isLocal(.hostPort(host: .name("example.com", nil), port: 1)))
    #expect(!HookListener.isLocal(.service(name: "x", type: "y", domain: "z", interface: nil)))
  }

  private func post(
    _ body: Data, to port: UInt16, path: String, origin: String? = nil
  ) async throws -> (Data, URLResponse) {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
    return try await URLSession(configuration: .ephemeral).data(for: request)
  }
}

@MainActor
private final class Collected {
  private(set) var events: [HookEvent] = []
  func add(_ event: HookEvent) { events.append(event) }
}
