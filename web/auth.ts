// Auth.js (next-auth v5) with the Microsoft Entra ID provider.
//
// - Lazy configuration: nothing is read at import or build time. A request with missing or
//   invalid settings throws ConfigError (callers fail closed with the configuration page).
// - The sign-in requests the station API scope, so the access token Entra returns is a station
//   token. It is stored, with the refresh token, only inside the encrypted session JWT
//   (httpOnly cookie) and refreshed server side.
// - The session object (what /api/auth/session returns to the browser) carries the display name
//   and roles only, never a token.
// - The profile is built from the ID token claims. The provider's default Graph photo request
//   is replaced, so the station token is never sent to another API.
// - Sign-in and sign-in errors use the review screen's own page (app/sign-in), not the Auth.js
//   default page.

import NextAuth, { type NextAuthConfig } from "next-auth";
import MicrosoftEntraID from "next-auth/providers/microsoft-entra-id";
import { SIGN_IN_PATH } from "./lib/auth-redirect";
import { readAuthConfig, type AuthConfig } from "./lib/config";
import {
  needsRefresh,
  readTokenSet,
  refreshTokenSet,
  TokenError,
  tokenSetFrom,
  type StationTokenSet,
} from "./lib/token";

/** A session lasts one working day; the user signs in again after that. */
export const SESSION_MAX_AGE_SECONDS = 12 * 60 * 60;

function reason(error: unknown): string {
  return error instanceof TokenError ? error.reason : "unexpected error";
}

export function buildAuthConfig(config: AuthConfig): NextAuthConfig {
  return {
    secret: config.secret,
    session: { strategy: "jwt", maxAge: SESSION_MAX_AGE_SECONDS },
    pages: { signIn: SIGN_IN_PATH, error: SIGN_IN_PATH },
    providers: [
      MicrosoftEntraID({
        clientId: config.clientId,
        clientSecret: config.clientSecret,
        issuer: config.issuer,
        authorization: {
          params: { scope: `openid profile email offline_access ${config.stationScope}` },
        },
        profile(profile) {
          const name =
            typeof profile.name === "string" && profile.name.length > 0
              ? profile.name
              : typeof profile.preferred_username === "string"
                ? profile.preferred_username
                : profile.sub;
          return {
            id: profile.sub,
            name,
            email: typeof profile.email === "string" ? profile.email : null,
            image: null,
          };
        },
      }),
    ],
    callbacks: {
      async jwt({ token, account }) {
        if (account) {
          // Sign-in: keep only what the server needs. No ID token, no profile photo.
          try {
            const station = tokenSetFrom({
              accessToken: account.access_token,
              expiresAt: account.expires_at,
              expiresIn: account.expires_in,
              refreshToken: account.refresh_token,
            });
            return { sub: token.sub ?? station.userId, station };
          } catch (error) {
            console.error(`[auth] sign-in rejected: ${reason(error)}`);
            return null;
          }
        }
        const station = readTokenSet(token.station);
        if (station === undefined) {
          return null;
        }
        if (!needsRefresh(station)) {
          return token;
        }
        try {
          const refreshed: StationTokenSet = await refreshTokenSet(station, config);
          return { ...token, station: refreshed };
        } catch (error) {
          // Signed out: the user is sent to sign-in again.
          console.warn(`[auth] station token refresh failed: ${reason(error)}`);
          return null;
        }
      },
      async session({ session, token }) {
        const station = readTokenSet(token.station);
        const visible = {
          expires: session.expires,
          user: { name: station?.name ?? null },
          roles: station?.roles ?? [],
        };
        return visible;
      },
    },
  };
}

export const { handlers, auth, signIn } = NextAuth(() => buildAuthConfig(readAuthConfig()));
