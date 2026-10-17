// Runs before every page, server action and route handler except the Auth.js routes and static
// assets (Next.js 16 "proxy", formerly middleware).
//
// - Missing or invalid settings: the configuration page (503), nothing else is served.
// - No session: GET and HEAD are redirected to sign-in; anything else gets 401
//   (lib/auth-redirect.ts).
// - Through the Auth.js wrapper, so a station token close to expiry is refreshed here and the
//   updated session cookie is set on the response.

import { NextResponse, type NextFetchEvent, type NextRequest } from "next/server";
import { auth } from "@/auth";
import { isAuthRoute, unauthenticatedResponse } from "@/lib/auth-redirect";
import { configProblems, failClosed } from "@/lib/config";

type SessionHandler = (request: NextRequest, event: NextFetchEvent) => Promise<Response | void>;

// With a lazy configuration, next-auth's auth(handler) resolves to the wrapped handler
// asynchronously (its type says it returns the handler directly); Promise.resolve covers both.
const withSession: Promise<SessionHandler> = Promise.resolve(
  auth((request) => {
    if (request.auth) {
      return NextResponse.next();
    }
    return unauthenticatedResponse(request);
  }) as unknown as SessionHandler | Promise<SessionHandler>,
);

export async function proxy(request: NextRequest, event: NextFetchEvent): Promise<Response> {
  if (isAuthRoute(request.nextUrl.pathname)) {
    return NextResponse.next();
  }
  const problems = configProblems();
  if (problems.length > 0) {
    return failClosed(problems);
  }
  const handler = await withSession;
  const response = await handler(request, event);
  return response ?? unauthenticatedResponse(request);
}

export const config = {
  matcher: ["/((?!api/auth|_next/static|_next/image|favicon.ico).*)"],
};
