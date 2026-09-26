import Foundation

/// The retry code the demo session works on, and its tests.
extension DemoSources {
  /// Error codes the policy retries, with the reason written beside each.
  static let transientCodes: [(String, String)] = [
    ("ECONNRESET", "the server closed the connection mid request"),
    ("ECONNREFUSED", "nothing listening yet, usually a deploy in progress"),
    ("ETIMEDOUT", "our own timeout fired before the response arrived"),
    ("EPIPE", "the socket went away while we were writing"),
    ("EAI_AGAIN", "DNS lookup failed temporarily"),
    ("ENETUNREACH", "the network dropped out, common on laptops waking up"),
    ("EHOSTUNREACH", "the route to the host went away for a moment"),
    ("UND_ERR_SOCKET", "undici reports a closed socket this way"),
    ("UND_ERR_CONNECT_TIMEOUT", "undici gave up connecting"),
    ("HTTP_408", "the server timed out waiting for us"),
    ("HTTP_425", "too early: the server wants the request replayed later"),
    ("HTTP_429", "rate limited; Retry-After says how long to wait"),
    ("HTTP_500", "internal error, retried because the API documents it as transient"),
    ("HTTP_502", "bad gateway from the load balancer"),
    ("HTTP_503", "service unavailable; Retry-After may be set"),
    ("HTTP_504", "gateway timeout"),
  ]

  static let retry: String =
    retryHead + transientCodes.map(retryRule).joined() + retryBody
    + resources.map(retryOverride).joined() + "};\n"

  private static let retryHead = """
    /**
     * Retries for the API client.
     *
     * A request is sent again when two things hold: the failure is one the API documents
     * as transient (TRANSIENT below), and sending the request twice cannot do anything
     * twice (GET and DELETE, or a write with an idempotency key). Everything else fails at
     * once, with the error the transport or the server gave.
     *
     * The wait before attempt n doubles from baseDelayMs and is capped at maxDelayMs. A
     * Retry-After header on a 429 or a 503 replaces it. RetryStats counts what happened so
     * a caller can report it; nothing here logs above debug level.
     */
    \(imports(["type { TransportRequest, TransportResponse } from './transport'", "{ TransportError } from './transport'", "{ log } from './log'"]))

    export interface RetryPolicy {
      maxAttempts: number;
      baseDelayMs: number;
      maxDelayMs: number;
      maxElapsedMs?: number;
      jitter: 'none' | 'full';
    }

    export const RetryPolicy = {
      default(): RetryPolicy {
        return { maxAttempts: 5, baseDelayMs: 200, maxDelayMs: 8_000, jitter: 'none' };
      },
    };

    interface RetryRule {
      /** Why this code is worth another attempt. */
      reason: string;
      /** Honour a Retry-After header when the server sends one. */
      respectRetryAfter: boolean;
      /** Where the failure came from, for the stats and the log. */
      kind: 'network' | 'server' | 'throttle';
    }

    /** Failures that may succeed when sent again. Everything else fails at once. */
    export const TRANSIENT: Record<string, RetryRule> = {

    """

  private static func retryRule(_ code: (String, String)) -> String {
    let after = code.0 == "HTTP_429" || code.0 == "HTTP_503"
    let kind =
      code.0.hasPrefix("HTTP_") ? (code.0 == "HTTP_429" ? "throttle" : "server") : "network"
    return """
        // \(code.1)
        \(code.0): {
          reason: '\(code.1)',
          respectRetryAfter: \(after),
          kind: '\(kind)',
        },

      """
  }

