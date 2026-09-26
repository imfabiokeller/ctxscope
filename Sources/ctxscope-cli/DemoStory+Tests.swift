import Foundation

extension DemoStory {
  static let mdn =
    "https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Math/random"

  static func elapsed(_ p: DemoProject) -> [DemoTurn] {
    let lastWait = DemoOutput.Failure(
      file: "tests/test_elapsed.ts", name: "elapsed cap › shortens the last wait",
      detail: """
            expect(received).toBe(expected) // Object.is equality

            Expected: 7500
            Received: 7000

              at Object.<anonymous> (tests/test_elapsed.ts:31:29)
        """)
    return [
      opening(
        6, [p.read("tests/helpers/clock.ts", DemoSources.clockEdited)], thinking: DemoText.plan,
        tokens: 4390, gap: 365, cache: .cold),
      step([
        p.fetch(
          mdn, "Exact range of Math.random, and how to get a bounded value", DemoText.mathRandom)
      ]),
      step(
        [p.write("tests/test_elapsed.ts", DemoSources.testElapsed)], thinking: "Six cases.",
        tokens: 210),
      step([
        p.bash(
          "npx jest tests/test_elapsed.ts", "jest tests/test_elapsed.ts",
          DemoOutput.npmTest(failures: [lastWait], seconds: "0.731"), failed: true)
      ]),
      step(
        [
          p.edit(
            "tests/test_elapsed.ts", "        expect(clock.elapsed()).toBe(7_500);",
            "        expect(clock.elapsed()).toBeLessThanOrEqual(7_500);")
        ],
        thinking: "The implementation stops instead of shortening the last wait. The cap holds, "
          + "so the test should assert the cap, not an exact total.", tokens: 380),
      step([
        p.bash(
          "npx jest tests/test_elapsed.ts", "jest tests/test_elapsed.ts",
          "PASS tests/test_elapsed.ts\n\nTests:       6 passed, 6 total\nTime:        0.702 s\n")
      ]),
      step([
        p.edit(
          "tests/helpers/clock.ts", "  let time = start;", "  let time = start;\n  let draws = 0;")
      ]),
      step([
        p.bash(
          "npx jest tests/test_elapsed.ts tests/test_backoff.ts", "jest, both timing suites",
          "PASS tests/test_backoff.ts\nPASS tests/test_elapsed.ts\n\n"
            + "Tests:       33 passed, 33 total\nTime:        1.106 s\n")
      ]),
      step([
        p.bash("npm run lint", "npm run lint", "\n> api-client@2.4.0 lint\n> eslint src tests\n")
      ]),
      step([p.bash("npm test", "npm test", DemoOutput.npmTest(logs: 54, seconds: "4.968"))]),
      step([
        p.edit(
          "CHANGELOG.md", "## Unreleased\n",
          "## Unreleased\n\n- Retries: full jitter and `maxElapsedMs`, a cap on the total time "
            + "spent retrying.\n")
      ]),
      step([
        p.bash(
          "git status --short", "git status",
          " M CHANGELOG.md\n M CLAUDE.md\n M src/api/client.ts\n M src/api/index.ts\n M src/api/retry.ts\n M tests/helpers/clock.ts\n?? src/api/policy.ts\n?? tests/test_elapsed.ts\n"
        )
      ]),
      reply(
        """
        Added `tests/test_elapsed.ts` with six cases: the budget holds, Retry-After past the \
        budget is not waited for, no cap by default, attempt time counts, and a zero budget \
        sends once. One case expected the last wait to be shortened to fit the budget; the \
        loop stops instead, so the test now asserts the cap. All 215 tests pass.
        """),
    ]
  }

  static func flaky(_ p: DemoProject) -> [DemoTurn] {
    let verbose = DemoOutput.npmTest(
      failures: [DemoOutput.elapsedFailure], verbose: true, logs: 216, seconds: "5.231")
    let loop =
      "for i in $(seq 50); do npx jest tests/test_backoff.ts -t 'caps elapsed' --silent "
      + ">/dev/null 2>&1 || echo \"run $i failed\"; done; echo done"
    return [
      opening(
        7, [p.bash("npm test -- --verbose", "npm test, full output", verbose, failed: true)],
        thinking: "See it fail with the full output first.", tokens: 170),
      step([p.read("tests/test_backoff.ts", DemoSources.testBackoff)], tokens: 90),
      step(
        [
          p.agent(
            DemoAgents.flaky(p), description: "Reproduce the flaky backoff test",
            report: DemoText.flakyReport)
        ],
        thinking: "It depends on the random draw. Let an agent reproduce it in a loop while I "
          + "look at every place backoff is computed.", tokens: 280),
      step([p.grep("backoff", DemoOutput.grep("backoff", count: 212), files: 12)], gap: 120),
      step(
        [
          p.edit(
            "src/api/retry.ts", "        slept += wait;\n        await sleep(wait);",
            "        const remaining = policy.maxElapsedMs === undefined\n"
              + "          ? wait\n          : Math.max(0, policy.maxElapsedMs - spent);\n"
              + "        const clamped = Math.min(wait, remaining);\n"
              + "        slept += clamped;\n        await sleep(clamped);")
        ], thinking: "Clamp the wait to what is left of the budget.", tokens: 240),
      step([
        p.edit(
          "tests/test_backoff.ts",
          "    const clock = fakeClock();\n    const transport = new ScriptedTransport(Array(8)",
          "    const clock = fakeClock(0, () => 0.97);\n    const transport = new ScriptedTransport(Array(8)"
        )
      ]),
      step([p.bash(loop, "Run the elapsed test 50 times", "done\n")]),
      step([p.bash("npm test", "npm test", DemoOutput.npmTest(logs: 30, seconds: "4.702"))]),
      reply(
        """
        It was flaky because `withRetry` checked the budget before sleeping, not after. With \
        full jitter the last wait is a random fraction of the backoff, so now and then a wait \
        that started under 30 s ended over it (30412 ms in the failing run). The wait is now \
        clamped to what is left of the budget, and the test pins `Math.random` to 0.97, the \
        draw that used to fail. 50 runs in a row pass, and so does the whole suite.
        """),
    ]
  }
}
