import Foundation

extension DemoSources {
  static let log = """
    const enabled = process.env.API_CLIENT_DEBUG === '1';

    /** Debug logging, silent unless API_CLIENT_DEBUG=1. Tests turn it on. */
    export const log = {
      debug(message: string): void {
        if (enabled) console.debug(message);
      },
      warn(message: string): void {
        console.warn(`[api-client] ${message}`);
      },
    };

    """

  static let index = """
    export { ApiClient } from './client';
    export type { ClientOptions, ListParams, Page } from './client';
    export * from './errors';
    export * from './transport';
    export * from './retry';
    export type * from './types';

    """

  static let clock = """
    /** A clock for tests: sleeping moves time on at once, and random draws are pinned. */
    export interface FakeClock {
      sleep(ms: number): Promise<void>;
      elapsed(): number;
      now(): number;
    }

    export function fakeClock(start = 0): FakeClock {
      let time = start;
      return {
        async sleep(ms: number) {
          time += ms;
        },
        elapsed: () => time - start,
        now: () => time,
      };
    }

    """

  static let clockEdited = clock.replacingOccurrences(
    of: "export function fakeClock(start = 0): FakeClock {",
    with: """
      export function fakeClock(start = 0, random: () => number = Math.random): FakeClock {
        jest.spyOn(Math, 'random').mockImplementation(random);
      """)

  static let testElapsed = """
    \(imports(["{ withRetry, RetryPolicy } from '../src/api/retry'", "{ ScriptedTransport } from '../src/api/transport'", "{ fakeClock } from './helpers/clock'"]))

    const request = { method: 'GET' as const, url: 'https://api.example.test/v2/payouts', headers: {} };

    function policy(overrides: Partial<RetryPolicy> = {}): RetryPolicy {
      return { ...RetryPolicy.default(), maxAttempts: 10, baseDelayMs: 1_000, ...overrides };
    }

    function failing(count: number, answer = { status: 503 }): ScriptedTransport {
      return new ScriptedTransport(Array(count).fill(answer));
    }

    describe('elapsed cap', () => {
      it('stops before the budget', async () => {
        const clock = fakeClock();
        const transport = failing(10);
        await withRetry(policy({ maxElapsedMs: 5_000 }), request, (r) => transport.send(r), clock.sleep);
        expect(clock.elapsed()).toBeLessThanOrEqual(5_000);
        expect(transport.sent.length).toBeLessThan(10);
      });

      it('shortens the last wait', async () => {
        const clock = fakeClock(0, () => 0.99);
        const transport = failing(10);
        await withRetry(
          policy({ maxElapsedMs: 7_500, jitter: 'full' }),
          request,
          (r) => transport.send(r),
          clock.sleep,
        );
        expect(clock.elapsed()).toBe(7_500);
      });

      it('ignores Retry-After past the budget', async () => {
        const clock = fakeClock();
        const transport = failing(3, { status: 429, headers: { 'retry-after': '60' } } as never);
        const response = await withRetry(
          policy({ maxElapsedMs: 10_000 }),
          request,
          (r) => transport.send(r),
          clock.sleep,
        );
        expect(response.status).toBe(429);
        expect(clock.elapsed()).toBe(0);
      });

      it('no cap by default', async () => {
        const clock = fakeClock();
        const transport = failing(5);
        await withRetry(RetryPolicy.default(), request, (r) => transport.send(r), clock.sleep);
        expect(clock.elapsed()).toBe(200 + 400 + 800 + 1_600);
      });

      it('counts the time of each attempt', async () => {
        const clock = fakeClock();
        const transport = failing(10, { status: 503, elapsedMs: 900 } as never);
        await withRetry(policy({ maxElapsedMs: 4_000 }), request, (r) => transport.send(r), clock.sleep);
        expect(transport.sent.length).toBeLessThanOrEqual(3);
      });

      it('zero budget sends once', async () => {
        const transport = failing(3);
        await withRetry(policy({ maxElapsedMs: 0 }), request, (r) => transport.send(r));
        expect(transport.sent).toHaveLength(1);
      });
    });

    """
}