  private static let retryBody = """
    };

    export function codeOf(outcome: TransportResponse | TransportError): string {
      return outcome instanceof TransportError ? outcome.code : `HTTP_${outcome.status}`;
    }

    export function isRetryable(request: TransportRequest, code: string): boolean {
      if (!(code in TRANSIENT)) return false;
      // A request that changes something is only sent again when it carries an
      // idempotency key, so the server can tell the second one from a new one.
      if (request.method === 'GET' || request.method === 'DELETE') return true;
      return request.headers['idempotency-key'] !== undefined;
    }

    export function computeDelay(policy: RetryPolicy, attempt: number): number {
      const backoff = Math.min(policy.maxDelayMs, policy.baseDelayMs * 2 ** attempt);
      const delay = backoff;
      return delay;
    }

    export function retryAfterMs(response: TransportResponse): number | undefined {
      const header = response.headers['retry-after'];
      if (!header) return undefined;
      const seconds = Number(header);
      if (Number.isFinite(seconds)) return seconds * 1000;
      const date = Date.parse(header);
      return Number.isNaN(date) ? undefined : Math.max(0, date - Date.now());
    }

    export async function withRetry(
      policy: RetryPolicy,
      request: TransportRequest,
      send: (request: TransportRequest) => Promise<TransportResponse>,
      sleep: (ms: number) => Promise<void> = (ms) => new Promise((done) => setTimeout(done, ms)),
    ): Promise<TransportResponse> {
      for (let attempt = 0; ; attempt++) {
        let outcome: TransportResponse | TransportError;
        try {
          outcome = await send(request);
          if (outcome.status < 400) return outcome;
        } catch (error) {
          if (!(error instanceof TransportError)) throw error;
          outcome = error;
        }
        const code = codeOf(outcome);
        const last = attempt + 1 >= policy.maxAttempts;
        if (last || !isRetryable(request, code)) {
          if (outcome instanceof TransportError) throw outcome;
          return outcome;
        }
        const wait =
          (outcome instanceof TransportError ? undefined : retryAfterMs(outcome)) ??
          computeDelay(policy, attempt);
        log.debug(
          `[retry] ${request.method} ${request.url} attempt ${attempt + 2} of ` +
            `${policy.maxAttempts} in ${Math.round(wait)} ms (${code})`,
        );
        await sleep(wait);
      }
    }

    /** Counts of what the retry loop did, per code, for a caller that wants to report it. */
    export class RetryStats {
      private attempts = 0;
      private retries = 0;
      private waitedMs = 0;
      private readonly byCode = new Map<string, number>();

      record(code: string, waitMs: number): void {
        this.retries += 1;
        this.waitedMs += waitMs;
        this.byCode.set(code, (this.byCode.get(code) ?? 0) + 1);
      }

      attempt(): void {
        this.attempts += 1;
      }

      /** The most frequent codes first. */
      top(count = 3): Array<[string, number]> {
        return [...this.byCode.entries()].sort((a, b) => b[1] - a[1]).slice(0, count);
      }

      summary(): string {
        const codes = this.top().map(([code, n]) => `${code} x${n}`).join(', ');
        return `${this.attempts} attempts, ${this.retries} retries, ` +
          `${Math.round(this.waitedMs)} ms waited${codes ? ` (${codes})` : ''}`;
      }
    }

    /**
     * A budget shared by every request of one client, so an outage does not turn into a
     * retry storm: each retry spends a token, each success earns a tenth of one back, and
     * with the bucket empty failures are returned at once.
     */
    export class RetryBudget {
      private tokens: number;

      constructor(
        private readonly capacity = 20,
        private readonly refillPerSuccess = 0.1,
      ) {
        this.tokens = capacity;
      }

      /** Takes a token for one retry. False when there is none left. */
      trySpend(): boolean {
        if (this.tokens < 1) return false;
        this.tokens -= 1;
        return true;
      }

      succeeded(): void {
        this.tokens = Math.min(this.capacity, this.tokens + this.refillPerSuccess);
      }

      get remaining(): number {
        return Math.floor(this.tokens);
      }
    }

    /** The jitter strategies worth knowing about. Only 'none' and 'full' are exposed. */
    export const JITTER = {
      /** Exactly the backoff: every client waits the same, and they all come back at once. */
      none: (backoff: number) => backoff,
      /** Anywhere from zero to the backoff: spreads clients out the most. */
      full: (backoff: number, random = Math.random) => random() * backoff,
      /** Half the backoff plus up to half again: never less than half the wait. */
      equal: (backoff: number, random = Math.random) => backoff / 2 + (random() * backoff) / 2,
      /** Grows from the previous wait instead of the attempt number. */
      decorrelated: (previous: number, base: number, cap: number, random = Math.random) =>
        Math.min(cap, base + random() * (previous * 3 - base)),
    };

    /** A sentence for an error message: why the client gave up, or why it did not retry. */
    export function explain(request: TransportRequest, code: string, attempts: number): string {
      const rule = TRANSIENT[code];
      if (!rule) return `${code} is not a transient failure, so it was not retried`;
      if (!isRetryable(request, code)) {
        return `${request.method} without an idempotency key is never sent twice (${code})`;
      }
      return `gave up after ${attempts} attempts: ${rule.reason}`;
    }

    /** Per route overrides: some endpoints are slow by nature, some must not wait long. */
    export const ROUTE_POLICY: Record<string, Partial<RetryPolicy>> = {

    """

  private static func retryOverride(_ resource: String) -> String {
    let slow = ["Upload", "Payout", "Transfer", "Dispute"].contains(resource)
    return """
        // \(plural(resource).lowercased()): \(slow ? "slow backend, wait longer" : "defaults")
        '\(route(resource))': {
          maxAttempts: \(slow ? 6 : 5),
          baseDelayMs: \(slow ? 500 : 200),
          maxDelayMs: \(slow ? "20_000" : "8_000"),
        },

      """
  }

  /// The policy object the refactor introduces.
  static let policy = """
    \(imports(["{ RetryPolicy } from './retry'", "{ ROUTE_POLICY } from './retry'"]))

    export interface PolicyOptions {
      maxAttempts?: number;
      baseDelayMs?: number;
      maxDelayMs?: number;
      maxElapsedMs?: number;
      jitter?: RetryPolicy['jitter'];
    }

    /** The one place a retry policy is put together. */
    export function makePolicy(options: PolicyOptions = {}): RetryPolicy {
      const policy = { ...RetryPolicy.default(), ...options };
      if (policy.maxAttempts < 1) throw new RangeError('maxAttempts must be at least 1');
      if (policy.baseDelayMs < 0) throw new RangeError('baseDelayMs must not be negative');
      if (policy.maxDelayMs < policy.baseDelayMs) {
        throw new RangeError('maxDelayMs must be at least baseDelayMs');
      }
      return Object.freeze(policy);
    }

    /** The policy for one route: the defaults, the route's override, then the caller's. */
    export function policyFor(path: string, options: PolicyOptions = {}): RetryPolicy {
      const route = Object.keys(ROUTE_POLICY).find((prefix) => path.startsWith(prefix));
      return makePolicy({ ...(route ? ROUTE_POLICY[route] : {}), ...options });
    }

    """
}
