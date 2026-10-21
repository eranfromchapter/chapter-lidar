// @vitest-environment jsdom
// Projects (web-review §6.1, artboard 2h, WR-AC3) and Packages (§6.2): heading, tabs with
// counts, the table's seven columns, verdicts with word and shape, empty / no match / error /
// no role states.

import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { StationRole } from "@/lib/roles";
import type { ViewerSession } from "@/lib/viewer";
import type { FakeStationData } from "./support/fake-station";
import { DEALS, drawnScenario, emptyScenario, IDS } from "./support/scenarios";
import { createFakeStation, sessionFor, type FakeStation } from "./support/station";

const state = vi.hoisted(() => ({ session: null as ViewerSession | null }));

vi.mock("@/lib/viewer", () => ({
  getViewerSession: async () => state.session,
  requireViewerSession: async () => state.session,
}));

const { default: ProjectsPage } = await import("@/app/(review)/page");
const { default: PackagesPage } = await import("@/app/(review)/packages/page");

const NOW = new Date("2026-10-21T18:00:00Z");

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(NOW);
});

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  state.session = null;
});

async function renderProjects(
  query: Record<string, string> = {},
  data: FakeStationData = drawnScenario(NOW),
  roles: StationRole[] = ["bim"],
): Promise<FakeStation> {
  const station = createFakeStation(data);
  state.session = sessionFor(roles, station);
  render(await ProjectsPage({ searchParams: Promise.resolve(query) }));
  return station;
}

function rows(): HTMLElement[] {
  return screen.getAllByRole("row").filter((row) => row.hasAttribute("data-deal"));
}

function cells(row: HTMLElement): string[] {
  return within(row)
    .getAllByRole("cell")
    .map((cell) => cell.textContent ?? "");
}

