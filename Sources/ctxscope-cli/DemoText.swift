import Foundation

enum DemoText {
  static let userMemory = """
    # Personal preferences

    - Explain the plan in two or three lines before a large change.
    - Prefer small commits with messages that say why.
    - TypeScript: strict mode, no `any`, named exports only.
    - Run the project's own test command, never a global one.
    - Keep answers short. No summaries of what I just said.
    """

  static let projectMemory = """
    # api-client

    TypeScript client for the billing API (v2). Published to the internal registry as
    `@example/api-client`. Node 22, no runtime dependencies besides the standard library.

    ## Commands

    - `npm test` runs jest over `tests/`, in band. It must pass before any commit.
    - `npm run typecheck` runs `tsc --noEmit` with the strict config.
    - `npm run lint` runs eslint with the project config; fix, do not disable rules.
    - `npm run build` writes `dist/`. Never edit `dist/` by hand.

    ## Layout

    """
    + DemoSources.resources.map { "- `src/api/types/\($0.lowercased()).ts`: the \($0) shapes\n" }
    .joined() + """

      - `src/api/client.ts`: `ApiClient`, one method per endpoint, all through `send()`.
      - `src/api/transport.ts`: `FetchTransport` and the scripted transport for tests.
      - `src/api/retry.ts`: the retry loop, delays, and which failures are transient.
      - `src/api/errors.ts`: `ApiError` and the mapping from status to error kind.
      - `src/api/log.ts`: debug logging, silent unless `API_CLIENT_DEBUG` is set.
      - `tests/helpers/clock.ts`: a fake clock; tests never sleep for real.

      ## Conventions

      - Every public method has a doc comment that says what it guarantees.
      - Errors are `ApiError` with a `kind`; never throw strings.
      - Write requests carry an idempotency key. Never retry one that does not.
      - Dates are ISO 8601 strings on the wire and `Date` objects nowhere.
      - Tests are named for the behaviour they protect, not for the function.
      - New endpoints get a test in `tests/test_client.ts` using `ScriptedTransport`.

      ## Errors

      - `ApiError.kind` is one of: invalid, auth, missing, conflict, throttled, server, network.
      - `ApiError.retryable` is true only for kinds the retry loop would have retried; by the
        time a caller sees one, the client has already given up on it.
      - Error messages name the request (`POST /invoices`) and the request id the server sent
        back in `x-request-id`, never the body or the headers.
      - `TransportError` is for failures below HTTP: DNS, connection, timeout. The client
        wraps it in an `ApiError` of kind network before it reaches a caller.

      ## Testing

      - Unit tests use `ScriptedTransport`: a list of answers, one per request, in order.
        A test that runs out of answers fails loudly, which is how a missing retry shows up.
      - Time is faked with `tests/helpers/clock.ts`. No test may sleep for real or read
        `Date.now()` directly.
      - Every retry rule has a test in `tests/test_retry.ts`: one that it retries, one that it
        gives up after `maxAttempts`.
      - Integration tests live in `tests/integration/`, need `API_CLIENT_SANDBOX_TOKEN`, and are
        not part of `npm test`. CI runs them nightly against the sandbox.
      - Coverage is not a goal in itself, but a new branch in `retry.ts` without a test will be
        asked about in review.

      ## Pull requests

      - One topic per pull request. Refactors and behaviour changes go in separate commits.
      - The description says what changed, why, and how it was tested, in that order.
      - Mention any change to retry behaviour in `CHANGELOG.md`: callers depend on the timing.
      - At least one review from the API team. The `retry` label pings the on-call reviewer.

      ## Performance

      - The client must not add more than a millisecond per request on top of the transport.
      - No request is ever retried more than `maxAttempts` times, whatever the route says.
      - List endpoints page with cursors; never load all pages into memory in library code.

      ## Releases

      - Bump the version in `package.json` and add a `CHANGELOG.md` entry in the same commit.
      - Tag as `v<version>`; CI publishes on tags only.

      """

  static let projectMemoryEdited =
    projectMemory + """
      ## Retries

      - Retries go through RetryPolicy only.
      - Never retry non-idempotent requests.
      - Run npm test before any commit.
      - Delays use full jitter; tests pin `Math.random` through the fake clock.
      - `maxElapsedMs` caps the total time spent, waits included.

      """

  static let environment = """
    Working directory: {cwd}
    Is a git repository: yes
    Platform: darwin
    Shell: zsh
    OS version: Darwin 25.0.0
    Branch: retry-policy
    Main branch: main
    Recent commits:
    4c1e9a2 client: typed pages for list endpoints
    9b7d310 transport: read the body once, even on errors
    e2a6f05 errors: map 425 to a transient kind
    """

