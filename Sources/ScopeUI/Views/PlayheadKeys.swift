internal import SwiftUI

/// `.focusable()` alone only takes focus with Keyboard navigation on in System
/// Settings, so focus is taken on appear.
struct PlayheadKeys: ViewModifier {
  let model: InstrumentModel
  @FocusState private var isFocused: Bool
  static let stride = 10

  func body(content: Content) -> some View {
    content
      .focusable(interactions: .edit)
      .focused($isFocused)
      .focusEffectDisabled()
      .onAppear { isFocused = true }
      .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
        let step = press.modifiers.contains(.shift) ? Self.stride : 1
        model.move(playheadTo: model.playhead + (press.key == .leftArrow ? -step : step))
        return .handled
      }
      .onKeyPress(keys: [.upArrow, .downArrow]) { press in
        model.moveSelection(by: press.key == .upArrow ? -1 : 1)
        return .handled
      }
      .onKeyPress(.space) {
        model.toggleReplay()
        return .handled
      }
      .onKeyPress(.escape) {
        model.select(nil)
        return .handled
      }
  }
}
