internal import Foundation
public import SwiftUI

@MainActor
@Observable
public final class ThemeStore {
  private let themes: [Theme]
  public private(set) var theme: Theme
  public private(set) var appearance: Theme.Appearance

  public init(themes: [Theme]? = nil, appearance: Theme.Appearance = .dark) {
    let loaded = themes ?? ThemeLoader.bundled()
    self.themes = loaded
    self.appearance = appearance
    theme = ThemeLoader.pick(loaded, for: appearance)
  }

  public func follow(system appearance: Theme.Appearance) {
    self.appearance = appearance
    theme = ThemeLoader.pick(themes, for: appearance)
  }
}

extension EnvironmentValues {
  @Entry public var theme: Theme = ThemeLoader.pick(ThemeLoader.bundled(), for: .dark)

  // A scroll view renders empty offscreen, so views show their clipped form while this is set.
  @Entry public var isRendering: Bool = false
}
