import Foundation
import ScopeCore
import SwiftUI
import Testing

@testable import ScopeUI

/// What the popover says, worked out from the same analyses the window
/// shows, and a popover that follows the model and the theme while it is
/// open.
@Suite("the popover's content", .serialized)
@MainActor
struct PopoverContentTests {
  private func model(focus: Bool = true) async throws -> InstrumentModel {
    let recording = SyntheticRecording.make()
    let model = InstrumentModel(feed: RecordingFeed(recordings: [recording]))
    model.reloadSessions()
    await model.settle()
    if focus {
      model.focus(session: recording.sessionID)
      await model.settle()
    }
    return model
  }

  private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
    return calendar
  }

  /// Twelve seconds after the lane's last request.
  private func context(_ model: InstrumentModel) -> PopoverPresenter.Context {
    let written = model.analysis?.lane.snapshots.last?.timestamp ?? 0
    return PopoverPresenter.Context(
      now: Date(timeIntervalSince1970: written + 12), home: "/Users/someone", calendar: utc)
  }

  private func focused(_ model: InstrumentModel) throws -> FocusedPopover {
    guard case .focused(let content) = PopoverSource.content(of: model, context: context(model))
    else {
      Issue.record("expected a session in focus")
      throw CancellationError()
    }
    return content
  }

  @Test("the figures are the analyzers' own")
  func figures() async throws {
    let model = try await model()
    let content = try focused(model)
    let analysis = try #require(model.analysis)
    let last = analysis.lastRequest
    let tally = try #require(analysis.tally(at: last))
    let costs = CostAnalyzer.run(analysis.lane)

    #expect(content.size == UIFormat.tokens(tally.total))
    #expect(content.sizeNote.hasPrefix("of \(TokenFormat.axis(analysis.lane.window.tokens)) · "))
    #expect(content.kinds.map(\.kind) == Kind.allCases)
    #expect(
      content.kinds.map(\.size) == Kind.allCases.map { UIFormat.tokens(tally.tokens(of: $0)) })
    #expect(content.figures.map(\.term) == ["This request", "Session so far", "Carried, unused"])
    #expect(content.figures[0].value == TokenFormat.dollars(costs.perRequest[last].context))
    #expect(content.figures[1].value == TokenFormat.dollars(costs.context(through: last)))
    #expect(content.figures[2].note?.hasPrefix("· $") == true)
  }

  @Test("the line under the name says where, which request and how long ago")
  func meta() async throws {
    let model = try await model()
    let content = try focused(model)
    let count = try #require(model.analysis?.requestCount)
    #expect(content.meta.hasSuffix(" · request \(count) · 12 s ago"))
    #expect(content.lane == "main lane")
    #expect(content.sparkRange == "1 \u{2192} \(count)")
  }

  @Test("one bar per request, the breaks marked, while they fit")
  func spark() async throws {
    let model = try await model()
    let content = try focused(model)
    let analysis = try #require(model.analysis)
    #expect(content.spark.count == analysis.requestCount)
    let marked = Set(content.spark.indices.filter { content.spark[$0].isBreak })
    #expect(marked == Set(analysis.cache.busts.map(\.request)))
    #expect(content.spark.allSatisfy { (0...1).contains($0.height) })
  }

  @Test("the last cache break is the newest one, with its extra")
  func lastBreak() async throws {
    let model = try await model()
    let content = try focused(model)
    let analysis = try #require(model.analysis)
    let bust = try #require(analysis.cache.busts.last)
    let shown = try #require(content.lastBreak)
    #expect(shown.line.hasPrefix("Request \(bust.request + 1) · "))
    #expect(
      shown.extra == "+" + TokenFormat.dollars(CostAnalyzer.run(analysis.lane).extra(of: bust)))
    let since = analysis.lastRequest - bust.request
    #expect(
      shown.ago == (since == 0 ? "this request" : TokenFormat.plural(since, "request") + " ago"))
  }

  @Test("with nothing in focus it offers the command and the recent sessions")
  func empty() async throws {
    let model = try await model(focus: false)
    guard case .empty(let content) = PopoverSource.content(of: model, context: context(model))
    else {
      Issue.record("expected nothing in focus")
      return
    }
    #expect(content.command == "/ctxscope")
    #expect(content.recent.map(\.id) == model.list.entries.prefix(3).map(\.id))
  }

  @Test("the session menu leaves out the session in focus")
  func others() {
    let now = Date(timeIntervalSince1970: 2_000_000)
    let entries = (0..<14).map { index in
      SessionList.Entry(
        session: .init(
          id: "s\(index)", project: "/Users/someone/code/p\(index)",
          url: URL(fileURLWithPath: "/tmp/s\(index).jsonl"), title: index == 1 ? nil : "t\(index)",
          lastActivity: now.addingTimeInterval(-Double(index) * 600), byteSize: 1, isLive: false))
    }
    let context = PopoverPresenter.Context(now: now, home: "/Users/someone", calendar: utc)
    let recent = PopoverPresenter.recent(entries, excluding: "s0", limit: 10, context: context)
    #expect(recent.count == 10)
    #expect(recent.first?.id == "s1")
    // A session with no title yet is called by its folder.
    #expect(recent.first?.name == "p1")
    #expect(recent.first?.detail == "~/code/p1")
    #expect(recent.first?.ago == "10 min ago")
  }

  @Test("the popover follows the theme while it is open, not the one it opened with")
  func followsTheTheme() async throws {
    let model = try await model()
    let themes = ThemeStore(appearance: .dark)
    let dark = try render(model, themes: themes)
    themes.follow(system: .light)
    #expect(try render(model, themes: themes) != dark)
  }

  @Test("what it shows follows the model")
  func followsTheModel() async throws {
    let model = try await model()
    let themes = ThemeStore(appearance: .light)
    let shown = try render(model, themes: themes)
    // A session that goes away leaves a popover that says so rather than
    // one that keeps showing numbers nothing stands behind.
    model.focus(session: nil)
    await model.settle()
    #expect(try render(model, themes: themes) != shown)
  }

  private func render(_ model: InstrumentModel, themes: ThemeStore) throws -> Data {
    let renderer = ImageRenderer(
      content: StatusPopoverHost(
        model: model, themes: themes, home: "/Users/someone", actions: PopoverActions()
      )
      .environment(\.isRendering, true))
    renderer.scale = 1
    let image = try #require(renderer.cgImage)
    let bitmap = try #require(image.dataProvider?.data as Data?)
    return bitmap
  }
}

