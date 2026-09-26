import Foundation

extension DemoStory {
  static func with(_ fields: [String: Any]) -> [String: Any] {
    fields.merging(["owner": "example", "repo": "api-client"]) { old, _ in old }
  }

  static func github(_ p: DemoProject) -> [DemoTurn] {
    let connected = DemoInput.rendered(
      "mcp_instructions_delta",
      "The github server is connected. Its tools act on repositories the person's token can "
        + "reach. Prefer them over the gh command line for pull requests and reviews.",
      fields: ["addedNames": ["github"]])
    let commit =
      "git add -A && git commit -m \"retries: one policy object, full jitter, elapsed cap\""
    return [
      opening(
        8,
        [
          p.bash(
            "git status --short --branch", "git status", "## retry-policy\n" + DemoGitHub.changed)
        ],
        extra: [connected, .loadedTools(DemoTools.github)],
        thinking: "Commit, push, then open the pull request through the GitHub tools.",
        tokens: 200, cache: .prefix),
      step([p.bash(commit, "git commit", DemoGitHub.commitOutput)]),
      step([p.bash("git push -u origin retry-policy", "git push", DemoGitHub.pushOutput)]),
      step([
        p.mcp("list_pull_requests", with(["head": "example:retry-policy", "state": "open"]), "[]")
      ]),
      step([p.bash("git log --oneline main..retry-policy", "git log", DemoGitHub.log)]),
      step(
        [
          p.mcp(
            "create_pull_request",
            with([
              "title": "Retries: one policy object, full jitter, elapsed cap",
              "head": "retry-policy",
              "base": "main", "body": DemoGitHub.body,
            ]), DemoGitHub.created)
        ], thinking: "Describe what changed, why, and how it was tested.", tokens: 260),
      step([
        p.mcp(
          "request_reviewers", with(["pull_number": 214, "reviewers": ["mara-k"]]),
          DemoGitHub.reviewers)
      ]),
      step([
        p.mcp("get_pull_request_status", with(["pull_number": 214]), DemoGitHub.status("pending"))
      ]),
      step(
        [
          p.mcp("get_pull_request_status", with(["pull_number": 214]), DemoGitHub.status("success"))
        ], gap: 95),
      step([p.mcp("get_pull_request", with(["pull_number": 214]), DemoGitHub.created)]),
      step([
        p.todo([
          ("Commit and push", "completed"), ("Open the pull request", "completed"),
          ("Wait for checks", "completed"),
        ])
      ]),
      reply(
        """
        Opened #214, "Retries: one policy object, full jitter, elapsed cap", from `retry-policy` \
        into `main`, and asked mara-k for a review. CI passed: typecheck, lint and the 215 \
        tests. The description lists the three changes and how each is tested.
        """),
    ]
  }

  static func review(_ p: DemoProject) -> [DemoTurn] {
    let replies = DemoGitHub.comments.map { comment in
      p.mcp(
        "add_pull_request_review_comment",
        with(["pull_number": 214, "comment_id": comment.id, "body": comment.reply]),
        "{\"id\": \(comment.id + 40), \"in_reply_to_id\": \(comment.id)}")
    }
    return [
      opening(
        9,
        [p.mcp("get_pull_request_comments", with(["pull_number": 214]), DemoGitHub.commentsJSON)],
        thinking: "Fetch the review first.", tokens: 120),
      step(
        [p.bash("git diff main...retry-policy", "git diff", DemoGitHub.diff)],
        thinking: "Three comments: a name, a missing validation, and a doc link. Read the diff "
          + "they refer to before changing anything.", tokens: 470),
      step([p.edit("src/api/retry.ts", "  let slept = 0;", "  let waited = 0;")]),
      step([p.edit("src/api/retry.ts", "        slept += clamped;", "        waited += clamped;")]),
      step([
        p.edit(
          "src/api/policy.ts", "  return Object.freeze(policy);",
          "  if (policy.jitter !== 'none' && policy.jitter !== 'full') {\n"
            + "    throw new RangeError(`unknown jitter: ${policy.jitter}`);\n  }\n"
            + "  return Object.freeze(policy);")
      ]),
      step([
        p.edit(
          "docs/retries.md", "## Elapsed time",
          "## Elapsed time\n\nSee `tests/test_elapsed.ts` for the cases the cap covers.")
      ]),
      step([p.bash("npm test", "npm test", DemoOutput.npmTest(logs: 12, seconds: "4.655"))]),
      step([p.bash("git commit -am \"retries: review fixes\"", "git commit", DemoGitHub.fixOutput)]
      ),
      step([
        p.bash(
          "git push", "git push",
          "To github.com:example/api-client.git\n   5d02c7e..b81f4a9  retry-policy -> retry-policy\n"
        )
      ]),
      step(replies, thinking: "Answer each comment where it was made.", tokens: 150),
      step(
        [
          p.mcp("get_pull_request_status", with(["pull_number": 214]), DemoGitHub.status("success"))
        ], gap: 80),
      reply(
        """
        Addressed all three comments on #214 and replied to each: `slept` is now `waited`, \
        `makePolicy` rejects an unknown jitter mode, and docs/retries.md points at the \
        elapsed-time tests. Pushed as b81f4a9; checks are green again.
        """),
    ]
  }
}
