public import SwiftUI

/// A segmented picker in two sizes: the window's view picker and a filter
/// above a table.
///
/// Drawn rather than wrapped: AppKit's segmented control cannot take the
/// theme's track, thumb and type, and it renders as an empty box offscreen.
/// Each item is a native button, so keyboard focus works item by item, and
/// the whole is presented to accessibility as a segmented `Picker`.
public struct SegmentedPicker<Value: Hashable>: View {
  public enum Size: Sendable {
    /// The window's view picker: 24 point items, 13 point titles, the
    /// selected one in medium weight.
    case toolbar
    /// A filter above a table: 22 point items, 12 point titles.
    case filter
  }

  private let label: String
  @Binding private var selection: Value
  private let options: [Value]
  private let size: Size
  private let title: (Value) -> String
  @Environment(\.theme) private var theme

  public init(
    _ label: String, selection: Binding<Value>, options: [Value], size: Size = .toolbar,
    title: @escaping (Value) -> String
  ) {
    self.label = label
    _selection = selection
    self.options = options
    self.size = size
    self.title = title
  }

  public var body: some View {
    let segmented = theme.metrics.segmented
    HStack(spacing: 0) {
      ForEach(options, id: \.self) { option in
        item(option, selected: option == selection, metrics: segmented)
      }
    }
    .padding(segmented.trackPadding)
    .background(
      RoundedRectangle(cornerRadius: segmented.trackRadius).fill(theme.control.track.color)
    )
    .fixedSize()
    .accessibilityRepresentation {
      Picker(label, selection: $selection) {
        ForEach(options, id: \.self) { option in
          Text(title(option)).tag(option)
        }
      }
      .pickerStyle(.segmented)
    }
  }

  private func item(_ option: Value, selected: Bool, metrics: Metrics.Segmented) -> some View {
    let shadow = theme.shadow.thumb
    return Button {
      selection = option
    } label: {
      Text(title(option))
        .font(font(selected: selected))
        .foregroundStyle(theme.text.primary.color)
        .padding(.horizontal, size == .toolbar ? metrics.toolbarPadding : metrics.filterPadding)
        .frame(height: size == .toolbar ? metrics.toolbarHeight : metrics.filterHeight)
        .background {
          if selected {
            RoundedRectangle(cornerRadius: metrics.thumbRadius)
              .fill(theme.control.thumb.color)
              .shadow(
                color: shadow.color.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func font(selected: Bool) -> Font {
    switch size {
    case .toolbar: selected ? theme.type.bodyMedium : theme.type.body
    case .filter: theme.type.caption
    }
  }
}

#Preview {
  @Previewable @State var page = "Context"
  @Previewable @State var filter = "All"
  VStack(spacing: 16) {
    SegmentedPicker("View", selection: $page, options: ["Context", "Timeline"]) { $0 }
    SegmentedPicker(
      "Show", selection: $filter, options: ["All", "Unused", "Sent every request"], size: .filter
    ) { $0 }
  }
  .padding()
  .environment(\.theme, Theme.preview)
}
