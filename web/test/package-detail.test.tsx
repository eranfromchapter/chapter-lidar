// @vitest-environment jsdom
// Package (web-review §6.4, artboard 2j, WR-AC5, WR-AC6): for the contract's verdict example and
// the station's verdict of every generated fixture, the verdict card and the capture checks in
// the spatial report's words (contract checkRows, Blocked > Limited > Passed > Not applicable);
// for the drawn sample, the header, plan, files, capture record, field controls, station and
// documents; and the states without a verdict.

import {
  checkCounts,
  checkRows,
  countsLine,
  sortCheckRows,
  verdictHeadline,
  type Verdict,
} from "@chapter/capture-contract";
import { act, cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { planSheetDetail, versionAtLeast } from "@/components/package/DocumentsCard";
import type { StationRole } from "@/lib/roles";
import type { PackageFile } from "@/lib/station-types";
import type { ViewerSession } from "@/lib/viewer";
import type { FakeStationData } from "./support/fake-station";
import { contractExampleCase, generatedFixtureCases, type FixtureCase } from "./support/fixtures";
import { drawnScenario, IDS, statesScenario } from "./support/scenarios";
import { createFakeStation, sessionFor, type FakeStation } from "./support/station";

const state = vi.hoisted(() => ({ session: null as ViewerSession | null }));

vi.mock("@/lib/viewer", () => ({
  getViewerSession: async () => state.session,
  requireViewerSession: async () => state.session,
}));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));

const { default: PackagePage } = await import("@/app/(review)/packages/[packageId]/page");

const NOW = new Date("2026-10-21T18:00:00Z");
const cases: FixtureCase[] = [contractExampleCase(), ...generatedFixtureCases()];

beforeAll(() => {
  Element.prototype.scrollIntoView = vi.fn();
});

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(NOW);
});

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  state.session = null;
});

async function renderPackage(
  data: FakeStationData,
  packageId: string,
  options: { roles?: StationRole[]; query?: Record<string, string> } = {},
): Promise<FakeStation> {
  const station = createFakeStation(data);
  state.session = sessionFor(options.roles ?? ["bim"], station);
  render(
    await PackagePage({
      params: Promise.resolve({ packageId }),
      searchParams: Promise.resolve(options.query ?? {}),
    }),
  );
  return station;
}

function caseData(
  fixture: FixtureCase,
  verdict: Verdict | null = fixture.verdict,
): FakeStationData {
  return {
    projects: [fixture.project],
    packages: [structuredClone(fixture.pkg)],
    verdicts: verdict === null ? {} : { [fixture.pkg.packageId]: verdict },
    decisions: {},
  };
}

function region(name: string | RegExp): HTMLElement {
  return screen.getByRole("region", { name });
}

function asideRows(name: string): Record<string, string> {
  const card = region(name);
  return Object.fromEntries(
    [...card.querySelectorAll(".kv")].map((row) => [
      row.querySelector(".kv__label")?.textContent ?? "",
      row.querySelector(".kv__value")?.textContent ?? "",
    ]),
  );
}

describe("fixture verdicts", () => {
  it("cover all three outcomes", () => {
    const outcomes = new Set(cases.map((fixture) => fixture.verdict.outcome));
    expect([...outcomes].sort()).toEqual(["blocked", "limited", "ready"]);
    expect(cases.length).toBe(14);
  });
});

