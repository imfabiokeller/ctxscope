public import SwiftUI

/// The Timeline page: context per request with its prompts and costs, the
/// prompts as a table, and the cache breaks and the selected prompt beside
/// them.
///
/// It takes plain values from `TimelinePresenter` and closures, and reads no
/// model: what a click means is the caller's to decide.
public struct TimelinePage<Header: View>: View {
  private let data: TimelineData
  private let onSelectPrompt: (Int) -> Void
  private let onMovePlayhead: (Int) -> Void
  private let onShowContext: (Int) -> Void
  private let hover: ColumnHover?
  private let header: Header
  @Environment(\.theme) private var theme

  /// `onSelectPrompt` gets a prompt's number, from one. `onMovePlayhead` and
  /// `onShowContext` get a request index, from zero. A click on a column
  /// moves the playhead there and selects the prompt it belongs to.
  public init(
    data: TimelineData,
    onSelectPrompt: @escaping (Int) -> Void,
    onMovePlayhead: @escaping (Int) -> Void,
    onShowContext: @escaping (Int) -> Void,
    hover: ColumnHover? = nil,
    @ViewBuilder header: () -> Header
  ) {
    self.hover = hover
    self.data = data
    self.onSelectPrompt = onSelectPrompt
    self.onMovePlayhead = onMovePlayhead
    self.onShowContext = onShowContext
    self.header = header()
  }

  public var body: some View {
    WindowLayout {
      header
    } main: {
      main
    } sidebar: {
      sidebar
    }
  }

  private var main: some View {
    let metrics = theme.metrics.timeline
    return VStack(alignment: .leading, spacing: metrics.sectionGap) {
      ContextChartSection(
        chart: data.chart, prompts: data.prompts, onSelectPrompt: onSelectPrompt,
        onPickColumn: pick, hover: hover
      )
      .zIndex(1)
      VStack(alignment: .leading, spacing: metrics.headingGap) {
        SectionHeader(TimelineWords.prompts).frame(height: metrics.headingHeight)
        PromptTable(prompts: data.prompts, onSelect: onSelectPrompt)
      }
    }
    .padding(.vertical, metrics.padding.vertical)
    .padding(.horizontal, metrics.padding.horizontal)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  /// The breaks and the selected prompt's detail, scrolled to the detail
  /// when another prompt is picked.
  private var sidebar: some View {
    let selected = data.prompts.first(where: \.isSelected)?.id
    return SidebarScroll(focus: selected) {
      TimelineSidebar(
        breaks: data.breaks, detail: data.detail, detailID: selected,
        onShowContext: onShowContext)
    }
  }

  private func pick(_ column: Int) {
    onMovePlayhead(column)
    if let prompt = data.prompts.first(where: { $0.requests.contains(column) }) {
      onSelectPrompt(prompt.id)
    }
  }
}
