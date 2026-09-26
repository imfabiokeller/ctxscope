package import Foundation

package enum JSONEdit {
  package static func append(
    to array: JSONSpan, in data: Data, layout: Layout, render: (String) -> String
  ) -> TextSplice {
    let elements = array.elements ?? []
    guard let last = elements.last else {
      let indent = SourceText.lineIndent(at: array.range.lowerBound, in: data) + layout.unit
      return .insert(at: array.range.lowerBound + 1, layout.breakLine + indent + render(indent))
    }
    let indent = SourceText.lineIndent(at: last.range.lowerBound, in: data)
    return .insert(at: last.range.upperBound, "," + layout.breakLine + indent + render(indent))
  }

  package static func add(
    member name: String, to object: JSONSpan, in data: Data, layout: Layout,
    render: (String) -> String
  ) -> TextSplice {
    let members = object.members ?? []
    let key = "\"\(name)\": "
    guard let last = members.last else {
      let indent = SourceText.lineIndent(at: object.range.lowerBound, in: data) + layout.unit
      return .insert(
        at: object.range.lowerBound + 1, layout.breakLine + indent + key + render(indent))
    }
    let indent = SourceText.lineIndent(at: last.range.lowerBound, in: data)
    return .insert(
      at: last.range.upperBound, "," + layout.breakLine + indent + key + render(indent))
  }

  package static func removal(ofElement slot: Int, from array: JSONSpan) -> Range<Int>? {
    guard let elements = array.elements, elements.indices.contains(slot) else { return nil }
    return span(slot: slot, siblings: elements.map(\.range), container: array)
  }

  package static func removal(ofMember slot: Int, from object: JSONSpan) -> Range<Int>? {
    guard let members = object.members, members.indices.contains(slot) else { return nil }
    return span(slot: slot, siblings: members.map(\.range), container: object)
  }

  private static func span(slot: Int, siblings: [Range<Int>], container: JSONSpan) -> Range<Int> {
    let range = siblings[slot]
    if slot > 0 { return siblings[slot - 1].upperBound..<range.upperBound }
    // The first entry owns the whitespace after the bracket unless something
    // follows, so removal exactly inverts append and undo restores the bytes.
    if siblings.count > slot + 1 { return range.lowerBound..<siblings[slot + 1].lowerBound }
    return (container.range.lowerBound + 1)..<range.upperBound
  }
}