describe.each(cases.map((fixture) => [fixture.name, fixture] as const))(
  "package detail: %s",
  (_name, fixture) => {
    it("shows the verdict in the report's words: headline, summary, counts, statement", async () => {
      await renderPackage(caseData(fixture), fixture.pkg.packageId);
      const { verdict } = fixture;
      const card = region(/^Verdict: /);
      expect(card.getAttribute("data-outcome")).toBe(verdict.outcome);
      expect(within(card).getByText(verdictHeadline(verdict))).toBeTruthy();
      expect(within(card).getByText(verdict.summary)).toBeTruthy();
      const rows = checkRows(verdict, fixture.pkg.captureRecord);
      expect(within(card).getByText(countsLine(checkCounts(rows)))).toBeTruthy();
      expect(within(card).getByText(verdict.statement)).toBeTruthy();
      for (const limitation of verdict.limitations) {
        expect(within(card).getByText(limitation)).toBeTruthy();
      }
      for (const action of verdict.nextActions) {
        expect(within(card).getByText(action)).toBeTruthy();
      }
      if (verdict.limitations.length === 0) {
        expect(within(card).getAllByText("None.").length).toBeGreaterThan(0);
      }
    });

    it("lists every check row as the spatial report does, Blocked > Limited > Passed > Not applicable", async () => {
      await renderPackage(caseData(fixture), fixture.pkg.packageId);
      const expected = sortCheckRows(checkRows(fixture.verdict, fixture.pkg.captureRecord));
      const card = region("Capture checks");
      const rows = within(card)
        .getAllByRole("row")
        .filter((row) => row.hasAttribute("data-result"));
      expect(rows.map((row) => row.getAttribute("data-rule"))).toEqual(
        expected.map((row) => row.ruleId),
      );
      const order = ["blocked", "limited", "passed", "not_applicable"];
      const results = rows.map((row) => order.indexOf(row.getAttribute("data-result") ?? ""));
      expect(results).toEqual([...results].sort((a, b) => a - b));
      expected.forEach((row, index) => {
        const cells = within(rows[index] as HTMLElement).getAllByRole("cell");
        expect(cells[0]?.textContent).toBe(`${row.title}${row.ruleId}`);
        expect(cells[1]?.textContent).toBe(row.word);
        expect(cells[2]?.textContent).toBe(
          row.found.length === 0
            ? "—"
            : row.found.map((block) => `${block.message}${block.values ?? ""}`).join(""),
        );
        expect(cells[3]?.textContent).toBe(
          row.nextActions.length === 0 ? "None" : row.nextActions.join(""),
        );
      });
      expect(card.textContent).toContain(`${expected.length} rules · evaluated`);
      expect(card.textContent).toContain("same table as the spatial report");
      expect(card.textContent).toContain(
        "Every rule the station ran is listed. Exports of one scan that agree with each other are not independent measurements.",
      );
    });

    it("lists the files with role, size, fingerprint and download links to this app only", async () => {
      await renderPackage(caseData(fixture), fixture.pkg.packageId);
      const card = region(/^Files · /);
      expect(within(card).getByRole("heading").textContent).toBe(
        `Files · ${fixture.pkg.totals.files}`,
      );
      const links = within(card).getAllByRole("link", { name: /^Download / });
      expect(links.length).toBeGreaterThan(0);
      for (const link of links) {
        expect(link.getAttribute("href")).toMatch(
          new RegExp(
            `^/packages/${fixture.pkg.packageId}/(files/download\\?path=|report/download$)`,
          ),
        );
      }
      expect(document.body.innerHTML).not.toContain("sig=");
    });
  },
);

