import Foundation

/// What the demo's commands print: test runs, searches, a diff. Built from the
/// demo's own sources, so a test named in a run is a test that exists.
enum DemoOutput {
  /// One failing test in a run: its suite file, its full name, and the
  /// explanation jest prints under it.
  struct Failure {
    let file: String
    let name: String
    let detail: String
  }

  /// Test files and their test names, in the order jest runs them.
  static func suites(withElapsed: Bool) -> [(file: String, tests: [String])] {
    let sources = DemoSources.self
    var client: [String] = []
    for resource in sources.resources {
      let many = sources.plural(resource)
      client += [
        "ApiClient › list\(many) sends the cursor", "ApiClient › get\(resource) escapes the id",
        "ApiClient › create\(resource) sends an idempotency key",
        "ApiClient › update\(resource) sends only the patch",
        "ApiClient › delete\(resource) treats 404 as done",
      ]
    }
    let codes = sources.transientCodes.map(\.0)
    var backoff = (0..<24).map { "backoff › computeDelay without jitter › case \($0 + 1)" }
    backoff += ["backoff › caps elapsed time", "backoff › stops at maxAttempts"]
    backoff += ["backoff › does not retry a 400"]
    var result: [(file: String, tests: [String])] = [
      (
        "tests/test_policy.ts",
        sources.resources.map { "policyFor › \(sources.route($0))" }
          + [
            "makePolicy › rejects", "makePolicy › freezes", "makePolicy › merges",
            "makePolicy › defaults", "makePolicy › validates the cap",
          ]
      ),
      ("tests/test_client.ts", client),
      ("tests/test_transport.ts", (0..<29).map { "FetchTransport › status text \($0 + 1)" }),
      ("tests/test_retry.ts", codes.flatMap { ["retries \($0)", "gives up on \($0)"] }),
      ("tests/test_errors.ts", (0..<20).map { "ApiError › maps status \($0 + 1)" }),
      ("tests/test_backoff.ts", backoff),
    ]
    if withElapsed {
      result.append(
        (
          "tests/test_elapsed.ts",
          [
            "elapsed cap › stops before the budget", "elapsed cap › shortens the last wait",
            "elapsed cap › ignores Retry-After past the budget", "elapsed cap › no cap by default",
            "elapsed cap › counts the time of each attempt", "elapsed cap › zero budget sends once",
          ]
        ))
    }
    return result
  }

  /// An `npm test` run. `logs` is how many retry log lines jest echoes, which
  /// is most of what makes a run long.
  static func npmTest(
    failures: [Failure] = [], verbose: Bool = false, logs: Int = 0, withElapsed: Bool = true,
    seconds: String = "4.812"
  ) -> String {
    var out = "\n> api-client@2.4.0 test\n> jest --runInBand\(verbose ? " --verbose" : "")\n\n"
    let suites = suites(withElapsed: withElapsed)
    var total = 0
    for (index, suite) in suites.enumerated() {
      let failed = failures.filter { $0.file == suite.file }
      out += (failed.isEmpty ? "PASS " : "FAIL ") + suite.file + "\n"
      if verbose {
        for (number, test) in suite.tests.enumerated() {
          let mark = failed.contains { $0.name.hasSuffix(test) } ? "✕" : "✓"
          out += "    \(mark) \(test) (\(1 + (number * 7 + index * 3) % 23) ms)\n"
        }
      }
      for line in 0..<(logs / suites.count) { out += log(index * 97 + line) }
      for failure in failed { out += "\n  ● \(failure.name)\n\n\(failure.detail)\n" }
      total += suite.tests.count
    }
    let failedSuites = Set(failures.map(\.file)).count
    out += "\nTest Suites: " + (failedSuites > 0 ? "\(failedSuites) failed, " : "")
    out += "\(suites.count - failedSuites) passed, \(suites.count) total\n"
    out += "Tests:       " + (failures.isEmpty ? "" : "\(failures.count) failed, ")
    out += "\(total - failures.count) passed, \(total) total\n"
    out += "Snapshots:   0 total\nTime:        \(seconds) s\nRan all test suites.\n"
    return out
  }

