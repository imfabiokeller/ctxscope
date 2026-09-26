internal import Foundation

struct SessionDiscovery {
  static let liveWindow: TimeInterval = 180
  static let tailBytes = 64 * 1024
  static let headBytes = 64 * 1024

  let root: URL

  func sessions(reusing known: [String: SessionRef] = [:]) throws -> [SessionRef] {
    let manager = FileManager.default
    guard let projects = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    else { return [] }

    var result: [SessionRef] = []
    let now = Date()
    for project in projects {
      var isDirectory: ObjCBool = false
      guard manager.fileExists(atPath: project.path, isDirectory: &isDirectory),
        isDirectory.boolValue,
        let files = try? manager.contentsOfDirectory(
          at: project,
          includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        )
      else { continue }
      for file in files where file.pathExtension == "jsonl" {
        let values = try? file.resourceValues(forKeys: [
          .contentModificationDateKey, .fileSizeKey,
        ])
        let modified = values?.contentModificationDate ?? .distantPast
        let size = values?.fileSize ?? 0
        let previous = known[file.path]
        let unchanged = previous?.byteSize == size && previous?.lastActivity == modified
        let slug = project.lastPathComponent
        result.append(
          SessionRef(
            id: file.deletingPathExtension().lastPathComponent,
            project: unchanged
              ? previous?.project ?? Self.projectName(slug)
              : Self.workingDirectory(of: file, slug: slug) ?? Self.projectName(slug),
            url: file,
            title: unchanged ? previous?.title : Self.title(of: file),
            lastActivity: modified,
            byteSize: size,
            isLive: now.timeIntervalSince(modified) < Self.liveWindow
          )
        )
      }
    }
    return result.sorted { $0.lastActivity > $1.lastActivity }
  }

  // A guess: the harness writes every non-alphanumeric character as `-`, so
  // `api-client` reads `api/client`.
  static func projectName(_ slug: String) -> String {
    slug.hasPrefix("-") ? "/" + slug.dropFirst().replacingOccurrences(of: "-", with: "/") : slug
  }

  // A `cwd` that does not match the folder is not believed: a session can change
  // directory on the way.
  static func workingDirectory(of url: URL, slug expected: String) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: headBytes) else { return nil }
    var lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
    // A read that stopped short of the end cut its last line off.
    if data.count == headBytes { lines.removeLast() }
    for line in lines where line.contains("\"cwd\"") {
      guard let value = try? JSONValue(parsing: Data(line.utf8)),
        let cwd = value["cwd"]?.string
      else { continue }
      return ClaudeCodeAdapter.folderName(of: cwd) == expected ? cwd : nil
    }
    return nil
  }

  // These records are appended, so only the tail is read.
  static func title(of url: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    guard let size = try? handle.seekToEnd() else { return nil }
    let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
    try? handle.seek(toOffset: start)
    guard let data = try? handle.readToEnd() else { return nil }
    // The tail usually starts mid-character: decode leniently; the partial first
    // line fails to parse and is skipped.
    let text = String(decoding: data, as: UTF8.self)
    var title: String?
    for line in text.split(separator: "\n") {
      guard line.contains("\"type\":\"custom-title\"") || line.contains("\"type\":\"ai-title\"")
      else { continue }
      guard let value = try? JSONValue(parsing: Data(line.utf8)) else { continue }
      if let custom = value["customTitle"]?.string ?? value["aiTitle"]?.string {
        title = custom
      }
    }
    return title
  }
}
