# Claude Code transcript format

A reference for the JSONL transcripts Claude Code 2.1.x writes, as far as
ctxscope relies on them. Structure only: no transcript text appears here or
anywhere in the repository. The format is not documented by Anthropic and can
change between versions, so a reader must tolerate what it does not know.

## 1. Layout on disk

```
~/.claude/projects/<project-slug>/
    <session-uuid>.jsonl              the session transcript
    <session-uuid>/
        subagents/agent-<agentId>.jsonl        one per subagent run
        subagents/agent-<agentId>.meta.json    how it links to the parent
        subagents/workflows/<wf-id>/*.jsonl    workflow scripts, same shape
        tool-results/<id>.txt                  large out-of-band tool output
        custom-title.json
    memory/                           project memory files
```

`<project-slug>` is the working directory with `/` replaced by `-`.

## 2. Entry types

Every line is one JSON object with a `type`. The common ones:

| type | carries |
|---|---|
| assistant | `message` with `usage`, `requestId` |
| attachment | `attachment`, sometimes `rendered` |
| user | `message`, often `toolUseResult` |
| system | `subtype`, see below |
| queue-operation | queued prompts |
| last-prompt | `leafUuid`, `lastPrompt` |
| custom-title | `customTitle` |
| ai-title | `aiTitle` |
| agent-name | `agentName` |
| mode | permission mode changes |
| file-history-snapshot, file-history-delta | editor snapshots |
| bridge-session, frame-link, artifact-*, and others | side records |

Only `user`, `assistant`, `attachment` and `system` take part in the prompt.
A parser must skip unknown types without failing: the list grows.

`system` subtypes include `stop_hook_summary`, `api_error`, `local_command`,
`compact_boundary` and `model_refusal_fallback`.

## 3. The conversation is a tree, not a list

Entries carry `uuid` and `parentUuid`. The prompt of a request is the path
from that request's assistant entry up to the root, reversed. Rewinds and
edited prompts create branches, so file order is not prompt order and two
requests can have disjoint tails.

Attachments sit inside the chain (`user -> attachment -> ... -> assistant`),
so walking `parentUuid` picks them up.

**A parent walk alone is not enough.** Every `tool_use` block is written as its
own assistant entry, and a request can issue several at once. Each result's
`parentUuid` is its own `tool_use` entry, so the chain continues through the
last result and every sibling result hangs off it:

```
... -> toolUse A -> toolUse B -> result B -> next request
              \
               -> result A                  (off the parent chain)
```

A reader has to attach the result of every `tool_use` entry that is on the
chain, and let it leave when that entry leaves. In ctxscope this is
`ChainExpansion`, and `validate` checks that every tool call in the context
brought its result.

## 4. Requests and usage

`requestId` identifies one API call. The streamed content blocks of one call
are written as several assistant entries that share it, with identical
`message.id` and identical `message.usage`. **Usage must be counted once per
requestId, never once per entry.** `apiBlockIndex` is present on only some
entries, so it cannot be the grouping key. A few assistant entries (aborted
or synthetic) have no `requestId` and fall back to their own uuid.

`message.usage` fields:

```
input_tokens, cache_creation_input_tokens, cache_read_input_tokens,
output_tokens, service_tier, inference_geo,
cache_creation.{ephemeral_1h_input_tokens, ephemeral_5m_input_tokens}
output_tokens_details.thinking_tokens
server_tool_use.{web_search_requests, web_fetch_requests}
```

`cache_creation_input_tokens` equals `ephemeral_1h + ephemeral_5m`, and the
two are not both non-zero on one entry.

The request's prompt total, the measured value everything else is normalized
to:

```
promptTotal = input_tokens + cache_read_input_tokens + cache_creation_input_tokens
```

Entries the CLI wrote itself carry the model `<synthetic>`.

## 5. Content blocks

`message.content` is either a string or an array of blocks.

| entry | block types |
|---|---|
| assistant | `tool_use`, `thinking`, `text`, `fallback` |
| user | `tool_result`, plain string, `text`, `image`, `document` |

- `thinking` blocks carry `thinking` and `signature`. The stored `thinking`
  text is a summary, not the full reasoning: it is far too short for the
  `thinking_tokens` it was billed at. The `signature` carries the real
  reasoning and is what gets billed when the block is sent back. A thinking
  block must be sized from `thinking_tokens`, never from its own text.
- `tool_result.content` is a string or a list of blocks, and may nest `text`,
  `image` and `tool_reference` blocks.
- Images are inline base64 in `source.data` (JPEG, PNG, WebP).
- Tool results are complete in the block (slightly longer than the structured
  `toolUseResult.file.content`, because of line numbers).
  `tool-results/*.txt` holds background task output, which is not part of the
  prompt.

