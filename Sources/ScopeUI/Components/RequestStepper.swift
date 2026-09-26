public import SwiftUI

/// Steps through the requests one at a time: "‹ Request 87 of 87 ›". An arrow
/// that has nowhere to go is disabled.
public struct RequestStepper: View {
  private let position: Int
  private let count: Int
  private let onPrevious: () -> Void
  private let onNext: () -> Void
  @Environment(\.theme) private var theme

  /// `position` counts from 1, the way requests are numbered.
  public init(
    position: Int, count: Int, onPrevious: @escaping () -> Void, onNext: @escaping () -> Void
  ) {
    self.position = position
    self.count = count
    self.onPrevious = onPrevious
    self.onNext = onNext
  }

  public var body: some View {
    let control = theme.metrics.control
    HStack(spacing: control.stepperGap) {
      Button(action: onPrevious) {
        GlyphView(.chevronLeft, side: control.stepperArrow, stroke: control.stepperArrowStroke)
      }
      .buttonStyle(StepperArrowStyle())
      .disabled(position <= 1)
      .accessibilityLabel("Previous request")

      label
        .font(theme.type.body)
        .foregroundStyle(theme.text.primary.color)
        .frame(minWidth: control.stepperLabelWidth)

      Button(action: onNext) {
        GlyphView(.chevronRight, side: control.stepperArrow, stroke: control.stepperArrowStroke)
      }
      .buttonStyle(StepperArrowStyle())
      .disabled(position >= count)
      .accessibilityLabel("Next request")
    }
  }

  private var label: Text {
    let current = Text(UIFormat.count(position)).font(theme.type.bodyStrong)
    return Text("Request \(current) of \(UIFormat.count(count))")
  }
}

/// A borderless square around an arrow, which only shows itself when
/// pressed.
private struct StepperArrowStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    StepperArrowFace(configuration: configuration)
  }
}

private struct StepperArrowFace: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.theme) private var theme
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    let control = theme.metrics.control
    let shape = RoundedRectangle(cornerRadius: control.cornerRadius)
    configuration.label
      .foregroundStyle((isEnabled ? theme.text.primary : theme.text.disabled).color)
      .frame(width: control.height, height: control.height)
      .background {
        if configuration.isPressed {
          shape.fill(theme.control.pressed.color)
        }
      }
      .contentShape(shape)
  }
}

#Preview {
  VStack {
    RequestStepper(position: 87, count: 87, onPrevious: {}, onNext: {})
    RequestStepper(position: 1, count: 87, onPrevious: {}, onNext: {})
  }
  .padding()
  .environment(\.theme, Theme.preview)
}
