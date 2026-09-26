import Foundation

extension DemoStory {
  static func policyFailure(_ name: String, _ line: Int) -> DemoOutput.Failure {
    DemoOutput.Failure(
      file: "tests/test_client.ts", name: name,
      detail: """
            expect(jest.fn()).toHaveBeenCalledTimes(expected)

            Expected number of calls: 2
            Received number of calls: 1

              at Object.<anonymous> (tests/test_client.ts:\(line):31)
        """)
  }

  static func fix(_ p: DemoProject) -> [DemoTurn] {
    let failures = [
      policyFailure("ApiClient › createPayout sends an idempotency key", 412),
      policyFailure("ApiClient › createTransfer sends an idempotency key", 488),
      policyFailure("ApiClient › createUpload sends an idempotency key", 262),
    ]
    return [
      opening(
        3,
        [
          p.bash(
            "npm test", "npm test",
            DemoOutput.npmTest(failures: failures, logs: 60, withElapsed: false), failed: true)
        ],
        thinking: "Run everything first to see what the refactor broke.", tokens: 150),
      step(
        [p.read("src/api/retry.ts", DemoSources.retry)],
        thinking: "All three are slow routes: Upload, Payout, Transfer. Their override raises "
          + "maxAttempts to 6, and the scripted transport only has two answers. The override "
          + "replaces the caller's policy instead of sitting under it.", tokens: 460),
      step([
        p.edit(
          "src/api/policy.ts",
          "  return makePolicy({ ...(route ? ROUTE_POLICY[route] : {}), ...options });",
          "  const override = route ? ROUTE_POLICY[route] : {};\n"
            + "  return makePolicy({ ...override, ...options, ...pinned(options) });")
      ]),
      step([
        p.bash(
          "npx jest tests/test_client.ts -t 'idempotency key'", "jest tests/test_client.ts",
          "PASS tests/test_client.ts\n\nTests:       16 passed, 64 skipped, 80 total\n"
            + "Time:        1.204 s\n")
      ]),
      step([
        p.edit(
          "src/api/policy.ts", "/** The one place a retry policy is put together. */",
          "/** Options the caller set explicitly always win over a route override. */\n"
            + "function pinned(options: PolicyOptions): PolicyOptions {\n"
            + "  return Object.fromEntries(Object.entries(options).filter(([, v]) => v !== undefined));\n"
            + "}\n\n/** The one place a retry policy is put together. */")
      ]),
      step([
        p.bash(
          "npm run typecheck", "npm run typecheck",
          "\n> api-client@2.4.0 typecheck\n> tsc --noEmit\n")
      ]),
      step([
        p.bash(
          "npm test", "npm test", DemoOutput.npmTest(logs: 30, withElapsed: false, seconds: "4.377")
        )
      ]),
      reply(
        """
        Fixed. The three failures were the slow routes (uploads, payouts, transfers): their \
        entry in `ROUTE_POLICY` replaced the options the caller passed, so a test that asked \
        for 2 attempts got 6. `policyFor` now applies the route override first and the \
        caller's explicit options last. All 209 tests pass.
        """),
    ]
  }