  /// One retry log line the way jest echoes a console call.
  private static func log(_ seed: Int) -> String {
    let resources = DemoSources.resources
    let codes = ["HTTP_503", "HTTP_429", "ECONNRESET", "HTTP_502", "ETIMEDOUT"]
    let attempt = 2 + seed % 4
    let wait = 200 << (attempt - 2)
    let path = DemoSources.route(resources[seed % resources.count])
    return """
        console.debug
          [retry] GET https://api.example.test/v2\(path) attempt \(attempt) of 5 in \
      \(wait) ms (\(codes[seed % codes.count]))

            at log (src/api/log.ts:12:13)
            at withRetry (src/api/retry.ts:\(118 + seed % 3):9)


      """
  }

  /// The failure jest prints for the elapsed time cap.
  static let elapsedFailure = Failure(
    file: "tests/test_backoff.ts", name: "backoff › caps elapsed time",
    detail: """
          expect(received).toBeLessThanOrEqual(expected)

          Expected: <= 30000
          Received:    30412

            237 |     };
            238 |     await withRetry(policy, request, (r) => transport.send(r), clock.sleep);
          > 239 |     expect(clock.elapsed()).toBeLessThanOrEqual(30_000);
                |                             ^
            240 |   });

            at Object.<anonymous> (tests/test_backoff.ts:239:29)
      """)

  /// A search's output, `path:line:text`, cycling through made-up matches in
  /// the project and in its dependencies until there are `count` of them.
  static func grep(_ word: String, count: Int) -> String {
    let places = [
      "src/api/retry.ts", "tests/test_backoff.ts", "docs/retries.md", "CHANGELOG.md",
      "node_modules/p-retry/index.js", "node_modules/exponential-backoff/dist/backoff.js",
      "node_modules/undici/lib/handler/retry-handler.js", "node_modules/ws/lib/websocket.js",
      "node_modules/@smithy/util-retry/dist-cjs/index.js",
      "node_modules/got/dist/source/as-promise.js",
      "node_modules/axios-retry/dist/cjs/index.js", "node_modules/ioredis/built/Redis.js",
    ]
    let texts = [
      "const \(word) = policy.baseDelayMs * 2 ** attempt;",
      "// \(word) with an upper bound, see the policy for the cap",
      "  \(word): computeDelay(policy, attempt),",
      "function \(word)Delay(attempt, options) {",
      "    return Math.min(options.maxDelay, options.\(word) * Math.pow(2, attempt));",
      "  const \(word)Ms = retryAfter ?? next\(word.capitalized)(attempt);",
      "* The \(word) grows exponentially and is capped at `maxDelay`.",
      "    this.\(word) = new \(word.capitalized)Strategy(this.options);",
      "- `\(word)`: milliseconds to wait before attempt n, doubled each time",
      "exports.\(word) = \(word);",
    ]
    var lines: [String] = []
    for index in 0..<count {
      let place = places[(index / 7) % places.count]
      let line = 12 + (index * 37) % 480
      lines.append("\(place):\(line):\(texts[(index * 3) % texts.count])")
    }
    return lines.joined(separator: "\n")
  }

  /// A whole new file as a diff adds it.
  static func added(_ path: String, _ content: String) -> String {
    var ids = DemoIDs(seed: path)
    let lines = content.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
    return """
      diff --git a/\(path) b/\(path)
      new file mode 100644
      index 0000000..\(ids.hex(7))
      --- /dev/null
      +++ b/\(path)
      @@ -0,0 +1,\(lines.count) @@

      """ + lines.map { "+" + $0 }.joined(separator: "\n") + "\n"
  }
}

extension String {
  fileprivate var capitalized: String { prefix(1).uppercased() + dropFirst() }
}