describe("the drawn sample (2j)", () => {
  const sample = () => drawnScenario(NOW);
  const ready = () => drawnScenario(NOW, { reportReady: true });

  it("shows the breadcrumb, title, badges and capture meta line", async () => {
    await renderPackage(sample(), IDS.westEnd1);
    const crumbs = screen.getByRole("navigation", { name: "Breadcrumb" });
    expect(
      within(crumbs)
        .getAllByRole("link")
        .map((link) => link.getAttribute("href")),
    ).toEqual(["/", "/projects/4417203"]);
    expect(crumbs.textContent).toBe("Projects/424 West End Ave, Apt 4K/Revision 1");
    expect(screen.getByRole("heading", { level: 1 }).textContent).toBe(
      "424 West End Ave, Apt 4K · Revision 1",
    );
    const titleRow = screen.getByRole("heading", { level: 2 }).parentElement as HTMLElement;
    expect(within(titleRow).getByText("Published to the HUB")).toBeTruthy();
    expect(within(titleRow).getByText("Limited")).toBeTruthy();
    const meta = (titleRow.parentElement as HTMLElement).querySelector(".meta-row");
    expect([...(meta?.children ?? [])].map((item) => item.textContent)).toEqual([
      "Captured Oct 17, 2026 by Test Operator",
      "iPhone 16 Pro · app 1.0.0",
      "whole floor × 1",
      "sealed Oct 17, 2026",
      "checked Oct 17, 2026 11:20 · rules station-checks v1.2.0",
      "capture 33ede7f4-cfcb-4cd6-9af5-7daffee829a9",
    ]);
  });

  it("offers the plan sheet, and the spatial report once the station has it", async () => {
    await renderPackage(sample(), IDS.westEnd1);
    const sheet = sample()
      .packages.find((pkg) => pkg.packageId === IDS.westEnd1)
      ?.files.find((file) => file.role === "plan_pdf");
    expect(screen.getByRole("link", { name: "Plan sheet PDF" }).getAttribute("href")).toBe(
      `/packages/${IDS.westEnd1}/files/download?path=${encodeURIComponent(sheet?.path ?? "")}`,
    );
    expect(screen.queryByRole("link", { name: "Spatial report PDF" })).toBeNull();
    cleanup();
    await renderPackage(ready(), IDS.westEnd1);
    const reports = screen.getAllByRole("link", { name: /Spatial report PDF/ });
    expect(
      reports.every(
        (link) => link.getAttribute("href") === `/packages/${IDS.westEnd1}/report/download`,
      ),
    ).toBe(true);
  });

  it("says revision 2 is in progress on the phone in the verdict card", async () => {
    await renderPackage(sample(), IDS.westEnd1);
    expect(region("Verdict: Limited").textContent).toContain(
      "Revision 2 is in progress on the phone with 1 of the 2 next actions.",
    );
  });

  it("previews the plan with its downloads, orientation and rooms not scanned", async () => {
    const station = await renderPackage(sample(), IDS.westEnd1);
    const plan = region("Plan");
    expect(within(plan).getByText("Floor 1 · whole floor")).toBeTruthy();
    const image = within(plan).getByRole("img", { name: "Plan of Floor 1" });
    expect(image.getAttribute("src")).toMatch(
      new RegExp(`^/packages/${IDS.westEnd1}/files/preview\\?path=.*plan\\.png$`),
    );
    expect(
      within(plan)
        .getAllByRole("link")
        .map((link) => link.textContent),
    ).toEqual(["plan.png", "plan.dxf", "plan sheet PDF"]);
    expect(plan.textContent).toContain(
      "Verified · true north from the compass, ±8°. The plan sheet shows the north arrow.",
    );
    expect(plan.textContent).toContain("Primary closet (locked) · Storage room (could not enter)");
    expect(plan.textContent).toContain(
      "From plan.png · fitted, not to scale. Use the plan sheet PDF for the drawing to scale.",
    );
    expect(plan.textContent).not.toContain("Rooms");
    expect(station.calls.some((call) => call.path.endsWith("/files/download"))).toBe(false);
  });

  it("adds the room facts and the checks page of the spatial report once it is ready", async () => {
    await renderPackage(ready(), IDS.westEnd1);
    expect(region("Plan").textContent).toContain(
      "12 scanned · 807.5 sq ft, sum of rooms · 5 unlabeled",
    );
    expect(region("Capture checks").textContent).toContain(
      "14 rules · evaluated Oct 17, 2026 11:20 · same table as page 4 of the spatial report",
    );
  });

  it("filters the files, groups the photos and shows all on request", async () => {
    await renderPackage(sample(), IDS.westEnd1);
    const card = region("Files · 33");
    const fileRows = () =>
      within(card)
        .getAllByRole("row")
        .filter((row) => row.hasAttribute("data-kind"));
    expect(fileRows()).toHaveLength(8);
    expect(card.textContent).toContain(
      "Files over 45 MB stay in Chapter's storage and are linked from the HUB. Compare a download with its SHA-256 fingerprint.",
    );
    const showAll = within(card).getByRole("button", { name: "Show all 33 files" });
    await act(async () => {
      fireEvent.click(showAll);
    });
    // 15 files, the photo group and the manifest (the spatial report is still pending).
    expect(fileRows().length).toBe(17);
    await act(async () => {
      fireEvent.click(within(card).getByRole("button", { name: "Show photos" }));
    });
    expect(fileRows().length).toBe(35);
    expect(
      within(card).getByRole("button", { name: "Hide photos" }).getAttribute("aria-expanded"),
    ).toBe("true");
    await act(async () => {
      fireEvent.change(within(card).getByRole("combobox", { name: "Role" }), {
        target: { value: "Plan DXF" },
      });
    });
    expect(fileRows().map((row) => row.querySelector(".hub-cell-title")?.textContent)).toEqual([
      "Floor 1 / plan.dxf",
    ]);
    await act(async () => {
      fireEvent.change(within(card).getByRole("searchbox", { name: "Search files" }), {
        target: { value: "nothing" },
      });
    });
    expect(card.textContent).toContain("No files match these filters.");
    await act(async () => {
      fireEvent.click(within(card).getByRole("button", { name: "Clear filters" }));
    });
    expect(fileRows().length).toBeGreaterThan(8);
    const roles = within(within(card).getByRole("combobox", { name: "Role" }))
      .getAllByRole("option")
      .map((option) => option.textContent);
    expect(roles).toEqual([
      "All roles",
      "Plan DXF",
      "Rooms CSV",
      "Plan sheet PDF",
      "Plan PNG",
      "Plan SVG",
      "Mesh GLB",
      "OBJ + MTL",
      "Point cloud LAS",
      "Raw RoomPlan",
      "Depth",
      "Capture model",
      "Site photo",
      "Field controls",
      "Capture record",
      "Manifest",
    ]);
  });

  it("highlights and scrolls to the file named by ?file=, inside its photo group", async () => {
    const photo = sample()
      .packages.find((pkg) => pkg.packageId === IDS.westEnd1)
      ?.files.find((file) => file.role === "photo") as PackageFile;
    await renderPackage(sample(), IDS.westEnd1, { query: { file: photo.path } });
    const target = document.querySelector('tr[aria-current="true"]');
    expect(target?.getAttribute("data-path")).toBe(photo.path);
    expect(target?.id).toBe("file-target");
    expect(Element.prototype.scrollIntoView).toHaveBeenCalled();
  });

  it("shows the capture record, field controls, station and documents", async () => {
    await renderPackage(sample(), IDS.westEnd1);
    expect(asideRows("Capture record")).toEqual({
      Address: "Confirmed on site",
      Floors: "1 · whole floor",
      Rooms: "2 not scanned",
      "Not scanned": "Primary closet (locked) · Storage room (could not enter)",
      "Coverage notes": "Room 4: the ceiling was only partly captured.",
      Compass: "Verified · 212° true, ±8°",
      Device: "iPhone 16 Pro · app 1.0.0",
      Operator: "Test Operator",
    });
    expect(region("Field controls").textContent).toContain("Field controls · tape and laser");
    expect(asideRows("Field controls")).toEqual({
      "Long distance A": "3,488 mm",
      "Long distance B": "6,001 mm",
      "Ceiling heights": "12 rooms",
      Openings: "14",
      "Floor to floor · landmarks": "none · one floor",
    });
    expect(
      within(region("Field controls")).getByRole("link", { name: "Download field-controls.json" }),
    ).toBeTruthy();
    const station = region("Station");
    expect([...station.querySelectorAll(".station-row")].map((row) => row.textContent)).toEqual([
      "RegisteredOct 17 · 11:05",
      "Checks run · 14 rules11:20",
      "Verdict · Limited11:20",
      "Published to the HUB11:21",
    ]);
    const documents = region("Documents");
    expect([...documents.querySelectorAll(".doc-row")].map((row) => row.textContent)).toEqual([
      "Spatial report PDFbeing generated",
      "Plan sheet PDF7.7 KB · from the phone",
      "verdict.jsonstation",
      "manifest.json33 entries · SHA-256",
    ]);
    expect(
      within(documents)
        .getByRole("link", { name: /verdict\.json/ })
        .getAttribute("href"),
    ).toBe(`/packages/${IDS.westEnd1}/verdict.json`);
  });

  it("links the report from the documents once it is ready, and the rooms in the record", async () => {
    await renderPackage(ready(), IDS.westEnd1);
    const documents = region("Documents");
    expect(within(documents).getByRole("link", { name: /Spatial report PDF/ }).textContent).toBe(
      "Spatial report PDF28 pages · 3.2 MB",
    );
    expect(asideRows("Capture record").Rooms).toBe("12 scanned · 2 not scanned");
  });

  it("links the HUB files folder when it is configured", async () => {
    vi.stubEnv(
      "HUB_FILES_URL_TEMPLATE",
      "https://hub.example/deals/{dealId}/files?folder={folder}",
    );
    try {
      await renderPackage(sample(), IDS.westEnd1);
      const link = within(region("Station")).getByRole("link", {
        name: /HUB › Files › Capture › r1/,
      });
      expect(link.getAttribute("href")).toBe(
        "https://hub.example/deals/4417203/files?folder=Capture%2Fb8dbc48a-f67f-4fd1-9859-7cfc2edaad7e%2Fr1",
      );
    } finally {
      vi.unstubAllEnvs();
    }
  });
});

