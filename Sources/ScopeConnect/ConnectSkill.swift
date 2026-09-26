package import Foundation

/// The user-level skill that makes `/ctxscope` work inside any Claude chat,
/// in the desktop app and in the terminal alike.
///
/// The format is the one in the skills reference: a directory under
/// `~/.claude/skills`, whose name is the command, holding a `SKILL.md` with
/// YAML front matter. A `` !`command` `` line runs before the text reaches
/// Claude, so opening the window costs no tool call and no turn.
///
/// `disable-model-invocation` keeps it to the person who types it. A window
/// that opens because a model thought it might help is a window nobody asked
/// for.
///
/// `allowed-tools` is not optional here. The skills reference says that
/// outside auto mode, an injected command whose permission check returns
/// anything but allow "aborts the invocation", an ask rule included, and that
/// pre-approving it with `allowed-tools` is what keeps it from doing that.
///
/// The rule is written `Bash(open *)`. The permissions reference says the
/// `:*` suffix is an equivalent way to write a trailing wildcard, so
/// `Bash(open:*)` would work too; the space form is the one the permission
/// dialog writes, which is what somebody comparing the two would see.
///
/// `${CLAUDE_SESSION_ID}` is substituted in the skill's markdown before the
/// shell sees it, so which chat the window opens on no longer depends on a
/// hook having fired first.
package enum ConnectSkill {
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
