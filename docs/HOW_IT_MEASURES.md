# How ctxscope measures

ctxscope reads the transcripts Claude Code writes to `~/.claude/projects` and
nothing else. It never sees the request that was actually sent, so some
numbers are exact and some are estimates. This page says which is which.

## Exact, derived, estimated

| What | How good | Where it comes from |
|---|---|---|
| Tokens in context per request | exact | `input_tokens + cache_read_input_tokens + cache_creation_input_tokens` from the API's `usage` |
| Cache read, cache write, uncached, output | exact | the same `usage` block |
| Cost per request and session so far | exact, given the prices | those counts times the price table |
| What entered between two requests | derived | the difference between two exact totals, minus the previous output |
| Size of the prefix (system, tools, memory) | derived | the first request's total minus the first turn |
| Size of one block | estimated (`~`) | the estimator, normalized to the exact totals |
| Reused / unused | estimated | the lexical judge |
| Window size | lower bound | the smallest known window (200k or 1M) that fits the largest request seen, unless given with `--window` |

Anything estimated is shown with a leading `~`. Everything else carries no
mark.

## Block sizes always add up

A block's size is estimated from its text (characters per token, fitted per
content class and refitted per session). What the transcript records as a
measured group is used directly: the blocks of one response share that
response's `output_tokens`, and a thinking block is sized from
`thinking_tokens`, never from the summary the transcript stores.

Each block is sized once, when it enters the context, and the estimates are
scaled so that the blocks in the context add up to the API's exact total at
every request. So the composition can be off, but the total never is.
`ctxscope-cli validate <session>` prints the check and the estimator's error
before normalization.

## The prefix

The system prompt, the tool definitions and part of the memory are not in the
transcript as messages. ctxscope derives their total and splits it with the
best source the session has:

| Source | Available when | What it gives |
|---|---|---|
| `prompt_snapshot` | newer Claude Code versions record it at the start of a session | the real system prompt blocks and the full tool list, so every tool is its own block with its own definition |
| `/context` report | someone ran `/context` in the session | the harness's own count per category and per MCP tool |
| prior | always | fixed shares for system, tools, MCP and memory |

What none of them accounts for becomes one **Unattributed** block rather than
being spread over blocks that did not earn it. `ctxscope-cli analyze` prints
which source a lane used.

## What "used" means

A block counts as **used** by a request when later output or tool input from
the agent contains some of its text word for word (five-word runs, with
boilerplate that appears in many blocks ignored). It is a lower bound: an
agent can follow an instruction or learn from a file without repeating it.

- **Unused** means nothing of the block had been reused by that request.
- **Not tracked** means reuse cannot be observed: system prompt, memory
  files, images, unattributed tokens.
- A **tool definition** is judged by its call instead: called or never called.
  It stays out of the reused share, which is about words.
- Use only looks backwards: moving to an earlier request never shows a use
  that happened later.

## How costs are attributed

- **Per request**: exact. Cache reads at the read price, cache writes at the
  write price, uncached input at the input price, plus output.
- **Cache break extra**: the tokens that had to be written again, times the
  difference between the write and the read price.
- **Per block, so far**: each request's cost split over its blocks by size, at
  the write price where the block was written to the cache and the read price
  where it was read. It inherits the block's estimate, and the block costs of
  a request do not add up to its exact cost to the cent: unattributed tokens
  and the few uncached tokens at the end of a prompt are billed but belong to
  no block.
- **Carried and unused**: the unused blocks in context, their tokens, their
  share of the context and their cost so far.

## Cache breaks

A cache break is a request whose cache read fell below what the request it
continued from had cached. The size is exact. The cause is inferred, in this
order: a compaction, a model switch, a rewind or edited prompt, a changed
system prompt, tool definitions or memory file (the first prefix block in
reading order that entered or left at that request), a pause longer than the
cache lifetime in force (one hour when the last request that wrote to the
cache wrote one-hour entries, which a Claude subscription gives the main
conversation, else five minutes), otherwise unknown.

## Known limitations

- **Prices** are Anthropic's list prices per million tokens as published on
  2026-10-23, matched by model id prefix in `ScopeCore/Prices.swift`, with
  five-minute and one-hour cache writes billed at their own rates. A model the
  table does not know is billed as Claude Fable 5.1, the most expensive current
  model. Claude Haiku 5.5 is billed at its rate for prompts up to 100,000
  tokens, and the API charges five times that above. Per-block cents are an
  allocation of a request's bill by block size, not a separate charge.
- **Cache break causes are inferred** from the transcript. A memory file or a
  tool loaded mid-session can happen to enter at a request that broke for
  another reason, and is then named as the cause.
- **Block sizes are estimates.** Totals are exact; how they divide among
  blocks is not. Images are sized from their base64 length.
- **The prefix is an estimate** unless the session recorded a
  `prompt_snapshot`, and even then its tool sizes are estimated unless a
  `/context` report exists. A snapshot in a resumed session can arrive late.
- **Reuse is lexical.** It only sees verbatim reuse, so "unused" is an upper
  bound on what the agent ignored.
- **Some exits are inferred.** When the context shrinks with nothing in the
  transcript to explain it (a long idle gap, a model switch), ctxscope decides
  which blocks left and marks that decision as inferred.
- **The window is a lower bound.** A session that never grew past 200k reads
  as a 200k window even if it ran with 1M. One window applies to every lane of
  a session, including subagents on another model.
- **Tasks start at typed prompts.** Requests before the first typed prompt
  belong to no task, and a transcript whose user turns all come from
  background work has none.
- **Workflow lanes** under `subagents/workflows/` are not read.
- **A recent session's request count** is known only once it has been opened.
- **Tool server names** are shown as recorded (`github`, not GitHub).
- **Exact mode is not in this version.** A local pass-through that records
  exactly what was sent, so every block is counted and every cache break names
  its cause, is planned.
