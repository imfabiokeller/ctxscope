internal import SwiftUI

/// Keyboard control of the window.
///
/// Left and right move the playhead, shift moves it further, up and down move
/// the selection through the blocks alive at the playhead in reading order,
/// and space toggles replay. A view nobody can drive without a pointer is a
/// view half the people who need it cannot drive.
///
/// `.focusable()` on its own only takes focus when "Keyboard navigation" is on
/// in System Settings, so focus is taken on appear through a FocusState. It is
/// not taken again on a click: a click belongs to whatever was clicked, the
/// filter field or the table, and the keys those leave alone still arrive
/// here because this is their ancestor.
struct PlayheadKeys: ViewModifier {
  let model: InstrumentModel
  @FocusState private var isFocused: Bool
  /// How far shift moves the playhead.
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
