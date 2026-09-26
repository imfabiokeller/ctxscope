import Foundation

extension DemoSources {
  static let transport: String =
    transportHead + statuses.map { "  \($0.0): '\($0.1)',\n" }.joined() + transportTail

  private static let statuses: [(Int, String)] = [
    (200, "OK"), (201, "Created"), (202, "Accepted"), (204, "No Content"),
    (301, "Moved Permanently"), (302, "Found"), (304, "Not Modified"),
    (307, "Temporary Redirect"), (308, "Permanent Redirect"), (400, "Bad Request"),
    (401, "Unauthorized"), (402, "Payment Required"), (403, "Forbidden"), (404, "Not Found"),
    (405, "Method Not Allowed"), (406, "Not Acceptable"), (408, "Request Timeout"),
    (409, "Conflict"), (410, "Gone"), (411, "Length Required"), (412, "Precondition Failed"),
    (413, "Content Too Large"), (415, "Unsupported Media Type"), (422, "Unprocessable Content"),
    (423, "Locked"), (425, "Too Early"), (428, "Precondition Required"),
    (429, "Too Many Requests"), (431, "Request Header Fields Too Large"),
    (500, "Internal Server Error"), (501, "Not Implemented"), (502, "Bad Gateway"),
    (503, "Service Unavailable"), (504, "Gateway Timeout"), (507, "Insufficient Storage"),
  ]

  private static let transportHead = """
    \(imports(["{ setTimeout as delay } from 'node:timers/promises'"]))

    export type Method = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';

    export interface TransportRequest {
      method: Method;
      url: string;
      query?: object;
      body?: unknown;
      headers: Record<string, string>;
      timeoutMs?: number;
    }

    export interface TransportResponse {
      status: number;
      statusText: string;
      headers: Record<string, string>;
      body: unknown;
      /** Milliseconds from sending the request to reading the whole body. */
      elapsedMs: number;
    }

    export interface Transport {
      send(request: TransportRequest): Promise<TransportResponse>;
    }

    /** Status texts, for messages. The server's own text wins when it sends one. */
    export const STATUS_TEXT: Record<number, string> = {

    """

