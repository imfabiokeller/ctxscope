import Foundation
import Testing

@testable import ScopeConnect

/// Files in memory. No test in this suite is allowed near a real home
/// directory, and a store that has no path to one cannot drift into it.
final class MemoryFiles: FileStore {
  private var entries: [String: Data] = [:]
  private var modes: [String: UInt16] = [:]
  /// Paths this store refuses to replace, so the read-only path is testable
  /// without a file on disk.
  var readOnly: Set<String> = []

  init(_ entries: [String: Data] = [:]) {
    self.entries = entries
  }

  func data(at url: URL) throws -> Data? { entries[url.path] }

  func exists(_ url: URL) -> Bool { entries[url.path] != nil }

  func mode(of url: URL) -> UInt16? { entries[url.path] == nil ? nil : modes[url.path] ?? 0o600 }

  func write(_ data: Data, to url: URL, mode: UInt16?) throws {
    entries[url.path] = data
    folders.insert(url.deletingLastPathComponent().path)
    if let mode { modes[url.path] = mode }
  }

  func isEmptyDirectory(_ url: URL) -> Bool {
    entries.keys.contains { $0.hasPrefix(url.path + "/") } == false
      && folders.contains(url.path)
  }

  /// Directories this store knows about, so an empty one can be told from one
  /// that was never there.
  var folders: Set<String> = []

  func checkWritable(_ url: URL) throws {
    guard readOnly.contains(url.path) else { return }
    throw Refusal.readOnly(url.lastPathComponent)
  }

  func mode(at url: URL) -> UInt16? { modes[url.path] }

  func remove(_ url: URL) throws {
    for path in entries.keys where path == url.path || path.hasPrefix(url.path + "/") {
      entries.removeValue(forKey: path)
    }
    folders.remove(url.path)
  }

  var paths: Set<String> { Set(entries.keys) }
}
