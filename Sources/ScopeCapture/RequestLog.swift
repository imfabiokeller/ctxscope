internal import Foundation

// Every entry of a request repeats the same prompt usage, so a request is
// published on its first entry and the rest of its response folded in later.
struct RequestLog {
  private(set) var requests: [LaneBuilder.RequestGroup] = []
  private(set) var byKey: [String: LaneBuilder.RequestGroup] = [:]
  private(set) var indexByKey: [String: Int] = [:]
  private(set) var compactions: [Int: JSONValue] = [:]

  private var keys: [String] = []
  private var entries: [String: [TranscriptEntry]] = [:]
  private var published: Set<String> = []
  private var grown: Set<String> = []
  // Bound to the next call that starts, not the next that finishes, so a whole
  // read and a line-at-a-time read agree.
  private var pendingCompaction: JSONValue?
  private var compactionByKey: [String: JSONValue] = [:]
  private var settled = 0

  struct Advance {
    var published: Range<Int>
    var grown: [Int] = []
  }

  mutating func note(compaction metadata: JSONValue) {
    pendingCompaction = metadata
  }

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

  // Keeps the last request unless `final`: more of it can still arrive.
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
