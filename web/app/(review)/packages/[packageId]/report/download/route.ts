// GET /packages/{packageId}/report/download
//
// bim and admin only (web-review §4, addendum D3). Asks the station for a 10-minute read-only
// link to its spatial report (getSpatialReportLink, GET /v1/packages/{id}/spatial-report) at
// the moment the user clicks, then redirects the browser to it. The link is never rendered into
// a page, cached or logged.

import {
  authorizePackageRequest,
  isFollowableLink,
  linkRedirect,
  textResponse,
} from "@/lib/file-access";
import { StationError } from "@/lib/station";

export const dynamic = "force-dynamic";

export async function GET(
  _request: Request,
  context: { params: Promise<{ packageId: string }> },
): Promise<Response> {
  const { packageId } = await context.params;
  const access = await authorizePackageRequest(packageId);
  if (!access.ok) {
    return access.response;
  }
  let url: string;
  try {
    url = (await access.session.station.getSpatialReportLink(packageId)).url;
  } catch (error) {
    if (!(error instanceof StationError)) {
      throw error;
    }
    switch (error.status) {
      case 401:
        return textResponse(401, "The station did not accept your sign-in. Sign in again.");
      case 403:
        return textResponse(403, "Your account cannot download package files.");
      case 404:
        return error.code === "report_not_ready"
          ? textResponse(404, "The spatial report is not ready yet.")
          : textResponse(404, "No such package.");
      default:
        return textResponse(502, "The station could not issue a download link. Try again.");
    }
  }
  if (!isFollowableLink(url)) {
    return textResponse(502, "The station returned an unusable download link.");
  }
  return linkRedirect(url);
}
