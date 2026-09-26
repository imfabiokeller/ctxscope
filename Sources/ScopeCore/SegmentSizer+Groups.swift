/// How the sizer treats the measured groups it was given: taking tokens back
/// off them when they overshoot, and saying how well each resulting size is
/// known.
extension SegmentSizer {
  /// Takes `amount` tokens off the measured groups, largest first, so the
  /// request total stays exact when the groups overshoot. Returns what it
  /// could not take.
  @discardableResult
  func shrinkGroups(_ tokens: inout [Int], grouped: [Int: [Int]], by amount: Int) -> Int {
    var left = amount
    let indices = grouped.values.flatMap { $0 }.sorted { tokens[$0] > tokens[$1] }
    for index in indices where left > 0 {
      let take = min(left, max(0, tokens[index] - 1))
      tokens[index] -= take
      left -= take
    }
    return left
  }

  func graded(
    _ tokens: [Int],
    request: SizingRequest,
    grouped: [Int: [Int]]
  ) -> [Tokens] {
    var groupSize: [Int: Int] = [:]
    for (group, indices) in grouped { groupSize[group] = indices.count }
    return tokens.enumerated().map { index, value in
      guard let group = request.entering[index].group, let size = groupSize[group],
        let total = request.groupTotals[group]
      else {
        return Tokens(value, .estimated)
      }
      // Measured means the number came from the API. A group of one whose
      // size still equals its measured total is exactly that. A split inside
      // a group, or a member the sizer had to shrink because the group
      // overshot the delta, is not: it is arithmetic on a measured whole.
      return Tokens(value, size == 1 && value == total ? .measured : .derived)
    }
  }

}
