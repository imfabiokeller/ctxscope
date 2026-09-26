import Foundation
import ScopeUI
import SwiftUI

/// The sample shots: the component gallery and the window's pages filled
/// with made-up values chosen to read well, in both appearances. Beside them,
/// the same pages over the synthetic recording, drawn by the real presenters.
@MainActor
enum SampleShot {
  struct Picture {
    let name: String
    let size: CGSize
    /// Built once per picture, so a shot over a model starts from a model
    /// nobody has moved or selected anything in.
    let view: @MainActor () async -> AnyView

    init(name: String, size: CGSize, view: @escaping @MainActor () async -> AnyView) {
      self.name = name
      self.size = size
      self.view = view
    }

    /// A picture of a view that needs nothing built first.
    init(name: String, size: CGSize, view: @autoclosure @escaping @MainActor () -> AnyView) {
      self.init(name: name, size: size) { view() }
    }
  }

  static var all: [Picture] { pages + PopoverShot.samples }

  private static let pages: [Picture] = [
    Picture(name: "components", size: ComponentGallery.size) { AnyView(ComponentGallery()) },
    Picture(name: "context", size: Metrics.standard.window.size) { AnyView(ContextSample()) },
    // The window over the synthetic 200k recording, through the model.
    Picture(name: "context-synthetic", size: Metrics.standard.window.size) {
      let model = await Shot.make(.small, withText: true)
      return AnyView(WindowFrame { InstrumentView(model: model) })
    },
    // The strip's magnifier open over the page, a block a third of the way
    // along: it has to cover the legend and the table under it, whole.
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
    // The same page as the window shows it, through the model: a block
    // shown in the timeline selects the prompt it entered in.
    Picture(name: "timeline-window-synthetic", size: Metrics.standard.window.size) {
      let model = await Shot.make(.small, withText: true)
      if let block = model.selection { model.showInTimeline(block: block) }
      return AnyView(WindowFrame { InstrumentView(model: model) })
    },
    // The magnifier open over the page near the plot's right end, where it
    // turns to the pointer's left: above the cost bars, the axis and the
    // table, whole.
    Picture(name: "timeline-hover", size: Metrics.standard.window.size) {
      let data = TimelineSynthetic.data()
      let column = data.chart.columns.count - 4
      return AnyView(
        TimelineShot(
          data: data,
          hover: ColumnHover(
            column: column, slice: data.chart.columns[column].slices.count / 2, x: 950)))
    },
    // The magnifier a hovered column shows, which no still picture of the
    // page can: request 60 of the synthetic lane, a block half way up.
    Picture(name: "timeline-magnifier", size: CGSize(width: 380, height: 480)) {
      AnyView(MagnifierShot(chart: TimelineSynthetic.data().chart))
    },
  ]

  /// Writes every shot in every theme to `<output>/samples`, and returns the
  /// names of the files written.
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

/// The header filled with the sample session, on either page.
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

/// The whole window on the Context page, with the sample header and the
/// page's two columns under it.
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

/// The whole window on the Timeline page.
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

/// The magnifier on its own, over the window's background.
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
