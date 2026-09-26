internal import CoreServices
package import Foundation

package struct ConnectReport: Sendable {
  package let home: URL
  package let status: ConnectService.Status?
  package let listener: HookProbe.Answer?
  package let schemeHandler: URL?
  package let schemeCopies: [URL]
  package let runningBundle: URL?
  package let failure: String?

  package var events: [String] {
    HookWiring.allEvents.filter { status?.events.contains($0) ?? false }
  }

  package var missing: [String] {
    guard status?.isConnected == true else { return [] }
    return HookWiring.allEvents.filter { !events.contains($0) }
  }

  package var lines: [String] {
    var lines = ["claude home    \(home.path)"]
    if let failure { lines.append("settings       cannot be read: \(failure)") }
    lines.append("settings       \(status?.hasSettings == true ? "present" : "not there")")
    lines.append("backup         \(status?.hasBackup == true ? "present" : "none")")
    if let status, status.isConnected {
      let listed = Set(status.ports).sorted().map(String.init).joined(separator: ", ")
      let reached = status.port.map { "port \($0)" } ?? "ports \(listed)"
      lines.append(
        "hooks          \(events.count) of \(HookWiring.allEvents.count) events, \(reached)")
      if !missing.isEmpty { lines.append("missing        \(missing.joined(separator: ", "))") }
      if let retired = status.retired.isEmpty ? nil : status.retired {
        lines.append(
          "older          \(retired.joined(separator: ", ")), from a previous ctxscope")
      }
    } else {
      lines.append("hooks          not connected")
    }
    if let listener, let port = status?.port {
      lines.append("listener       \(listener.rawValue) on 127.0.0.1:\(port)")
    }
    if let blocked = status?.blocked { lines.append("blocked        \(blocked)") }
    lines.append("skill          \(skillLine)")
    lines.append("url scheme     \(schemeLine)")
    return lines
  }

  private var schemeLine: String {
    guard let handler = schemeHandler else { return "no handler" }
    let others = schemeCopies.filter { $0.standardizedFileURL != handler.standardizedFileURL }
    let copies =
      others.isEmpty
      ? ""
      : ", \(others.count + 1) copies registered: \(others.map(\.path).joined(separator: ", "))"
    guard let running = runningBundle else {
      return "handled by \(handler.path), not run from a bundle" + copies
    }
    return handler.standardizedFileURL == running.standardizedFileURL
      ? "handled by \(handler.path), which is this copy" + copies
      : "handled by \(handler.path), not this copy at \(running.path)" + copies
  }

  private var skillLine: String {
    switch status?.skill ?? .none {
    case .none: "not there"
    case .ours: "present"
    case .edited: "present, edited by hand"
    }
  }

  package var isHealthy: Bool {
    failure == nil && status?.isConnected == true && status?.isPartial == false
      && listener == .listening && status?.skill == .ours && schemeHandler != nil
      && status?.blocked == nil
  }
}

extension ConnectService {
  // Read only, so it is safe against the real home directory.
  package func report(probe: Bool = true) -> ConnectReport {
    let status = try? status()
    return ConnectReport(
      home: home.root,
      status: status,
      listener: probe ? status?.port.map { HookProbe.ask(port: $0) } : nil,
      schemeHandler: SchemeRegistration.handler(),
      schemeCopies: SchemeRegistration.copies(),
      runningBundle: SchemeRegistration.runningBundle(),
      failure: status == nil ? readFailure() : nil
    )
  }

  private func readFailure() -> String {
    do {
      _ = try status()
      return "unknown"
    } catch {
      return "\(error)"
    }
  }
}

package enum SchemeRegistration {
  package static func handler() -> URL? {
    guard let url = URL(string: ScopeURL.show()) else { return nil }
    var failure: Unmanaged<CFError>?
    return LSCopyDefaultApplicationURLForURL(url as CFURL, .viewer, &failure)?
      .takeRetainedValue() as URL?
  }

  package static func copies() -> [URL] {
    guard let url = URL(string: ScopeURL.show()) else { return [] }
    return
      (LSCopyApplicationURLsForURL(url as CFURL, .viewer)?
      .takeRetainedValue() as? [URL]) ?? []
  }

  package static func runningBundle() -> URL? {
    Bundle.main.bundleIdentifier == nil ? nil : Bundle.main.bundleURL
  }
}
