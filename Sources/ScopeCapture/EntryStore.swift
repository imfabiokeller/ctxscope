internal import Foundation

/// Where one entry sits in its file, so its content can be served by reading
/// those bytes again instead of holding the parsed entry forever.
struct EntryRange: Sendable, Hashable {
  var offset: UInt64
  var length: Int
}

/// Parent links and byte ranges for every entry of one lane, plus the entries
/// that have not been used yet.
///
/// Holding every parsed entry kept 600 MB resident for a 117 MB session, base64
/// images included. Once a request has been processed only the parent link is
/// still needed, so the payload is dropped and a block's text is read back from the
/// file. An entry that never had a range, which is what a test that feeds
/// entries directly produces, is kept, because nothing could read it back.
struct EntryStore: Sendable {
  /// How many bytes of transcript a lane may hold parsed while it is reading.
  /// Counting entries rather than bytes is no bound at all: one tool result
  /// can be megabytes and an image entry larger still. A batch of entries fits
  /// inside this, so the ordinary case never re-reads.
  static let cacheBytes = 8 << 20
  /// What is kept once a read has finished. Between reads nothing needs a
  /// payload: anything asked for later is read back from the file.
  static let settledBytes = 64 << 10
  /// A ceiling on the count as well, for entries that arrived without a range
  /// and so have no size to count.
  static let cacheLimit = 4096

  /// The file the entries came from, when they came from one.
  let url: URL?

  private var parents: [String: String] = [:]
  private var ranges: [String: EntryRange] = [:]
  private var cache: [String: TranscriptEntry] = [:]
  /// Cache keys in arrival order, so the oldest payload goes first.
  private var order: [String] = []
  /// Bytes of transcript the cached entries were parsed from.
  private var cachedBytes = 0

  init(url: URL? = nil) {
    self.url = url
  }

  /// Takes one entry in. Its parent link and byte range are kept for the whole
  /// lane, its payload only until something has used it.
  mutating func keep(_ entry: TranscriptEntry) {
    guard let uuid = entry.uuid else { return }
    if let parent = entry.parentUUID { parents[uuid] = parent }
    if let range = entry.range { ranges[uuid] = range }
    if cache.updateValue(entry, forKey: uuid) == nil {
      order.append(uuid)
      cachedBytes += entry.range?.length ?? 0
    }
    trim()
  }

  func parent(of uuid: String) -> String? { parents[uuid] }

  /// The entry, from the cache or from the file it was read out of.
  func entry(_ uuid: String) -> TranscriptEntry? {
    if let cached = cache[uuid] { return cached }
    guard let url, let range = ranges[uuid] else { return nil }
    return Self.read(range, from: url)
  }

  /// Drops the payload of an entry that has been turned into segments. The
  /// parent link and the range stay.
  mutating func release(_ uuid: String) {
    guard let range = ranges[uuid], cache.removeValue(forKey: uuid) != nil else { return }
    cachedBytes -= range.length
    if let slot = order.firstIndex(of: uuid) { order.remove(at: slot) }
  }

  /// Entries whose payload is still held. The number a memory test asserts on.
  var cachedCount: Int { cache.count }

  /// Lets go of what a finished read no longer needs.
  mutating func settle() {
    trim(toBytes: Self.settledBytes, count: Self.cacheLimit)
  }

  private mutating func trim() {
    trim(toBytes: Self.cacheBytes, count: Self.cacheLimit)
  }

  private mutating func trim(toBytes bytes: Int, count: Int) {
    guard cachedBytes > bytes || cache.count > count else { return }
    var index = 0
    while cachedBytes > bytes || cache.count > count, index < order.count {
      let uuid = order[index]
      guard let range = ranges[uuid] else {
        index += 1
        continue
      }
      cache.removeValue(forKey: uuid)
      cachedBytes -= range.length
      order.remove(at: index)
    }
  }

  private static func read(_ range: EntryRange, from url: URL) -> TranscriptEntry? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    try? handle.seek(toOffset: range.offset)
    guard let data = try? handle.read(upToCount: range.length), data.count == range.length,
      let value = try? JSONValue(parsing: data)
    else { return nil }
    return TranscriptEntry(value, range: range)
  }
}
