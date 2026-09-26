import Foundation
import ScopeConnect
import ScopeUI
import SwiftUI

/// The Connect panel in each of the states a person can meet it in, drawn
/// against settings files made for the pictures.
///
/// Never the real home directory: a shot has to look the same every time, and
/// nothing here may touch the settings of the person running it.
@MainActor
enum ConnectShot {
  static let size = Metrics.standard.connect.size

  struct Shot {
    let name: String
    let view: ConnectPanel
  }

  /// Every state, and the temporary directory they were built in.
  static func all() async -> (shots: [Shot], home: URL)? {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "ctxscope-shot-\(UUID().uuidString)")
    guard
      (try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true))
        != nil
    else { return nil }
    let plain = "{\n  \"model\": \"opus\"\n}\n"
    var shots: [Shot] = []

    let off = ConnectModel(home: home(in: root, "off", plain), listening: 45871)
    shots.append(Shot(name: "connect-off", view: ConnectPanel(model: off)))

    let on = ConnectModel(home: home(in: root, "on", plain), listening: 45871)
    on.act()
    shots.append(Shot(name: "connect-on", view: ConnectPanel(model: on)))

    // Connected, and ctxscope is somewhere else.
    let movedHome = home(in: root, "moved", plain)
    ConnectModel(home: movedHome, listening: 45871).act()
    let moved = ConnectModel(home: movedHome, listening: 45873)
    shots.append(Shot(name: "connect-moved", view: ConnectPanel(model: moved)))

    // The file changed while the panel sat open.
    let changedHome = home(in: root, "changed", plain)
    let changed = ConnectModel(home: changedHome, listening: 45871)
    try? Data("{\n  \"model\": \"opus\",\n  \"permissions\": {}\n}\n".utf8)
      .write(to: changedHome.settings)
    changed.act()
    shots.append(Shot(name: "connect-changed", view: ConnectPanel(model: changed)))

    // A settings file ctxscope will not touch.
    let refused = ConnectModel(
      home: home(in: root, "refused", "{\n  \"model\": \"opus\",\n}\n"), listening: 45871)
    shots.append(Shot(name: "connect-refused", view: ConnectPanel(model: refused)))

    // The renderer never runs a task, so the diffs are waited for here.
    for model in [off, on, moved, changed, refused] { await model.settle() }
    return (shots, root)
  }

  private static func home(in root: URL, _ name: String, _ settings: String) -> ClaudeHome {
    let folder = root.appending(path: name)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let home = ClaudeHome(root: folder)
    try? Data(settings.utf8).write(to: home.settings)
    return home
  }
}
