import AppKit
import ScopeUI

/// The part of a status item the controller draws on.
///
/// A protocol because everything the controller decides, what the item shows
/// and when a redraw is worth doing, is otherwise only checkable by hanging an
/// item in a real menu bar and looking at it.
@MainActor
protocol StatusButton: AnyObject {
  /// The display the bar is on, which decides the scale it is drawn at.
  var barScreen: NSScreen? { get }
  func draw(image: NSImage?, number: NSAttributedString, tooltip: String, value: String)
  /// Fades from what is drawn now to whatever is drawn next.
  func crossFade(seconds: Double)
}

extension NSStatusBarButton: StatusButton {
  var barScreen: NSScreen? { window?.screen }

  func draw(image: NSImage?, number: NSAttributedString, tooltip: String, value: String) {
    self.image = image
    attributedTitle = number
    toolTip = tooltip
    setAccessibilityLabel(StatusVoice.name)
    setAccessibilityValue(value)
  }

  /// One Core Animation transition, added before the next drawing and gone
  /// once it has run. The system drives it: there is no timer, no repeat and
  /// nothing to switch off afterwards.
  func crossFade(seconds: Double) {
    wantsLayer = true
    let fade = CATransition()
    fade.type = .fade
    fade.duration = seconds
    layer?.add(fade, forKey: "contents")
  }
}
