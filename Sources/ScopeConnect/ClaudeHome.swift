package import Foundation

// Always passed in. Tests and every run that is not the owner pressing Connect
// get a temporary directory, never the real home.
package struct ClaudeHome: Sendable, Equatable {
  package let root: URL

  package init(root: URL) {
    self.root = root
  }

  // Only the app's Connect panel and the CLI's own commands may ask for this.
  package static func real() -> ClaudeHome {
    ClaudeHome(root: URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".claude"))
  }

  package var settings: URL { root.appending(path: "settings.json") }
  // Empty means there was no settings file, which is what undo has to put back.
  package var backup: URL { root.appending(path: "settings.json.ctxscope-backup") }
  package var skillFolder: URL { root.appending(path: "skills/ctxscope") }
  package var skill: URL { skillFolder.appending(path: "SKILL.md") }
}

package protocol FileStore {
  func data(at url: URL) throws -> Data?
  func exists(_ url: URL) -> Bool
  func mode(of url: URL) -> UInt16?
  func write(_ data: Data, to url: URL, mode: UInt16?) throws
  func remove(_ url: URL) throws
  func isEmptyDirectory(_ url: URL) -> Bool
  func checkWritable(_ url: URL) throws
}

extension FileStore {
  func write(_ data: Data, to url: URL) throws {
    try write(data, to: url, mode: nil)
  }
}

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

  // An atomic write is a rename: it takes this process's umask and replaces a
  // symlink with a regular file, so the target and its attributes are kept.
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
    // Safety: writing through a dangling link would replace it with a file,
    // and undo would then delete the link.
    if isLink(url), !isRegularFile(target) {
      throw Refusal.danglingLink(url.lastPathComponent)
    }
    // A rename ignores the file's own write bit, so read-only is refused here.
    if manager.fileExists(atPath: target.path), !manager.isWritableFile(atPath: target.path) {
      throw Refusal.readOnly(target.lastPathComponent)
    }
    let folder = target.deletingLastPathComponent()
    if manager.fileExists(atPath: folder.path), !manager.isWritableFile(atPath: folder.path) {
      throw Refusal.readOnly(folder.lastPathComponent)
    }
  }
}
