import Foundation

/// Which session ctxscope is showing, kept between launches.
///
/// Focus is the person's choice, made by typing `/ctxscope` in a session or by
/// picking one in the window. It is ctxscope's own setting, like the power
/// state: Claude's settings file is written once and never again.
struct FocusStore {
  static let key = "focus.session"
  let defaults: any Settings

  init(defaults: any Settings) {
    self.defaults = defaults
  }

  var session: String? { defaults.string(forKey: Self.key) }

  func set(_ session: String?) {
    guard let session else { return defaults.removeObject(forKey: Self.key) }
    defaults.set(session, forKey: Self.key)
  }
}
