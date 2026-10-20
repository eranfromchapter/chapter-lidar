// What the proxy does with a request that has no session, and where sign-in returns to.

import { NextResponse, type NextRequest } from "next/server";

/** The review screen's sign-in page (app/sign-in), also Auth.js's signIn and error page. */
export const SIGN_IN_PATH = "/sign-in";

/** Auth.js routes stay reachable without a session (sign-in, callback, sign-out). */
export function isAuthRoute(pathname: string): boolean {
  return pathname === "/api/auth" || pathname.startsWith("/api/auth/");
}

/** The sign-in page stays reachable without a session; it shows no data. */
export function isSignInPage(pathname: string): boolean {
  return pathname === SIGN_IN_PATH;
}

/**
 * The path on this site to return to after sign-in, from a callbackUrl that is a path or an
 * absolute URL (Auth.js passes absolute ones). Only the path and query are kept, so the result
 * never leaves this site; anything unreadable, another scheme or the sign-in page itself is "/".
 */
export function safeReturnPath(value: string | undefined): string {
  if (value === undefined) {
    return "/";
  }
  let url: URL;
  try {
    url = new URL(value, "http://return.invalid");
  } catch {
    return "/";
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    return "/";
  }
  if (url.pathname.startsWith("//") || isSignInPage(url.pathname)) {
    return "/";
  }
  return `${url.pathname}${url.search}`;
}

/**
 * GET and HEAD are redirected to sign-in with the current path as callbackUrl; anything else
 * (server actions, other methods) is refused with 401.
 */
export function unauthenticatedResponse(request: NextRequest): Response {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Sign in to continue.", {
      status: 401,
      headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" },
    });
  }
  const target = new URL(SIGN_IN_PATH, request.nextUrl.origin);
  target.searchParams.set("callbackUrl", `${request.nextUrl.pathname}${request.nextUrl.search}`);
  return NextResponse.redirect(target);
}
