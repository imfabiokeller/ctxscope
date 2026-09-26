public import CoreGraphics
internal import ScopeCore
internal import SwiftUI

/// What the menu bar item looks like: the mark filled or outlined, whether
/// it is dimmed, and the number beside it.
///
/// One decision in one place. The application wraps it in an `NSImage` and a
/// title, the snapshot tool draws it to a file, and a test reads it, so none
/// of the three can disagree about what a state looks like. The image is
/// always a template, so the system inverts it with the bar and highlights
/// it on a click.
public struct StatusFace: Sendable, Equatable {
  public enum Style: Sendable, Equatable {
    /// A session is in focus.
    case filled
    /// None is.
    case outlined
  }

  public let style: Style
  /// The session in focus is idle.
  public let isDimmed: Bool
  /// The context size, "143k", while the session in focus is being written.
  public let number: String?

  public init(style: Style, isDimmed: Bool, number: String?) {
    self.style = style
    self.isDimmed = isDimmed
    self.number = number
  }

  /// What the item shows for this reading.
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

/// The mark as pixels, at one scale.
///
/// The application asks for one image per scale a bar can be shown at and
/// wraps them in an `NSImage`; the snapshot tool asks for the same pixels and
/// writes them to a file. Nothing draws the mark anywhere else.
@MainActor
public enum StatusRender {
  public static func image(_ face: StatusFace, ink: ThemeColor, scale: CGFloat) -> CGImage? {
    let renderer = ImageRenderer(content: StatusBars(face: face, ink: ink, scale: scale))
    renderer.scale = scale
    return renderer.cgImage
  }
}
