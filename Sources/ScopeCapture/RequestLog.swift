internal import Foundation

/// The API calls of one lane, assembled out of the entries that carry them.
///
/// The prompt side of a request is final on its first entry: every entry of a
/// request repeats the same input, cache read and cache write. So a request is
/// published as soon as it starts, and the rest of its response is folded in
/// as it arrives. Holding it back until the next request started meant the
/// fill at the end of a turn was stale until the next prompt.
struct RequestLog {
  /// Requests in the order the calls happened.
  private(set) var requests: [LaneBuilder.RequestGroup] = []
  private(set) var byKey: [String: LaneBuilder.RequestGroup] = [:]
  private(set) var indexByKey: [String: Int] = [:]
  /// The compaction boundary that belongs to a request, by request index.
  private(set) var compactions: [Int: JSONValue] = [:]

  /// Keys in order, with the entries of the ones that can still grow.
  private var keys: [String] = []
  private var entries: [String: [TranscriptEntry]] = [:]
  private var published: Set<String> = []
  private var grown: Set<String> = []
  /// A compaction boundary belongs to the next call that starts after it, not
  /// to the next one that happens to finish. Binding it to the key as soon as
  /// that call appears is what keeps the two the same whether the file is read
  /// in one go or a line at a time.
  private var pendingCompaction: JSONValue?
  private var compactionByKey: [String: JSONValue] = [:]
  /// How many keys have been settled: counted, and their entries let go.
  private var settled = 0

  /// What one pass over newly arrived lines did to the list.
  struct Advance {
    /// Requests that appeared, to be stepped through for the first time.
    var published: Range<Int>
    /// Requests already published whose response grew, so their output side
    /// has to be taken again.
    var grown: [Int] = []
  }

  mutating func note(compaction metadata: JSONValue) {
    pendingCompaction = metadata
  }

  /// Files one entry under the call it belongs to.
  mutating func ingest(_ entry: TranscriptEntry) {
    let key = entry.requestID ?? entry.uuid ?? UUID().uuidString
    if entries[key] == nil {
      keys.append(key)
      entries[key] = []
      if let metadata = pendingCompaction {
        compactionByKey[key] = metadata
        pendingCompaction = nil
      }
    } else if published.contains(key) {
      grown.insert(key)
    }
    entries[key]?.append(entry)
  }

  mutating func advance(final: Bool) -> Advance {
    let first = requests.count
    for key in keys where !published.contains(key) {
      published.insert(key)
      guard let group = entries[key], let request = LaneBuilder.group(key: key, entries: group)
      else { continue }
      let index = requests.count
      requests.append(request)
      byKey[key] = request
      indexByKey[key] = index
      if let metadata = compactionByKey.removeValue(forKey: key) {
        compactions[index] = metadata
      }
    }
    var advance = Advance(published: first..<requests.count)

    for key in grown {
      guard let index = indexByKey[key], let group = entries[key],
        let request = LaneBuilder.group(key: key, entries: group)
      else { continue }
      requests[index] = request
      byKey[key] = request
      advance.grown.append(index)
    }
    grown.removeAll(keepingCapacity: true)
    advance.grown.sort()

    return advance
  }

  /// Lets go of the requests that can no longer grow, once the caller has
  /// finished with them. Returns how many of them never reported a stop
  /// reason.
  ///
  /// A settled request keeps its usage, its key, its entry uuids and what was
  /// worked out from its blocks, never the parsed blocks themselves: on a 1021
  /// request lane those held 99 MB of dictionaries for the rest of the session.
  mutating func settle(final: Bool) -> Int {
    var unfinished = 0
    let settleTo = final ? keys.count : max(0, keys.count - 1)
    while settled < settleTo {
      let key = keys[settled]
      settled += 1
      guard entries.removeValue(forKey: key) != nil, let index = indexByKey[key] else { continue }
      if !requests[index].isFinished { unfinished += 1 }
      requests[index] = requests[index].settled()
      byKey[key] = requests[index]
    }
    return unfinished
  }
}
