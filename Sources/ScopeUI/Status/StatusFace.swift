public import CoreGraphics
internal import ScopeCore
internal import SwiftUI

public struct StatusFace: Sendable, Equatable {
  public enum Style: Sendable, Equatable {
    case filled
    case outlined
  }

  public let style: Style
  public let isDimmed: Bool
  public let number: String?

  public init(style: Style, isDimmed: Bool, number: String?) {
    self.style = style
    self.isDimmed = isDimmed
    self.number = number
  }

  public init(reading: StatusReading?) {
    guard let reading else {
      self.init(style: .outlined, isDimmed: false, number: nil)
      return
    }
    self.init(
      style: .filled, isDimmed: !reading.isLive,
      number: reading.isLive ? TokenFormat.brief(reading.totalTokens) : nil)
  }
}

@MainActor
public enum StatusRender {
  public static func image(_ face: StatusFace, ink: ThemeColor, scale: CGFloat) -> CGImage? {
    let renderer = ImageRenderer(content: StatusBars(face: face, ink: ink, scale: scale))
    renderer.scale = scale
    return renderer.cgImage
  }
}
