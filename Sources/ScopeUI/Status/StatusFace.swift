public import CoreGraphics
internal import ScopeCore
internal import SwiftUI

public struct StatusFace: Sendable, Equatable {
  public let state: StatusGlyph.State
  public let fill: Double
  public let number: String?

  public init(state: StatusGlyph.State, fill: Double, number: String?) {
    self.state = state
    self.fill = StatusGlyph.snapped(fill)
    self.number = number
  }

  public init(reading: StatusReading?) {
    guard let reading else {
      self.init(state: .idle, fill: 0, number: nil)
      return
    }
    self.init(
      state: Self.state(of: reading), fill: reading.fill,
      number: reading.isLive ? TokenFormat.brief(reading.totalTokens) : nil)
  }

  static func state(of reading: StatusReading) -> StatusGlyph.State {
    guard reading.isLive else { return .idle }
    return reading.breaksCache ? .cacheBreak : .live
  }
}

@MainActor
public enum StatusRender {
  public static func image(_ face: StatusFace, ink: ThemeColor, scale: CGFloat) -> CGImage? {
    let renderer = ImageRenderer(content: StatusBars(face: face, ink: ink))
    renderer.scale = scale
    return renderer.cgImage
  }
}
