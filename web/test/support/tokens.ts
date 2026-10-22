// Unsigned test JWTs shaped like Entra station access tokens, and session cookies sealed the
// way Auth.js seals them. Test values only; nothing here is a real credential.

import { encode } from "next-auth/jwt";
import type { StationRole } from "@/lib/roles";

export const TEST_ENV = {
  AUTH_SECRET: "test-only-auth-secret-0123456789abcdef0123456789abcdef",
  AUTH_MICROSOFT_ENTRA_ID_ID: "00000000-0000-4000-8000-00000000c11e",
  AUTH_MICROSOFT_ENTRA_ID_SECRET: "test-only-client-value",
  AUTH_MICROSOFT_ENTRA_ID_ISSUER:
    "https://login.microsoftonline.com/00000000-0000-4000-8000-0000000000aa/v2.0",
  STATION_API_URL: "https://station.test",
  STATION_API_SCOPE: "api://00000000-0000-4000-8000-0000000000bb/access_as_user",
} as const;

function base64url(value: string): string {
  return Buffer.from(value, "utf8").toString("base64url");
}

/** An unsigned JWT with the given claims (the web app only reads claims; the station verifies). */
export function fakeAccessToken(claims: Record<string, unknown>): string {
  return `${base64url(JSON.stringify({ alg: "none", typ: "JWT" }))}.${base64url(
    JSON.stringify(claims),
  )}.c2lnbmF0dXJl`;
}

export const SESSION_COOKIE = "authjs.session-token";

/** A sealed Auth.js session cookie value holding a station token set. */
export async function sessionCookie(options: {
  roles: StationRole[];
  expiresInSeconds?: number;
  refreshToken?: string;
  /** Display name of the signed-in user (default "Casey Capture"). */
  name?: string;
  /** Session secret (default TEST_ENV.AUTH_SECRET). */
  secret?: string;
}): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const expiresAt = now + (options.expiresInSeconds ?? 3600);
  const name = options.name ?? "Casey Capture";
  const accessToken = fakeAccessToken({
    oid: "22222222-2222-4222-8222-222222222222",
    name,
    roles: options.roles,
    exp: expiresAt,
  });
  return encode({
    secret: options.secret ?? TEST_ENV.AUTH_SECRET,
    salt: SESSION_COOKIE,
    token: {
      sub: "22222222-2222-4222-8222-222222222222",
      station: {
        accessToken,
        expiresAt,
        ...(options.refreshToken === undefined ? {} : { refreshToken: options.refreshToken }),
        userId: "22222222-2222-4222-8222-222222222222",
        name,
        roles: options.roles,
      },
    },
  });
}
