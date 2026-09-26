import Foundation

extension DemoTools {
  static let server = "github"

  static var github: [[String: Any]] {
    githubVerbs.map(githubTool)
  }

  private static func githubTool(
    _ verb: (name: String, about: String, properties: [Property], required: [String])
  ) -> [String: Any] {
    let name = "mcp__\(server)__\(verb.name)"
    let properties = repository + verb.properties
    return [
      "name": name, "server": server, "description": verb.about,
      "input_schema": schema(name, verb.about, properties, ["owner", "repo"] + verb.required)[
        "input_schema"] ?? [:],
      "defer_loading": true, "eager_input_streaming": true,
    ]
  }

  private static let repository: [Property] = [
    ("owner", "string", "Account or organization that owns the repository"),
    ("repo", "string", "Repository name"),
  ]

  private static let number: Property = ("pull_number", "number", "Pull request number")
  private static let issue: Property = ("issue_number", "number", "Issue number")
  private static let page: [Property] = [
    ("page", "number", "Page of results, from 1"),
    ("perPage", "number", "Results per page, at most 100"),
  ]

  private static let githubVerbs:
    [(name: String, about: String, properties: [Property], required: [String])] = [
      (
        "create_pull_request", "Create a new pull request in a GitHub repository.",
        [
          ("title", "string", "Title of the pull request"),
          ("body", "string", "Description, in Markdown"),
          ("head", "string", "Branch that holds the changes"),
          ("base", "string", "Branch to merge into"),
          ("draft", "boolean", "Open it as a draft"),
        ], ["title", "head", "base"]
      ),
      ("get_pull_request", "Get the details of one pull request.", [number], ["pull_number"]),
      (
        "list_pull_requests", "List pull requests, filtered by state and branch.",
        [
          ("state", "string", "open, closed or all"), ("head", "string", "Filter by head branch"),
          ("base", "string", "Filter by base branch"),
        ] + page, []
      ),
      (
        "update_pull_request", "Change the title, body, base or state of a pull request.",
        [
          number, ("title", "string", "New title"), ("body", "string", "New description"),
          ("state", "string", "open or closed"),
        ], ["pull_number"]
      ),
      (
        "merge_pull_request", "Merge a pull request.",
        [
          number, ("merge_method", "string", "merge, squash or rebase"),
          ("commit_title", "string", "Title of the merge commit"),
        ], ["pull_number"]
      ),
      (
        "get_pull_request_files", "List the files a pull request changes.", [number],
        ["pull_number"]
      ),
      (
        "get_pull_request_comments",
        "Get the review comments on a pull request, with the "
          + "file and line each one is attached to.", [number], ["pull_number"]
      ),
      ("get_pull_request_reviews", "Get the reviews of a pull request.", [number], ["pull_number"]),
      (
        "create_pull_request_review", "Submit a review: approve, request changes, or comment.",
        [
          number, ("body", "string", "Review text"),
          ("event", "string", "APPROVE, REQUEST_CHANGES or COMMENT"),
        ], ["pull_number", "event"]
      ),
      (
        "add_pull_request_review_comment", "Reply to a review comment on a pull request.",
        [
          number, ("comment_id", "number", "Comment to reply to"),
          ("body", "string", "Reply text"),
        ], ["pull_number", "body"]
      ),
      (
        "request_reviewers", "Ask people or teams to review a pull request.",
        [number, ("reviewers", "array", "User names")], ["pull_number"]
      ),
      (
        "get_pull_request_status", "Get the combined status of the checks on a pull request.",
        [number], ["pull_number"]
      ),
      (
        "create_issue", "Open a new issue.",
        [
          ("title", "string", "Issue title"), ("body", "string", "Issue text"),
          ("labels", "array", "Labels to add"), ("assignees", "array", "People to assign"),
        ], ["title"]
      ),
      ("get_issue", "Get one issue.", [issue], ["issue_number"]),
      (
        "list_issues", "List issues, filtered by state and labels.",
        [("state", "string", "open, closed or all"), ("labels", "array", "Labels")] + page, []
      ),
      (
        "update_issue", "Change an issue's title, body, state, labels or assignees.",
        [issue, ("title", "string", "New title"), ("state", "string", "open or closed")],
        ["issue_number"]
      ),
      (
        "add_issue_comment", "Comment on an issue or a pull request.",
        [issue, ("body", "string", "Comment text")], ["issue_number", "body"]
      ),
      (
        "search_issues", "Search issues and pull requests.",
        [("q", "string", "Search query")] + page, []
      ),
      (
        "search_code", "Search code across repositories.", [("q", "string", "Search query")] + page,
        []
      ),
      (
        "search_repositories", "Search repositories.", [("query", "string", "Search query")] + page,
        []
      ),
      (
        "get_file_contents", "Get a file or a folder listing from a repository.",
        [("path", "string", "Path in the repository"), ("ref", "string", "Branch, tag or commit")],
        ["path"]
      ),
      (
        "create_or_update_file", "Create or replace one file with a commit.",
        [
          ("path", "string", "Path in the repository"), ("content", "string", "New content"),
          ("message", "string", "Commit message"), ("branch", "string", "Branch to commit to"),
          ("sha", "string", "Blob of the file being replaced"),
        ], ["path", "content", "message", "branch"]
      ),
      (
        "push_files", "Commit several files at once.",
        [
          ("branch", "string", "Branch to push to"), ("files", "array", "Paths and contents"),
          ("message", "string", "Commit message"),
        ], ["branch", "files", "message"]
      ),
      (
        "create_branch", "Create a branch.",
        [("branch", "string", "New branch"), ("from_branch", "string", "Branch to start from")],
        ["branch"]
      ),
      (
        "list_commits", "List the commits of a branch.",
        [("sha", "string", "Branch or commit to start from")] + page, []
      ),
      ("list_branches", "List the branches of a repository.", page, []),
    ]
}
