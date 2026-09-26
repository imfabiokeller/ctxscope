/// How a request is numbered wherever a person reads one.
///
/// Inside a recording a request is an index from zero, because it is an index
/// into arrays. To a person the first request of a lane is request 1. The two
/// were the same number until a session with a single request said "0 / 0" in
/// one place and "since request 0, 0 requests" in another, which reads as
/// a session that has not happened.
///
/// One convention, one place: the window, the menu bar and the CLI all count
/// from one, and a number a person types is read back through `index`.
public enum RequestNumber {
  /// The number a person sees for a request index.
  public static func of(_ index: Int) -> Int { index + 1 }

  /// The index of a number a person gave.
  public static func index(_ number: Int) -> Int { max(0, number - 1) }

  /// "3 / 12", the command line's form. A lane with no requests says so with two
  /// zeros, which is the one place that reading is true.
  public static func counter(_ index: Int, of count: Int) -> String {
    guard count > 0 else { return "0 / 0" }
    return "\(of(min(index, count - 1))) / \(count)"
  }

  /// "request 3", for a mark that stands on its own.
  public static func name(_ index: Int) -> String { "request \(of(index))" }
}
