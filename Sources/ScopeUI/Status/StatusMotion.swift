/// When the item is worth a cross-fade, and for how long.
///
/// The one piece of motion in the menu bar. Apple discourages constant
/// animation there and the idle budget forbids it, so this is a single fade
/// from the old picture to the new one, driven by the change itself: a
/// request landing and changing the number, the session going quiet, or a
/// session coming into focus or leaving it. Nothing moves while nothing
/// happens, nothing repeats, and nothing is scheduled.
public enum StatusMotion {
  /// About a fifth of a second: long enough to be seen out of the corner of
  /// an eye, short enough that the number is never behind the truth.
  public static let seconds = 0.2

  public static func crossFades(
    from previous: StatusFace?,
    to face: StatusFace,
    reduceMotion: Bool
  ) -> Bool {
    // The first picture has nothing to fade from, and neither does the item
    // coming back after being turned off.
    guard let previous else { return false }
    // Reduce Motion means no motion, not less of it.
    guard !reduceMotion else { return false }
    return previous != face
  }
}
