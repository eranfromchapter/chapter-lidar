// Shared checks of the download route handlers (files, plan preview, spatial report,
// verdict.json). All are bim/admin only and need a signed-in session and a well-formed package
// id (and, for files, a path). The station enforces the same roles; this refuses early so
// capture users never trigger a link (web-review §6.6, §10).

import "server-only";
import { isPackageId, LIMITS } from "./decisions";
import { StationError } from "./station";
import { getViewerSession, type ViewerSession } from "./viewer";

export const NO_STORE = { "cache-control": "no-store" } as const;

export function textResponse(status: number, message: string): Response {
  return new Response(message, {
    status,
    headers: { "content-type": "text/plain; charset=utf-8", ...NO_STORE },
  });
}

export type PackageAccess =
  | { readonly ok: true; readonly session: ViewerSession }
  | { readonly ok: false; readonly response: Response };

export type FileAccess =
  | { readonly ok: true; readonly session: ViewerSession; readonly path: string }
  | { readonly ok: false; readonly response: Response };

/** Session, bim/admin role and package id, before any station call. */
export async function authorizePackageRequest(packageId: string): Promise<PackageAccess> {
  const session = await getViewerSession();
  if (session === null) {
    return { ok: false, response: textResponse(401, "Sign in to download files.") };
  }
  if (!session.viewer.canReview) {
    return {
      ok: false,
      response: textResponse(403, "Only BIM operators and admins can download package files."),
    };
  }
  if (!isPackageId(packageId)) {
    return { ok: false, response: textResponse(404, "No such package.") };
  }
  return { ok: true, session };
}

/** As authorizePackageRequest, plus the file path of ?path=. */
export async function authorizeFileRequest(
  request: Request,
  packageId: string,
): Promise<FileAccess> {
  const access = await authorizePackageRequest(packageId);
  if (!access.ok) {
    return access.response.status === 404
      ? { ok: false, response: textResponse(404, "No such package file.") }
      : access;
  }
  const path = new URL(request.url).searchParams.get("path") ?? "";
  if (path.length === 0 || path.length > LIMITS.path) {
    return { ok: false, response: textResponse(404, "No such package file.") };
  }
  return { ok: true, session: access.session, path };
}

/** Plain answer for a station error on a file route. Never includes the link or token. */
export function fileErrorResponse(error: unknown): Response {
  if (!(error instanceof StationError)) {
    throw error;
  }
  switch (error.status) {
    case 401:
      return textResponse(401, "The station did not accept your sign-in. Sign in again.");
    case 403:
      return textResponse(403, "Your account cannot download package files.");
    case 404:
      return textResponse(404, "No such package file.");
    case 409:
      return textResponse(409, "This file has no verified upload yet, so it cannot be downloaded.");
    default:
      return textResponse(502, "The station could not issue a download link. Try again.");
  }
}

/** Only http(s) links are followed (Azure Blob, or Azurite on the local stack). */
export function isFollowableLink(url: string): boolean {
  try {
    const parsed = new URL(url);
    return parsed.protocol === "https:" || parsed.protocol === "http:";
  } catch {
    return false;
  }
}

/** 303 to a short-lived link: never cached, never sent on as a referrer. */
export function linkRedirect(url: string): Response {
  return new Response(null, {
    status: 303,
    headers: {
      location: url,
      "cache-control": "no-store",
      "referrer-policy": "no-referrer",
    },
  });
}
