// GET /packages/{packageId}/verdict.json
//
// bim and admin only (web-review §4, §10). The station's verdict (getVerdict) as a file:
// verdict-r{revision}.json, JSON with nosniff and a closed content security policy, never
// cached. 404 "No verdict yet." while the checks have not finished.

import { authorizePackageRequest, NO_STORE, textResponse } from "@/lib/file-access";
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
  let verdict;
  try {
    verdict = await access.session.station.getVerdict(packageId);
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
        return textResponse(404, "No such package.");
      default:
        return textResponse(502, "The station could not answer. Try again.");
    }
  }
  if (verdict === null) {
    return textResponse(404, "No verdict yet.");
  }
  return new Response(`${JSON.stringify(verdict, null, 2)}\n`, {
    status: 200,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "content-disposition": `attachment; filename="verdict-r${verdict.revision}.json"`,
      "x-content-type-options": "nosniff",
      "content-security-policy": "default-src 'none'",
      ...NO_STORE,
    },
  });
}
