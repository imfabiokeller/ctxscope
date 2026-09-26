public import Foundation
public import ScopeCore

/// The popover's words and shares, from the analyses the window shows.
///
/// Pure functions: everything they read is passed in, including the time,
/// so "12 s ago" is as old as the moment the caller asked, and a test can
/// hold the clock. Nothing here measures anything; the numbers are the
/// analyzers', and the formatting is `TokenFormat`'s and `UIFormat`'s.
public enum PopoverPresenter {
  /// What a person types in a Claude Code chat to focus it.
  public static let command = "/ctxscope"
  /// The recent sessions the empty popover lists, and the most the session
  /// menu offers.
  public static let recentCount = 3
  public static let menuCount = 10

  /// Which session this is, apart from its lanes.
  public struct Session: Sendable, Equatable {
    public let id: String
    public let title: String?
    /// The project folder, as a path.
    public let project: String

    public init(id: String, title: String?, project: String) {
      self.id = id
      self.title = title
      self.project = project
    }

    /// Its title, or its folder's name when it has none yet.
    public var name: String {
      title ?? project.split(separator: "/").last.map(String.init) ?? String(id.prefix(8))
    }
  }

  /// When the popover is asked for, and whose home a folder is shortened
  /// against.
  public struct Context: Sendable {
    public let now: Date
    public let home: String
    public let calendar: Calendar

    public init(now: Date, home: String, calendar: Calendar = .current) {
      self.now = now
      self.home = home
      self.calendar = calendar
    }
  }

  /// The popover of a session in focus, at its latest request. Nil for a
  /// lane with no requests yet, which has nothing to show.
  public static func focused(
    session: Session, lane: Lane, tally: Tally, costs: CostAnalysis, cache: CacheAnalysis,
    unused: UnusedSummary, isLive: Bool, sessions: [SessionList.Entry], context: Context
  ) -> FocusedPopover? {
    let last = lane.snapshots.count - 1
    guard last >= 0, last < tally.perRequest.count, last < costs.perRequest.count else {
      return nil
    }
    let entry = tally.perRequest[last]
    let window = lane.window.tokens
    let written = lane.snapshots[last].timestamp
    let meta = [
      UIFormat.folder(session.project, home: context.home),
      RequestNumber.name(last),
      written > 0
        ? UIFormat.ago(
          Date(timeIntervalSince1970: written), now: context.now, calendar: context.calendar)
        : nil,
    ]
    return FocusedPopover(
      title: session.name,
      lane: lane.id == .main ? "main lane" : "\(lane.agentType ?? "subagent") lane",
      isLive: isLive,
      meta: meta.compactMap { $0 }.joined(separator: " · "),
      size: UIFormat.tokens(entry.total),
      sizeNote: "of \(TokenFormat.axis(window)) · \(TokenFormat.percent(entry.fill))",
      kinds: Kind.allCases.map { kind in
        let tokens = entry.tokens(of: kind)
        return FocusedPopover.KindPart(
          kind: kind, share: Double(tokens.value) / Double(max(1, window)),
          size: UIFormat.tokens(tokens))
      },
      figures: [
        .init(term: "This request", value: TokenFormat.dollars(costs.perRequest[last].context)),
        .init(term: "Session so far", value: TokenFormat.dollars(costs.context(through: last))),
        .init(
          term: "Carried, unused", value: UIFormat.tokens(unused.tokens),
          note: "· " + TokenFormat.dollars(unused.dollars)),
      ],
      lastBreak: lastBreak(cache: cache, costs: costs, at: last),
      sparkRange: "\(RequestNumber.of(0)) \u{2192} \(RequestNumber.of(last))",
      spark: SparkBars.make(
        totals: tally.perRequest.map(\.total.value),
        breaks: Set(cache.busts.map(\.request)), window: window,
        capacity: Metrics.standard.popover.sparkCapacity),
      others: recent(sessions, excluding: session.id, limit: menuCount, context: context)
    )
  }

  /// The popover with no session in focus.
  public static func empty(sessions: [SessionList.Entry], context: Context) -> EmptyPopover {
    EmptyPopover(
      command: command,
      recent: recent(sessions, excluding: nil, limit: recentCount, context: context))
  }

  /// The newest cache break up to a request, with how long ago it was and
  /// what it added.
  static func lastBreak(
    cache: CacheAnalysis, costs: CostAnalysis, at request: Int
  ) -> FocusedPopover.CacheBreak? {
    guard let bust = cache.busts.last(where: { $0.request <= request }) else { return nil }
    let since = request - bust.request
    return FocusedPopover.CacheBreak(
      ago: since == 0 ? "this request" : TokenFormat.plural(since, "request") + " ago",
      line: "Request \(RequestNumber.of(bust.request)) · \(UIFormat.cause(bust.cause))",
      extra: "+" + TokenFormat.dollars(costs.extra(of: bust)))
  }

  /// Sessions somebody can pick, in the list's order: live first, then by
  /// when they were last written.
  static func recent(
    _ entries: [SessionList.Entry], excluding id: String?, limit: Int, context: Context
  ) -> [RecentSession] {
    entries.lazy.filter { $0.id != id }.prefix(limit).map { entry in
      let session = entry.session
      // How long a session is is only known once it has been opened.
      let requests = entry.lanes.first { $0.lane == .main }?.requests
      let detail = [
        UIFormat.folder(session.project, home: context.home),
        requests.map { TokenFormat.plural($0, "request") },
      ]
      return RecentSession(
        id: session.id,
        name: Session(id: session.id, title: session.title, project: session.project).name,
        detail: detail.compactMap { $0 }.joined(separator: " · "),
        ago: UIFormat.ago(session.lastActivity, now: context.now, calendar: context.calendar))
    }
  }
}
