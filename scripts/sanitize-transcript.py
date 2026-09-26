#!/usr/bin/env python3
"""Turn a real Claude Code transcript into a fixture.

Structure is kept exactly: entry order, parent links, request grouping, usage
numbers, attachment types, content block shapes, and the length in characters
of every piece of text. Text itself is replaced with filler.

The filler is a function of a hash of the original, so two identical pieces of
text stay identical and the duplication analyzer still has something to find,
while nothing of the original can be read back out of it.

Usage:
    scripts/sanitize-transcript.py INPUT OUTPUT [--tail N]

`--tail N` keeps only the last N entries, which is how a long session is cut
down to fixture size. Chains that run off the start are exactly what a
partially read transcript looks like, so the adapter has to cope anyway.

Identifiers are remapped, not kept: uuids, session, request, message and tool
use ids, thinking signatures and the connector id inside an MCP tool name all
become stable fakes of the same shape, so every relation between entries
survives and nothing points back at a real session or account. Timestamps are
shifted by a fixed offset, which keeps order and gaps.
"""

import argparse
import hashlib
import json
import sys

WORDS = (
    "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima "
    "mike november oscar papa quebec romeo sierra tango uniform victor whiskey "
    "xray yankee zulu"
).split()

# Fields that are structure, not content, and are copied through untouched.
KEEP = {
    "type", "subtype", "role", "isSidechain", "userType", "entrypoint", "version",
    "usage", "input_tokens", "output_tokens", "cache_creation_input_tokens",
    "cache_read_input_tokens", "cache_creation", "output_tokens_details",
    "ephemeral_1h_input_tokens", "ephemeral_5m_input_tokens", "thinking_tokens",
    "service_tier", "stop_reason", "is_error", "media_type", "isCompactSummary",
    "compactMetadata", "trigger", "preTokens", "postTokens",
    "cumulativeDroppedTokens", "durationMs", "apiBlockIndex", "isMeta", "level",
    "index", "size",
}

# `kind` is structure in exactly one place: it says whether a category of the
# `/context` report is in the context at all. Everywhere else it is a word
# somebody wrote, so it is filler like any other. Only the four values the
# report uses are copied through, and only there.
CONTEXT_KINDS = {"used", "deferred", "buffer", "free"}

# `origin.kind` says who put a user turn there. A background task's report is
# not a prompt the person typed, and the adapter tells the two apart by it, so
# the values it acts on are copied through. Any other value is filler.
ORIGIN_KINDS = {"human", "task-notification"}

# Identifiers: structure, but they name a real session, request or account, so
# each distinct value is remapped to a stable fake of the same shape. Relations
# between entries survive because the mapping is one to one.
IDENTIFIERS = {
    "uuid", "parentUuid", "logicalParentUuid", "sessionId", "requestId", "id",
    "tool_use_id", "agentId", "promptId", "leafUuid", "messageId",
    "snapshotMessageId", "sourceToolAssistantUUID", "sourceToolUseID", "toolUseID",
    "toolUseId", "headUuid", "anchorUuid", "tailUuid", "parentAgentId",
    "bridgeSessionId", "ownerAccountUuid", "ownerOrganizationUuid", "accountUuid",
    "backgroundTaskId", "taskId", "signature",
}

# Lists whose elements are identifiers rather than text.
IDENTIFIER_LISTS = {"uuids", "allUuids", "retractedMessageUuids"}

# Harness vocabulary rather than content: tool names and the like, which the
# adapter maps onto bands and which a fixture therefore has to keep. MCP tool
# names carry a connector id that belongs to one account, so those are rewritten
# while the shape that decides the band is kept.
VOCABULARY = {"name", "style", "agentType", "attachmentType", "toolName", "model"}

MCP_PREFIX = "mcp__"

# Anything that looks like a path gets a path-shaped replacement.
PATHS = {
    "cwd", "file_path", "filePath", "path", "displayPath", "notebook_path",
    "outputFile", "planFilePath", "worktreePath", "scratchpadDirectory",
    "trackingPath", "originalFile",
}


