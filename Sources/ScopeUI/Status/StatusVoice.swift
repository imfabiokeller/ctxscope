internal import ScopeCore

public enum StatusVoice {
  public static let name = "ctxscope"

  public static func value(_ reading: StatusReading?) -> String {
    guard let reading else { return "no session in focus" }
    let size =
      "\(TokenFormat.short(reading.totalTokens)) of \(TokenFormat.axis(reading.window))"
    return reading.isLive ? size : "\(size), idle"
  }

  public static func tooltip(_ reading: StatusReading?) -> String {
    "\(name), \(value(reading))"
  }
}
