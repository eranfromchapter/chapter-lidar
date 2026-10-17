// What the proxy does with a request that has no session.

import { NextResponse, type NextRequest } from "next/server";

export const SIGN_IN_PATH = "/api/auth/signin";

/** Auth.js routes stay reachable without a session (sign-in, callback, sign-out). */
export function isAuthRoute(pathname: string): boolean {
  return pathname === "/api/auth" || pathname.startsWith("/api/auth/");
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
