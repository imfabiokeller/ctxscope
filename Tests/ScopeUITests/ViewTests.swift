import Foundation
import ScopeCore
import Testing

@testable import ScopeUI

@Suite("Views")
struct ViewTests {
  @Test("the header names the lane shown and counts the others")
  @MainActor
  func laneTitle() {
    let lanes = (0..<3).map { index in
      SessionList.LaneEntry(
        lane: index == 0 ? .main : LaneID("agent-\(index)"),
        agentType: index == 0 ? nil : "explore", requests: 10, fill: 0.5)
    }
    #expect(
      HeaderPresenter.lane(.main, in: lanes) == PopUpTitle("Lane: main", subtitle: "+ 2 subagents"))
    #expect(HeaderPresenter.lane(LaneID("agent-1"), in: lanes).title == "Lane: explore")
    #expect(HeaderPresenter.lane(.main, in: []).subtitle == nil)
    #expect(HeaderPresenter.item(lanes[1]) == "explore · 10 requests · 50%")
    #expect(
      UIFormat.folder(NSHomeDirectory() + "/code/api", home: NSHomeDirectory()) == "~/code/api")
    #expect(UIFormat.folder("/tmp/api", home: NSHomeDirectory()) == "/tmp/api")
  }
}
