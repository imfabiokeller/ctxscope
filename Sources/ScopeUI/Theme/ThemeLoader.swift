internal import Foundation

/// Where themes come from: the two that ship in the bundle.
///
/// Separate from the store because a theme has to be loadable without a
/// store, so that the environment has one before any window exists. There is
/// no user themes folder: a file on disk that can change what the instrument
/// says is one thing too many.
public enum ThemeLoader {
  public static func bundled() -> [Theme] {
    let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Themes")
    let themes = (urls ?? []).compactMap(decode).sorted { $0.name < $1.name }
    // A build without its themes is a broken build, not a themeless one.
    precondition(!themes.isEmpty, "no themes in the bundle")
    return themes
  }

  /// The theme for an appearance: the one named after it, or any that says it
  /// belongs to it.
  public static func pick(_ themes: [Theme], for appearance: Theme.Appearance) -> Theme {
    themes.first { $0.appearance == appearance && $0.name == appearance.rawValue }
      ?? themes.first { $0.appearance == appearance }
      ?? themes[0]
  }

  /// A theme file that does not decode is not a theme. Only the bundle is read, so that is a broken build.
  private static func decode(_ url: URL) -> Theme? {
    guard let data = try? Data(contentsOf: url),
      let theme = try? JSONDecoder().decode(Theme.self, from: data)
    else { return nil }
    return theme
  }
}
