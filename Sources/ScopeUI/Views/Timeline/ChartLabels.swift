internal import CoreGraphics

/// Where the prompt bands' numbers go. A pure function of the bands' spans
/// and the numbers' widths, so no number is ever drawn over another or cut
/// through a glyph, and that is tested without drawing.
///
/// A band shows its number inside it when the number fits with its inset.
/// The selected band always shows its number: inside when it fits, otherwise
/// on a chip of its own centered over the band, and a neighbour's number the
/// chip would cover is not shown.
enum PromptLabels {
  struct Span: Hashable {
    let x: CGFloat
    let width: CGFloat
  }

  enum Place: Hashable {
    case inside
    case hidden
    /// On a chip from `x`, `width` wide.
    case chip(x: CGFloat, width: CGFloat)
  }

  static func place(
    _ spans: [Span], labels: [CGFloat], selected: Int?, total: CGFloat, inset: CGFloat,
    chipInset: CGFloat
  ) -> [Place] {
    var places = zip(spans, labels).map { span, label in
      label + 2 * inset <= span.width ? Place.inside : .hidden
    }
    guard let selected, places.indices.contains(selected), places[selected] == .hidden else {
      return places
    }
    let span = spans[selected]
    let width = labels[selected] + 2 * chipInset
    let x = max(0, min(total - width, span.x + span.width / 2 - width / 2))
    places[selected] = .chip(x: x, width: width)
    for index in places.indices where index != selected && places[index] == .inside {
      let center = spans[index].x + spans[index].width / 2
      let left = center - labels[index] / 2
      if left < x + width && left + labels[index] > x { places[index] = .hidden }
    }
    return places
  }
}

/// Where the cache breaks' numbers go over the plot. Breaks whose badges
/// would touch share one, which names the first and the last of them, "3–4",
/// and stands where the first one's would. Each break keeps its own line.
enum BreakBadges {
  struct Group: Hashable {
    /// Positions in the list of breaks, first to last.
    let breaks: ClosedRange<Int>
    let x: CGFloat
    let width: CGFloat
    let label: String
  }

  /// `centers` and `numbers` are the breaks', in the order they happened.
  /// `width(of:)` measures a label; one break's badge is `badge` wide, and a
  /// shared one's label gets `inset` either side.
  static func group(
    centers: [CGFloat], numbers: [Int], badge: CGFloat, inset: CGFloat, gap: CGFloat,
    total: CGFloat, width: (String) -> CGFloat
  ) -> [Group] {
    func make(_ range: ClosedRange<Int>) -> Group {
      let first = numbers[range.lowerBound]
      let last = numbers[range.upperBound]
      let label = first == last ? "\(first)" : "\(first)\u{2013}\(last)"
      // One break's number fits its round badge; a shared one's label gets
      // a capsule as wide as it needs.
      let size = first == last ? badge : max(badge, width(label) + 2 * inset)
      let x = max(0, min(total - size, centers[range.lowerBound] - badge / 2))
      return Group(breaks: range, x: x, width: size, label: label)
    }
    var groups: [Group] = []
    for index in centers.indices {
      if let current = groups.last, centers[index] - badge / 2 < current.x + current.width + gap {
        groups[groups.count - 1] = make(current.breaks.lowerBound...index)
      } else {
        groups.append(make(index...index))
      }
      // Held inside the plot at its right end, a badge can move back onto
      // the one before it; then the two are one.
      while groups.count > 1, let last = groups.last,
        last.x < groups[groups.count - 2].x + groups[groups.count - 2].width + gap
      {
        let first = groups[groups.count - 2].breaks.lowerBound
        groups.removeLast(2)
        groups.append(make(first...last.breaks.upperBound))
      }
    }
    return groups
  }
}