## 6. Attachments

Attachments are the harness's injected context: reminders, memory, skill and
tool listings, environment. There are a few dozen types.

### 6.1 `rendered` is one block with a `content` key

Some attachments carry `rendered`, which is the text the harness injected:

```json
"rendered": [{"content": "<the injected text>"}]
```

No `type` and no `text` key. Almost always one object, occasionally more, so a
reader has to join what it finds. `environment`, `instructions`,
`session_context`, `model`, `date` and `output_style_instructions` carry a
rendering and little else a reader can size.

An attachment without a rendering has to be read from its own fields:

| type | fields | readable without `rendered` |
|---|---|---|
| prompt_snapshot | `systemPrompt`, `tools`, `cliPrefix` | yes, see 6.2 |
| environment | `snapshot` (object), `changes` | no |
| instructions | `files[]` of `{path, content, type}` | the file contents |
| session_context | `context` (object) | no |
| output_style_instructions | `style` `{name, prompt}` | the prompt |
| nested_memory | `content` `{path, content, type}` | the inner content |
| skill_listing | `content` (string), `names[]`, `skillCount` | yes, `content` |
| mcp_instructions_delta | `addedNames[]`, `addedBlocks[]` | the blocks |
| deferred_tools_delta | `addedNames[]`, `addedLines[]`, and the server lists | the lines |
| deferred_tools_record | `entries[]` of full tool records | the records |
| agent_listing_delta | `addedTypes[]`, `addedLines[]` | the lines |
| model | `identity`, `text` | yes, `text` |
| date | `date` | yes |

### 6.2 `prompt_snapshot`, the only recorded prefix

Written from Claude Code 2.1.260 on, but not in every session of those
versions, so a reader has to work with and without it.

It appears twice per session, on the parent chain, at the front:

| | position | carries |
|---|---|---|
| first | last attachment before the first request's response | `systemPrompt` |
| second | before the second request's response | `systemPrompt`, `tools`, `cliPrefix` |

A session resumed under a newer CLI can have its first snapshot much later,
and can have a third. The snapshots inside one session are byte identical,
even across a version change, so they look replayed from session state: an
identical snapshot after a resume is not proof that the prompt stayed the
same. ctxscope applies the first snapshot of a lane to the first request and
reports it as the lane's prefix source.

- `systemPrompt` is a list of strings, one per system block (13 to 16 of
  them). Each becomes one block.
- `tools` is the full tool list of the request, entries of
  `{name, description, schema}`, plus `server` on the MCP ones from 2.1.266
  on. Each tool's `schema` is the record the API was given (`name`,
  `description`, `input_schema`, `eager_input_streaming`), so the description
  appears twice; ctxscope measures and shows the schema alone. `server` is the
  connector id the name already carries (`mcp__<server>__<verb>`), with
  punctuation replaced by underscores. Deferred tools are not in the list,
  which is what makes it usable as the list of tool blocks.
- `cliPrefix` is a short fixed string on the second snapshot only.

### 6.3 What records tool names

Three deltas name tools without their schemas, all written into the user turn
rather than the prefix:

- `deferred_tools_delta.addedNames` and `.addedLines`, one line per tool.
- `mcp_instructions_delta.addedNames` and `.addedBlocks`, one block of server
  instructions per connected MCP server.
- `agent_listing_delta.addedTypes` and `.addedLines`, one line per subagent
  type.

`deferred_tools_record` is the exception: its `entries` carry the full
definition (`defer_loading`, `description`, `input_schema`,
`eager_input_streaming`) of every tool a tool search loaded. These are
appended content in the turn that loaded them, not a change to the prefix, so
they do not break the cache.

## 7. Subagents

A subagent run is `<session>/subagents/agent-<agentId>.jsonl`. Entries have
the same shape as the parent's, plus `agentId` and `isSidechain: true`.
Top-level files contain no sidechain entries.

`agent-<agentId>.meta.json` links the lane to its parent:

```
agentType, description, toolUseId, spawnDepth,
model?, worktreePath?, worktreeBranch?, parentAgentId?, stoppedByUser?
```

`toolUseId` matches the `tool_use` block in the parent that spawned it, and
the parent's `toolUseResult` for that call carries `agentId`, `usage`,
`totalTokens` and `toolStats`. Either direction resolves the link.

## 8. Compaction

A compaction writes a `system` entry with `subtype: "compact_boundary"` and
`compactMetadata`:

```
trigger, preTokens, postTokens, cumulativeDroppedTokens, durationMs,
preCompactDiscoveredTools[], preservedSegment{headUuid, anchorUuid, tailUuid},
preservedMessages{anchorUuid, uuids[], allUuids[]}
```

