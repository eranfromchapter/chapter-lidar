// @vitest-environment jsdom
// Project (web-review §6.3, artboard 2i, addendum D7, WR-AC4): back link, title with the latest
// verdict, meta with the PM, the revision on the phone above revision 1, "What revision 2
// adds", the latest verdict and the decision log; the capture role sees status only.

import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { StationRole } from "@/lib/roles";
import type { ViewerSession } from "@/lib/viewer";
import type { FakeStationData } from "./support/fake-station";
import { DEALS, drawnScenario, IDS, statesScenario } from "./support/scenarios";
import { createFakeStation, sessionFor, type FakeStation } from "./support/station";

const state = vi.hoisted(() => ({ session: null as ViewerSession | null }));

vi.mock("@/lib/viewer", () => ({
  getViewerSession: async () => state.session,
  requireViewerSession: async () => state.session,
}));

const { default: ProjectPage } = await import("@/app/(review)/projects/[dealId]/page");

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

async function renderProject(
  dealId: string,
  options: { roles?: StationRole[]; tab?: string; data?: FakeStationData } = {},
): Promise<FakeStation> {
  const station = createFakeStation(options.data ?? drawnScenario(NOW));
  state.session = sessionFor(options.roles ?? ["bim"], station);
  render(
    await ProjectPage({
      params: Promise.resolve({ dealId }),
      searchParams: Promise.resolve(options.tab === undefined ? {} : { tab: options.tab }),
    }),
  );
  return station;
}

function tableRows(): HTMLElement[] {
  const table = screen.getByRole("region", { name: "Packages" });
  return within(table)
    .getAllByRole("row")
    .filter((row) => row.hasAttribute("data-revision"));
}

function cells(row: HTMLElement): string[] {
  return within(row)
    .getAllByRole("cell")
    .map((cell) => cell.textContent ?? "");
}

describe("project page of the 424 sample (2i)", () => {
  it("shows the back link, the title with the latest verdict and the meta line", async () => {
    await renderProject(DEALS.westEnd);
    expect(screen.getByRole("link", { name: "Projects" }).getAttribute("href")).toBe("/");
    expect(screen.getByRole("heading", { level: 1 }).textContent).toBe("424 West End Ave, Apt 4K");
    const title = screen.getByRole("heading", { level: 2 });
    expect(title.textContent).toBe("424 West End Ave, Apt 4K");
    expect(screen.getByText("Limited · latest")).toBeTruthy();
    for (const meta of [
      "100 Example Street, Testville, NY 00000",
      `deal ${DEALS.westEnd}`,
      "PM Sam Rivera",
      "2 packages",
    ]) {
      expect(screen.getByText(meta)).toBeTruthy();
    }
  });

  it("links the HUB deal from the station, and the spatial report only when it is ready", async () => {
    await renderProject(DEALS.westEnd);
    const hub = screen.getByRole("link", { name: /Open in the HUB/ });
    expect(hub.getAttribute("href")).toBe(`https://hub.example/deals/${DEALS.westEnd}`);
    expect(hub.getAttribute("target")).toBe("_blank");
    expect(screen.queryByRole("link", { name: /Spatial report PDF/ })).toBeNull();
    cleanup();
    await renderProject(DEALS.westEnd, { data: drawnScenario(NOW, { reportReady: true }) });
    expect(screen.getByRole("link", { name: "Spatial report PDF · r1" }).getAttribute("href")).toBe(
      `/packages/${IDS.westEnd1}/report/download`,
    );
  });

  it("lists revision 2 on the phone above revision 1, as drawn", async () => {
    await renderProject(DEALS.westEnd);
    const [phone, first] = tableRows();
    expect(phone?.getAttribute("data-on-phone")).toBe("true");
    expect(cells(phone as HTMLElement)).toEqual([
      "Revision 2not sealed · on the phone",
      "Not checked yet",
      "Today · Test Operator",
      "—",
      "+ primary closet · + 1 control · + 3 photos",
      "—",
      "",
    ]);
    expect(within(phone as HTMLElement).queryByRole("link")).toBeNull();
    expect(cells(first as HTMLElement)).toEqual([
      "Revision 1capture 33ede7f4…",
      "Limited",
      "Oct 17, 2026 · Test Operator",
      "Oct 17, 2026 11:20",
      "1 floor · 33 files · 584 KB",
      "Published Oct 17, 2026",
      "Open",
    ]);
    const tabs = within(screen.getByRole("navigation", { name: "Project" })).getAllByRole("link");
    expect(tabs.map((tab) => tab.textContent)).toEqual(["Packages2", "Decision log3"]);
  });

  it("prints the rooms of the spatial report in Contents once it is ready", async () => {
    await renderProject(DEALS.westEnd, { data: drawnScenario(NOW, { reportReady: true }) });
    expect(cells(tableRows()[1] as HTMLElement)[4]).toBe("1 floor · 12 rooms · 33 files · 584 KB");
  });

  it("says what revision 2 adds, with the limitation it answers", async () => {
    await renderProject(DEALS.westEnd);
    const card = screen.getByRole("region", { name: "What revision 2 adds" });
    expect(card.textContent).toContain("from the phone, not sealed yet");
    expect(card.textContent).toContain("Primary closet scannedanswers limitation 1 · coverage");
    expect(card.textContent).toContain("Room 4 ceiling height, tape2,490 mm");
    expect(card.textContent).toContain("3 photosprimary closet · general, ceiling, opening");
    expect(card.textContent).toContain(
      "Revision 1 stays unchanged and keeps its verdict. The station checks revision 2 as a whole package and issues a new spatial report.",
    );
  });

  it("shows the latest verdict with its limitations and next actions", async () => {
    await renderProject(DEALS.westEnd);
    const card = screen.getByRole("region", { name: "Latest verdict: Limited" });
    expect(card.textContent).toContain("Latest verdict · revision 1");
    expect(card.textContent).toContain("Floor 1: Primary closet not captured");
    expect(within(card).getByText("Limitations")).toBeTruthy();
    expect(within(card).getByText("Next actions")).toBeTruthy();
    expect(within(card).getByRole("link", { name: "Capture checks →" }).getAttribute("href")).toBe(
      `/packages/${IDS.westEnd1}#checks`,
    );
  });

  it("summarises the decision log with the two newest entries", async () => {
    await renderProject(DEALS.westEnd);
    const card = screen.getByRole("region", { name: "Decision log" });
    expect(card.textContent).toContain("Decision log · 3 entries");
    expect(card.textContent).toContain("Room 4 ceiling — height from the room schedule");
    expect(card.textContent).toContain("Kitchen cabinetry — mesh linked as reference only");
    expect(card.textContent).not.toContain("Living Room walls");
    expect(card.textContent).toContain("Dana BIM · Oct 17, 2026 12:40");
    expect(within(card).getByRole("link", { name: "All entries →" }).getAttribute("href")).toBe(
      `/projects/${DEALS.westEnd}?tab=log`,
    );
  });

  it("lists every decision of the project newest first on the log tab", async () => {
    await renderProject(DEALS.westEnd, { tab: "log" });
    const log = screen.getByRole("region", { name: "Modeling decision log" });
    expect(log.textContent).toContain("3 entries · newest first");
    const entries = within(log).getAllByRole("listitem");
    expect(entries.map((entry) => entry.querySelector("b")?.textContent)).toEqual([
      "Room 4 ceiling",
      "Kitchen cabinetry",
      "Living Room walls",
    ]);
    expect(entries[2]?.textContent).toContain("Revision 1");
    expect(entries[2]?.textContent).toContain("from Floor 1 / plan.dxf + Distance A (laser)");
    expect(
      within(log)
        .getByRole("link", { name: "Log a decision on revision 1 →" })
        .getAttribute("href"),
    ).toBe(`/packages/${IDS.westEnd1}#decisions`);
    expect(screen.queryByRole("region", { name: "Packages" })).toBeNull();
  });
});

