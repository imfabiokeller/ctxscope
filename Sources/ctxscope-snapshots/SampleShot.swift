import Foundation
import ScopeUI
import SwiftUI

@MainActor
enum SampleShot {
  struct Picture {
    let name: String
    let size: CGSize
    // A closure, so each picture starts from a model nobody has moved or selected in.
    let view: @MainActor () async -> AnyView

    init(name: String, size: CGSize, view: @escaping @MainActor () async -> AnyView) {
      self.name = name
      self.size = size
      self.view = view
    }

    init(name: String, size: CGSize, view: @autoclosure @escaping @MainActor () -> AnyView) {
      self.init(name: name, size: size) { view() }
    }
  }

  static var all: [Picture] { pages + PopoverShot.samples }

  private static let pages: [Picture] = [
    Picture(name: "components", size: ComponentGallery.size) { AnyView(ComponentGallery()) },
    Picture(name: "context", size: Metrics.standard.window.size) { AnyView(ContextSample()) },
    Picture(name: "context-synthetic", size: Metrics.standard.window.size) {
      let model = await Shot.make(.small, withText: true)
      return AnyView(WindowFrame { InstrumentView(model: model) })
    },
    Picture(name: "context-magnifier", size: Metrics.standard.window.size) {
      let model = await Shot.make(.small, withText: true)
      let count = model.figures?.column.slices.count ?? 0
      return AnyView(
        WindowFrame {
          InstrumentView(model: model, stripHover: StripHover(index: count / 3, x: 300))
        })
    },
    Picture(name: "timeline", size: Metrics.standard.window.size) {
      AnyView(TimelineShot(data: TimelineSample.data()))
    },
    Picture(name: "timeline-synthetic", size: Metrics.standard.window.size) {
      AnyView(TimelineShot(data: TimelineSynthetic.data()))
    },
    Picture(name: "timeline-window-synthetic", size: Metrics.standard.window.size) {
      let model = await Shot.make(.small, withText: true)
      if let block = model.selection { model.showInTimeline(block: block) }
      return AnyView(WindowFrame { InstrumentView(model: model) })
    },
    Picture(name: "timeline-hover", size: Metrics.standard.window.size) {
      let data = TimelineSynthetic.data()
      let column = data.chart.columns.count - 4
      return AnyView(
        TimelineShot(
          data: data,
          hover: ColumnHover(
            column: column, slice: data.chart.columns[column].slices.count / 2, x: 950)))
    },
    Picture(name: "timeline-magnifier", size: CGSize(width: 380, height: 480)) {
      AnyView(MagnifierShot(chart: TimelineSynthetic.data().chart))
    },
  ]

  static func run(output: URL) async -> [String] {
    let folder = output.appending(path: "samples")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var written: [String] = []
    for shot in all {
      for theme in ThemeLoader.bundled() {
        let name = "\(shot.name)-\(theme.name).png"
        guard
          let url = Renderer.write(
            await shot.view().environment(\.theme, theme).environment(\.isRendering, true),
            size: shot.size,
            to: folder.appending(path: name))
        else {
          FileHandle.standardError.write(Data("could not render \(name)\n".utf8))
          continue
        }
        written.append("samples/\(url.lastPathComponent)")
      }
    }
    return written
  }
}

private struct SampleHeader<Trailing: View>: View {
  let page: WindowPage
  @ViewBuilder let trailing: () -> Trailing

  var body: some View {
    WindowHeader(
      session: PopUpTitle("retry-policy", subtitle: "~/code/api-client", emphasized: true),
      sessionItems: { Button("retry-policy") {} },
      lane: PopUpTitle("Lane: main", subtitle: "+ 2 subagents"),
      laneItems: { Button("Main") {} },
      pages: WindowPage.allCases, page: .constant(page), pageTitle: \.rawValue,
      liveTitle: "Live", trailing: trailing)
  }
}

struct ContextWindow<Main: View, Sidebar: View>: View {
  let main: Main
  let sidebar: Sidebar

  init(@ViewBuilder main: () -> Main, @ViewBuilder sidebar: () -> Sidebar) {
    self.main = main()
    self.sidebar = sidebar()
  }

  var body: some View {
    WindowFrame {
      WindowLayout {
        SampleHeader(page: .context) {
          RequestStepper(position: 87, count: 87, onPrevious: {}, onNext: {})
        }
      } main: {
        main
      } sidebar: {
        sidebar
      }
    }
  }
}

private struct TimelineShot: View {
  let data: TimelineData
  var hover: ColumnHover?

  var body: some View {
    WindowFrame {
      TimelinePage(
        data: data, onSelectPrompt: { _ in }, onMovePlayhead: { _ in }, onShowContext: { _ in },
        hover: hover
      ) {
        SampleHeader(page: .timeline) { HeaderNote(data.headerNote) }
      }
    }
  }
}

private struct MagnifierShot: View {
  let chart: TimelineChart
  @Environment(\.theme) private var theme

  var body: some View {
    let column = min(59, chart.columns.count - 1)
    ColumnMagnifier(
      chart: chart, column: column, slice: chart.columns[column].slices.count / 2
    )
    .fixedSize()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.surface.window.color)
  }
}
