package import Foundation

/// Adding one piece to a parsed document and taking it out again.
///
/// The two are exact inverses, which is the whole point: what `append` writes
/// is one contiguous span, and `removal` names that same span. Disconnecting a
/// settings file nothing else has touched therefore gives the original bytes
/// back rather than a file that merely parses the same.
///
/// What goes in is rendered by a closure rather than handed over as text,
/// because the indentation it has to be written at is only known here, from
/// the lines it is going between.
package enum JSONEdit {
  /// Appends an element to an array, indented like whatever is already in it.
  package static func append(
    to array: JSONSpan, in data: Data, layout: Layout, render: (String) -> String
  ) -> TextSplice {
    let elements = array.elements ?? []
    guard let last = elements.last else {
      // An empty array: the element goes in right after the bracket, so taking
      // it out again leaves whatever was between the brackets before.
      let indent = SourceText.lineIndent(at: array.range.lowerBound, in: data) + layout.unit
      return .insert(at: array.range.lowerBound + 1, layout.breakLine + indent + render(indent))
    }
    let indent = SourceText.lineIndent(at: last.range.lowerBound, in: data)
    return .insert(at: last.range.upperBound, "," + layout.breakLine + indent + render(indent))
  }

  /// Adds a member to an object, the same way.
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

  /// The span one element of an array occupies, together with the separator
  /// that was written with it.
  package static func removal(ofElement slot: Int, from array: JSONSpan) -> Range<Int>? {
    guard let elements = array.elements, elements.indices.contains(slot) else { return nil }
    return span(slot: slot, siblings: elements.map(\.range), container: array)
  }

  /// The same for a member of an object.
  package static func removal(ofMember slot: Int, from object: JSONSpan) -> Range<Int>? {
    guard let members = object.members, members.indices.contains(slot) else { return nil }
    return span(slot: slot, siblings: members.map(\.range), container: object)
  }

  private static func span(slot: Int, siblings: [Range<Int>], container: JSONSpan) -> Range<Int> {
    let range = siblings[slot]
    if slot > 0 { return siblings[slot - 1].upperBound..<range.upperBound }
    // The first one is the one ctxscope wrote into an empty container, so it
    // owns the whitespace after the opening bracket and takes it with it.
    // When something follows, that whitespace belongs to what follows now:
    // taking it too would leave the next entry hard against the bracket.
    if siblings.count > slot + 1 { return range.lowerBound..<siblings[slot + 1].lowerBound }
    return (container.range.lowerBound + 1)..<range.upperBound
  }
}
