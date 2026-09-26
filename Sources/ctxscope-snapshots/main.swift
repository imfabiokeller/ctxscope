import AppKit
import Foundation
import ScopeCore
import ScopeUI
import SwiftUI

@MainActor
func run() async {
  let output = URL(fileURLWithPath: Arguments.value("out") ?? "artifacts")
  try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
  if Arguments.flag("samples") {
    let written = await SampleShot.run(output: output)
    print(written.joined(separator: "\n"))
    print("\(written.count) sample shots in \(output.appending(path: "samples").path)")
    return
  }
  let themes = ThemeLoader.bundled()
  var written: [String] = []

  // Never render into the repository: a picture of a real session is transcript content.
  if let id = Arguments.value("session") {
    guard let model = await Shot.session(id) else {
      FileHandle.standardError.write(Data("no session \(id)\n".utf8))
      return
    }
    let pages = Arguments.value("page").map { [WindowPage(argument: $0)].compactMap(\.self) }
    for page in pages ?? WindowPage.allCases {
      model.page = page
      if page == .timeline, let block = model.selection { model.showInTimeline(block: block) }
      for theme in themes {
        let name = "session-\(page.argument)-\(theme.name)"
        // Hosted, so scroll views lay out the way the app lays them out.
        guard
          let url = await Renderer.writeHosted(
            InstrumentView(model: model).environment(\.theme, theme),
            size: Shot.windowSize, to: output.appending(path: "\(name).png"))
        else { continue }
        written.append(url.lastPathComponent)
      }
    }
    print(written.joined(separator: "\n"))
    return
  }

  for shot in StatusShot.all(themes: themes) {
    guard
      let url = Renderer.write(
        shot.view.environment(\.theme, themes[0]).environment(\.isRendering, true),
        size: shot.size,
        to: output.appending(path: "\(shot.name).png")
      )
    else { continue }
    written.append(url.lastPathComponent)
  }

  for shot in Shot.popovers {
    for theme in themes {
      let model = await shot.model()
      let content = PopoverSource.content(of: model, context: Shot.popoverContext(model))
      guard
        let url = Renderer.write(
          OnDesktop { StatusPopover(content: content, actions: PopoverActions()) }
            .environment(\.theme, theme).environment(\.isRendering, true),
          size: shot.size,
          to: output.appending(path: "\(shot.name)-\(theme.name).png")
        )
      else { continue }
      written.append(url.lastPathComponent)
    }
  }

  if let connect = await ConnectShot.all() {
    for shot in connect.shots {
      for theme in themes {
        guard
          let url = Renderer.write(
            shot.view.environment(\.theme, theme).environment(\.isRendering, true),
            size: ConnectShot.size,
            to: output.appending(path: "\(shot.name)-\(theme.name).png")
          )
        else { continue }
        written.append(url.lastPathComponent)
      }
    }
    try? FileManager.default.removeItem(at: connect.home)
  }

  for shot in Shot.all {
    for theme in themes {
      let model = await shot.model()
      let name = "\(shot.name)-\(theme.name)"
      guard
        let url = Renderer.write(
          InstrumentView(model: model).environment(\.theme, theme)
            .environment(\.isRendering, true),
          size: shot.size,
          to: output.appending(path: "\(name).png")
        )
      else {
        FileHandle.standardError.write(Data("could not render \(name)\n".utf8))
        continue
      }
      written.append(url.lastPathComponent)
    }
  }
  print(written.sorted().joined(separator: "\n"))
  print("\(written.count) snapshots in \(output.path)")
}

await run()
