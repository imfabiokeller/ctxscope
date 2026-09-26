import Foundation
import ScopeCore
import ScopeUI
import SwiftUI

/// The popover filled with sample values, focused on a session and with
/// nothing in focus.
///
/// A shot is the panel's own box, border included, with the desktop behind
/// its corners and its shadow drawn where it falls inside that box.
@MainActor
enum PopoverShot {
  /// The panel's height with these values, in points.
  static let focusedHeight: CGFloat = 450.5
  static let emptyHeight: CGFloat = 333.5

  static var samples: [SampleShot.Picture] {
    let width = Metrics.standard.popover.width + 2 * Metrics.standard.hairline
    return [
      SampleShot.Picture(
        name: "popover", size: CGSize(width: width, height: focusedHeight),
        view: AnyView(OnDesktop { StatusPopover(content: .focused(focused), actions: .init()) })),
      SampleShot.Picture(
        name: "popover-empty", size: CGSize(width: width, height: emptyHeight),
        view: AnyView(OnDesktop { StatusPopover(content: .empty(empty), actions: .init()) })),
    ]
  }

  /// The sample session.
  static let focused = FocusedPopover(
    title: "retry-policy", lane: "main lane", isLive: true,
    meta: "~/code/api-client · request 87 · 12 s ago",
    size: "142.6k", sizeNote: "of 200k · 71%",
    kinds: [
      .init(kind: .system, share: 0.0155, size: "3.1k"),
      .init(kind: .tools, share: 0.092, size: "18.4k"),
      .init(kind: .memory, share: 0.021, size: "4.2k"),
      .init(kind: .you, share: 0.034, size: "6.8k"),
      .init(kind: .agent, share: 0.1065, size: "21.3k"),
      .init(kind: .results, share: 0.444, size: "88.8k"),
    ],
    figures: [
      .init(term: "This request", value: "$0.058"),
      .init(term: "Session so far", value: "$3.94"),
      .init(term: "Carried, unused", value: "61.2k", note: "· $1.12"),
    ],
    lastBreak: .init(
      ago: "23 requests ago", line: "Request 64 · tool definitions changed", extra: "+$0.39"),
    sparkRange: "1 \u{2192} 87", spark: spark, others: [])

  /// The sample chart: a formula for the context of each of 87 requests,
  /// with breaks at requests 23, 42 and 64, and heights rounded to a tenth
  /// of a point.
  static var spark: [SparkBar] {
    let ends = [5, 14, 22, 30, 41, 54, 63, 75, 87]
    return (1...87).map { request in
      let share = Double(request) / 87
      let phase = Double((ends.firstIndex { $0 >= request } ?? 8) + 1)
      let total =
        3100 + (request >= 64 ? 18400 : 8600) + (request >= 23 ? 4200 : 3700) + 6800 * phase / 9
        + 21300 * share + 88800 * pow(share, 1.25)
      let points = (total / 200_000 * 40 * 10).rounded() / 10
      return SparkBar(height: points / 40, isBreak: [23, 42, 64].contains(request))
    }
  }

  static let empty = EmptyPopover(
    command: "/ctxscope",
    recent: [
      .init(
        id: "1", name: "retry-policy", detail: "~/code/api-client · 87 requests",
        ago: "2 min ago"),
      .init(
        id: "2", name: "helm-chart-bump", detail: "~/infra/charts · 31 requests",
        ago: "48 min ago"),
      .init(
        id: "3", name: "ocr-pipeline-timeouts", detail: "~/code/doc-ingest · 214 requests",
        ago: "Yesterday"),
    ])
}

/// The panel at the top of its box, on the desktop.
struct OnDesktop<Content: View>: View {
  let content: Content
  @Environment(\.theme) private var theme

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    // An overlay, so a panel taller than the box still starts at its top
    // rather than being centered on it.
    theme.chrome.desktop.color
      .overlay(alignment: .top) { content }
      .clipped()
  }
}
