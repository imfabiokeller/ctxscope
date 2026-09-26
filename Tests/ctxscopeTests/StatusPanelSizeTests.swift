import SwiftUI
import Testing

@testable import ScopeUI
@testable import ctxscope

/// The panel measures its content before it is placed. A measurement of zero
/// once put an empty box over the menu bar, and the placement tests, which
/// are handed a size, could not see it.
@Suite("the panel's measured size")
@MainActor
struct StatusPanelSizeTests {
  @Test("is the content's size, not zero")
  func measured() {
    let panel = StatusPanel(
      content: Text("retry-policy").frame(width: 362, height: 450), theme: .preview)
    #expect(panel.panelSize.width == 362)
    #expect(panel.panelSize.height == 450)
  }
}
