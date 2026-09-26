import AppKit
import ScopeUI

@MainActor
protocol StatusButton: AnyObject {
  var barScreen: NSScreen? { get }
  func draw(image: NSImage?, number: NSAttributedString, tooltip: String, value: String)
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

  func crossFade(seconds: Double) {
    wantsLayer = true
    let fade = CATransition()
    fade.type = .fade
    fade.duration = seconds
    layer?.add(fade, forKey: "contents")
  }
}
