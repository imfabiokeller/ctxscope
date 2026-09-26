#!/usr/bin/env python3
# Turns a real transcript into a fixture: structure and text lengths kept, text and ids replaced.
# Usage: scripts/sanitize-transcript.py INPUT OUTPUT [--tail N]

import argparse
import hashlib
import json
import sys

WORDS = (
    "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima "
    "mike november oscar papa quebec romeo sierra tango uniform victor whiskey "
    "xray yankee zulu"
).split()

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

# `kind` is structure only in a `/context` category row; everywhere else it is filler.
CONTEXT_KINDS = {"used", "deferred", "buffer", "free"}

# The adapter reads these `origin.kind` values; any other value is filler.
ORIGIN_KINDS = {"human", "task-notification"}

# These name a real session or account, so each is remapped one to one to a fake.
IDENTIFIERS = {
    "uuid", "parentUuid", "logicalParentUuid", "sessionId", "requestId", "id",
    "tool_use_id", "agentId", "promptId", "leafUuid", "messageId",
    "snapshotMessageId", "sourceToolAssistantUUID", "sourceToolUseID", "toolUseID",
    "toolUseId", "headUuid", "anchorUuid", "tailUuid", "parentAgentId",
    "bridgeSessionId", "ownerAccountUuid", "ownerOrganizationUuid", "accountUuid",
    "backgroundTaskId", "taskId", "signature",
}

IDENTIFIER_LISTS = {"uuids", "allUuids", "retractedMessageUuids"}

# Kept because the adapter maps them onto bands; an MCP connector id is still rewritten.
VOCABULARY = {"name", "style", "agentType", "attachmentType", "toolName", "model"}

MCP_PREFIX = "mcp__"

PATHS = {
    "cwd", "file_path", "filePath", "path", "displayPath", "notebook_path",
    "outputFile", "planFilePath", "worktreePath", "scratchpadDirectory",
    "trackingPath", "originalFile",
}


def filler(text):
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
    # The mutable defaults are deliberate: they memoize the mapping for the whole run.
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
    if not name.startswith(MCP_PREFIX):
        return name
    parts = name.split("__")
    if len(parts) < 3:
        return name
    parts[1] = fake_identifier(parts[1])[:12]
    return "__".join(parts)


def shift_timestamp(value):
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
        row = category and "kind" in value and "tokens" in value
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
        # Unknown fields are treated as content, so nothing real leaks through.
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
