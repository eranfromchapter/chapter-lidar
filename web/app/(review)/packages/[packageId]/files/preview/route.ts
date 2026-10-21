// GET /packages/{packageId}/files/preview?path=<manifest path of a plan PNG>
//
// Inline plan preview for bim and admin. The server gets a short-lived link from the station
// (getFileDownloadLink), reads the PNG itself and streams it back, so the signed link never
// reaches the browser. Only verified plan_png files of the package, up to PREVIEW_MAX_BYTES.

import {
  authorizeFileRequest,
  fileErrorResponse,
  isFollowableLink,
  textResponse,
} from "@/lib/file-access";

export const dynamic = "force-dynamic";

/** Plan PNGs are small; anything larger is not previewed (download it instead). */
const PREVIEW_MAX_BYTES = 25 * 1000 * 1000;

export async function GET(
  request: Request,
  context: { params: Promise<{ packageId: string }> },
): Promise<Response> {
  const { packageId } = await context.params;
  const access = await authorizeFileRequest(request, packageId);
  if (!access.ok) {
    return access.response;
  }
  const { station } = access.session;
  let url: string;
  try {
    const pkg = await station.getPackage(packageId);
    const file = pkg.files.find((item) => item.path === access.path);
    if (file === undefined || file.role !== "plan_png" || file.status !== "verified") {
      return textResponse(404, "No plan preview for this file.");
    }
    if (file.bytes > PREVIEW_MAX_BYTES) {
      return textResponse(413, "This plan is too large to preview. Download it instead.");
    }
    url = (await station.getFileDownloadLink(packageId, access.path)).url;
  } catch (error) {
    return fileErrorResponse(error);
  }
  if (!isFollowableLink(url)) {
    return textResponse(502, "The station returned an unusable link.");
  }
  let blob: Response;
  try {
    blob = await fetch(url, { cache: "no-store", signal: AbortSignal.timeout(20_000) });
  } catch {
    return textResponse(502, "The plan could not be read from storage.");
  }
  if (!blob.ok || blob.body === null) {
    return textResponse(502, "The plan could not be read from storage.");
  }
  return new Response(blob.body, {
    status: 200,
    headers: {
      "content-type": "image/png",
      "cache-control": "private, no-store",
      "x-content-type-options": "nosniff",
      "content-security-policy": "default-src 'none'",
    },
  });
}
