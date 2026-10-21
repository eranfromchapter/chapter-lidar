// @vitest-environment jsdom
// The app shell (web-review §3, WR-AC2): the HUB "chapter" wordmark in white linked home,
// "Capture review", the navigation by role and path, the signed-in user, the topbar.

import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Topbar } from "@/components/shell/Topbar";
import { activeItem } from "@/components/shell/SidebarNav";
import { initials } from "@/components/hub/Avatar";
import type { StationRole } from "@/lib/roles";
import type { ViewerSession } from "@/lib/viewer";
import { drawnScenario } from "./support/scenarios";
import { createFakeStation, sessionFor } from "./support/station";

const state = vi.hoisted(() => ({
  session: null as ViewerSession | null,
  pathname: "/",
}));

vi.mock("@/lib/viewer", () => ({
  getViewerSession: async () => state.session,
  requireViewerSession: async () => state.session,
}));
vi.mock("next/navigation", async (original) => ({
  ...(await original<typeof import("next/navigation")>()),
  usePathname: () => state.pathname,
}));

const { default: ReviewLayout } = await import("@/app/(review)/layout");

async function renderShell(roles: StationRole[], name = "Dana BIM", pathname = "/") {
  state.session = sessionFor(roles, createFakeStation(drawnScenario(new Date())), name);
  state.pathname = pathname;
  return render(await ReviewLayout({ children: <p>Page body</p> }));
}

afterEach(() => {
  cleanup();
  vi.unstubAllEnvs();
  state.session = null;
});

describe("sidebar", () => {
  it("shows the HUB wordmark linked home and the Capture review label", async () => {
    const { container } = await renderShell(["bim"]);
    const home = screen.getByRole("link", { name: "Chapter capture review, home" });
    expect(home.getAttribute("href")).toBe("/");
    const wordmark = home.querySelector("img");
    expect(wordmark?.getAttribute("src")).toBe("/brand/chapter-wordmark.svg");
    expect(wordmark?.getAttribute("alt")).toBe("");
    expect(screen.getByText("Capture review")).toBeTruthy();
    expect(container.textContent).not.toMatch(/RENOVATION/i);
    expect(container.querySelector('img[src="/brand/chapter-logo.svg"]')).toBeNull();
    expect(screen.getByText("Page body")).toBeTruthy();
  });

  it("lists the navigation for bim and admin, and hides the decision log from capture", async () => {
    await renderShell(["bim"]);
    const nav = screen.getByRole("navigation", { name: "Main" });
    expect(
      within(nav)
        .getAllByRole("link")
        .map((link) => link.textContent),
    ).toEqual(["Projects", "Packages", "Decision log"]);
    cleanup();
    await renderShell(["capture"], "Casey Capture");
    const captureNav = screen.getByRole("navigation", { name: "Main" });
    expect(within(captureNav).queryByRole("link", { name: "Decision log" })).toBeNull();
    expect(within(captureNav).getAllByRole("link")).toHaveLength(2);
  });

  it("adds the intake guide, in a new tab, only when it is configured", async () => {
    vi.stubEnv("INTAKE_GUIDE_URL", "https://hub.example/guides/intake");
    await renderShell(["bim"]);
    const guide = screen.getByRole("link", { name: /Intake guide/ });
    expect(guide.getAttribute("href")).toBe("https://hub.example/guides/intake");
    expect(guide.getAttribute("target")).toBe("_blank");
    expect(guide.getAttribute("rel")).toBe("noopener noreferrer");
    expect(guide.textContent).toContain("(opens in a new tab)");
    expect(guide.getAttribute("aria-current")).toBeNull();
  });

  it.each([
    ["/", "Projects"],
    ["/projects/4417203", "Projects"],
    ["/packages/5d236b10-70f2-42f9-8f3f-7e56547a3146", "Projects"],
    ["/packages", "Packages"],
    ["/decisions", "Decision log"],
  ])("marks the current item on %s", async (pathname, current) => {
    await renderShell(["admin"], "Avery Admin", pathname);
    const nav = screen.getByRole("navigation", { name: "Main" });
    const marked = within(nav)
      .getAllByRole("link")
      .filter((link) => link.getAttribute("aria-current") === "page");
    expect(marked.map((link) => link.textContent)).toEqual([current]);
  });

  it("shows the signed-in user with initials and role", async () => {
    await renderShell(["bim"], "Dana BIM");
    expect(screen.getByText("Dana BIM")).toBeTruthy();
    expect(screen.getByText("BIM operator · Entra")).toBeTruthy();
    expect(screen.getByText("DB").getAttribute("aria-hidden")).toBe("true");
    cleanup();
    await renderShell(["capture"], "Casey Capture");
    expect(screen.getByText("Capture operator · Entra")).toBeTruthy();
  });

  it("renders nothing around a page without a session (the page redirects)", async () => {
    state.session = null;
    render(await ReviewLayout({ children: <p>Page body</p> }));
    expect(screen.queryByRole("navigation", { name: "Main" })).toBeNull();
  });
});

describe("navigation rules", () => {
  it("knows which item a path belongs to", () => {
    expect(activeItem("/")).toBe("projects");
    expect(activeItem("/packages")).toBe("packages");
    expect(activeItem("/packages/x")).toBe("projects");
    expect(activeItem("/decisions")).toBe("decisions");
    expect(activeItem("/sign-in")).toBeUndefined();
  });

  it("takes the first letters of the first two words for the avatar", () => {
    expect(initials("Dana BIM")).toBe("DB");
    expect(initials("casey")).toBe("C");
    expect(initials("Mary Ann Smith")).toBe("MA");
    expect(initials("  ")).toBe("?");
  });
});

describe("topbar", () => {
  it("shows the title and the project search", () => {
    render(<Topbar title="Capture review" query="424 West" />);
    expect(screen.getByRole("heading", { level: 1 }).textContent).toBe("Capture review");
    const search = screen.getByRole("searchbox", { name: "Search projects" });
    expect((search as HTMLInputElement).value).toBe("424 West");
    expect(search.getAttribute("placeholder")).toBe("Address, deal or capture id");
    expect(search.getAttribute("maxlength")).toBe("200");
    const form = screen.getByRole("search");
    expect(form.getAttribute("action")).toBe("/");
    expect(screen.queryByRole("link", { name: /Open the HUB/ })).toBeNull();
  });

  it("links Open the HUB in a new tab when HUB_APP_URL is set", () => {
    vi.stubEnv("HUB_APP_URL", "https://hub.example");
    render(<Topbar title="Packages" />);
    const hub = screen.getByRole("link", { name: /Open the HUB/ });
    expect(hub.getAttribute("href")).toBe("https://hub.example/");
    expect(hub.getAttribute("rel")).toBe("noopener noreferrer");
  });
});
