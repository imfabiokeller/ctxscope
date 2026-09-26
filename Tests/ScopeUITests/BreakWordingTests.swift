import Foundation
import ScopeCore
import Testing

@testable import ScopeUI

/// Each card says what the facts of its break carry, and no more.
@Suite("Cache break cards")
struct BreakWordingTests {
  private func card(_ lane: Lane) throws -> BreakCard {
    try #require(TimelineLanes.present(lane).breaks.cards.first)
  }

  @Test("an edited memory file")
  func memory() throws {
    // CLAUDE.md leaves at request 3 and its new text enters there.
    var lane = TimelineLanes.lane(
      requests: 5,
      extra: [.init(band: .mem, label: "CLAUDE.md", tokens: 2100, born: 3)],
      reads: [3: 11_000])
    lane = replacing(lane, label: "CLAUDE.md", diedAt: 3)
    let card = try card(lane)
    #expect(card.title == "Memory changed")
    #expect(
      card.detail
        == "CLAUDE.md was edited, so everything after the system prompt and tools was sent uncached."
    )
    #expect(card.place == "Request 4 · prompt 1")
    #expect(card.extra.hasPrefix("+$"))
  }

  @Test("a server's tools arriving")
  func tools() throws {
    let lane = TimelineLanes.lane(
      requests: 4,
      extra: [
        .init(band: .mcp, label: "mcp__github__create_issue", tokens: 600, born: 2),
        .init(band: .mcp, label: "mcp__github__list_issues", tokens: 400, born: 2),
      ],
      reads: [2: 11_000])
    let card = try card(lane)
    #expect(card.title == "Tool definitions changed")
    #expect(
      card.detail
        == "The github MCP server connected and added 2 tools (~1.0k). "
        + "Everything after the system prompt and tools was sent uncached.")
  }

  @Test("a pause longer than the cache lasts")
  func idle() throws {
    let lane = TimelineLanes.lane(requests: 4, reads: [2: 0], gaps: [2: 360])
    let card = try card(lane)
    #expect(card.title == "Cache expired")
    #expect(
      card.detail
        == "6 minutes passed since request 2, longer than the cache lasts. "
        + "The whole context was sent uncached.")
  }

  @Test("a switch of model")
  func model() throws {
    let lane = TimelineLanes.lane(
      requests: 3, reads: [2: 0], models: [2: "other"])
    let card = try card(lane)
    #expect(card.title == "Model changed")
    #expect(
      card.detail
        == "The model changed from model to other. A model keeps its own cache, "
        + "so the whole context was sent uncached.")
  }

  @Test("a break nothing explains says so")
  func unknown() throws {
    let lane = TimelineLanes.lane(requests: 4, reads: [2: 14_000])
    let card = try card(lane)
    #expect(card.title == "Cause not recorded")
    #expect(
      card.detail
        == "The transcript does not show what changed. "
        + "Everything after the first 14.0k was sent uncached.")
  }

  @Test("durations read the way a person says them")
  func durations() {
    #expect(BreakWording.duration(45) == "45 seconds")
    #expect(BreakWording.duration(360) == "6 minutes")
    #expect(BreakWording.duration(7200) == "2 hours")
  }

  /// The lane with the first block of a label leaving at a request.
  private func replacing(_ lane: Lane, label: String, diedAt request: Int) -> Lane {
    var segments = lane.segments
    if let index = segments.firstIndex(where: { $0.label == label }) {
      segments[index].died = request
    }
    return Lane(
      id: lane.id, window: lane.window, segments: segments, snapshots: lane.snapshots,
      prompts: lane.prompts)
  }
}
