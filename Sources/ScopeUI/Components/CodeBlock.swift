public import SwiftUI

/// Recorded text in a box: a block's text in the sidebar, or the diff the
/// Connect panel shows before it writes.
public struct CodeBlock: View {
  public enum Height: Sendable {
    /// Cut off at a fixed height: the sidebar shows the start of a block,
    /// and the whole of it is a copy away.
    case capped
    /// As tall as the room there is, scrolling what does not fit.
    case filling
  }

  private let text: String
  private let height: Height
  @Environment(\.theme) private var theme
  @Environment(\.isRendering) private var isRendering

  public init(_ text: String, height: Height = .capped) {
    self.text = text
    self.height = height
  }

  public var body: some View {
    let code = theme.metrics.code
    let shape = RoundedRectangle(cornerRadius: code.cornerRadius)
    Group {
      // A scroll view renders as an empty box offscreen, so under the
      // renderer the filling box is cut off like the capped one.
      if height == .filling, !isRendering {
        ScrollView { lines.frame(maxWidth: .infinity, alignment: .leading) }
      } else {
        // All of the text is laid out and the box cuts it at its height,
        // rather than the last line that fits being shortened with an
        // ellipsis.
        lines
          .fixedSize(horizontal: false, vertical: true)
          .frame(
            maxWidth: .infinity, minHeight: 0,
            maxHeight: height == .capped ? code.maxHeight : .infinity, alignment: .topLeading
          )
          .clipped()
      }
    }
    .padding(code.padding)
    .background(shape.fill(theme.surface.code.color))
    .overlay { shape.strokeBorder(theme.line.card.color, lineWidth: theme.metrics.hairline) }
  }

  private var lines: some View {
    Text(text)
      .font(theme.type.code)
      .lineSpacing(theme.type.codeLineSpacing)
      .foregroundStyle(theme.text.code.color)
      .textSelection(.enabled)
      // A line height puts half the extra space above the first line and
      // half below the last, where line spacing puts none.
      .padding(.vertical, theme.type.codeLineSpacing / 2)
  }
}

/// A short command set on its own, with room to copy it: `/ctxscope` in the
/// popover.
public struct InlineCode: View {
  private let text: String
  @Environment(\.theme) private var theme

  public init(_ text: String) {
    self.text = text
  }

  public var body: some View {
    Text(text)
      .font(theme.type.codeLarge)
      .foregroundStyle(theme.text.primary.color)
      .textSelection(.enabled)
      // SF Mono at 13 points has the line height SF Pro has.
      .line(theme.type.lines.body)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(theme.metrics.code.inlinePadding)
      .background(
        RoundedRectangle(cornerRadius: theme.metrics.control.cornerRadius)
          .fill(theme.surface.inlineCode.color))
  }
}

#Preview {
  VStack(spacing: 12) {
    CodeBlock("> api-client@2.4.0 test\n> jest --runInBand\n\nPASS  tests/test_policy.ts")
    InlineCode("/ctxscope")
  }
  .frame(width: 296)
  .padding()
  .environment(\.theme, Theme.preview)
}