describe("other project states", () => {
  it("shows an upload in progress", async () => {
    await renderProject(DEALS.valley);
    const [row] = tableRows();
    expect(cells(row as HTMLElement)[0]).toMatch(/^Revision 1uploading from the phone · \d+%$/);
    expect(screen.getByRole("region", { name: "Latest verdict" }).textContent).toContain(
      "No verdict yet. The station checks a package after it is sealed.",
    );
    expect(screen.queryByText(/· latest/)).toBeNull();
  });

  it("lists revisions newest first and has no revision card once revision 2 has a verdict", async () => {
    await renderProject(DEALS.shawnee);
    expect(tableRows().map((row) => row.getAttribute("data-revision"))).toEqual(["2", "1"]);
    expect(screen.queryByRole("region", { name: /What revision/ })).toBeNull();
    expect(screen.getByText("Ready · latest")).toBeTruthy();
  });

  it("labels an upload the phone replaced and compares the new revision with it", async () => {
    await renderProject("4419004", { data: statesScenario(NOW) });
    const [second, first] = tableRows();
    expect(cells(first as HTMLElement)[0]).toBe(
      "Revision 1upload stopped · replaced by revision 2",
    );
    expect(cells(second as HTMLElement)[0]).toMatch(/^Revision 2uploading from the phone/);
    const card = screen.getByRole("region", { name: "What revision 2 adds" });
    expect(card.textContent).toContain("uploading from the phone, not checked yet");
  });

  it("falls back to the capture record when the HUB no longer knows the deal", async () => {
    const data = drawnScenario(NOW);
    data.projects = data.projects.filter((project) => project.dealId !== DEALS.westEnd);
    await renderProject(DEALS.westEnd, { data });
    expect(screen.getByRole("heading", { level: 2 }).textContent).toBe("Fixture sample-424");
    expect(screen.queryByText(/^PM /)).toBeNull();
  });

  it("is not found when the station knows neither the deal nor packages of it", async () => {
    await expect(renderProject("no-such-deal")).rejects.toThrow(/NEXT_HTTP_ERROR_FALLBACK;404/);
  });
});

describe("capture role", () => {
  it("sees the packages and the latest verdict, no report, no decision log", async () => {
    const station = await renderProject(DEALS.westEnd, {
      roles: ["capture"],
      data: drawnScenario(NOW, { reportReady: true }),
    });
    expect(tableRows()).toHaveLength(2);
    expect(screen.queryByRole("link", { name: /Spatial report PDF/ })).toBeNull();
    expect(screen.queryByRole("link", { name: /Decision log/ })).toBeNull();
    expect(screen.queryByRole("region", { name: "Decision log" })).toBeNull();
    expect(screen.queryByRole("link", { name: "Capture checks →" })).toBeNull();
    expect(screen.getByRole("link", { name: /Open in the HUB/ })).toBeTruthy();
    expect(station.calls.some((call) => call.path === "/modeling-decisions")).toBe(false);
  });

  it("is shown the packages tab when asking for the log", async () => {
    await renderProject(DEALS.westEnd, { roles: ["capture"], tab: "log" });
    expect(screen.getByRole("region", { name: "Packages" })).toBeTruthy();
  });
});
