import SwiftUI
import Testing

@testable import ScopeUI
@testable import ctxscope

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