describe("projects page (2h)", () => {
  it("shows the heading, the sentence and the count line", async () => {
    await renderProjects();
    expect(screen.getByRole("heading", { level: 1 }).textContent).toBe("Capture review");
    expect(screen.getByRole("heading", { level: 2 }).textContent).toBe("Projects");
    expect(
      screen.getByText(
        "Capture packages from the station, by project. Verdicts are the station's; re-sealing a Blocked package happens on the phone.",
      ),
    ).toBeTruthy();
    expect(screen.getByText("5 projects · updated 2 min ago")).toBeTruthy();
  });

  it("shows five tabs with counts, All selected", async () => {
    await renderProjects();
    const tabs = within(screen.getByRole("navigation", { name: "Verdicts" })).getAllByRole("link");
    expect(tabs.map((tab) => tab.textContent)).toEqual([
      "All5",
      "Blocked1",
      "Limited1",
      "Ready2",
      "Uploading1",
    ]);
    expect(tabs[0]?.getAttribute("aria-current")).toBe("page");
    expect(tabs[2]?.getAttribute("href")).toBe("/?tab=limited");
  });

  it("lists one row per project with the drawn cells, most recent first", async () => {
    await renderProjects();
    const headers = screen.getAllByRole("columnheader").map((header) => header.textContent);
    expect(headers).toEqual([
      "Project",
      "Latest package",
      "Verdict",
      "Floors",
      "Captured",
      "In the HUB",
      "Open",
    ]);
    const table = rows();
    expect(table.map((row) => row.getAttribute("data-deal"))).toEqual([
      DEALS.westEnd,
      DEALS.valley,
      DEALS.shawnee,
      DEALS.blocked,
      DEALS.east81,
    ]);
    expect(cells(table[0] as HTMLElement)).toEqual([
      `424 West End Ave, Apt 4Kdeal ${DEALS.westEnd}`,
      "Revision 1 · sealed Oct 17, 2026",
      "Limited",
      "1",
      "Oct 17, 2026 · Test Operator",
      "Published Oct 17, 2026",
      "Open",
    ]);
    const valley = cells(table[1] as HTMLElement);
    expect(valley.slice(1, 6)).toEqual([
      "Revision 1 · uploading from the phone",
      "Not checked yet",
      "2",
      "Today · Casey Capture",
      "—",
    ]);
    const bar = within(table[1] as HTMLElement).getByRole("progressbar");
    expect(Number(bar.getAttribute("aria-valuenow"))).toBeGreaterThan(55);
    expect(bar.getAttribute("aria-label")).toBe(`Upload ${bar.getAttribute("aria-valuenow")}%`);
    expect(cells(table[3] as HTMLElement)[5]).toBe("Not published · re-seal needed");
    expect(cells(table[2] as HTMLElement)[1]).toBe("Revision 2 · sealed Oct 17, 2026");
    const open = within(table[0] as HTMLElement).getByRole("link", {
      name: "Open 424 West End Ave, Apt 4K",
    });
    expect(open.getAttribute("href")).toBe(`/projects/${DEALS.westEnd}`);
  });

  it("draws each verdict with a word and a shape, never colour alone", async () => {
    await renderProjects();
    for (const row of rows()) {
      const badge = within(row).getAllByRole("cell")[2] as HTMLElement;
      const verdict = badge.textContent ?? "";
      if (["Ready", "Limited", "Blocked"].includes(verdict)) {
        expect(badge.querySelector("svg[aria-hidden='true']"), verdict).not.toBeNull();
      }
    }
    expect(screen.getByText(/Verdicts always show a word and a shape:/).textContent).toBe(
      "Verdicts always show a word and a shape: Ready · Limited · Blocked.",
    );
  });

  it("filters by tab and says when a tab is empty", async () => {
    await renderProjects({ tab: "limited" });
    expect(rows().map((row) => row.getAttribute("data-deal"))).toEqual([DEALS.westEnd]);
    cleanup();
    const data = drawnScenario(NOW);
    data.packages = data.packages.filter((pkg) => pkg.status !== "uploading");
    await renderProjects({ tab: "progress" }, data);
    expect(screen.getByText("No packages uploading or being checked.")).toBeTruthy();
  });

  it("searches through the station and keeps the search in the tabs", async () => {
    const station = await renderProjects({ q: "West End" });
    const call = station.calls.find((item) => item.path === "/review/projects");
    expect(call?.search.get("q")).toBe("West End");
    expect(rows()).toHaveLength(1);
    expect(screen.getByText("1 project · updated 2 min ago")).toBeTruthy();
    const tabs = within(screen.getByRole("navigation", { name: "Verdicts" })).getAllByRole("link");
    expect(tabs[1]?.getAttribute("href")).toBe("/?q=West+End&tab=blocked");
    expect((screen.getByRole("searchbox") as HTMLInputElement).value).toBe("West End");
  });

  it("offers to clear a search that matches nothing", async () => {
    await renderProjects({ q: "nothing like this" });
    expect(screen.getByText("No project matches “nothing like this”")).toBeTruthy();
    expect(screen.getByText("Search by address, deal or capture id.")).toBeTruthy();
    expect(screen.getByRole("link", { name: "Clear search" }).getAttribute("href")).toBe("/");
    expect(screen.queryByText(/projects · updated/)).toBeNull();
  });

  it("shows the empty state with the tabs at 0 when the station has no packages", async () => {
    await renderProjects({}, emptyScenario());
    expect(screen.getByText("No capture packages yet")).toBeTruthy();
    expect(
      screen.getByText(
        "Packages appear here when the Chapter Capture app uploads a sealed capture.",
      ),
    ).toBeTruthy();
    const tabs = within(screen.getByRole("navigation", { name: "Verdicts" })).getAllByRole("link");
    expect(tabs.map((tab) => tab.textContent)).toEqual([
      "All0",
      "Blocked0",
      "Limited0",
      "Ready0",
      "Uploading0",
    ]);
    expect(screen.queryByText(/updated/)).toBeNull();
  });

  it("says when the station shows only the most recent projects", async () => {
    const data = drawnScenario(NOW);
    const station = createFakeStation(data);
    state.session = sessionFor(["bim"], station);
    const original = station.fetch;
    const truncating: typeof fetch = async (input, init) => {
      const response = await original(input, init);
      if (String(input).includes("/review/projects")) {
        const body = (await response.json()) as Record<string, unknown>;
        return new Response(JSON.stringify({ ...body, truncated: true }), {
          headers: { "content-type": "application/json" },
        });
      }
      return response;
    };
    state.session = {
      ...state.session,
      station: (await import("@/lib/station")).createStationClient({
        baseUrl: "https://station.test",
        accessToken: "test-access-token",
        fetchImpl: truncating,
      }),
    };
    render(await ProjectsPage({ searchParams: Promise.resolve({}) }));
    expect(
      screen.getByText(
        "Showing the 5 most recently active projects. Search by address, deal or capture id to find others.",
      ),
    ).toBeTruthy();
  });

  it("explains a station that does not answer, without data", async () => {
    const data = drawnScenario(NOW);
    const station = createFakeStation(data);
    station.failWith = 503;
    state.session = sessionFor(["bim"], station);
    render(await ProjectsPage({ searchParams: Promise.resolve({}) }));
    const alert = screen.getByRole("alert");
    expect(alert.textContent).toContain("The station could not answer");
    expect(alert.textContent).toContain("(status 503)");
    expect(within(alert).getByRole("link", { name: "Try again" }).getAttribute("href")).toBe("/");
    expect(screen.queryByRole("table")).toBeNull();
  });

  it("tells a user without a station role, without calling the station", async () => {
    const station = await renderProjects({}, drawnScenario(NOW), []);
    expect(screen.getByRole("alert").textContent).toContain("No access");
    expect(station.calls).toHaveLength(0);
  });

  it("is the same list for the capture role", async () => {
    await renderProjects({}, drawnScenario(NOW), ["capture"]);
    expect(rows()).toHaveLength(5);
  });
});

describe("packages page (6.2)", () => {
  it("lists every package newest first with project, verdict, capture, check and HUB", async () => {
    const station = createFakeStation(drawnScenario(NOW));
    state.session = sessionFor(["bim"], station);
    render(await PackagesPage({ searchParams: Promise.resolve({}) }));
    expect(screen.getByRole("heading", { level: 2 }).textContent).toBe("Packages");
    expect(screen.getByText("Every package revision the station has, newest first.")).toBeTruthy();
    expect(screen.getByText("6 packages")).toBeTruthy();
    const table = screen.getAllByRole("row").filter((row) => row.hasAttribute("data-package"));
    expect(table[0]?.getAttribute("data-package")).toBe(IDS.valley1);
    const westEnd = table.find((row) => row.getAttribute("data-package") === IDS.westEnd1);
    expect(cells(westEnd as HTMLElement)).toEqual([
      "424 West End Ave, Apt 4KRevision 1 · capture 33ede7f4…",
      "Limited",
      "Oct 17, 2026 · Test Operator",
      "Oct 17, 2026 11:20",
      "Published Oct 17, 2026",
      "Open",
    ]);
    expect(
      within(westEnd as HTMLElement)
        .getByRole("link", { name: /^Open/ })
        .getAttribute("href"),
    ).toBe(`/packages/${IDS.westEnd1}`);
  });

  it("shows the empty state", async () => {
    state.session = sessionFor(["capture"], createFakeStation(emptyScenario()));
    render(await PackagesPage({ searchParams: Promise.resolve({}) }));
    expect(screen.getByText("No capture packages yet")).toBeTruthy();
  });
});
