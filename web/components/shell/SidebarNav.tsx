"use client";

// The sidebar's main navigation (web-review §3.1). A client component only to read the current
// path for aria-current; the items come from the server (role and configuration decide them).

import { usePathname } from "next/navigation";
import {
  DecisionLogIcon,
  IntakeGuideIcon,
  PackagesIcon,
  ProjectsIcon,
} from "@/components/hub/icons";

export type NavItemId = "projects" | "packages" | "decisions" | "guide";

export interface NavItem {
  readonly id: NavItemId;
  readonly label: string;
  readonly href: string;
  readonly external?: boolean;
}

/** Which item a path belongs to; the intake guide is never current. */
export function activeItem(pathname: string): NavItemId | undefined {
  if (pathname === "/packages") {
    return "packages";
  }
  if (pathname === "/decisions") {
    return "decisions";
  }
  if (pathname === "/" || pathname.startsWith("/projects/") || pathname.startsWith("/packages/")) {
    return "projects";
  }
  return undefined;
}

const ICONS = {
  projects: ProjectsIcon,
  packages: PackagesIcon,
  decisions: DecisionLogIcon,
  guide: IntakeGuideIcon,
} as const;

export function SidebarNav({ items }: { readonly items: readonly NavItem[] }) {
  const pathname = usePathname() ?? "";
  const active = activeItem(pathname);
  return (
    <nav aria-label="Main" className="sidebar__nav">
      {items.map((item) => {
        const Icon = ICONS[item.id];
        const current = item.id === active && item.external !== true;
        return (
          <a
            key={item.id}
            href={item.href}
            className="sidebar__link"
            aria-current={current ? "page" : undefined}
            {...(item.external === true ? { target: "_blank", rel: "noopener noreferrer" } : {})}
          >
            <Icon size={18} />
            {item.label}
            {item.external === true ? (
              <span className="visually-hidden"> (opens in a new tab)</span>
            ) : null}
          </a>
        );
      })}
    </nav>
  );
}
