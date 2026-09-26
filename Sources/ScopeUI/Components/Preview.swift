extension Theme {
  static var preview: Theme {
    ThemeLoader.pick(ThemeLoader.bundled(), for: .light)
  }
}
