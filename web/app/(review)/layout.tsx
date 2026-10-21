// The app shell of every signed-in review page (web-review §3): the ink sidebar and, beside it,
// the page (each page renders its own topbar and main). Without a session the page itself
// redirects to sign-in with its return path; the shell then renders nothing around it.

import type { ReactNode } from "react";
import { Sidebar } from "@/components/shell/Sidebar";
import { intakeGuideUrl } from "@/lib/links";
import { getViewerSession } from "@/lib/viewer";

export const dynamic = "force-dynamic";

export default async function ReviewLayout({ children }: { readonly children: ReactNode }) {
  const session = await getViewerSession();
  if (session === null) {
    return <>{children}</>;
  }
  return (
    <div className="shell">
      <Sidebar viewer={session.viewer} intakeGuideUrl={intakeGuideUrl()} />
      <div className="shell__body">{children}</div>
    </div>
  );
}
