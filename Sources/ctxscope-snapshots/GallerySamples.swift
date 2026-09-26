import ScopeUI
import SwiftUI

struct SurfacesSection: View {
  @Environment(\.theme) private var theme

  var body: some View {
    GallerySection("Surfaces") {
      HStack(spacing: theme.metrics.card.gap) {
        StatCard(
          label: "Context", figure: "142.6k", unit: "of 200k",
          detail: "71% full · +3.7k this request")
        StatCard(
          label: "Session so far", figure: "$3.94",
          detail: "87 requests · 9 prompts · 3 cache breaks")
      }
      Card {
        HStack(spacing: theme.metrics.card.infoHeaderGap) {
          NumberBadge(1)
          Text("Request 23 · prompt 4").font(theme.type.caption)
            .foregroundStyle(theme.text.supporting.color)
          Spacer(minLength: 0)
          Text("+$0.17").font(theme.type.bodyStrong)
        }
        Text("Memory changed").font(theme.type.bodyMedium)
        Text(
          "CLAUDE.md was edited, so everything after the system prompt and tools was sent uncached."
        )
        .font(theme.type.caption)
        .lineSpacing(theme.type.captionLineSpacing)
        .foregroundStyle(theme.text.secondary.color)
      }
      .foregroundStyle(theme.text.primary.color)
      VStack(spacing: 0) {
        Text("Hairline, divider and row rules above the popover's footer")
          .font(theme.type.caption).foregroundStyle(theme.text.secondary.color)
          .padding(theme.metrics.table.cellPadding)
        Hairline()
        Hairline(.divider).padding(.top, theme.metrics.table.cellPadding)
        Hairline(.row).padding(.vertical, theme.metrics.table.cellPadding)
        PanelFooter {
          Button {
          } label: {
            Text("Open window").frame(maxWidth: .infinity)
          }
          .buttonStyle(.primaryPush)
          Button("Change session…") {}.buttonStyle(.borderedPush)
          Button {
          } label: {
            GlyphView(.ellipsis, side: theme.metrics.control.ellipsis)
          }
          .buttonStyle(.iconPush)
          .accessibilityLabel("More")
        }
        PanelFooter(.text) {
          Button("Open window") {}.buttonStyle(.textLink)
          Spacer(minLength: 0)
          Button("Quit ctxscope") {}.buttonStyle(.textLink(.plain))
        }
      }
      .frame(width: theme.metrics.popover.width)
      .background(theme.surface.popover.color)
    }
  }
}

private struct BlockRow: Identifiable {
  let id: Int
  let kind: String
  let label: String
  let size: String
  let carried: String
  let used: Bool?
  let cost: String
}

private struct PromptRow: Identifiable {
  let id: Int
  let prompt: String
  let range: String
  let added: String
  let cost: String
  let breaks: String
}

struct TablesSection: View {
  @Environment(\.theme) private var theme

  var body: some View {
    let blocks = theme.metrics.table.blocks
    let prompts = theme.metrics.table.prompts
    GallerySection("Tables") {
      SectionHeader(
        "Blocks", detail: Text("1,284 in this request · largest first"), layout: .inline
      ) {
        SegmentedPicker(
          "Show", selection: .constant("All"), options: ["All", "Unused", "Sent every request"],
          size: .filter
        ) { $0 }
        SearchField("Filter blocks", text: .constant(""))
      }
      DataTable(
        Self.blockRows, selection: .constant(0),
        columns: [
          DataColumn("Kind", width: .fixed(blocks.kind)) { row in
            KindLegendItem(color: color(row.kind), name: row.kind, style: .table)
          },
          DataColumn("Block") { $0.label },
          DataColumn("Size ↓", width: .fixed(blocks.size), alignment: .trailing) { $0.size },
          DataColumn("Carried", width: .fixed(blocks.carried), alignment: .trailing) {
            $0.carried
          },
          DataColumn("Used", width: .fixed(blocks.used)) { row in
            Text(row.used.map { $0 ? "yes" : "no" } ?? "not tracked")
              .foregroundStyle((row.used == false ? theme.text.unused : theme.text.primary).color)
          },
          DataColumn("Cost so far", width: .fixed(blocks.cost), alignment: .trailing) {
            $0.cost
          },
        ]
      )
      .frame(height: theme.metrics.table.headerHeight + theme.metrics.table.rowHeight * 5)
      DataTable(
        Self.promptRows, selection: .constant(7), density: .compact,
        columns: [
          DataColumn("#", width: .fixed(prompts.number)) { row in
            Text(UIFormat.count(row.id)).foregroundStyle(theme.text.secondary.color)
          },
          DataColumn("Prompt") { $0.prompt },
          DataColumn("Requests", width: .fixed(prompts.requests), alignment: .trailing) {
            $0.range
          },
          DataColumn("Context added", width: .fixed(prompts.added), alignment: .trailing) {
            $0.added
          },
          DataColumn("Cost", width: .fixed(prompts.cost), alignment: .trailing) { $0.cost },
          DataColumn("Cache breaks", width: .fixed(prompts.breaks), alignment: .trailing) {
            $0.breaks
          },
        ]
      )
      .frame(
        height: theme.metrics.table.compactHeaderHeight + theme.metrics.table.compactRowHeight
          * 3)
    }
  }