def filler(text):
    """Filler of exactly len(text) characters, stable for a given input."""
    if not text:
        return text
    seed = int(hashlib.blake2b(text.encode("utf-8"), digest_size=8).hexdigest(), 16)
    out = []
    length = 0
    target = len(text)
    while length < target:
        word = WORDS[seed % len(WORDS)]
        seed = (seed * 6364136223846793005 + 1442695040888963407) % (1 << 64)
        out.append(word)
        length += len(word) + 1
    joined = " ".join(out)[:target]
    # Keep the newline shape, so content classification lands the same way.
    joined = list(joined)
    for index, character in enumerate(text):
        if character == "\n" and index < len(joined):
            joined[index] = "\n"
    return "".join(joined)


def fake_identifier(value, counter={}, seen={}):
    """A stable fake of the same shape. A uuid stays a uuid, a hex id stays hex."""
    if value in seen:
        return seen[value]
    index = counter.get("n", 0) + 1
    counter["n"] = index
    digest = hashlib.blake2b(str(index).encode(), digest_size=16).hexdigest()
    if len(value) == 36 and value.count("-") == 4:
        fake = f"{digest[:8]}-{digest[8:12]}-{digest[12:16]}-{digest[16:20]}-{digest[20:32]}"
    elif value.startswith("req_") or value.startswith("msg_") or value.startswith("toolu_"):
        head = value.split("_", 1)[0]
        fake = head + "_" + digest[: max(8, len(value) - len(head) - 1)]
    else:
        fake = digest[: max(4, len(value))]
    seen[value] = fake
    return fake


def fake_tool_name(name):
    """Keeps the mcp__ shape and the verb, drops the connector id."""
    if not name.startswith(MCP_PREFIX):
        return name
    parts = name.split("__")
    if len(parts) < 3:
        return name
    parts[1] = fake_identifier(parts[1])[:12]
    return "__".join(parts)


def shift_timestamp(value):
    """Moves every timestamp by the same offset, so gaps and order survive."""
    if not value or not value[0].isdigit() or "T" not in value:
        return value
    try:
        year = int(value[:4])
    except ValueError:
        return value
    return str(year - 6) + value[4:]


def fake_path(path):
    parts = [p for p in path.split("/") if p]
    return "/" + "/".join(filler(p).replace(" ", "_") for p in parts)


def scrub(value, key=None, category=False):
    if isinstance(value, dict):
        if key == "origin" and value.get("kind") in ORIGIN_KINDS:
            return {k: (v if k == "kind" else scrub(v, k)) for k, v in value.items()}
        # A row of the report's category table, which is the one place `kind`
        # means what the reader of the report needs it to mean.
        row = category and "kind" in value and "tokens" in value
        # Keys can be paths too, as in a file history snapshot.
        return {
            (fake_path(k) if k.startswith("/") else k): scrub(
                v, k, category=(k == "categories") or (row and k == "kind")
            )
            for k, v in value.items()
        }
    if isinstance(value, list):
        if key in IDENTIFIER_LISTS:
            return [fake_identifier(v) if isinstance(v, str) else scrub(v) for v in value]
        return [
            scrub(v, key) if not isinstance(v, (dict, list)) else scrub(v, category=category)
            for v in value
        ]
    if isinstance(value, str):
        if category and key == "kind" and value in CONTEXT_KINDS:
            return value
        if key in IDENTIFIERS:
            return fake_identifier(value)
        if key == "timestamp":
            return shift_timestamp(value)
        if key in VOCABULARY:
            return fake_tool_name(value)
        if key in KEEP:
            return value
        if key in PATHS:
            return fake_path(value)
        # Everything else is content until proven otherwise.
        return filler(value)
    return value


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("output")
    parser.add_argument("--tail", type=int, default=0)
    args = parser.parse_args()

    lines = []
    with open(args.input, "r", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(entry, dict):
                lines.append(entry)

    if args.tail and len(lines) > args.tail:
        lines = lines[-args.tail:]

    with open(args.output, "w") as handle:
        for entry in lines:
            handle.write(json.dumps(scrub(entry), separators=(",", ":")) + "\n")

    print(f"{len(lines)} entries -> {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
