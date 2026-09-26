internal import ScopeCore

public enum StatusVoice {
  public static let name = "ctxscope"

  public static func value(_ reading: StatusReading?) -> String {
    guard let reading else { return "no session in focus" }
    let size =
      "\(TokenFormat.short(reading.totalTokens)) of \(TokenFormat.axis(reading.window)), "
      + "\(TokenFormat.percent(reading.fill)) full"
    guard reading.isLive else { return "\(size), idle" }
    return reading.breaksCache ? "\(size), cache break on the last request" : size
  }

  public static func tooltip(_ reading: StatusReading?) -> String {
    "\(name), \(value(reading))"
  }
}
