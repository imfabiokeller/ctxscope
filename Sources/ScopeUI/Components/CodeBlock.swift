public import SwiftUI

public struct CodeBlock: View {
  public enum Height: Sendable {
    case capped
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
      // A scroll view renders as an empty box offscreen.
      if height == .filling, !isRendering {
        ScrollView { lines.frame(maxWidth: .infinity, alignment: .leading) }
      } else {
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
      // Line spacing adds nothing above the first line or below the last.
      .padding(.vertical, theme.type.codeLineSpacing / 2)
  }
}

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
      // SF Mono at 13 points has SF Pro's line height.
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
