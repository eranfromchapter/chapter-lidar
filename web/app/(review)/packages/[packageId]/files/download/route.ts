// GET /packages/{packageId}/files/download?path=<manifest path>
//
// bim and admin only. Asks the station for a 10-minute read-only link (getFileDownloadLink) at
// the moment the user clicks, then redirects the browser to it. The link is never rendered into
// a page, cached or logged. Also serves the sealed manifest (its path, web-review §9.1 F).

import {
  authorizeFileRequest,
  fileErrorResponse,
  isFollowableLink,
  linkRedirect,
  textResponse,
} from "@/lib/file-access";

export const dynamic = "force-dynamic";

export async function GET(
  request: Request,
  context: { params: Promise<{ packageId: string }> },
): Promise<Response> {
  const { packageId } = await context.params;
  const access = await authorizeFileRequest(request, packageId);
  if (!access.ok) {
    return access.response;
  }
  let url: string;
  try {
    const link = await access.session.station.getFileDownloadLink(packageId, access.path);
    url = link.url;
  } catch (error) {
    return fileErrorResponse(error);
  }
  if (!isFollowableLink(url)) {
    return textResponse(502, "The station returned an unusable download link.");
  }
  return linkRedirect(url);
}
