package import Foundation

package enum SettingsEdit {
  package static func isBlank(_ data: Data) -> Bool {
    data.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }
  }

  package static func installedPorts(_ data: Data) throws -> [UInt16] {
    try handlers(in: data).compactMap { $0.url?.text.flatMap(HookWiring.port(ofURL:)) }
  }

  package static func installedEvents(_ data: Data) throws -> Set<String> {
    Set(try handlers(in: data).map(\.event))
  }

  private struct Handler {
    let event: String
    let url: JSONSpan?
    let command: JSONSpan?
  }

  package static func hasStaleWake(_ data: Data) throws -> Bool {
    try handlers(in: data).contains { handler in
      guard let command = handler.command?.text else { return false }
      return command != HookWiring.wakeCommand
    }
  }

  private static func handlers(in data: Data) throws -> [Handler] {
    guard !isBlank(data) else { return [] }
    let root = try JSONSpan.parse(data)
    var found: [Handler] = []
    for event in root["hooks"]?.members ?? [] {
      for group in event.value.elements ?? [] {
        for handler in group["hooks"]?.elements ?? [] where HookWiring.isOurs(handler: handler) {
          found.append(
            Handler(event: event.name, url: handler["url"], command: handler["command"]))
        }
      }
    }
    return found
  }

  package static func connected(_ data: Data?, port: UInt16) throws -> Data {
    guard let data, !isBlank(data) else { return Data(fresh(port: port).utf8) }
    var current = data
    current = try retire(in: current)
    while let splice = try misdirected(in: current, port: port) {
      current = SourceText.apply([splice], to: current)
    }
    while let splice = try staleWake(in: current) {
      current = SourceText.apply([splice], to: current)
    }
    let layout = Layout(reading: current)
    for event in HookWiring.allEvents {
      // Re-read per event: adding the first one to a file with no `hooks` block
      // writes the block with every event in it.
      guard !(try installedEvents(current)).contains(event) else { continue }
      current = try add(event: event, port: port, to: current, layout: layout)
    }
    return current
  }

  private static func fresh(port: UInt16) -> String {
    let layout = Layout()
    return "{\(layout.breakLine)\(layout.unit)\"hooks\": "
      + HookWiring.hooksObject(port: port, indent: layout.unit, layout: layout)
      + layout.breakLine + "}" + layout.breakLine
  }

  private static func misdirected(in data: Data, port: UInt16) throws -> TextSplice? {
    let wanted = HookWiring.url(port: port)
    guard let url = try handlers(in: data).compactMap(\.url).first(where: { $0.text != wanted })
    else { return nil }
    return TextSplice(range: url.range, text: "\"\(wanted)\"")
  }

  private static func retire(in data: Data) throws -> Data {
    var current = data
    var touched: Set<String> = []
    while let found = try ours(in: current, where: { !HookWiring.allEvents.contains($0) }) {
      touched.insert(found.event)
      current = SourceText.apply([found.splice], to: current)
    }
    guard !touched.isEmpty else { return current }
    // Safe to remove whole keys: an emptied key held nothing but our group.
    while let splice = try leftover(in: current, touched: touched, kept: nil) {
      current = SourceText.apply([splice], to: current)
    }
    return current
  }

  private static func staleWake(in data: Data) throws -> TextSplice? {
    guard
      let command = try handlers(in: data).compactMap(\.command)
        .first(where: { $0.text != HookWiring.wakeCommand })
    else { return nil }
    return TextSplice(range: command.range, text: "\"\(HookWiring.wakeCommand)\"")
  }

  private static func add(event: String, port: UInt16, to data: Data, layout: Layout) throws
    -> Data
  {
    let root = try JSONSpan.parse(data)
    guard case .object = root.kind else {
      throw Refusal.notAnObject
    }
    guard let hooks = root["hooks"] else {
      let splice = JSONEdit.add(member: "hooks", to: root, in: data, layout: layout) { indent in
        HookWiring.hooksObject(port: port, indent: indent, layout: layout)
      }
      return SourceText.apply([splice], to: data)
    }
    guard case .object = hooks.kind else {
      throw Refusal.notReadable
    }
    guard let array = hooks[event] else {
      let splice = JSONEdit.add(member: event, to: hooks, in: data, layout: layout) { indent in
        HookWiring.array(event: event, port: port, indent: indent, layout: layout)
      }
      return SourceText.apply([splice], to: data)
    }
    guard case .array = array.kind else {
      throw Refusal.notReadable
    }
    let splice = JSONEdit.append(to: array, in: data, layout: layout) { indent in
      event == HookWiring.wakeEvent
        ? HookWiring.wakeGroup(indent: indent, layout: layout)
        : HookWiring.group(port: port, indent: indent, layout: layout)
    }
    return SourceText.apply([splice], to: data)
  }

  package static func disconnected(_ data: Data, original: Data? = nil) throws -> Data {
    guard !isBlank(data) else { return data }
    var current = data
    var touched: Set<String> = []
    while let found = try ours(in: current) {
      touched.insert(found.event)
      current = SourceText.apply([found.splice], to: current)
    }
    guard !touched.isEmpty else { return current }
    let kept = try before(original)
    while let splice = try leftover(in: current, touched: touched, kept: kept) {
      current = SourceText.apply([splice], to: current)
    }
    return current
  }

  private static func before(_ original: Data?) throws -> Set<String>? {
    guard let original, !isBlank(original), let root = try? JSONSpan.parse(original),
      let hooks = root["hooks"], let members = hooks.members
    else { return nil }
    return Set(members.map(\.name))
  }

  private struct Found {
    let splice: TextSplice
    let event: String
  }

  private static func ours(
    in data: Data, where isWanted: (String) -> Bool = { _ in true }
  ) throws -> Found? {
    let root = try JSONSpan.parse(data)
    guard let hooks = root["hooks"] else { return nil }
    for event in hooks.members ?? [] where isWanted(event.name) {
      let groups = event.value.elements ?? []
      for (slot, group) in groups.enumerated() where HookWiring.isOurs(group: group) {
        guard let range = JSONEdit.removal(ofElement: slot, from: event.value) else { continue }
        return Found(splice: .remove(range), event: event.name)
      }
      for group in groups {
        guard let handlers = group["hooks"] else { continue }
        for (slot, handler) in (handlers.elements ?? []).enumerated()
        where HookWiring.isOurs(handler: handler) {
          guard let range = JSONEdit.removal(ofElement: slot, from: handlers) else { continue }
          return Found(splice: .remove(range), event: event.name)
        }
      }
    }
    return nil
  }

  private static func leftover(in data: Data, touched: Set<String>, kept: Set<String>?) throws
    -> TextSplice?
  {
    let root = try JSONSpan.parse(data)
    guard let hooks = root["hooks"], let members = hooks.members else { return nil }
    for (slot, event) in members.enumerated()
    where touched.contains(event.name) && (event.value.elements?.isEmpty ?? false)
      && !(kept?.contains(event.name) ?? false)
    {
      guard let range = JSONEdit.removal(ofMember: slot, from: hooks) else { continue }
      return .remove(range)
    }
    guard members.isEmpty, kept == nil, let outer = root.members,
      let slot = outer.firstIndex(where: { $0.name == "hooks" }),
      let range = JSONEdit.removal(ofMember: slot, from: root)
    else { return nil }
    return .remove(range)
  }
}