describe("plan sheet documents (D8)", () => {
  const base: PackageFile = {
    path: "x/plan-sheet.pdf",
    role: "plan_pdf",
    sha256: "a".repeat(64),
    bytes: 2_100_000,
    status: "verified",
  };

  it("says Tabloid for a v2 plan sheet and the size for an older plan PDF", () => {
    expect(
      planSheetDetail({
        ...base,
        generator: "chapter-capture-ios/PlanExport",
        generatorVersion: "2.0.0",
      }),
    ).toBe("Tabloid · 1 sheet · from the phone");
    expect(
      planSheetDetail({
        ...base,
        generator: "chapter-capture-ios/PlanExport",
        generatorVersion: "1.9.3",
      }),
    ).toBe("2.1 MB · from the phone");
    expect(
      planSheetDetail({
        ...base,
        generator: "chapter-fixtures/PlanExport",
        generatorVersion: "2.0.0",
      }),
    ).toBe("2.1 MB · from the phone");
    expect(versionAtLeast("2.10.0", "2.9.0")).toBe(true);
    expect(versionAtLeast("10.0.0", "2.0.0")).toBe(true);
    expect(versionAtLeast("x", "2.0.0")).toBe(false);
  });
});

describe("two floors", () => {
  it("has one plan tab per floor and shows the floor named by ?floor=", async () => {
    await renderPackage(statesScenario(NOW), IDS.twoFloors, { query: { floor: "floor-2" } });
    const plan = region("Plan");
    const tabs = within(within(plan).getByRole("navigation", { name: "Floors" })).getAllByRole(
      "link",
    );
    expect(tabs.map((tab) => [tab.textContent, tab.getAttribute("href")])).toEqual([
      ["Floor 1", "?floor=floor-1#plan"],
      ["Floor 2", "?floor=floor-2#plan"],
    ]);
    expect(tabs[1]?.getAttribute("aria-current")).toBe("page");
    expect(within(plan).getByText("Floor 2 · whole floor")).toBeTruthy();
    expect(asideRows("Capture record").Compass).toBe("Floor 1 verified · Floor 2 not read");
    expect(Object.keys(asideRows("Field controls"))).toContain("Floor 2 · long distance A");
  });
});

