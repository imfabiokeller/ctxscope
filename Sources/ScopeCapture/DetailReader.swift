internal import Foundation
internal import ScopeCore

/// Reads blocks' details back out of a lane's transcript, one entry at a
/// time.
///
/// Blocks of one entry sit in neighbouring slots, and a result's call is
/// usually the entry just before it, so the last few entries read are kept
/// for the length of one pass and nothing past it.
struct DetailReader {
  let store: EntryStore
  let reader: EntryReader
  private var recent: [String: TranscriptEntry] = [:]
  private var order: [String] = []
  /// Entries kept while reading.
  private static let kept = 8

  init(store: EntryStore, reader: EntryReader) {
    self.store = store
    self.reader = reader
  }

  /// The detail of the piece at `index` of the entry `uuid`. Nil when the
  /// entry cannot be read back or the piece says nothing that could be shown.
  mutating func detail(entry uuid: String, piece index: Int) -> BlockDetail? {
    guard let entry = entry(uuid) else { return nil }
    let pieces = reader.pieces(of: entry)
    guard index >= 0, index < pieces.count, let subject = pieces[index].subject else {
      return nil
    }
    let project = entry.raw["cwd"]?.string
    switch subject {
    case .firstLine(let head):
      return BlockDetail.line(head, text: pieces[index].text)
    case .attachment(let type):
      return BlockDetail.attachment(type: type, record: entry.attachment, project: project)
    case .memory(let path):
      return BlockDetail.memory(path: path, project: project)
    case .toolCall(let id, let name):
      return BlockDetail.tool(
        name, input: Self.input(of: id, in: entry), project: project, isCall: true)
    case .toolResult(let id, let name):
      let call = reader.toolCalls[id].flatMap { self.entry($0) }
      return BlockDetail.tool(
        name, input: call.flatMap { Self.input(of: id, in: $0) },
        result: entry.raw["toolUseResult"], project: call?.raw["cwd"]?.string ?? project)
    }
  }

  /// The input of the tool call `id` in an assistant entry.
  private static func input(of id: String, in entry: TranscriptEntry) -> JSONValue? {
    entry.blocks.first { $0["type"]?.string == "tool_use" && $0["id"]?.string == id }?["input"]
  }

  private mutating func entry(_ uuid: String) -> TranscriptEntry? {
    if let kept = recent[uuid] { return kept }
    guard let entry = store.entry(uuid) else { return nil }
    recent[uuid] = entry
    order.append(uuid)
    if order.count > Self.kept { recent[order.removeFirst()] = nil }
    return entry
  }
}