`logicalParentUuid` on the entry points at the pre-compaction tail. The
summary itself is a `user` entry with `isCompactSummary: true` and
`isVisibleInTranscriptOnly: true`. So what a compaction dropped and kept is
recorded, not inferred. `message.context_management` exists but has been seen
empty (`applied_edits: []`).

## 9. What follows for measurement

1. The prefix (system prompt, tool schemas, MCP schemas, memory not injected
   as an attachment) is not in the transcript as messages. It is derived as
   `promptTotal(first request) - estimated size of the first turn`, and split
   by the best record the lane has (section 6.2, section 12, or a fixed
   prior).
2. Assistant content is measured, not estimated: re-sending a response costs
   about that response's `output_tokens`. For small user turns,
   `promptTotal(t) - promptTotal(t-1) - output_tokens(t-1)` is a few dozen
   tokens, and measured output accounts for a large share of all context
   growth.
3. Everything else is estimated from characters per token per content class,
   fitted against derived deltas, with a fixed cost per block and a framing
   term per request. The shipped prior (`EstimatorRates.prior`):

   | class | characters per token |
   |---|---|
   | prose | 2.84 |
   | code | 3.05 |
   | json | 2.63 |
   | image (base64 characters) | 220 |

   plus 8 tokens per block and about 141 tokens of framing per request.

   These rates are lower than a tokenizer would give for the same text,
   because they also absorb what the transcript cannot see: the
   `<system-reminder>` blocks and tool result framing the harness injects.
   The estimator predicts token deltas; it is not a tokenizer. It is refitted
   per lane, and `ctxscope-cli calibrate` refits the prior from local
   sessions.
4. Sizes are assigned once, when a block enters the context, so that every
   request total is exact by construction (see `Normalizer` and
   [ARCHITECTURE.md](ARCHITECTURE.md)).

## 10. The context can shrink with nothing to explain it

At some requests the measured total is smaller than the previous one by more
than anything that left the parent chain accounts for. The cases observed are
a long idle gap with a cold cache, a model switch, and a compaction. Thinking
is not stripped at every user turn.

Nothing in the transcript records the drop, only its effect on the next
`usage`. A reader has to decide which blocks left and say that it decided.
`LaneBuilder.retire` tests "all the thinking that was live is gone" against
the room that frees, falls back to the oldest content first, grades every such
exit `inferred`, and emits a lane event.

Model switches mid-lane are recorded as events: the prefix and the cache both
change with the model.

## 11. Some responses report an impossible output total

In subagent transcripts a response is sometimes written with an
`output_tokens` no reading of its content supports, such as one token for a
response carrying text and a tool call. Believing it would pin the real blocks
at one token and zero. So a group total is only taken as measured when it
could be right: at least one token per block, and at least a quarter of what
the estimator says the same content costs. Otherwise the estimator is used,
and `validate` reports how many totals were refused.

This is not the partial total an early entry of a streamed response can
carry; that case is solved by taking the largest total across the group.

## 12. The harness's own context report

When someone runs `/context`, Claude Code writes a `system` entry with
`subtype: "local_command"`:

```
content       the markdown report, as the transcript view shows it
contextUsage  the same numbers, structured
commandRun    {command, args}
```

`contextUsage` is what ctxscope reads (the markdown is rounded):

```
model, total_tokens, raw_max_tokens, percentage,
categories[]   {name, tokens, kind}
mcp_tools[]    {name, server_name, tokens}
memory_files[] {path, type, tokens}
skills[]       {name, source, tokens}
agents[]
```

`kind` decides what is in the context:

| kind | categories | meaning |
|---|---|---|
| used | System prompt, System tools, MCP tools, Memory files, Skills, Messages | sums to `total_tokens` exactly |
| deferred | MCP tools (deferred), System tools (deferred) | not in the context |
| buffer | Autocompact buffer | room kept free for a compaction |
| free | Free space | the rest of the window |

`used`, `buffer` and `free` add up to `raw_max_tokens`. Deferred categories
are schemas of tools that load on demand and must not be counted.

`mcp_tools` lists loaded and deferred tools together with no flag. The loaded
ones are the rows whose name is in `prompt_snapshot.tools` (equivalently, the
rows no `deferred_tools_delta.addedNames` names). ctxscope uses the snapshot;
without one, MCP stays one block. `System tools` has no per-tool rows, so the
built-in tools share that category by the length of their schemas.

Memory files, skills and messages are not taken from the report, because the
transcript already records them with their own text (`instructions`,
`nested_memory`, `skill_listing`); taking both would count them twice.

A report is rare, since it exists only where someone typed the command. It is
not a number the API reported, so it is graded estimated, but it is far
better than a fixed prior.
