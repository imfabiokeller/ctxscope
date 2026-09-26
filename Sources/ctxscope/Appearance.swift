import AppKit
import Combine
import ScopeUI

/// What the system is showing, and when it changes.
///
/// `preferredColorScheme` makes a window's own `colorScheme` its own override,
/// so a view that watches it never sees a system switch. AppKit's effective
/// appearance is the only thing that knows.
enum Appearance {
  @MainActor
  static func current() -> Theme.Appearance {
    from(NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing())
  }

  static func from(_ appearance: NSAppearance) -> Theme.Appearance {
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
  }

  /// Fires when the system switches. Distributed notifications need no
  /// permission and are what the system posts for this.
  @MainActor
  static let changes = DistributedNotificationCenter.default()
    .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
}
