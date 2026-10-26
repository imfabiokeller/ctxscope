internal import Foundation

// Bundle only: no user themes folder, so no file on disk can change what the instrument says.
public enum ThemeLoader {
  public static func bundled() -> [Theme] {
    let urls = resources.urls(forResourcesWithExtension: "json", subdirectory: "Themes")
    let themes = (urls ?? []).compactMap(decode).sorted { $0.name < $1.name }
    precondition(!themes.isEmpty, "no themes in the bundle")
    return themes
  }

  // SwiftPM's `Bundle.module` looks beside the app and in the build folder it came
  // from, never in Contents/Resources, so a bundled app that left the Mac it was
  // built on would not find its themes.
  private static var resources: Bundle {
    let name = "ctxscope_ScopeUI.bundle"
    if let url = Bundle.main.resourceURL?.appending(path: name), let found = Bundle(url: url) {
      return found
    }
    return Bundle.module
  }

  public static func pick(_ themes: [Theme], for appearance: Theme.Appearance) -> Theme {
    themes.first { $0.appearance == appearance && $0.name == appearance.rawValue }
      ?? themes.first { $0.appearance == appearance }
      ?? themes[0]
  }

  private static func decode(_ url: URL) -> Theme? {
    guard let data = try? Data(contentsOf: url),
      let theme = try? JSONDecoder().decode(Theme.self, from: data)
    else { return nil }
    return theme
  }
}
