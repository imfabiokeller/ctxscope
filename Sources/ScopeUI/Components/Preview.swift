extension Theme {
  /// The theme the component previews are drawn with: the light one.
  static var preview: Theme {
    ThemeLoader.pick(ThemeLoader.bundled(), for: .light)
  }
}
