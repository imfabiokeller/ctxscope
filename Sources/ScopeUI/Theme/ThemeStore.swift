internal import Foundation
public import SwiftUI

/// The theme the instrument is drawn with.
///
/// Dark and light ship in the bundle and follow the system appearance. A
/// theme is still data, a JSON file per appearance, but there is no user
/// themes folder and no picker: one fewer thing in the window, and one fewer
/// way for a file on disk to change what the instrument says.
@MainActor
@Observable
public final class ThemeStore {
  private let themes: [Theme]
  /// The theme in use.
  public private(set) var theme: Theme
  /// What the system is showing. The app keeps this up to date.
  public private(set) var appearance: Theme.Appearance

  public init(themes: [Theme]? = nil, appearance: Theme.Appearance = .dark) {
    let loaded = themes ?? ThemeLoader.bundled()
    self.themes = loaded
    self.appearance = appearance
    theme = ThemeLoader.pick(loaded, for: appearance)
  }

  /// Takes the appearance the system is showing now, and the theme with it.
  public func follow(system appearance: Theme.Appearance) {
    self.appearance = appearance
    theme = ThemeLoader.pick(themes, for: appearance)
  }
}

extension EnvironmentValues {
  /// The theme every view reads its colors and fonts from. There is no other
  /// way for a view to get one.
  @Entry public var theme: Theme = ThemeLoader.pick(ThemeLoader.bundled(), for: .dark)

  /// True while the window is being rendered to an image rather than shown.
  /// A scroll view renders as an empty box offscreen, so the views that have
  /// one show their clipped form instead. Nothing else may depend on this.
  @Entry public var isRendering: Bool = false
}