/// How the popover says when, and where.
@Suite("the popover's words")
struct PopoverWordsTests {
  private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
    return calendar
  }

  @Test("how long ago, the way the popover writes it")
  func ago() throws {
    let now = try #require(utc.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 10)))
    let ago = { (seconds: Double) in UIFormat.ago(now - seconds, now: now, calendar: utc) }
    #expect(ago(12) == "12 s ago")
    #expect(ago(-5) == "0 s ago")
    #expect(ago(120) == "2 min ago")
    #expect(ago(48 * 60) == "48 min ago")
    #expect(ago(3 * 3600) == "3 h ago")
    #expect(ago(14 * 3600) == "Yesterday")
    #expect(ago(4 * 86_400) == "4 days ago")
  }

  @Test("a folder under the home directory starts with a tilde")
  func folder() {
    #expect(UIFormat.folder("/Users/someone/code/api", home: "/Users/someone") == "~/code/api")
    #expect(UIFormat.folder("/Users/someone", home: "/Users/someone/") == "~")
    #expect(
      UIFormat.folder("/Users/someonex/code", home: "/Users/someone") == "/Users/someonex/code")
    #expect(UIFormat.folder("/opt/code", home: "") == "/opt/code")
  }

  @Test("every cause of a break has its words")
  func causes() {
    #expect(UIFormat.cause(.toolsChanged) == "tool definitions changed")
    let words = CacheBustCause.allCases.map(UIFormat.cause)
    #expect(Set(words).count == CacheBustCause.allCases.count)
    #expect(words.allSatisfy { $0.first?.isLowercase == true })
  }

  @Test("more requests than bars share them, and the newest is the last bar")
  func bucketed() {
    let totals = (0..<1000).map { $0 * 100 }
    let bars = SparkBars.make(totals: totals, breaks: [3], window: 200_000, capacity: 164)
    #expect(bars.count == 164)
    #expect(bars.last?.height == Double(totals[999]) / 200_000)
    #expect(bars[0].isBreak)
    #expect(bars.dropFirst().allSatisfy { !$0.isBreak })
    // A context past its window is the top of the chart, never past it.
    let over = SparkBars.make(totals: [300_000], breaks: [], window: 200_000, capacity: 164)
    #expect(over.first?.height == 1)
  }
}