  static func memory(_ p: DemoProject) -> [DemoTurn] {
    let edited = DemoFile(
      path: p.path("CLAUDE.md"), type: "Project", content: DemoText.projectMemoryEdited)
    return [
      opening(
        4, [p.read("CLAUDE.md", DemoText.projectMemoryEdited)], extra: [.nestedMemory(edited)],
        thinking: "They started a Retries section. Fill it in from what the code now does.",
        tokens: 180, cache: .prefix),
      step([
        p.edit(
          "CLAUDE.md", "- Retries go through RetryPolicy only.",
          "- Retries go through RetryPolicy only, built by `makePolicy` or `policyFor`.\n"
            + "- Route overrides live in `ROUTE_POLICY`; explicit caller options win over them.")
      ]),
      step([
        p.edit(
          "CLAUDE.md", "- Never retry non-idempotent requests.",
          "- Never retry non-idempotent requests: POST and PATCH need an idempotency key.")
      ]),
      step([
        p.bash(
          "git diff --stat", "git diff --stat",
          " CLAUDE.md          | 9 +++++++--\n src/api/client.ts  | 4 +++-\n src/api/index.ts   | 1 +\n 3 files changed, 11 insertions(+), 3 deletions(-)\n"
        )
      ]),
      step(
        [
          p.bash(
            "API_CLIENT_DEBUG=1 npm test", "npm test, with retry logging",
            DemoOutput.npmTest(logs: 150, withElapsed: false, seconds: "5.102"))
        ],
        thinking: "Check the rules against the retry log before writing them down as fact.",
        tokens: 230),
      step([p.grep("maxElapsedMs", DemoOutput.grep("maxElapsedMs", count: 5), files: 2)]),
      step([p.read("docs/retries.md", DemoText.retriesDoc)]),
      reply(
        """
        Updated the Retries section of CLAUDE.md: policies come from `makePolicy` or \
        `policyFor`, route overrides sit under explicit options, and writes need an \
        idempotency key to be retried. I left your two lines on jitter and `maxElapsedMs` \
        as they are, but neither is implemented yet: nothing reads `maxElapsedMs`, and \
        delays have no jitter.
        """),
    ]
  }

  static func jitter(_ p: DemoProject) -> [DemoTurn] {
    [
      opening(
        5,
        [
          p.todo([
            ("Full jitter in computeDelay", "in_progress"),
            ("Enforce maxElapsedMs in withRetry", "pending"),
            ("Validate the new options", "pending"),
            ("jest tests/test_backoff.ts", "pending"),
          ])
        ],
        thinking: "Full jitter: a uniform draw between zero and the capped backoff. The cap on "
          + "elapsed time has to count the waits and the time each attempt took.", tokens: 540),
      step([p.grep("jitter", DemoOutput.grep("jitter", count: 110), files: 12)]),
      step([
        p.edit(
          "src/api/retry.ts", "  const delay = backoff;",
          "  const delay = policy.jitter === 'full'\n    ? Math.random() * backoff\n    : backoff;")
      ]),
      step([
        p.edit(
          "src/api/retry.ts", "  for (let attempt = 0; ; attempt++) {",
          "  const started = Date.now();\n  let slept = 0;\n  for (let attempt = 0; ; attempt++) {")
      ]),
      step([
        p.edit(
          "src/api/retry.ts", "        await sleep(wait);",
          "        const spent = Date.now() - started + slept;\n"
            + "        if (policy.maxElapsedMs !== undefined && spent >= policy.maxElapsedMs) {\n"
            + "          return outcome instanceof TransportError ? Promise.reject(outcome) : outcome;\n"
            + "        }\n        slept += wait;\n        await sleep(wait);")
      ]),
      step([
        p.edit(
          "src/api/policy.ts", "  return Object.freeze(policy);",
          "  if (policy.maxElapsedMs !== undefined && policy.maxElapsedMs < 0) {\n"
            + "    throw new RangeError('maxElapsedMs must not be negative');\n  }\n"
            + "  return Object.freeze(policy);")
      ]),
      step([
        p.bash(
          "npm run typecheck", "npm run typecheck",
          "\n> api-client@2.4.0 typecheck\n> tsc --noEmit\n")
      ]),
      step([
        p.bash(
          "npx jest tests/test_backoff.ts", "jest tests/test_backoff.ts",
          "PASS tests/test_backoff.ts\n\nTests:       27 passed, 27 total\nTime:        0.884 s\n")
      ]),
      step([p.edit("tests/helpers/clock.ts", DemoSources.clock, DemoSources.clockEdited)]),
      step([
        p.bash(
          "npm test", "npm test", DemoOutput.npmTest(logs: 60, withElapsed: false, seconds: "4.590")
        )
      ]),
      reply(
        """
        Done. `computeDelay` draws full jitter when `policy.jitter` is `'full'`, and \
        `withRetry` stops retrying once the time spent, attempts and waits together, reaches \
        `maxElapsedMs`. `makePolicy` rejects a negative cap, and the fake clock can now pin \
        `Math.random`. All 209 tests pass, but nothing tests the cap itself yet.
        """),
    ]
  }
}
