internal import Foundation

struct EntryRange: Sendable, Hashable {
  var offset: UInt64
  var length: Int
}

struct EntryStore: Sendable {
  static let cacheBytes = 8 << 20
  static let settledBytes = 64 << 10
  static let cacheLimit = 4096

  let url: URL?

  private var parents: [String: String] = [:]
  private var ranges: [String: EntryRange] = [:]
  private var cache: [String: TranscriptEntry] = [:]
  private var order: [String] = []
  private var cachedBytes = 0

  init(url: URL? = nil) {
    self.url = url
  }

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

  func entry(_ uuid: String) -> TranscriptEntry? {
    if let cached = cache[uuid] { return cached }
    guard let url, let range = ranges[uuid] else { return nil }
    return Self.read(range, from: url)
  }

  mutating func release(_ uuid: String) {
    guard let range = ranges[uuid], cache.removeValue(forKey: uuid) != nil else { return }
    cachedBytes -= range.length
    if let slot = order.firstIndex(of: uuid) { order.remove(at: slot) }
  }

  var cachedCount: Int { cache.count }

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
      // An entry without a range cannot be read back, so it stays.
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
