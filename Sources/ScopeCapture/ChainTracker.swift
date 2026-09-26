struct ChainTracker {
  private(set) var chain: [String] = []
  private var position: [String: Int] = [:]

  struct Change {
    var added: [String]
    var removed: [String]
    var restarted: Bool
  }

  mutating func move(to leaf: String?, parent: (String) -> String?) -> Change {
    var collected: [String] = []
    var seen: Set<String> = []
    var anchor: Int?
    var cursor = leaf
    while let uuid = cursor {
      if let index = position[uuid] {
        anchor = index
        break
      }
      // A malformed transcript can point a parent at a descendant: stop on a repeat.
      guard seen.insert(uuid).inserted else { break }
      collected.append(uuid)
      cursor = parent(uuid)
    }

    let restarted = anchor == nil && !chain.isEmpty
    let keep = (anchor.map { $0 + 1 }) ?? 0
    let removed = Array(chain[keep...])
    let added = Array(collected.reversed())
    for uuid in removed { position.removeValue(forKey: uuid) }
    chain.removeLast(removed.count)
    for uuid in added {
      position[uuid] = chain.count
      chain.append(uuid)
    }
    return Change(added: added, removed: removed, restarted: restarted)
  }
}
