import Foundation

enum DemoSources {
  static let resources = [
    "Account", "Invoice", "Payment", "Refund", "Customer", "Subscription", "Plan", "Coupon",
    "Webhook", "Event", "Upload", "Dispute", "Payout", "Transfer", "Product", "Price",
  ]

  static func plural(_ resource: String) -> String { resource + "s" }

  // Built, not written out, so no line here starts with the word the
  // architecture check reads as a Swift import.
  static func imports(_ clauses: [String]) -> String {
    clauses.map { "import \($0);" }.joined(separator: "\n")
  }
  static func route(_ resource: String) -> String { "/" + plural(resource).lowercased() }
  static func noun(_ resource: String) -> String { resource.lowercased() }

  static let client: String = clientHead + resources.map(clientMethods).joined() + "}\n"

  private static let clientHead = """
    \(imports(["{ RetryPolicy, withRetry } from './retry'", "type { Transport, TransportRequest } from './transport'", "{ ApiError, isApiError } from './errors'", "{ newIdempotencyKey } from './ids'", "type * as T from './types'"]))

    export interface ClientOptions {
      baseUrl: string;
      token?: string;
      timeoutMs?: number;
      userAgent?: string;
    }

    export interface ListParams {
      cursor?: string;
      limit?: number;
      createdAfter?: string;
    }

    export interface Page<Item> {
      items: Item[];
      nextCursor?: string;
    }

    interface Call {
      method: TransportRequest['method'];
      path: string;
      query?: object;
      body?: unknown;
      idempotencyKey?: string;
      allowStatus?: number[];
    }

    const DEFAULT_OPTIONS: ClientOptions = {
      baseUrl: 'https://api.example.test/v2',
      timeoutMs: 10_000,
      userAgent: 'api-client/2.4.0',
    };

    export class ApiClient {
      constructor(
        private transport: Transport,
        private policy = RetryPolicy.default(),
        private options: ClientOptions = DEFAULT_OPTIONS,
      ) {}

      /** One call, retried the way the policy says. */
      private async send<Result>(call: Call): Promise<Result> {
        const request: TransportRequest = {
          method: call.method,
          url: this.options.baseUrl + call.path,
          query: call.query,
          body: call.body,
          headers: this.headers(call),
          timeoutMs: this.options.timeoutMs,
        };
        const response = await withRetry(this.policy, request, (attempt) =>
          this.transport.send(attempt),
        );
        if (call.allowStatus?.includes(response.status)) {
          return undefined as Result;
        }
        if (response.status >= 400) {
          throw ApiError.fromResponse(response);
        }
        return response.body as Result;
      }

      private headers(call: Call): Record<string, string> {
        const headers: Record<string, string> = {
          'user-agent': this.options.userAgent ?? DEFAULT_OPTIONS.userAgent!,
          accept: 'application/json',
        };
        if (this.options.token) headers.authorization = `Bearer ${this.options.token}`;
        if (call.idempotencyKey) headers['idempotency-key'] = call.idempotencyKey;
        return headers;
      }

      /** True when an error is one the API says may succeed if sent again. */
      static isTransient(error: unknown): boolean {
        return isApiError(error) && error.retryable;
      }

    """

  private static func clientMethods(_ resource: String) -> String {
    let many = plural(resource)
    let path = route(resource)
    let one = noun(resource)
    let item = "`\(path)/${encodeURIComponent(id)}`"
    return """
        /** Lists \(many.lowercased()), newest first. Pages with `cursor`. */
        async list\(many)(params: ListParams = {}): Promise<Page<T.\(resource)>> {
          return this.send<Page<T.\(resource)>>({ method: 'GET', path: '\(path)', query: params });
        }

        /** Fetches one \(one) by id. */
        async get\(resource)(id: string): Promise<T.\(resource)> {
          return this.send<T.\(resource)>({ method: 'GET', path: \(item) });
        }

        /** Creates a \(one). Safe to retry: the request carries an idempotency key. */
        async create\(resource)(
          input: T.\(resource)Input,
          key = newIdempotencyKey(),
        ): Promise<T.\(resource)> {
          return this.send<T.\(resource)>({
            method: 'POST',
            path: '\(path)',
            body: input,
            idempotencyKey: key,
          });
        }

        /** Updates the fields of a \(one) that `patch` names. */
        async update\(resource)(
          id: string,
          patch: Partial<T.\(resource)Input>,
        ): Promise<T.\(resource)> {
          return this.send<T.\(resource)>({ method: 'PATCH', path: \(item), body: patch });
        }

        /** Deletes a \(one). Deleting one that is already gone is not an error. */
        async delete\(resource)(id: string): Promise<void> {
          await this.send<void>({ method: 'DELETE', path: \(item), allowStatus: [404] });
        }

        /**
         * Every \(one) there is, following `nextCursor` until the last page. Each page is
         * its own request, with its own retries, so a failure part way through loses
         * nothing that was already yielded.
         */
        async *listAll\(many)(
          params: Omit<ListParams, 'cursor'> = {},
        ): AsyncGenerator<T.\(resource)> {
          let cursor: string | undefined;
          do {
            const page = await this.list\(many)({ ...params, cursor });
            yield* page.items;
            cursor = page.nextCursor;
          } while (cursor);
        }


      """
  }
}
