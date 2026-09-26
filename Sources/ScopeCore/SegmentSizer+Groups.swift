extension SegmentSizer {
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
      return Tokens(value, size == 1 && value == total ? .measured : .derived)
    }
  }

}
