import type { ReactNode } from "react";
import type { ProjectNavData } from "@/lib/projects";
import { roleLabel } from "@/lib/roles";
import type { Viewer } from "@/lib/viewer";
import { ProjectNav } from "./ProjectNav";

export interface PageFrameProps {
  readonly viewer: Viewer;
  /** Project list for the left column; null when the user has no station role. */
  readonly nav: ProjectNavData | null;
  readonly selectedDealId?: string;
  readonly children: ReactNode;
}

/** Header, project column and main column of every review page (screen-review). */
export function PageFrame({ viewer, nav, selectedDealId, children }: PageFrameProps) {
  return (
    <>
      <header className="app-header">
        <div className="app-header__brand">
          <a
            className="app-header__home"
            href="/"
            aria-label="Chapter Renovation, capture review home"
          >
            {/* The Chapter logo (public/brand), 1756:635; CSS sets the height. */}
            <img
              className="app-header__logo"
              src="/brand/chapter-logo.svg"
              width={94}
              height={34}
              alt="Chapter Renovation"
            />
          </a>
          <span className="app-header__title">Capture review</span>
        </div>
        <span className="app-header__user">
          {viewer.name} · {roleLabel(viewer.roles)}
        </span>
      </header>
      <div className="frame">
        {nav === null ? null : <ProjectNav data={nav} selectedDealId={selectedDealId} />}
        <main id="pkg" className="main">
          {children}
        </main>
      </div>
    </>
  );
}
