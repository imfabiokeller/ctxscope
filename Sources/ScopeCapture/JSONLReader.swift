internal import Foundation

// The file is input only: nothing here writes, moves or locks it.
struct JSONLReader: Sendable {
  static let chunkSize = 1 << 20

  struct Position: Sendable, Hashable {
    var offset: UInt64

    init(offset: UInt64 = 0) {
      self.offset = offset
    }

    static let start = Position()
  }

  struct Line: Sendable {
    let value: JSONValue
    let range: EntryRange
  }

  struct Result: Sendable {
    let entries: [Line]
    let position: Position
    // A file being appended to can end in half a line; that is normal.
    let skipped: Int
  }

  let url: URL

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

  @discardableResult
  func stream(from position: Position = .start, _ body: (Data, EntryRange) throws -> Void) throws
    -> Position
  {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    if position.offset > 0 { try handle.seek(toOffset: position.offset) }

    var consumed = position.offset
    var remainder = Data()
    // `JSONSerialization` returns autoreleased objects; without these pools they
    // stay alive until the process ends.
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
