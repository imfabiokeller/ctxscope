import Foundation

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