describe("states without a verdict", () => {
  const states = () => statesScenario(NOW);

  it("shows the upload progress and what is not there yet", async () => {
    const station = await renderPackage(states(), IDS.valley1);
    const card = screen.getByRole("status", { name: "Uploading from the phone" });
    expect(card.textContent).toContain(
      "Not every file is verified and sealed yet. The checks start when the package is sealed.",
    );
    const bar = within(card).getByRole("progressbar");
    expect(card.textContent).toMatch(
      new RegExp(`of 230 KB · ${bar.getAttribute("aria-valuenow")}%`),
    );
    expect(screen.queryByRole("region", { name: "Capture checks" })).toBeNull();
    expect(screen.queryByRole("region", { name: "Plan" })).toBeNull();
    expect(region("Capture record").textContent).toContain(
      "The capture record is available once the package is sealed.",
    );
    expect(region("Field controls").textContent).toContain(
      "Field controls are shown once the package is sealed.",
    );
    expect(
      [...region("Documents").querySelectorAll(".doc-row")].map((row) => row.textContent),
    ).toContain("manifest.jsonafter sealing");
    expect(region("Station").textContent).toContain("Checksafter upload");
    expect(document.body.textContent).toContain("uploading since Oct 21, 2026");
    expect(station.calls.some((call) => call.path.endsWith("/verdict"))).toBe(false);
  });

  it("says the checks are running", async () => {
    await renderPackage(states(), IDS.checking);
    expect(screen.getByRole("status", { name: "Checks running" }).textContent).toContain(
      "The station is checking this package. The verdict and findings appear here when the checks finish.",
    );
    expect(region("Station").textContent).toContain("Checks running");
  });

  it("says the checks could not complete, as an alert, not a verdict", async () => {
    await renderPackage(states(), IDS.checkError);
    const card = screen.getByRole("alert");
    expect(card.textContent).toContain("The checks could not complete");
    expect(region("Station").textContent).toContain("Checks did not finish");
  });

  it("says when the phone replaced an upload with a new revision", async () => {
    await renderPackage(states(), IDS.stopped1);
    const card = screen.getByRole("status", { name: "Upload stopped" });
    expect(card.textContent).toContain(
      "The phone stopped this upload and sealed the capture again as revision 2. This revision is not checked.",
    );
    expect(within(card).getByRole("link", { name: "Open revision 2 →" }).getAttribute("href")).toBe(
      `/packages/${IDS.stopped2}`,
    );
  });

  it("words a stopped upload as stopped everywhere on its page, waiting for nothing", async () => {
    await renderPackage(states(), IDS.stopped1);
    const header = document.querySelector(".title-row") as HTMLElement;
    expect(within(header).getByText("Not checked")).toBeTruthy();
    expect(header.querySelector(".meta-row")?.textContent).toBe(
      "upload stopped · replaced by revision 2",
    );
    expect(document.body.textContent).not.toContain("uploading since");
    expect(
      [...region("Station").querySelectorAll(".station-row")].map((row) => row.textContent),
    ).toEqual([
      expect.stringMatching(/^Registered/),
      "Upload stoppedreplaced by revision 2",
      "Verdictnot checked",
      "Not published—",
    ]);
    expect(
      [...region("Documents").querySelectorAll(".doc-row")].map((row) => row.textContent),
    ).toEqual([
      "Spatial report PDFnot checked",
      "verdict.jsonnot checked",
      "manifest.jsonnot sealed",
    ]);
    expect(document.body.textContent).not.toMatch(/after upload|after the checks|after sealing/);
  });

  it("treats verdict_not_ready as checks running", async () => {
    const fixture = contractExampleCase();
    await renderPackage(caseData(fixture, null), fixture.pkg.packageId);
    expect(screen.getByRole("status", { name: "Checks running" })).toBeTruthy();
    expect(screen.queryByRole("region", { name: /^Verdict: / })).toBeNull();
  });
});

