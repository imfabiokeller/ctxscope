package import Foundation

package enum ConnectSkill {
  // `allowed-tools` is required: outside auto mode, an injected command that
  // is not pre-approved aborts the skill.
  package static let text = """
    ---
    name: ctxscope
    description: Opens the ctxscope window on this session.
    allowed-tools: Bash(open *)
    disable-model-invocation: true
    ---

    !`open "\(ScopeURL.show(session: ScopeURL.sessionPlaceholder))"`

    The ctxscope window is open on this session. Say so in one line.

    """

  package static var data: Data { Data(text.utf8) }
}