  private static let transportTail = """
    };

    export class TransportError extends Error {
      constructor(
        message: string,
        readonly code: string,
        readonly request: TransportRequest,
      ) {
        super(message);
        this.name = 'TransportError';
      }
    }

    export type ErrorKind =
      | 'redirect'
      | 'invalid'
      | 'auth'
      | 'missing'
      | 'conflict'
      | 'throttled'
      | 'server'
      | 'unknown';

    /** What a status means for the caller, which decides the error the client throws. */
    export function kindOf(status: number): ErrorKind {
      if (status >= 300 && status < 400) return 'redirect';
      if (status === 401 || status === 403) return 'auth';
      if (status === 404 || status === 410) return 'missing';
      if (status === 409 || status === 412 || status === 423) return 'conflict';
      if (status === 429) return 'throttled';
      if (status >= 500) return 'server';
      if (status >= 400) return 'invalid';
      return 'unknown';
    }

    /** The rate limit the server reports on every response, when it reports one. */
    export interface RateLimit {
      limit: number;
      remaining: number;
      resetAt: Date;
    }

    export function rateLimitOf(headers: Record<string, string>): RateLimit | undefined {
      const limit = Number(headers['x-ratelimit-limit']);
      const remaining = Number(headers['x-ratelimit-remaining']);
      const reset = Number(headers['x-ratelimit-reset']);
      if (![limit, remaining, reset].every(Number.isFinite)) return undefined;
      return { limit, remaining, resetAt: new Date(reset * 1000) };
    }

    /** The `next` cursor of a Link header, for the endpoints that page that way. */
    export function nextLink(headers: Record<string, string>): string | undefined {
      const link = headers.link;
      if (!link) return undefined;
      for (const part of link.split(',')) {
        const match = /<([^>]+)>;\\s*rel="next"/.exec(part.trim());
        if (match) return match[1];
      }
      return undefined;
    }

    /** Headers that must never reach a log line. */
    const SECRET_HEADERS = new Set(['authorization', 'cookie', 'set-cookie', 'x-api-key']);

    /** A copy of the headers that is safe to log. */
    export function redact(headers: Record<string, string>): Record<string, string> {
      const safe: Record<string, string> = {};
      for (const [name, value] of Object.entries(headers)) {
        safe[name] = SECRET_HEADERS.has(name.toLowerCase()) ? '<redacted>' : value;
      }
      return safe;
    }

    /** Lower-cases header names, later values winning, so lookups need no care. */
    export function mergeHeaders(...sets: Array<Record<string, string> | undefined>) {
      const merged: Record<string, string> = {};
      for (const set of sets) {
        for (const [name, value] of Object.entries(set ?? {})) merged[name.toLowerCase()] = value;
      }
      return merged;
    }

    /** Wraps a transport and keeps every exchange, for debugging a live session. */
    export class RecordingTransport implements Transport {
      readonly exchanges: Array<{ request: TransportRequest; response?: TransportResponse; error?: unknown }> = [];

      constructor(private inner: Transport, private limit = 200) {}

      async send(request: TransportRequest): Promise<TransportResponse> {
        const entry: (typeof this.exchanges)[number] = {
          request: { ...request, headers: redact(request.headers) },
        };
        this.exchanges.push(entry);
        if (this.exchanges.length > this.limit) this.exchanges.shift();
        try {
          entry.response = await this.inner.send(request);
          return entry.response;
        } catch (error) {
          entry.error = error;
          throw error;
        }
      }
    }

    /** Sends requests with fetch. Knows nothing about retries: the client does. */
    export class FetchTransport implements Transport {
      constructor(private fetchImpl: typeof fetch = fetch) {}

      async send(request: TransportRequest): Promise<TransportResponse> {
        const started = performance.now();
        const controller = new AbortController();
        const timer = request.timeoutMs
          ? setTimeout(() => controller.abort(), request.timeoutMs)
          : undefined;
        try {
          const response = await this.fetchImpl(withQuery(request.url, request.query), {
            method: request.method,
            headers: request.headers,
            body: request.body === undefined ? undefined : JSON.stringify(request.body),
            signal: controller.signal,
          });
          const text = await response.text();
          return {
            status: response.status,
            statusText: response.statusText || STATUS_TEXT[response.status] || '',
            headers: Object.fromEntries(response.headers.entries()),
            body: text ? parseBody(text, response.headers.get('content-type')) : undefined,
            elapsedMs: performance.now() - started,
          };
        } catch (error) {
          throw toTransportError(error, request);
        } finally {
          clearTimeout(timer);
        }
      }
    }

    /** A transport that answers from a script, for tests. */
    export class ScriptedTransport implements Transport {
      readonly sent: TransportRequest[] = [];

      constructor(private answers: Array<Partial<TransportResponse> | Error>) {}

      async send(request: TransportRequest): Promise<TransportResponse> {
        this.sent.push(request);
        const next = this.answers.shift();
        if (next === undefined) throw new Error('ScriptedTransport ran out of answers');
        if (next instanceof Error) throw next;
        await delay(0);
        return { status: 200, statusText: 'OK', headers: {}, body: undefined, elapsedMs: 1, ...next };
      }
    }

    function withQuery(url: string, query?: object): string {
      if (!query) return url;
      const params = new URLSearchParams();
      for (const [key, value] of Object.entries(query)) {
        if (value !== undefined && value !== null) params.set(key, String(value));
      }
      const text = params.toString();
      return text ? `${url}?${text}` : url;
    }

    function parseBody(text: string, type: string | null): unknown {
      if (type?.includes('application/json')) return JSON.parse(text);
      return text;
    }

    function toTransportError(error: unknown, request: TransportRequest): TransportError {
      if (error instanceof TransportError) return error;
      if (error instanceof DOMException && error.name === 'AbortError') {
        return new TransportError(`timed out after ${request.timeoutMs} ms`, 'ETIMEDOUT', request);
      }
      const code = (error as { cause?: { code?: string } }).cause?.code ?? 'EUNKNOWN';
      return new TransportError(String(error), code, request);
    }

    """
}
