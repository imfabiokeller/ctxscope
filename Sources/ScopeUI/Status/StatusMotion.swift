public enum StatusMotion {
  public static let seconds = 0.2

  public static func crossFades(
    from previous: StatusFace?,
    to face: StatusFace,
    reduceMotion: Bool
  ) -> Bool {
    guard let previous else { return false }
    guard !reduceMotion else { return false }
    return previous != face
  }
}