describe("newer revisions", () => {
  it("points from revision 1 to the newer verdict of revision 2", async () => {
    await renderPackage(drawnScenario(NOW), IDS.shawnee1);
    const card = region("Verdict: Blocked");
    expect(card.textContent).toContain("Revision 2 has a newer verdict:");
    expect(within(card).getByRole("link", { name: "Open revision 2 →" }).getAttribute("href")).toBe(
      `/packages/${IDS.shawnee2}`,
    );
  });

  it("lists the retired phone report of a legacy package", async () => {
    await renderPackage(statesScenario(NOW), IDS.legacy);
    const card = region(/^Files · /);
    await act(async () => {
      fireEvent.click(within(card).getByRole("button", { name: /Show all/ }));
    });
    expect(card.textContent).toContain("Spatial report · phone (retired)");
  });
});

describe("station problems", () => {
  it("is not found for an unknown package", async () => {
    await expect(
      renderPackage(drawnScenario(NOW), "00000000-0000-4000-8000-000000000000"),
    ).rejects.toThrow(/NEXT_HTTP_ERROR_FALLBACK;404/);
  });

  it("asks to sign in again when the station refuses the token", async () => {
    const station = createFakeStation(drawnScenario(NOW));
    station.failWith = 401;
    state.session = sessionFor(["bim"], station);
    render(
      await PackagePage({
        params: Promise.resolve({ packageId: IDS.westEnd1 }),
        searchParams: Promise.resolve({}),
      }),
    );
    const alert = screen.getByRole("alert");
    expect(alert.textContent).toContain("Sign in again");
    expect(within(alert).getByRole("link", { name: "Sign in again" }).getAttribute("href")).toBe(
      "/sign-in",
    );
  });
});
