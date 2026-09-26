import AppKit
import Combine
import ScopeUI

// `preferredColorScheme` overrides a window's `colorScheme`, so only AppKit's effective
// appearance sees a system switch.
enum Appearance {
  @MainActor
  static func current() -> Theme.Appearance {
    from(NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing())
  }

  static func from(_ appearance: NSAppearance) -> Theme.Appearance {
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
  }

  @MainActor
  static let changes = DistributedNotificationCenter.default()
    .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
}
