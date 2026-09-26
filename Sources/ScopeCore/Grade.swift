/// Provenance of a number: measured, derived or estimated, as
/// `docs/HOW_IT_MEASURES.md` describes. The UI never shows a token count
/// without one, so the grade travels with the value.
public enum Grade: String, Sendable, Codable, CaseIterable, Comparable {
  /// Reported by the API.
  case measured = "M"
  /// Arithmetic on measured values.
  case derived = "D"
  /// Produced by the local estimator.
  case estimated = "E"

  /// Ordered by strength: measured is the strongest.
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

/// A token count with its provenance.
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

/// A share with its provenance, for the same reason a token count has one.
public struct GradedShare: Sendable, Hashable, Codable {
  public var value: Double
  public var grade: Grade

  public init(value: Double, grade: Grade) {
    self.value = value
    self.grade = grade
  }
}
