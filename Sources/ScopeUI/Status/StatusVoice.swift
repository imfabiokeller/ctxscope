internal import ScopeCore

/// What the menu bar item says when it is read out loud or hovered.
///
/// Every state has a name, a value and a tooltip, including the state where
/// nothing is in focus: an item with no name is an unnamed button in the
/// middle of the bar, and an item with no tooltip is one nobody can ask what
/// it is.
public enum StatusVoice {
  /// The item's name, which never changes: it is the same application
  /// whatever it happens to be showing.
  public static let name = "ctxscope"

  /// What it is showing, in words: "142.6k of 200k".
  public static func value(_ reading: StatusReading?) -> String {
    guard let reading else { return "no session in focus" }
    let size =
      "\(TokenFormat.short(reading.totalTokens)) of \(TokenFormat.axis(reading.window))"
    // An idle session drops its number from the bar, so it says why.
    return reading.isLive ? size : "\(size), idle"
  }

  /// The same, as one line under the pointer: "ctxscope, 142.6k of 200k".
  public static func tooltip(_ reading: StatusReading?) -> String {
    "\(name), \(value(reading))"
  }
}
