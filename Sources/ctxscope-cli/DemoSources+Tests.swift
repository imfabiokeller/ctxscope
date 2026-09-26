import Foundation

extension DemoSources {
  static let testBackoff: String =
    backoffHead + backoffCases.map(backoffCase).joined()
    + backoffTail

  private static let backoffCases: [(attempt: Int, base: Int, cap: Int)] = (0..<24).map {
    (attempt: $0 % 8, base: [100, 200, 500][$0 / 8], cap: [2_000, 8_000, 30_000][$0 % 3])
  }

  private static let backoffHead = """
    \(imports(["{ computeDelay, withRetry, RetryPolicy } from '../src/api/retry'", "{ ScriptedTransport } from '../src/api/transport'", "{ fakeClock } from './helpers/clock'"]))

    const request = { method: 'GET' as const, url: 'https://api.example.test/v2/invoices', headers: {} };

    describe('backoff', () => {
      describe('computeDelay without jitter', () => {

    """

  private static func backoffCase(_ item: (attempt: Int, base: Int, cap: Int)) -> String {
    let expected = min(item.cap, item.base << item.attempt)
    return """
          it('attempt \(item.attempt), base \(item.base) ms, cap \(item.cap) ms', () => {
            const policy: RetryPolicy = {
              maxAttempts: 9,
              baseDelayMs: \(item.base),
              maxDelayMs: \(item.cap),
              jitter: 'none',
            };
            expect(computeDelay(policy, \(item.attempt))).toBe(\(expected));
            const jittered = { ...policy, jitter: 'full' as const };
            for (const draw of [0, 0.25, 0.5, 0.999]) {
              jest.spyOn(Math, 'random').mockReturnValue(draw);
              const delay = computeDelay(jittered, \(item.attempt));
              expect(delay).toBeGreaterThanOrEqual(0);
              expect(delay).toBeLessThan(\(expected) + 1);
            }
          });


      """
  }

  private static let backoffTail = """
      });

      it('caps elapsed time', async () => {
        const clock = fakeClock();
        const transport = new ScriptedTransport(Array(8).fill({ status: 503 }));
        const policy: RetryPolicy = {
          maxAttempts: 8,
          baseDelayMs: 1_000,
          maxDelayMs: 16_000,
          maxElapsedMs: 30_000,
          jitter: 'full',
        };
        await withRetry(policy, request, (r) => transport.send(r), clock.sleep);
        expect(clock.elapsed()).toBeLessThanOrEqual(30_000);
      });

      it('stops at maxAttempts', async () => {
        const clock = fakeClock();
        const transport = new ScriptedTransport(Array(5).fill({ status: 503 }));
        const response = await withRetry(RetryPolicy.default(), request, (r) => transport.send(r), clock.sleep);
        expect(response.status).toBe(503);
        expect(transport.sent).toHaveLength(5);
      });

      it('does not retry a 400', async () => {
        const transport = new ScriptedTransport([{ status: 400 }]);
        const response = await withRetry(RetryPolicy.default(), request, (r) => transport.send(r));
        expect(response.status).toBe(400);
        expect(transport.sent).toHaveLength(1);
      });
    });

    """
}
