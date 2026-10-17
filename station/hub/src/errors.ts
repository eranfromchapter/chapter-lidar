// HUB failures and the error object stored in hub_publications.error.
//
// Rules: a HubError message is written by the station (fixed text plus numbers), never a raw
// HUB response body, header or URL query, and never the service credential. The optional
// hubMessage is a short excerpt of the HUB's own error text (a JSON "message", "error", "title"
// or "detail" string) after scrubbing the credential and anything token-shaped.

export type HubFailure =
  | "timeout"
  | "network"
  | "redirect"
  | "http_status"
  | "too_large"
  | "invalid_json"
  | "unexpected_shape"
  | "request"
  | "verification"
  | "conflict"
  | "integrity";

/** The HUB did not answer, answered with something unusable, or a publish rule failed. */
export class HubError extends Error {
  constructor(
    readonly failure: HubFailure,
    /** Station-written, credential-free description. */
    message: string,
    /** HTTP status of the HUB answer, when there was one. */
    readonly status?: number,
    /** Scrubbed excerpt of the HUB's own error text. */
    readonly hubMessage?: string,
    /** Retry-After of a 429/503 answer, in milliseconds. */
    readonly retryAfterMs?: number,
  ) {
    super(message);
    this.name = "HubError";
  }

  /**
   * Worth another attempt: network errors, timeouts, 429, 5xx, and a failed post-upload
   * verification. Other 4xx, redirects, unexpected shapes and publish-rule failures are not.
   */
  get retryable(): boolean {
    switch (this.failure) {
      case "timeout":
      case "network":
      case "verification":
        return true;
      case "http_status":
        return this.status === 429 || (this.status !== undefined && this.status >= 500);
      default:
        return false;
    }
  }
}

/** The error stored in hub_publications.error: { status, message }. */
export interface PublicationError {
  /** HTTP status of the HUB answer, or null when there was none. */
  readonly status: number | null;
  readonly message: string;
}

export const MAX_ERROR_MESSAGE = 500;

const JWT_PATTERN = /eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]*/g;
const BEARER_PATTERN = /\b(Bearer|Basic)\s+\S+/gi;
const QUERY_PATTERN = /(https?:\/\/[^\s?#"']+)\?[^\s"']*/gi;
const KEY_VALUE_PATTERN =
  /\b(AccountKey|SharedAccessSignature|SharedAccessKey|Password|Pwd|sig|token|access_token|client_secret|api[_-]?key)=[^;&\s"']*/gi;

/**
 * Removes secrets from text: every occurrence of the given secrets (the HUB credential), JWTs,
 * bearer/basic values, URL query strings and key=value secrets. Collapses whitespace and
 * truncates to max characters.
 */
export function scrub(
  text: string,
  secrets: readonly string[] = [],
  max = MAX_ERROR_MESSAGE,
): string {
  let out = text;
  for (const secret of secrets) {
    if (secret.length > 0) {
      out = out.split(secret).join("[redacted]");
    }
  }
  out = out
    .replace(JWT_PATTERN, "[redacted]")
    .replace(BEARER_PATTERN, (_match, scheme: string) => `${scheme} [redacted]`)
    .replace(QUERY_PATTERN, (_match, base: string) => `${base}?[redacted]`)
    .replace(KEY_VALUE_PATTERN, (_match, name: string) => `${name}=[redacted]`)
    .replace(/\s+/g, " ")
    .trim();
  return out.length <= max ? out : `${out.slice(0, max - 1)}…`;
}

/** The stored error of a failure: HubError status and message (with the HUB excerpt). */
export function publicationErrorOf(
  error: unknown,
  secrets: readonly string[] = [],
): PublicationError {
  if (error instanceof HubError) {
    const text =
      error.hubMessage === undefined ? error.message : `${error.message}: ${error.hubMessage}`;
    return { status: error.status ?? null, message: scrub(text, secrets) };
  }
  // Not a HUB answer (a bug or a storage failure): keep the type and the scrubbed message only.
  const message =
    error instanceof Error ? `${error.name}: ${error.message}` : "unknown publish failure";
  return { status: null, message: scrub(message, secrets) };
}
