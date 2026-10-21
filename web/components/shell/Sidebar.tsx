// The ink sidebar of every review page (web-review §3.1): the HUB "chapter" wordmark in white
// linked home, "Capture review", the main navigation by role, and the signed-in user.

import { Avatar } from "@/components/hub/Avatar";
import { canReview, roleLabel } from "@/lib/roles";
import type { Viewer } from "@/lib/viewer";
import { SidebarNav, type NavItem } from "./SidebarNav";

export interface SidebarProps {
  readonly viewer: Pick<Viewer, "name" | "roles">;
  /** INTAKE_GUIDE_URL; null hides "Intake guide". */
  readonly intakeGuideUrl: string | null;
}

/** The navigation items a viewer sees, in order. */
export function navItems(roles: Viewer["roles"], intakeGuideUrl: string | null): NavItem[] {
  const items: NavItem[] = [
    { id: "projects", label: "Projects", href: "/" },
    { id: "packages", label: "Packages", href: "/packages" },
  ];
  if (canReview(roles)) {
    items.push({ id: "decisions", label: "Decision log", href: "/decisions" });
  }
  if (intakeGuideUrl !== null) {
    items.push({ id: "guide", label: "Intake guide", href: intakeGuideUrl, external: true });
  }
  return items;
}

export function Sidebar({ viewer, intakeGuideUrl }: SidebarProps) {
  return (
    // The ink column runs the full height of the page; the sidebar in it stays in view.
    <div className="shell__side">
      <aside className="sidebar">
        <div className="sidebar__brand">
          <a href="/" className="sidebar__home" aria-label="Chapter capture review, home">
            {/* The HUB wordmark (public/brand/chapter-wordmark.svg), reversed to white by CSS. */}
            <img
              className="sidebar__wordmark"
              src="/brand/chapter-wordmark.svg"
              alt=""
              width={96}
              height={22}
            />
          </a>
          <span className="sidebar__label">Capture review</span>
        </div>
        <SidebarNav items={navItems(viewer.roles, intakeGuideUrl)} />
        <div className="sidebar__user">
          <Avatar name={viewer.name} size={34} />
          <div className="sidebar__user-text">
            <div className="sidebar__user-name" title={viewer.name}>
              {viewer.name}
            </div>
            <div className="sidebar__user-role">{roleLabel(viewer.roles)} · Entra</div>
          </div>
        </div>
      </aside>
    </div>
  );
}
