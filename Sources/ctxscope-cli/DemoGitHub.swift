import Foundation

enum DemoGitHub {
  static let changed = """
     M CHANGELOG.md
     M CLAUDE.md
     M src/api/client.ts
     M src/api/index.ts
     M src/api/retry.ts
     M tests/helpers/clock.ts
     M tests/test_backoff.ts
    ?? src/api/policy.ts
    ?? tests/test_elapsed.ts

    """

  static let commitOutput = """
    [retry-policy 5d02c7e] retries: one policy object, full jitter, elapsed cap
     9 files changed, 214 insertions(+), 19 deletions(-)
     create mode 100644 src/api/policy.ts
     create mode 100644 tests/test_elapsed.ts

    """

  static let pushOutput = """
    remote:
    remote: Create a pull request for 'retry-policy' on GitHub by visiting:
    remote:      https://github.com/example/api-client/pull/new/retry-policy
    remote:
    To github.com:example/api-client.git
     * [new branch]      retry-policy -> retry-policy
    branch 'retry-policy' set up to track 'origin/retry-policy'.

    """

  static let log = "5d02c7e retries: one policy object, full jitter, elapsed cap\n"

  static let body = """
    ## What

    - `src/api/policy.ts`: `makePolicy` and `policyFor` build every retry policy, from the \
    defaults, the route override and the caller's options.
    - `computeDelay` draws full jitter when `jitter: 'full'`.
    - `withRetry` enforces `maxElapsedMs`, waits included, and clamps the last wait.

    ## Why

    Retry settings came from three places and only one of them was read. Retries also all \
    fired at the same moments after an outage.

    ## Tests

    - `tests/test_elapsed.ts`: six cases for the cap.
    - `tests/test_backoff.ts`: `caps elapsed time` pins `Math.random`; it was flaky.
    - `npm test`: 215 passed.
    """

  static let created = """
    {"number": 214, "state": "open", "title": "Retries: one policy object, full jitter, \
    elapsed cap", "html_url": "https://github.com/example/api-client/pull/214", "head": \
    {"ref": "retry-policy", "sha": "5d02c7e"}, "base": {"ref": "main"}, "draft": false, \
    "mergeable": true, "additions": 214, "deletions": 19, "changed_files": 9}
    """

  static let reviewers = """
    {"number": 214, "requested_reviewers": [{"login": "mara-k"}]}
    """

  static func status(_ state: String) -> String {
    let checks = ["typecheck", "lint", "test (node 22)", "test (node 20)"]
    let rows = checks.map { "{\"context\": \"\($0)\", \"state\": \"\(state)\"}" }
    return "{\"state\": \"\(state)\", \"total_count\": 4, \"statuses\": ["
      + rows.joined(separator: ", ") + "]}"
  }

  static let comments: [(id: Int, path: String, line: Int, body: String, reply: String)] = [
    (
      9101, "src/api/retry.ts", 131,
      "`slept` reads like a boolean. `waited`?", "Renamed to `waited`."
    ),
    (
      9102, "src/api/policy.ts", 18,
      "makePolicy validates the numbers but not `jitter`. A typo in config would silently "
        + "mean no jitter.",
      "Good catch: makePolicy now throws on an unknown jitter mode."
    ),
    (
      9103, "docs/retries.md", 40,
      "Link the new tests from the elapsed time section?", "Done, it points at test_elapsed.ts."
    ),
  ]

  static let commentsJSON: String =
    "["
    + comments.map {
      "{\"id\": \($0.id), \"user\": {\"login\": \"mara-k\"}, \"path\": \"\($0.path)\", "
        + "\"line\": \($0.line), \"body\": \"\($0.body)\"}"
    }.joined(separator: ", ") + "]"

  static let fixOutput = """
    [retry-policy b81f4a9] retries: review fixes
     3 files changed, 8 insertions(+), 3 deletions(-)

    """

  static let diff: String =
    DemoOutput.added("src/api/policy.ts", DemoSources.policy)
    + DemoOutput.added("tests/test_elapsed.ts", DemoSources.testElapsed)
      + """
      diff --git a/src/api/retry.ts b/src/api/retry.ts
      index 7c41e0b..e93d5a2 100644
      --- a/src/api/retry.ts
      +++ b/src/api/retry.ts
      @@ -86,8 +86,11 @@ export function computeDelay(policy: RetryPolicy, attempt: number): number {
         const backoff = Math.min(policy.maxDelayMs, policy.baseDelayMs * 2 ** attempt);
      -  const delay = backoff;
      +  const delay = policy.jitter === 'full'
      +    ? Math.random() * backoff
      +    : backoff;
         return delay;
       }
      @@ -107,6 +110,8 @@ export async function withRetry(
       ): Promise<TransportResponse> {
      +  const started = Date.now();
      +  let slept = 0;
         for (let attempt = 0; ; attempt++) {
      @@ -128,7 +133,16 @@ export async function withRetry(
      -        await sleep(wait);
      +        const spent = Date.now() - started + slept;
      +        if (policy.maxElapsedMs !== undefined && spent >= policy.maxElapsedMs) {
      +          return outcome instanceof TransportError ? Promise.reject(outcome) : outcome;
      +        }
      +        const remaining = policy.maxElapsedMs === undefined
      +          ? wait
      +          : Math.max(0, policy.maxElapsedMs - spent);
      +        const clamped = Math.min(wait, remaining);
      +        slept += clamped;
      +        await sleep(clamped);
         }
       }

      """ + DemoText.memoryDiff
}
