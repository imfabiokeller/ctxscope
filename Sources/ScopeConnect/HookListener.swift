internal import Dispatch
internal import Foundation
internal import Network

@MainActor
package final class HookListener {
  package var onEvent: ((HookEvent) -> Void)?

  package private(set) var port: UInt16?

  private var listener: NWListener?
  private let idleSeconds: Double
  private nonisolated static let queue = DispatchQueue(label: "dev.fabiokeller.ctxscope.hooks")

  package init(idleSeconds: Double = 5) {
    self.idleSeconds = idleSeconds
  }

  @discardableResult
  package func start(preferring wanted: UInt16? = nil) async -> UInt16? {
    stop()
    var seen: Set<UInt16> = []
    let ladder = (0..<HookWiring.portAttempts).map { HookWiring.defaultPort &+ UInt16($0) }
    for candidate in ([wanted].compactMap { $0 } + ladder).filter({ seen.insert($0).inserted }) {
      guard let bound = await bind(candidate) else { continue }
      listener = bound
      port = candidate
      return candidate
    }
    return nil
  }

  package func stop() {
    listener?.newConnectionHandler = nil
    listener?.cancel()
    listener = nil
    port = nil
  }

  private func bind(_ candidate: UInt16) async -> NWListener? {
    guard let number = NWEndpoint.Port(rawValue: candidate) else { return nil }
    let parameters = NWParameters.tcp
    parameters.allowLocalEndpointReuse = true
    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: number)
    guard let listener = try? NWListener(using: parameters) else { return nil }
    let deliver: @Sendable (HookEvent) -> Void = { [weak self] event in
      Task { @MainActor in self?.onEvent?(event) }
    }
    let bound = candidate
    let idle = idleSeconds
    // Before `start`: a listener started without a connection handler fails at
    // once with "invalid argument" and takes no port.
    listener.newConnectionHandler = { connection in
      Self.accept(connection, port: bound, idle: idle, deliver: deliver)
    }
    // An AsyncStream, not a continuation: the state handler fires more than once.
    let outcome = AsyncStream<Bool> { yield in
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready: yield.yield(true)
        case .failed, .cancelled: yield.yield(false)
        default: break
        }
      }
      listener.start(queue: Self.queue)
    }
    var ready = false
    for await value in outcome {
      ready = value
      break
    }
    listener.stateUpdateHandler = nil
    guard ready else {
      listener.cancel()
      return nil
    }
    return listener
  }

  private nonisolated static func accept(
    _ connection: NWConnection, port: UInt16, idle: Double,
    deliver: @escaping @Sendable (HookEvent) -> Void
  ) {
    guard isLocal(connection.endpoint) else { return connection.cancel() }
    connection.start(queue: queue)
    queue.asyncAfter(deadline: .now() + idle) { connection.cancel() }
    receive(connection, port: port, buffer: Data(), deliver: deliver)
  }

  // Security: repeats the loopback bind, in case the bind ever changes.
  nonisolated static func isLocal(_ endpoint: NWEndpoint) -> Bool {
    guard case .hostPort(let host, _) = endpoint else { return false }
    switch host {
    case .ipv4(let address): return address.rawValue.first == 127
    case .ipv6(let address): return address == .loopback
    case .name: return false
    @unknown default: return false
    }
  }

  private nonisolated static func receive(
    _ connection: NWConnection, port: UInt16, buffer: Data,
    deliver: @escaping @Sendable (HookEvent) -> Void
  ) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
      chunk, _, isComplete, error in
      let more = chunk.map { buffer + $0 } ?? buffer
      took(
        connection, port: port, buffer: more, ended: isComplete || error != nil, deliver: deliver)
    }
  }

  private nonisolated static func took(
    _ connection: NWConnection, port: UInt16, buffer: Data, ended: Bool,
    deliver: @escaping @Sendable (HookEvent) -> Void
  ) {
    switch HTTPWire.read(buffer) {
    case .incomplete:
      if ended { return connection.cancel() }
      receive(connection, port: port, buffer: buffer, deliver: deliver)
    case .refuse(let status):
      answer(connection, status)
    case .request(let request):
      let status = HookRouter.status(for: request, port: port)
      answer(connection, status)
      // Only after the answer, so a hook never waits on ctxscope's work.
      guard status == .ok, let event = HookEvent.decode(request.body) else { return }
      deliver(event)
    }
  }

  private nonisolated static func answer(_ connection: NWConnection, _ status: HTTPStatus) {
    connection.send(
      content: HTTPWire.response(status), isComplete: true,
      completion: .contentProcessed { _ in connection.cancel() })
  }
}
