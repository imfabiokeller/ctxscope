public import SwiftUI

// The push buttons, as button styles, so every button stays a native
// `Button` with its keyboard, focus and accessibility behavior and only its
// face comes from the theme.

/// A white button with a border: "Copy text", "Change session…".
public struct BorderedPushStyle: ButtonStyle {
  public enum Size: Sendable {
    case regular
    /// Beside a command in the popover, which is set taller.
    case tall
  }

  let size: Size

  public func makeBody(configuration: Configuration) -> some View {
    PushFace(configuration: configuration, isIconOnly: false, size: size)
  }
}

/// A square bordered button holding one glyph: the popover's "More".
public struct IconPushStyle: ButtonStyle {
  public func makeBody(configuration: Configuration) -> some View {
    PushFace(configuration: configuration, isIconOnly: true, size: .regular)
  }
}

/// The one filled button in a panel: "Open window".
public struct PrimaryPushStyle: ButtonStyle {
  public func makeBody(configuration: Configuration) -> some View {
    PrimaryFace(configuration: configuration)
  }
}

/// A button that is only its text: a link in the accent color, or a plain
/// command such as "Quit ctxscope".
public struct TextLinkStyle: ButtonStyle {
  public enum Tone: Sendable {
    case accent
    case plain
  }

  let tone: Tone

  public func makeBody(configuration: Configuration) -> some View {
    LinkFace(configuration: configuration, tone: tone)
  }
}

/// A whole row that is one button, with no face until it is pressed: a
/// recent session in the popover.
public struct ListRowStyle: ButtonStyle {
  public func makeBody(configuration: Configuration) -> some View {
    RowFace(configuration: configuration)
  }
}

extension ButtonStyle where Self == ListRowStyle {
  public static var listRow: ListRowStyle { ListRowStyle() }
}

extension ButtonStyle where Self == BorderedPushStyle {
  public static var borderedPush: BorderedPushStyle { BorderedPushStyle(size: .regular) }
  public static func borderedPush(_ size: BorderedPushStyle.Size) -> BorderedPushStyle {
    BorderedPushStyle(size: size)
  }
}

extension ButtonStyle where Self == IconPushStyle {
  public static var iconPush: IconPushStyle { IconPushStyle() }
}

extension ButtonStyle where Self == PrimaryPushStyle {
  public static var primaryPush: PrimaryPushStyle { PrimaryPushStyle() }
}

extension ButtonStyle where Self == TextLinkStyle {
  public static var textLink: TextLinkStyle { TextLinkStyle(tone: .accent) }
  public static func textLink(_ tone: TextLinkStyle.Tone) -> TextLinkStyle {
    TextLinkStyle(tone: tone)
  }
}

/// The face of a bordered and an icon button. A view rather than a function
/// of the style, because only a view can read the theme and whether the
/// button is enabled.
private struct PushFace: View {
  let configuration: ButtonStyleConfiguration
  let isIconOnly: Bool
  let size: BorderedPushStyle.Size
  @Environment(\.theme) private var theme
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    let control = theme.metrics.control
    let height = size == .tall ? control.tallHeight : control.height
    let shape = RoundedRectangle(cornerRadius: control.cornerRadius)
    configuration.label
      .font(theme.type.body)
      .foregroundStyle((isEnabled ? theme.text.primary : theme.text.disabled).color)
      // The padding is inside the border.
      .padding(.horizontal, isIconOnly ? 0 : control.buttonPadding + theme.metrics.hairline)
      .frame(width: isIconOnly ? height : nil, height: height)
      .background {
        shape.fill(theme.control.fill.color)
        if configuration.isPressed {
          shape.fill(theme.control.pressed.color)
        }
      }
      .overlay { shape.strokeBorder(theme.line.control.color, lineWidth: theme.metrics.hairline) }
      .contentShape(shape)
  }
}

private struct PrimaryFace: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.theme) private var theme

  var body: some View {
    let control = theme.metrics.control
    let fill = configuration.isPressed ? theme.control.accentPressed : theme.control.accent
    configuration.label
      .font(theme.type.bodyMedium)
      .foregroundStyle(theme.text.onAccent.color)
      .padding(.horizontal, control.buttonPadding)
      .frame(height: control.height)
      .background(RoundedRectangle(cornerRadius: control.cornerRadius).fill(fill.color))
      .contentShape(RoundedRectangle(cornerRadius: control.cornerRadius))
  }
}

private struct RowFace: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.theme) private var theme

  var body: some View {
    let popover = theme.metrics.popover
    let shape = RoundedRectangle(cornerRadius: theme.metrics.control.cornerRadius)
    configuration.label
      .padding(.horizontal, popover.rowPadding)
      .frame(maxWidth: .infinity, minHeight: popover.rowHeight, maxHeight: popover.rowHeight)
      .background {
        if configuration.isPressed { shape.fill(theme.control.pressed.color) }
      }
      .contentShape(shape)
  }
}

private struct LinkFace: View {
  let configuration: ButtonStyleConfiguration
  let tone: TextLinkStyle.Tone
  @Environment(\.theme) private var theme
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    configuration.label
      .font(theme.type.body)
      .foregroundStyle(ink.color)
      .line(theme.type.lines.body)
      .contentShape(Rectangle())
  }

  private var ink: ThemeColor {
    guard isEnabled else { return theme.text.disabled }
    switch tone {
    case .accent: return configuration.isPressed ? theme.text.linkPressed : theme.text.link
    case .plain: return configuration.isPressed ? theme.text.secondary : theme.text.primary
    }
  }
}

#Preview {
  HStack(spacing: 8) {
    Button {
    } label: {
      Text("Open window").frame(maxWidth: .infinity)
    }
    .buttonStyle(.primaryPush)
    Button("Change session…") {}.buttonStyle(.borderedPush)
    Button {
    } label: {
      GlyphView(.ellipsis, side: Theme.preview.metrics.control.ellipsis)
    }
    .buttonStyle(.iconPush)
    .accessibilityLabel("More")
    Button("Show context") {}.buttonStyle(.textLink)
  }
  .frame(width: 460)
  .padding()
  .environment(\.theme, Theme.preview)
}