  static let mathRandom = """
    The page documents `Math.random()`. Summary of what matters for retry delays:

    - It returns a floating point number in the range from 0 up to but not including 1, \
    spread roughly evenly over that range.
    - It is not seedable. There is no way to ask for a repeatable sequence, so code that \
    needs repeatable values in tests has to wrap it and replace the wrapper.
    - It is not suitable for anything security related. The page points to \
    `crypto.getRandomValues()` for that.
    - To get an integer in a range, the page multiplies by the size of the range and \
    floors the result, adding the lower bound afterwards. Using `Math.round` instead \
    makes the two ends of the range half as likely as the rest.
    - The upper bound is exclusive, so `Math.random() * n` never reaches `n`. A \
    delay computed as `Math.random() * cap` is always strictly below the cap.

    Examples on the page, restated:

    ```js
    function randomBetween(min, max) {
      return Math.random() * (max - min) + min;
    }

    function randomInt(min, max) {
      const low = Math.ceil(min);
      const high = Math.floor(max);
      return Math.floor(Math.random() * (high - low) + low);
    }
    ```

    The page also notes that the precision of the result depends on the engine, and that \
    the values are produced by a pseudo random generator chosen by the implementation. \
    Nothing on the page discusses retries or backoff directly.

    What follows for the elapsed-time cap, in my own reading of the page:

    1. Because the upper bound is exclusive, a full jitter wait `Math.random() * backoff` \
    is always strictly less than `backoff`, but it can come arbitrarily close to it. A \
    draw of 0.9999 is as likely as a draw of 0.5, so a test that assumes the wait is \
    "about half the backoff" will pass most of the time and fail now and then.
    2. The lower bound is inclusive, so a wait of exactly 0 ms is possible. A retry loop \
    that treats a zero wait as "no wait configured" would misbehave on that draw.
    3. The values are not seedable, so the only way to make a test repeatable is to \
    replace the function: `jest.spyOn(Math, 'random').mockReturnValue(x)` for a fixed \
    draw, or `mockImplementation` with a list of draws for a sequence.
    4. Floating point: `Math.random() * n` can produce values with long fractions. A total \
    of waits compared against a budget in whole milliseconds should either round each \
    wait or compare with a tolerance; the page does not cover this, but its examples \
    floor the result whenever an integer is needed.

    Related pages linked from it: `crypto.getRandomValues()`, `Math.floor()`, and \
    `Number.EPSILON`. None of them change the conclusions above.
    """

  static let exploreReport = """
    Retry behaviour in src/api, as it stands:

    1. src/api/client.ts: every endpoint method goes through `ApiClient.send()`, which \
    calls `withRetry(this.policy, ...)`. The policy is a constructor argument, defaulting \
    to `RetryPolicy.default()` (5 attempts, 200 ms base, 8 s cap, no jitter).
    2. src/api/retry.ts: `withRetry` loops up to `maxAttempts`, classifies each failure \
    with `codeOf` and `isRetryable`, waits `computeDelay(policy, attempt)` or the server's \
    Retry-After, and logs each retry through `log.debug`.
    3. `ROUTE_POLICY` in retry.ts overrides attempts and base delay for 16 routes, but \
    nothing reads it: `send()` always passes `this.policy`.
    4. `isRetryable` only resends POST and PATCH when an idempotency key header is set; \
    all create methods set one, update methods do not.
    5. src/api/transport.ts does not retry. `ScriptedTransport` is what the tests use.

    Not found anywhere: jitter, a cap on total elapsed time, or a test of the route \
    overrides. `maxElapsedMs` is declared on the interface and never read.
    """

  static let flakyReport = """
    Reproduced: `caps elapsed time` fails 3 times in 40 runs, always with a total just \
    over 30000 (30118 to 30412).

    Cause: `withRetry` checks the budget before it sleeps, not after. With full jitter the \
    last wait is `Math.random() * backoff`, and when the elapsed time is, say, 27900 ms and \
    the drawn wait is 2512 ms, the check passes (27900 < 30000) and the sleep carries the \
    total to 30412. Without jitter the waits line up so the budget is never crossed, which \
    is why the test only started failing after jitter was switched on.

    Fix: clamp the wait to what is left of the budget, `Math.min(wait, remaining)`, and \
    stop when nothing is left. The fake clock already makes the sleeps exact, so with the \
    clamp the test is deterministic; I ran it 200 times with the change applied locally \
    and reverted it: 0 failures.

    Also: the test does not pin `Math.random`, so its failures depend on the draw. Pinning \
    it through `fakeClock({ random })` would make the bad case reproducible.
    """

  static let plan = """
    Plan for the jitter cap tests. The cap has to apply to total elapsed time, not per \
    attempt. Options: track a deadline in the loop, or compute the remaining budget before \
    each sleep. The loop does the second. What can go wrong: a Retry-After longer than the \
    budget, attempts that are slow on their own, a zero budget, jitter drawing close to the \
    full backoff on the last wait. The fake clock makes sleeps instant, so every case can \
    assert exact totals. Check what Math.random can return first: if it can return 1, a \
    full jitter wait can equal the backoff, which changes the edge case.
    """

  static let retriesDoc = """
    # Retries

    The client retries a request when the failure is transient and the request is safe to
    send again. This page explains both conditions and the settings that control them.

    ## Transient failures

    Connection resets, timeouts, DNS hiccups, and the statuses 408, 425, 429, 500, 502, 503
    and 504. Everything else fails at once. The list is `TRANSIENT` in `src/api/retry.ts`.

    ## Safe to send again

    GET and DELETE always. POST and PATCH only with an idempotency key, which every create
    method sets. The server keeps keys for 24 hours.

    ## Delays

    The wait before attempt n is `baseDelayMs * 2 ** n`, capped at `maxDelayMs`. A
    Retry-After header on a 429 or 503 replaces it.

    ## Elapsed time

    Not enforced yet.

    """

  static let memoryDiff = """
    diff --git a/CLAUDE.md b/CLAUDE.md
    index 1f0a3c4..6b9e2d1 100644
    --- a/CLAUDE.md
    +++ b/CLAUDE.md
    @@ -52,4 +52,11 @@ TypeScript client for the billing API (v2).
    +## Retries
    +
    +- Retries go through RetryPolicy only, built by `makePolicy` or `policyFor`.
    +- Route overrides live in `ROUTE_POLICY`; explicit caller options win over them.
    +- Never retry non-idempotent requests: POST and PATCH need an idempotency key.
    +- Run npm test before any commit.
    +- Delays use full jitter; tests pin `Math.random` through the fake clock.
    +- `maxElapsedMs` caps the total time spent, waits included.

    """
}
