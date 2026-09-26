public enum RequestNumber {
  public static func of(_ index: Int) -> Int { index + 1 }

  public static func index(_ number: Int) -> Int { max(0, number - 1) }

  public static func counter(_ index: Int, of count: Int) -> String {
    guard count > 0 else { return "0 / 0" }
    return "\(of(min(index, count - 1))) / \(count)"
  }

  public static func name(_ index: Int) -> String { "request \(of(index))" }
}
