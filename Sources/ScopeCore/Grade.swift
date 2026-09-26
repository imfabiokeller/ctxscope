public enum Grade: String, Sendable, Codable, CaseIterable, Comparable {
  case measured = "M"
  case derived = "D"
  case estimated = "E"

  private var strength: Int {
    switch self {
    case .measured: 0
    case .derived: 1
    case .estimated: 2
    }
  }

  public static func < (lhs: Grade, rhs: Grade) -> Bool {
    lhs.strength < rhs.strength
  }
}

public struct Tokens: Sendable, Hashable, Codable {
  public var value: Int
  public var grade: Grade

  public init(_ value: Int, _ grade: Grade) {
    self.value = value
    self.grade = grade
  }

  public static let zero = Tokens(0, .measured)

  public static func + (lhs: Tokens, rhs: Tokens) -> Tokens {
    Tokens(lhs.value + rhs.value, max(lhs.grade, rhs.grade))
  }

  public static func += (lhs: inout Tokens, rhs: Tokens) {
    lhs = lhs + rhs
  }
}

public struct GradedShare: Sendable, Hashable, Codable {
  public var value: Double
  public var grade: Grade

  public init(value: Double, grade: Grade) {
    self.value = value
    self.grade = grade
  }
}
