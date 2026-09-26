internal import Foundation

/// Finds the sessions on the machine and the little that can be known about
/// them without parsing: project, title, last activity, liveness.
///
/// Titles and last prompts are single-line records the harness appends, so
/// they are read from the tail of the file rather than by parsing all of it.
struct SessionDiscovery {
  /// A file written to this recently counts as live.
  static let liveWindow: TimeInterval = 180
  /// How much of the tail to scan for title records.
  static let tailBytes = 64 * 1024
  /// How much of the head to look for the working directory in.
  static let headBytes = 64 * 1024

  let root: URL

  /// Sessions on the machine, reusing what a previous scan already learned.
  ///
  /// The only expensive part of a scan is reading the tail of every file for
  /// its title. A file whose size and modification date have not moved cannot
  /// have gained one, so its title is taken from the previous answer. On this
  /// machine that is the difference between 0.78 s and a directory listing.
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

  /// `-Users-someone-code-api-client` reads better as a path.
  ///
  /// It is a guess: the harness writes every character that is not a letter
  /// or a digit as `-`, so `api-client` comes back as `api/client`. The
  /// folder the session ran in is taken from the transcript where it says.
  static func projectName(_ slug: String) -> String {
    slug.hasPrefix("-") ? "/" + slug.dropFirst().replacingOccurrences(of: "-", with: "/") : slug
  }

  /// The `cwd` the first entries of a transcript record, when it is the
  /// folder the transcript is filed under. Only the head is read, and a
  /// folder that does not match is not believed: a session can change
  /// directory on the way, and the folder name is what it started in.
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

  /// The last `custom-title` or `ai-title` record in the file, if there is
  /// one. Only the tail is read: these records are appended.
  static func title(of url: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    guard let size = try? handle.seekToEnd() else { return nil }
    let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
    try? handle.seek(toOffset: start)
    guard let data = try? handle.readToEnd() else { return nil }
    // The tail almost always starts inside a character, which makes strict
    // decoding return nil and lose the title. The first partial line is
    // rubbish either way and is skipped as unparseable.
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
