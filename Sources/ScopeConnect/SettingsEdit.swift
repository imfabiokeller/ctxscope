package import Foundation

/// The settings file with ctxscope's hooks added, and without them again.
///
/// Both are text edits on the bytes that are there. Keys keep their order,
/// indentation keeps its shape, and a key ctxscope does not know is a key
/// ctxscope does not touch.
package enum SettingsEdit {
  /// The file is there but holds nothing but whitespace, which is the same as
  /// not being there at all.
  package static func isBlank(_ data: Data) -> Bool {
    data.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }
  }

  /// The ports the hook entries in this file point at. One port is a file
  /// ctxscope wrote in one go; several are a half-written state that
  /// connecting again tidies up.
  package static func installedPorts(_ data: Data) throws -> [UInt16] {
    try handlers(in: data).compactMap { $0.url?.text.flatMap(HookWiring.port(ofURL:)) }
  }

  /// The events this file already has an entry of ours for.
  package static func installedEvents(_ data: Data) throws -> Set<String> {
    Set(try handlers(in: data).map(\.event))
  }

  /// One handler of ours, and where its URL sits in the file. The handler
  /// that wakes ctxscope has no URL: it runs a command, and that is where its
  /// text sits.
  private struct Handler {
    let event: String
    let url: JSONSpan?
    let command: JSONSpan?
  }

  /// True when a wake entry of ours is not the command ctxscope writes now.
  ///
  /// A settings file written before the launch flag existed still runs `open
  /// -g ctxscope://wake`, which reads as connected while it would turn an off
  /// ctxscope on. Matching the command exactly is what tells the two apart.
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

  // MARK: connecting

  /// The file with our hooks in it. An entry that is already there is left
  /// where it is, and one pointing at another port is moved rather than
  /// doubled, so connecting twice writes the same bytes.
  ///
  /// An entry for an event ctxscope does not ask for any more is taken out.
  /// A file written by an older ctxscope carries five of those, and leaving
  /// them would be leaving hooks in somebody else's settings file that
  /// nothing reads.
  package static func connected(_ data: Data?, port: UInt16) throws -> Data {
    guard let data, !isBlank(data) else { return Data(fresh(port: port).utf8) }
    var current = data
    current = try retire(in: current)
    while let splice = try misdirected(in: current, port: port) {
      current = SourceText.apply([splice], to: current)
    }
    // A wake command from an older ctxscope is brought up to date rather than
    // left beside a new one, for the same reason a URL that moved is.
    while let splice = try staleWake(in: current) {
      current = SourceText.apply([splice], to: current)
    }
    let layout = Layout(reading: current)
    for event in HookWiring.allEvents {
      // Asked again for every event, because adding the first one to a file
      // with no `hooks` block writes the block with all of them in it.
      guard !(try installedEvents(current)).contains(event) else { continue }
      current = try add(event: event, port: port, to: current, layout: layout)
    }
    return current
  }

  /// A settings file ctxscope writes from nothing.
  private static func fresh(port: UInt16) -> String {
    let layout = Layout()
    return "{\(layout.breakLine)\(layout.unit)\"hooks\": "
      + HookWiring.hooksObject(port: port, indent: layout.unit, layout: layout)
      + layout.breakLine + "}" + layout.breakLine
  }

  /// One of our URLs that points at another port, and the new one in its place.
  private static func misdirected(in data: Data, port: UInt16) throws -> TextSplice? {
    let wanted = HookWiring.url(port: port)
    guard let url = try handlers(in: data).compactMap(\.url).first(where: { $0.text != wanted })
    else { return nil }
    return TextSplice(range: url.range, text: "\"\(wanted)\"")
  }

  /// Takes out our entries for events ctxscope no longer asks for, and the
  /// event keys they leave empty behind them.
  private static func retire(in data: Data) throws -> Data {
    var current = data
    var touched: Set<String> = []
    while let found = try ours(in: current, where: { !HookWiring.allEvents.contains($0) }) {
      touched.insert(found.event)
      current = SourceText.apply([found.splice], to: current)
    }
    guard !touched.isEmpty else { return current }
    // The event keys are ours to remove: nothing else was ever in them, or
    // the group we removed would not have been all of it.
    while let splice = try leftover(in: current, touched: touched, kept: nil) {
      current = SourceText.apply([splice], to: current)
    }
    return current
  }

  /// A wake command of ours that is not the one ctxscope writes now, and the
  /// current one in its place.
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

  // MARK: disconnecting

  /// The file without anything ctxscope put in it. A file that holds nothing
  /// of ours comes back untouched, byte for byte.
  ///
  /// An event key and a `hooks` block ctxscope created itself have to go too,
  /// or undo would leave empty shells behind. Which of them were created is
  /// not a thing a settings file records, so the file as it was before is
  /// passed in and asked. Without it the rule is that an empty hook array does
  /// nothing and may go, which is the best a caller with no record can do.
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

  /// What the file had under `hooks` before ctxscope wrote anything: the event
  /// names, or nil when there was no `hooks` block to speak of.
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
      // A handler of ours somebody put into a group of their own comes out on
      // its own, so their group survives.
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
