import { notFound } from "next/navigation";
import { SIGN_IN_PATH } from "@/lib/auth-redirect";
import { StationError } from "@/lib/station";
import { Notice } from "./Notice";

/**
 * Turns a station error on a page into what the user sees (web-review §6.8): 404 is the
 * not-found page, 401, 403 and an unreachable station are explained in place. Anything else is
 * rethrown to the error page. Never substitutes data. `retryHref` is the page's own URL.
 */
export function stationProblem(error: unknown, retryHref = "/") {
  if (!(error instanceof StationError)) {
    throw error;
  }
  if (error.status === 404) {
    notFound();
  }
  if (error.status === 403) {
    return (
      <Notice role="alert" title="No access">
        Your account does not have a station role that can open this.
      </Notice>
    );
  }
  if (error.status === 401) {
    return (
      <Notice
        role="alert"
        title="Sign in again"
        action={{ label: "Sign in again", href: SIGN_IN_PATH }}
      >
        The station did not accept your sign-in.
      </Notice>
    );
  }
  return (
    <Notice
      role="alert"
      title="The station could not answer"
      action={{ label: "Try again", href: retryHref }}
    >
      The data could not be loaded from the station (status {error.status}). Try again in a moment.
    </Notice>
  );
}

/** Shown to signed-in users without any station role. */
export function NoStationRole() {
  return (
    <Notice role="alert" title="No access">
      Your account has no Chapter Capture station role. Ask a Chapter admin for the bim role to
      review packages.
    </Notice>
  );
}