  private func color(_ kind: String) -> ThemeColor {
    theme.kind.named.first { $0.name == kind }?.color ?? theme.kind.system
  }

  private static let blockRows = [
    BlockRow(
      id: 0, kind: "results", label: "Bash · npm test (full output)", size: "~14.2k",
      carried: "32 req", used: false, cost: "$0.14"),
    BlockRow(
      id: 1, kind: "results", label: "Read · src/api/client.ts", size: "~12.4k",
      carried: "31 req", used: true, cost: "$0.12"),
    BlockRow(
      id: 2, kind: "tools", label: "GitHub MCP · 26 tool definitions", size: "~9.8k",
      carried: "24 req", used: nil, cost: "$0.07"),
    BlockRow(
      id: 3, kind: "agent", label: "Thinking · plan for the jitter cap", size: "~4.4k",
      carried: "46 req", used: false, cost: "$0.06"),
    BlockRow(
      id: 4, kind: "memory", label: "CLAUDE.md", size: "~3.6k", carried: "65 req", used: nil,
      cost: "$0.07"),
  ]

  private static let promptRows = [
    PromptRow(
      id: 6, prompt: "Write tests for the elapsed-time cap", range: "42–54", added: "+17.5k",
      cost: "$0.73", breaks: "1"),
    PromptRow(
      id: 7, prompt: "Why is test_backoff flaky?", range: "55–63", added: "+14.0k",
      cost: "$0.37", breaks: "0"),
    PromptRow(
      id: 8, prompt: "Connect GitHub and open a pull request", range: "64–75",
      added: "+25.5k", cost: "$1.04", breaks: "1"),
  ]
}

struct ListsSection: View {
  @Environment(\.theme) private var theme

  var body: some View {
    GallerySection("Lists and text") {
      FactGrid(Self.facts, isWide: \.wide) { fact in
        FactTile(
          label: fact.id, value: fact.value, detail: fact.detail,
          swatch: fact.wide ? theme.kind.results : nil, trailing: fact.wide ? "14.2k" : nil)
      }
      .frame(width: theme.metrics.window.sidebarWidth - 2 * theme.metrics.card.gap * 2)
      DefinitionList([
        .init("This request", "$0.058"),
        .init("Carried, unused", carriedUnused),
      ])
      .frame(width: theme.metrics.popover.width)
      HStack(alignment: .top, spacing: theme.metrics.card.gap * 2) {
        CodeBlock(Self.testOutput)
        InlineCode("/ctxscope")
      }
    }
  }

  private struct Fact: Identifiable {
    let id: String
    let value: String
    let detail: String?
    let wide: Bool
  }

  private static let facts = [
    Fact(id: "Context", value: "+14.0k", detail: "81.7k → 95.7k", wide: false),
    Fact(id: "Cost", value: "$0.37", detail: "9 requests", wide: false),
    Fact(id: "Per request", value: "$0.04", detail: nil, wide: false),
    Fact(id: "Cache breaks", value: "1", detail: "+$0.27 sent again", wide: false),
    Fact(id: "Largest addition", value: "Bash · npm test, full output", detail: nil, wide: true),
  ]

  private var carriedUnused: Text {
    let cost = Text("· $1.12").font(theme.type.body).foregroundStyle(theme.text.secondary.color)
    return Text("61.2k \(cost)")
  }

  private static let testOutput = """
    > api-client@2.4.0 test
    > jest --runInBand

    PASS  tests/test_policy.ts
    FAIL  tests/test_backoff.ts

    Tests: 1 failed, 214 passed, 215 total
    …
    """
}
