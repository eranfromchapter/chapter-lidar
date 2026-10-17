// The station access token held in the encrypted Auth.js session cookie (httpOnly, JWE with
// AUTH_SECRET). It is read and refreshed on the server only; it never reaches a client
// component, page props, a JS-readable cookie or a log line.
//
// Roles, user id and display name are read from the access token's claims. The token is not
// verified here: it came straight from the Entra token endpoint over TLS in a server-side code
// exchange, and the station verifies it (signature, issuer, audience, tenant) on every call.
// The claims only gate the UI.

import { rolesFrom, type StationRole } from "./roles";

export interface StationTokenSet {
  /** Bearer token for the station API. Secret. */
  readonly accessToken: string;
  /** Expiry of the access token, epoch seconds. */
  readonly expiresAt: number;
  /** Entra refresh token. Secret. */
  readonly refreshToken?: string;
  /** Entra object id (`oid`). */
  readonly userId: string;
  /** Display name: `name`, else `preferred_username`, else the object id. */
  readonly name: string;
  readonly roles: readonly StationRole[];
}

/** Refresh this long before expiry, so a request never starts with a token about to lapse. */
export const REFRESH_MARGIN_SECONDS = 5 * 60;

/** Decodes the payload of a JWT without verifying it. Returns undefined when malformed. */
export function decodeJwtPayload(token: string): Record<string, unknown> | undefined {
  const parts = token.split(".");
  if (parts.length !== 3 || parts[1] === undefined || parts[1].length === 0) {
    return undefined;
  }
  try {
    const base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
    const binary = atob(padded);
    const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
    const payload: unknown = JSON.parse(new TextDecoder().decode(bytes));
    return typeof payload === "object" && payload !== null && !Array.isArray(payload)
      ? (payload as Record<string, unknown>)
      : undefined;
  } catch {
    return undefined;
  }
}

function stringClaim(payload: Record<string, unknown>, name: string): string | undefined {
  const found = payload[name];
  return typeof found === "string" && found.length > 0 ? found : undefined;
}

export class TokenError extends Error {
  constructor(
    /** Safe, token-free reason for logs. */
    readonly reason: string,
  ) {
    super(reason);
    this.name = "TokenError";
  }
}

/**
 * Builds the token set from an access token and its metadata. Throws TokenError when the access
 * token has no usable claims.
 */
export function tokenSetFrom(input: {
  accessToken: string | undefined;
  expiresAt?: number | undefined;
  expiresIn?: number | undefined;
  refreshToken?: string | undefined;
  now?: number;
}): StationTokenSet {
  const { accessToken } = input;
  if (accessToken === undefined || accessToken.length === 0) {
    throw new TokenError("no station access token was issued");
  }
  const payload = decodeJwtPayload(accessToken);
  if (payload === undefined) {
    throw new TokenError("station access token is not a JWT");
  }
  const userId = stringClaim(payload, "oid");
  if (userId === undefined) {
    throw new TokenError("station access token has no oid claim");
  }
  const now = input.now ?? Math.floor(Date.now() / 1000);
  const claimExp = typeof payload.exp === "number" ? payload.exp : undefined;
  const expiresAt =
    input.expiresAt ?? (input.expiresIn !== undefined ? now + input.expiresIn : claimExp);
  if (expiresAt === undefined || !Number.isFinite(expiresAt)) {
    throw new TokenError("station access token has no expiry");
  }
  const name = (
    stringClaim(payload, "name") ??
    stringClaim(payload, "preferred_username") ??
    userId
  ).slice(0, 200);
  return {
    accessToken,
    expiresAt: Math.floor(expiresAt),
    ...(input.refreshToken === undefined ? {} : { refreshToken: input.refreshToken }),
    userId,
    name,
    roles: rolesFrom(payload.roles),
  };
}

/** Reads a token set stored in the session JWT; undefined when absent or malformed. */
export function readTokenSet(value: unknown): StationTokenSet | undefined {
  if (typeof value !== "object" || value === null) {
    return undefined;
  }
  const record = value as Record<string, unknown>;
  const { accessToken, expiresAt, refreshToken, userId, name, roles } = record;
  if (
    typeof accessToken !== "string" ||
    accessToken.length === 0 ||
    typeof expiresAt !== "number" ||
    typeof userId !== "string" ||
    typeof name !== "string"
  ) {
    return undefined;
  }
  return {
    accessToken,
    expiresAt,
    ...(typeof refreshToken === "string" && refreshToken.length > 0 ? { refreshToken } : {}),
    userId,
    name,
    roles: rolesFrom(roles),
  };
}

/** True when the access token is expired or expires within `marginSeconds`. */
export function needsRefresh(
  set: Pick<StationTokenSet, "expiresAt">,
  marginSeconds: number = REFRESH_MARGIN_SECONDS,
  now: number = Math.floor(Date.now() / 1000),
): boolean {
  return set.expiresAt - marginSeconds <= now;
}

export interface RefreshSettings {
  readonly issuer: string;
  readonly clientId: string;
  readonly clientSecret: string;
  readonly stationScope: string;
}

const tokenEndpoints = new Map<string, string>();

async function tokenEndpoint(issuer: string, fetchImpl: typeof fetch): Promise<string> {
  const cached = tokenEndpoints.get(issuer);
  if (cached !== undefined) {
    return cached;
  }
  const discovery = `${issuer.replace(/\/+$/, "")}/.well-known/openid-configuration`;
  const response = await fetchImpl(discovery, {
    cache: "no-store",
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) {
    throw new TokenError(`openid configuration returned ${response.status}`);
  }
  const body: unknown = await response.json();
  const endpoint =
    typeof body === "object" && body !== null
      ? (body as Record<string, unknown>).token_endpoint
      : undefined;
  if (typeof endpoint !== "string" || !endpoint.startsWith("https://")) {
    throw new TokenError("openid configuration has no https token_endpoint");
  }
  tokenEndpoints.set(issuer, endpoint);
  return endpoint;
}

/**
 * Gets a new station access token with the refresh token. Throws TokenError (with a token-free
 * reason) when there is no refresh token or Entra refuses it.
 */
export async function refreshTokenSet(
  current: StationTokenSet,
  settings: RefreshSettings,
  fetchImpl: typeof fetch = fetch,
): Promise<StationTokenSet> {
  if (current.refreshToken === undefined) {
    throw new TokenError("no refresh token");
  }
  const endpoint = await tokenEndpoint(settings.issuer, fetchImpl);
  const response = await fetchImpl(endpoint, {
    method: "POST",
    cache: "no-store",
    signal: AbortSignal.timeout(10_000),
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      client_id: settings.clientId,
      client_secret: settings.clientSecret,
      refresh_token: current.refreshToken,
      scope: `${settings.stationScope} offline_access`,
    }),
  });
  const body: unknown = await response.json().catch(() => undefined);
  const record = typeof body === "object" && body !== null ? (body as Record<string, unknown>) : {};
  if (!response.ok) {
    const code = typeof record.error === "string" ? record.error : "unknown_error";
    throw new TokenError(`refresh refused (${response.status} ${code})`);
  }
  const accessToken = typeof record.access_token === "string" ? record.access_token : undefined;
  const rawExpiresIn = record.expires_in;
  const expiresIn =
    typeof rawExpiresIn === "number"
      ? rawExpiresIn
      : typeof rawExpiresIn === "string" && /^\d+$/.test(rawExpiresIn)
        ? Number(rawExpiresIn)
        : undefined;
  const refreshToken =
    typeof record.refresh_token === "string" ? record.refresh_token : current.refreshToken;
  return tokenSetFrom({ accessToken, expiresIn, refreshToken });
}
