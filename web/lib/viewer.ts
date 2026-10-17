// The signed-in user and a station client bound to their token, for server components,
// server actions and route handlers.
//
// The station token is read from the encrypted session cookie on the server. The proxy
// refreshes it ahead of expiry and stores the new cookie; if it has nonetheless expired by the
// time this request reads it (for example the cookie of this very request is the old one), it is
// refreshed again in memory for this request only. A missing session, a malformed token or a
// refused refresh means "not signed in". Missing settings throw ConfigError (fail closed).

import "server-only";
import { getToken } from "next-auth/jwt";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { cache } from "react";
import { readAuthConfig, readStationConfig } from "./config";
import { canReview, type StationRole } from "./roles";
import { createStationClient, type StationClient } from "./station";
import { needsRefresh, readTokenSet, refreshTokenSet, TokenError } from "./token";

export interface Viewer {
  readonly name: string;
  readonly userId: string;
  readonly roles: readonly StationRole[];
  /** bim or admin: may download, preview plans and read or log modeling decisions. */
  readonly canReview: boolean;
}

export interface ViewerSession {
  readonly viewer: Viewer;
  readonly station: StationClient;
}

const SECURE_COOKIE_PATTERN = /(?:^|;\s*)__Secure-authjs\.session-token(?:\.\d+)?=/;

/** Seconds of validity a token must still have to be used without a refresh. */
const USE_MARGIN_SECONDS = 30;

export const getViewerSession = cache(async (): Promise<ViewerSession | null> => {
  const authConfig = readAuthConfig();
  const stationConfig = readStationConfig();
  const cookie = (await headers()).get("cookie") ?? "";
  if (cookie.length === 0) {
    return null;
  }
  const token = await getToken({
    // Only the cookie header: a bearer header is never accepted as a session here.
    req: { headers: { cookie } },
    secret: authConfig.secret,
    secureCookie: SECURE_COOKIE_PATTERN.test(cookie),
  });
  if (token === null) {
    return null;
  }
  let station = readTokenSet(token.station);
  if (station === undefined) {
    return null;
  }
  if (needsRefresh(station, USE_MARGIN_SECONDS)) {
    try {
      station = await refreshTokenSet(station, authConfig);
    } catch (error) {
      const reason = error instanceof TokenError ? error.reason : "unexpected error";
      console.warn(`[auth] station token refresh failed: ${reason}`);
      return null;
    }
  }
  return {
    viewer: {
      name: station.name,
      userId: station.userId,
      roles: station.roles,
      canReview: canReview(station.roles),
    },
    station: createStationClient({
      baseUrl: stationConfig.apiUrl,
      accessToken: station.accessToken,
    }),
  };
});

/** Sign-in URL that returns to `returnTo` (a path on this site). */
export function signInPath(returnTo: string): string {
  const safe = returnTo.startsWith("/") && !returnTo.startsWith("//") ? returnTo : "/";
  return `/api/auth/signin?callbackUrl=${encodeURIComponent(safe)}`;
}

/** The signed-in user, or a redirect to sign-in. For server components. */
export async function requireViewerSession(returnTo: string): Promise<ViewerSession> {
  const session = await getViewerSession();
  if (session === null) {
    redirect(signInPath(returnTo));
  }
  return session;
}
