internal import Foundation

/// Reads a JSONL transcript line by line and remembers where it stopped, so a
/// growing file costs only its new lines.
///
/// It reads in chunks and parses each line as it completes, so the whole file
/// is never held at once. A 117 MB session is 117 MB of transcript, not of
/// memory.
///
/// The file is input, never output: nothing here writes, moves or locks it.
struct JSONLReader: Sendable {
  /// Large enough that the syscall overhead disappears, small enough that the
  /// buffer is never the thing that matters.
  static let chunkSize = 1 << 20

  struct Position: Sendable, Hashable {
    var offset: UInt64

    init(offset: UInt64 = 0) {
      self.offset = offset
    }

    static let start = Position()
  }

  /// One parsed line and where it sits in the file, so its content can be
  /// read again later without keeping it in memory.
  struct Line: Sendable {
    let value: JSONValue
    let range: EntryRange
  }

  struct Result: Sendable {
    let entries: [Line]
    let position: Position
    /// Lines that were not valid JSON. A transcript being appended to can end
    /// in half a line, which is normal, not an error.
    let skipped: Int
  }

  let url: URL

  /// Reads every complete line after `position`.
  func read(from position: Position = .start) throws -> Result {
    var entries: [Line] = []
    var skipped = 0
    let end = try stream(from: position) { line, range in
      if let value = try? JSONValue(parsing: line), value.object != nil {
        entries.append(Line(value: value, range: range))
      } else {
        skipped += 1
      }
    }
    return Result(entries: entries, position: end, skipped: skipped)
  }

  /// Hands every complete line after `position` to `body`, with where that
  /// line sits in the file, holding one chunk and one line at a time. Returns
  /// where the last complete line ended.
  @discardableResult
  func stream(from position: Position = .start, _ body: (Data, EntryRange) throws -> Void) throws
    -> Position
  {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    if position.offset > 0 { try handle.seek(toOffset: position.offset) }

    var consumed = position.offset
    var remainder = Data()
    // One pool per chunk and one per line. `JSONSerialization` hands back
    // autoreleased Foundation objects, and without a pool to drain them a
    // read of a 117 MB session left 295 MB of buffers and strings alive until
    // the process ended. Draining them costs nothing and was the difference
    // between 571 MB and 322 MB of peak memory.
    while true {
      let done = try autoreleasepool { () -> Bool in
        guard let chunk = try handle.read(upToCount: Self.chunkSize), !chunk.isEmpty else {
          return true
        }
        var buffer = remainder
        buffer.append(chunk)
        var start = buffer.startIndex
        while let newline = buffer[start...].firstIndex(of: 0x0a) {
          let line = buffer[start..<newline]
          if !line.isEmpty {
            let range = EntryRange(offset: consumed, length: newline - start)
            try autoreleasepool { try body(Data(line), range) }
          }
          consumed += UInt64(newline - start + 1)
          start = buffer.index(after: newline)
        }
        remainder = Data(buffer[start...])
        return false
      }
      if done { break }
    }
    return Position(offset: consumed)
  }
}
