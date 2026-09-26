import Foundation

/// The two subagent runs of the demo session: one maps the retry path while
/// the first prompt is answered, one chases the flaky test.
enum DemoAgents {
  static func explore(_ p: DemoProject) -> DemoAgent {
    DemoAgent(
      id: "a41c7e02b95d3f168", type: "Explore",
      prompt: "Map every place in src/api that decides whether and how a request is retried: "
        + "the retry loop, the policy and where it comes from, route overrides, idempotency "
        + "rules, and anything declared but unused. Report file:line for each.",
      turns: [
        DemoTurn(
          thinking: "Search first, then read the two files that matter.", thinkingTokens: 90,
          calls: [
            p.grep(
              "withRetry|RetryPolicy|ROUTE_POLICY", DemoOutput.grep("withRetry", count: 14),
              files: 4)
          ]),
        DemoTurn(calls: [p.read("src/api/retry.ts", DemoSources.retry)], gap: 6),
        DemoTurn(calls: [p.read("src/api/transport.ts", DemoSources.transport)], gap: 5),
        DemoTurn(
          thinking: "maxElapsedMs is on the interface. Is it read anywhere?", thinkingTokens: 70,
          calls: [p.grep("maxElapsedMs|jitter", DemoOutput.grep("jitter", count: 6), files: 2)],
          gap: 5),
        DemoTurn(
          thinking: "Nothing reads ROUTE_POLICY.", thinkingTokens: 110,
          text: DemoText.exploreReport,
          gap: 9),
      ])
  }

  static func flaky(_ p: DemoProject) -> DemoAgent {
    let loop =
      "for i in $(seq 40); do npx jest tests/test_backoff.ts -t 'caps elapsed' --silent "
      + ">/dev/null 2>&1 || echo \"run $i failed\"; done"
    return DemoAgent(
      id: "a9e2d6b07c14f5a83", type: "general-purpose",
      prompt: "tests/test_backoff.ts › 'caps elapsed time' fails now and then with a total a "
        + "little over 30000 ms. Reproduce it, find the cause in src/api/retry.ts, and propose "
        + "the smallest fix. Do not commit anything.",
      turns: [
        DemoTurn(
          thinking: "Run it in a loop to see how often it fails.", thinkingTokens: 80,
          calls: [
            p.bash(
              loop, "Run the elapsed test 40 times", "run 7 failed\nrun 22 failed\nrun 31 failed\n")
          ]),
        DemoTurn(calls: [p.read("src/api/retry.ts", DemoSources.retry)], gap: 7),
        DemoTurn(
          thinking: "The budget is checked before the sleep. With full jitter the last sleep "
            + "can cross it.", thinkingTokens: 260,
          calls: [
            p.bash(
              "API_CLIENT_DEBUG=1 npx jest tests/test_backoff.ts -t 'caps elapsed' 2>&1 | tail -20",
              "Show the retry log of one run",
              DemoOutput.npmTest(
                failures: [DemoOutput.elapsedFailure], logs: 12, withElapsed: false,
                seconds: "0.912"))
          ], gap: 12),
        DemoTurn(
          thinking: "Clamp the wait to the remaining budget.", thinkingTokens: 140,
          text: DemoText.flakyReport, gap: 14),
      ])
  }
}
