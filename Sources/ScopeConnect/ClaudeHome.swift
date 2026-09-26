package import Foundation

/// The directory Claude Code keeps its settings and skills in. The desktop app
/// and the terminal read the same one, which is why connecting once covers
/// both.
///
/// Always a value that was passed in. Nothing in this module reaches for the
/// real one on its own: a test, and every run that is not a person pressing
/// Connect, is handed a temporary directory instead.
package struct ClaudeHome: Sendable, Equatable {
  package let root: URL

  package init(root: URL) {
    self.root = root
  }

  /// The one on this machine. Only the app's Connect panel and the CLI's own
  /// commands ask for it.
  package static func real() -> ClaudeHome {
    ClaudeHome(root: URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".claude"))
  }

  package var settings: URL { root.appending(path: "settings.json") }
  /// The file as it was before ctxscope first wrote to it. Empty means there
  /// was no settings file at all, which is what undo has to put back.
  package var backup: URL { root.appending(path: "settings.json.ctxscope-backup") }
  package var skillFolder: URL { root.appending(path: "skills/ctxscope") }
  package var skill: URL { skillFolder.appending(path: "SKILL.md") }
}

/// Reading and writing files, injected so nothing here can touch a path a
/// test did not give it.
package protocol FileStore {
  func data(at url: URL) throws -> Data?
  /// Cheaper than reading a file to find out it is there.
  func exists(_ url: URL) -> Bool
  /// The file's permissions, or nil when there is no file.
  func mode(of url: URL) -> UInt16?
  /// Writes atomically. `mode` is what the file should end up with; without
  /// one an existing file keeps its own.
  func write(_ data: Data, to url: URL, mode: UInt16?) throws
  func remove(_ url: URL) throws
  /// True when the directory is there and holds nothing.
  func isEmptyDirectory(_ url: URL) -> Bool
  /// Throws when this path could not be replaced, before anything is planned
  /// around the idea that it could.
  func checkWritable(_ url: URL) throws
}

extension FileStore {
  func write(_ data: Data, to url: URL) throws {
    try write(data, to: url, mode: nil)
  }
}

/// The real one.
///
/// An atomic write is a rename, so the file that ends up on disk carries this
/// process's umask rather than the one it replaced, and a symlink is replaced
/// by a regular file. Both are put back: a settings file that is a link into a
/// dotfiles repository stays a link, and a backup of a 0600 file is 0600.
package struct DiskFiles: FileStore {
  package init() {}

  package func data(at url: URL) throws -> Data? {
    let target = url.resolvingSymlinksInPath()
    guard FileManager.default.fileExists(atPath: target.path) else { return nil }
    return try Data(contentsOf: target)
  }

  package func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.resolvingSymlinksInPath().path)
  }

  package func mode(of url: URL) -> UInt16? {
    let path = url.resolvingSymlinksInPath().path
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
      let number = attributes[.posixPermissions] as? NSNumber
    else { return nil }
    return number.uint16Value
  }

  package func write(_ data: Data, to url: URL, mode: UInt16?) throws {
    let target = url.resolvingSymlinksInPath()
    let manager = FileManager.default
    try manager.createDirectory(
      at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    let before = try? manager.attributesOfItem(atPath: target.path)
    try data.write(to: target, options: .atomic)
    var restore: [FileAttributeKey: Any] = [:]
    if let wanted = mode ?? (before?[.posixPermissions] as? NSNumber)?.uint16Value {
      restore[.posixPermissions] = NSNumber(value: wanted)
    }
    if let owner = before?[.ownerAccountID] { restore[.ownerAccountID] = owner }
    if let group = before?[.groupOwnerAccountID] { restore[.groupOwnerAccountID] = group }
    guard !restore.isEmpty else { return }
    try? manager.setAttributes(restore, ofItemAtPath: target.path)
  }

  /// Whether the path itself is a symbolic link, which a resolved path can no
  /// longer say.
  private func isLink(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
  }

  private func isRegularFile(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return false
    }
    return !isDirectory.boolValue
  }

  package func remove(_ url: URL) throws {
    let target = url.resolvingSymlinksInPath()
    guard FileManager.default.fileExists(atPath: target.path) else { return }
    try FileManager.default.removeItem(at: target)
  }

  package func isEmptyDirectory(_ url: URL) -> Bool {
    let target = url.resolvingSymlinksInPath()
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { return false }
    return (try? FileManager.default.contentsOfDirectory(atPath: target.path))?.isEmpty ?? false
  }

  package func checkWritable(_ url: URL) throws {
    let target = url.resolvingSymlinksInPath()
    let manager = FileManager.default
    // A link that resolves to nothing, or round to itself, is left where it
    // is: writing would replace the link with a regular file, and undo would
    // then delete the link rather than restore it.
    if isLink(url), !isRegularFile(target) {
      throw Refusal.danglingLink(url.lastPathComponent)
    }
    // A rename ignores a file's own write bit, so a read-only settings file
    // would be replaced without complaint. It is asked about instead.
    if manager.fileExists(atPath: target.path), !manager.isWritableFile(atPath: target.path) {
      throw Refusal.readOnly(target.lastPathComponent)
    }
    let folder = target.deletingLastPathComponent()
    if manager.fileExists(atPath: folder.path), !manager.isWritableFile(atPath: folder.path) {
      throw Refusal.readOnly(folder.lastPathComponent)
    }
  }
}
