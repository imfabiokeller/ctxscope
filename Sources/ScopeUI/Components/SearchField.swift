public import SwiftUI

/// A text field renders as an empty box offscreen, so the renderer gets plain text.
public struct SearchField: View {
  private let label: String
  private let prompt: String
  @Binding private var text: String
  @FocusState private var isFocused: Bool
  @Environment(\.theme) private var theme
  @Environment(\.isRendering) private var isRendering

  public init(_ label: String, prompt: String = "Filter", text: Binding<String>) {
    self.label = label
    self.prompt = prompt
    _text = text
  }

  public var body: some View {
    let search = theme.metrics.search
    let control = theme.metrics.control
    let shape = RoundedRectangle(cornerRadius: control.cornerRadius)
    field
      .font(theme.type.caption)
      .foregroundStyle(theme.text.primary.color)
      .padding(.leading, search.textInset + theme.metrics.hairline)
      .padding(.trailing, search.trailingInset + theme.metrics.hairline)
      .frame(width: search.width, height: search.height)
      .background(shape.fill(theme.control.fill.color))
      .overlay { shape.strokeBorder(theme.line.control.color, lineWidth: theme.metrics.hairline) }
      .overlay(alignment: .leading) {
        GlyphView(.magnifier, side: search.glass, stroke: search.glassStroke)
          .foregroundStyle(theme.text.tertiary.color)
          .padding(.leading, search.glassInset)
      }
      .overlay {
        if isFocused {
          shape.inset(by: -control.focusRingWidth / 2)
            .stroke(theme.control.focusRing.color, lineWidth: control.focusRingWidth)
        }
      }
  }

  /// The prompt is drawn here: AppKit sets a text field prompt in its own
  /// placeholder color whatever style it is given.
  private var field: some View {
    ZStack(alignment: .leading) {
      if text.isEmpty {
        Text(prompt)
          .foregroundStyle(theme.text.tertiary.color)
          .lineLimit(1)
          .accessibilityHidden(true)
      }
      if isRendering {
        Text(text).lineLimit(1)
      } else {
        TextField(label, text: $text, prompt: Text(""))
          .textFieldStyle(.plain)
          .focused($isFocused)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

#Preview {
  @Previewable @State var text = ""
  SearchField("Filter blocks", text: $text)
    .padding()
    .environment(\.theme, Theme.preview)
}
