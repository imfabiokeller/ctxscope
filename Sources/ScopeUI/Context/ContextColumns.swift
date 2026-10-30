public import ScopeCore
public import SwiftUI

public struct ContextMain: View {
  private let data: ContextPageData
  @Binding private var filter: BlockFilter
  @Binding private var query: String
  @Binding private var selection: SegmentID?
  private let hover: StripHover?
  @Environment(\.theme) private var theme

  public init(
    data: ContextPageData, filter: Binding<BlockFilter>, query: Binding<String>,
    selection: Binding<SegmentID?>, hover: StripHover? = nil
  ) {
    self.data = data
    self.hover = hover
    _filter = filter
    _query = query
    _selection = selection
  }

  public var body: some View {
    let page = theme.metrics.contextPage
    VStack(alignment: .leading, spacing: page.sectionGap) {
      HStack(spacing: theme.metrics.card.gap) {
        ForEach(data.cards) { card in
          StatCard(
            label: card.label, figure: card.figure, unit: card.unit, detail: card.detail,
            fillsHeight: true)
        }
      }
      .fixedSize(horizontal: false, vertical: true)
      ContextStrip(strip: data.strip, legend: data.legend, hover: hover) { selection = $0 }
        // The magnifier hangs below the strip, over the blocks.
        .zIndex(1)
      BlocksSection(
        blocks: data.blocks, filter: $filter, query: $query, selection: $selection)
    }
    .padding(page.padding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

public struct ContextSidebar: View {
  private let inspector: InspectorData?
  private let noSelection: String
  private let onShowInTimeline: (SegmentID) -> Void
  private let onCopy: (String) -> Void
  @Environment(\.theme) private var theme

  public init(
    inspector: InspectorData?, noSelection: String,
    onShowInTimeline: @escaping (SegmentID) -> Void, onCopy: @escaping (String) -> Void
  ) {
    self.inspector = inspector
    self.noSelection = noSelection
    self.onShowInTimeline = onShowInTimeline
    self.onCopy = onCopy
  }

  public var body: some View {
    let page = theme.metrics.contextPage
    SidebarScroll {
      Group {
        if let inspector {
          details(inspector)
        } else {
          Text(noSelection)
            .font(theme.type.body)
            .foregroundStyle(theme.text.secondary.color)
        }
      }
      .padding(page.sidebarPadding)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
  }

  private func details(_ inspector: InspectorData) -> some View {
    let page = theme.metrics.contextPage
    return VStack(alignment: .leading, spacing: page.sidebarGap) {
      VStack(alignment: .leading, spacing: page.titleGap) {
        KindLegendItem(
          color: theme.color(of: inspector.kind),
          name: inspector.kindName, style: .caption)
        Text(inspector.title)
          .font(theme.type.title)
          .lineSpacing(theme.type.titleLineSpacing)
          .foregroundStyle(theme.text.primary.color)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.vertical, theme.type.titleLineSpacing / 2)
          .accessibilityAddTraits(.isHeader)
      }
      FactsView(facts: inspector.facts)
      if let text = inspector.text {
        VStack(alignment: .leading, spacing: page.textGap) {
          Text(inspector.textTitle)
            .font(theme.type.captionStrong)
            .foregroundStyle(theme.text.primary.color)
            .line(theme.type.lines.caption)
          // The sidebar scrolls, so the whole text is readable.
          CodeBlock(text, height: .full)
        }
      }
      HStack(spacing: theme.metrics.control.buttonGap) {
        Button(inspector.timelineTitle) { onShowInTimeline(inspector.block) }
        Button(inspector.copyTitle) { inspector.text.map(onCopy) }
          .disabled(inspector.text == nil)
      }
      .buttonStyle(.borderedPush)
    }
  }
}
