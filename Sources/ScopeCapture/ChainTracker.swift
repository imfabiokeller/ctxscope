/// Keeps the current prompt chain and answers what changed when the next
/// request starts from a different leaf.
///
/// A transcript is a tree: rewinds and edited prompts branch it, and a
/// compaction restarts it. Recomputing the whole chain per request would be
/// quadratic, so this walks up only as far as the first entry both chains
/// share, which is what makes a growing session cost only its new lines.
struct ChainTracker {
  private(set) var chain: [String] = []
  private var position: [String: Int] = [:]

  struct Change {
    var added: [String]
    var removed: [String]
    /// True when the walk found no entry the previous chain also had. The
    /// whole context changed at once, which is either a compaction, a new
    /// conversation, or a transcript whose history is missing.
    var restarted: Bool
  }

  /// Moves to the chain that ends at `leaf`. `parent` walks one step up.
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
      // A malformed transcript can point a parent at a descendant. Stop at
      // the first uuid seen twice rather than walking a cycle.
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
