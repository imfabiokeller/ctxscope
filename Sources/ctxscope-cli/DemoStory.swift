import Foundation

/// The demo session, request by request: 87 requests under 9 typed prompts, a
/// memory edit at request 23, a pause of six minutes before request 42 and the
/// GitHub server connecting at request 64. The snapshot tool's sample
/// screens tell the same story.
enum DemoStory {
  static let title = "retry-policy"

  static let prompts = [
    "Read the API client and map how retries work",
    "Refactor retries into a single policy object",
    "Run the tests and fix the failures",
    "Update CLAUDE.md with the new retry rules",
    "Add jitter and a cap on total elapsed time",
    "Write tests for the elapsed-time cap",
    "Why is test_backoff flaky?",
    "Connect GitHub and open a pull request",
    "Address the review comments",
  ]

  static func turns(_ project: DemoProject) -> [DemoTurn] {
    explore(project) + refactor(project) + fix(project) + memory(project) + jitter(project)
      + elapsed(project) + flaky(project) + github(project) + review(project)
  }

  /// A request that only calls tools, after a short pause.
  static func step(
    _ calls: [DemoCall], thinking: String? = nil, tokens: Int = 0, gap: Double = 11
  ) -> DemoTurn {
    DemoTurn(thinking: thinking, thinkingTokens: tokens, calls: calls, gap: gap)
  }

  /// The answer that ends a prompt's work.
  static func reply(_ text: String, thinking: String? = nil, tokens: Int = 0) -> DemoTurn {
    DemoTurn(thinking: thinking, thinkingTokens: tokens, text: text, gap: 16)
  }

  /// The first request after a typed prompt.
  static func opening(
    _ number: Int, _ calls: [DemoCall], extra: [DemoInput] = [], thinking: String,
    tokens: Int, gap: Double = 70, cache: DemoCache = .warm
  ) -> DemoTurn {
    DemoTurn(
      inputs: [.prompt(prompts[number - 1])] + extra, thinking: thinking, thinkingTokens: tokens,
      calls: calls, gap: gap, cache: cache)
  }

  static func explore(_ p: DemoProject) -> [DemoTurn] {
    let first: [DemoInput] = [
      .rendered("environment", DemoText.environment.replacingOccurrences(of: "{cwd}", with: p.cwd)),
      .instructions([
        DemoFile(path: p.home + "/.claude/CLAUDE.md", type: "User", content: DemoText.userMemory),
        DemoFile(path: p.path("CLAUDE.md"), type: "Project", content: DemoText.projectMemory),
      ]),
      .rendered("date", "Today's date is \(p.today).", fields: ["date": p.today]),
    ]
    return [
      opening(
        1, [p.read("src/api/client.ts", DemoSources.client)], extra: first,
        thinking: "Start with the client, since every call goes through it.", tokens: 190,
        gap: 0),
      step(
        [
          p.agent(
            DemoAgents.explore(p), description: "Map retry call sites",
            report: DemoText.exploreReport)
        ],
        thinking: "send() hands every request to withRetry. The rest of the retry path is spread "
          + "over retry.ts and the transport; an explore agent can map it while I keep reading.",
        tokens: 340),
      step([p.grep("RetryPolicy", DemoOutput.grep("RetryPolicy", count: 9), files: 3)], gap: 105),
      step([p.read("src/api/log.ts", DemoSources.log)], tokens: 60),
      reply(
        """
        How retries work today:

        - Every endpoint in `src/api/client.ts` goes through `ApiClient.send()`, which calls \
        `withRetry(this.policy, ...)` with the one policy the client was built with.
        - `withRetry` in `src/api/retry.ts` retries transient failures (16 codes in \
        `TRANSIENT`), honours Retry-After on 429 and 503, and otherwise waits \
        `baseDelayMs * 2 ** attempt`, capped at `maxDelayMs`.
        - Writes are only retried with an idempotency key. Creates send one, updates do not.
        - `ROUTE_POLICY` defines overrides for 16 routes, but nothing reads it.
        - `maxElapsedMs` and `jitter` are declared and never used.

        So there are three places a retry setting can come from, and only one of them is \
        live. A single policy object would fix that.
        """, thinking: "Enough to answer.", tokens: 120),
    ]
  }

  static func refactor(_ p: DemoProject) -> [DemoTurn] {
    [
      opening(
        2,
        [
          p.todo([
            ("Add a policy module that builds RetryPolicy", "in_progress"),
            ("Use the route policy in ApiClient.send", "pending"),
            ("Export the policy helpers", "pending"), ("npm run typecheck", "pending"),
          ])
        ],
        thinking: "One module that builds a policy from defaults, the route override and "
          + "the caller's options, in that order.", tokens: 410),
      step([p.read("src/api/transport.ts", DemoSources.transport)]),
      step(
        [p.write("src/api/policy.ts", DemoSources.policy)], thinking: "Freeze the result.",
        tokens: 150),
      step([
        p.edit(
          "src/api/client.ts", "import { RetryPolicy, withRetry } from './retry';",
          "import { RetryPolicy, withRetry } from './retry';\nimport { policyFor } from './policy';"
        )
      ]),
      step([
        p.edit(
          "src/api/client.ts",
          "    const response = await withRetry(this.policy, request, (attempt) =>",
          "    const policy = policyFor(call.path, this.policy);\n"
            + "    const response = await withRetry(policy, request, (attempt) =>")
      ]),
      step([p.read("src/api/index.ts", DemoSources.index)]),
      step([
        p.edit(
          "src/api/index.ts", "export * from './retry';",
          "export * from './retry';\nexport { makePolicy, policyFor } from './policy';")
      ]),
      step([
        p.bash(
          "npm run typecheck", "npm run typecheck",
          "\n> api-client@2.4.0 typecheck\n> tsc --noEmit\n")
      ]),
      reply(
        """
        Added `src/api/policy.ts` with `makePolicy()` and `policyFor(path, options)`: defaults, \
        then the route override from `ROUTE_POLICY`, then the caller's options, validated and \
        frozen. `ApiClient.send()` now asks `policyFor` for each call, so the route overrides \
        are live for the first time. Typecheck passes; I have not run the tests yet.
        """),
    ]
  }
}
