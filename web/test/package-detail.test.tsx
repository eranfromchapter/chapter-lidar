// @vitest-environment jsdom
// AC2: package detail shows the outcome and every finding from the station, for the contract's
// verdict example and for the verdict the station checks produce on every generated fixture.

import type { Finding, Verdict } from "@chapter/capture-contract";
import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import {
  formatBytes,
  outcomeHeadline,
  pathDisplayName,
  SEVERITY_ORDER,
  severityLabel,
} from "@/lib/format";
import type { ViewerSession } from "@/lib/viewer";
import { contractExampleCase, generatedFixtureCases, type FixtureCase } from "./support/fixtures";
import { createFakeStation, sessionFor, type FakeStation } from "./support/station";

const state = vi.hoisted(() => ({ session: null as ViewerSession | null }));

vi.mock("@/lib/viewer", () => ({
  getViewerSession: async () => state.session,
  requireViewerSession: async () => {
    if (state.session === null) {
      throw new Error("requireViewerSession called without a session");
    }
    return state.session;
  },
}));

const { default: PackagePage } = await import("@/app/packages/[packageId]/page");

const cases: FixtureCase[] = [contractExampleCase(), ...generatedFixtureCases()];

/** `verdict: null` makes the station answer 404 verdict_not_ready. */
function stationFor(fixture: FixtureCase, verdict: Verdict | null = fixture.verdict) {
  return createFakeStation({
    projects: [fixture.project],
    packages: [structuredClone(fixture.pkg)],
    verdicts: verdict === null ? {} : { [fixture.pkg.packageId]: verdict },
    decisions: {},
  });
}

async function renderPackage(
  fixture: FixtureCase,
  station: FakeStation,
  searchParams: Record<string, string> = {},
) {
  state.session = sessionFor(["bim"], station);
  return render(
    await PackagePage({
      params: Promise.resolve({ packageId: fixture.pkg.packageId }),
      searchParams: Promise.resolve(searchParams),
    }),
  );
}

function findingRows(): HTMLElement[] {
  const findings = screen.getByRole("region", { name: "Findings" });
  return within(findings)
    .getAllByRole("row")
    .filter((row) => row.hasAttribute("data-severity"));
}

/** Findings in the order the screen lists them: grouped by severity, station order inside. */
function expectedOrder(verdict: Verdict): Finding[] {
  return SEVERITY_ORDER.flatMap((severity) =>
    verdict.findings.filter((finding) => finding.severity === severity),
  );
}

beforeAll(() => {
  Element.prototype.scrollIntoView = vi.fn();
});

afterEach(() => {
  cleanup();
  state.session = null;
});

describe("fixture verdicts", () => {
  it("covers all three outcomes", () => {
    const outcomes = new Set(cases.map((fixture) => fixture.verdict.outcome));
    expect([...outcomes].sort()).toEqual(["blocked", "limited", "ready"]);
    expect(cases.length).toBe(12);
  });
});

describe.each(cases.map((fixture) => [fixture.name, fixture] as const))(
  "package detail: %s",
  (_name, fixture) => {
    it("shows the outcome in plain words with its shape, the summary and the counts", async () => {
      const station = stationFor(fixture);
      await renderPackage(fixture, station);
      const { verdict } = fixture;
      const card = screen.getByRole("region", { name: /^Verdict: / });
      expect(card.getAttribute("data-outcome")).toBe(verdict.outcome);
      expect(within(card).getByText(outcomeHeadline(verdict.outcome))).toBeTruthy();
      expect(within(card).getByText(verdict.summary)).toBeTruthy();
      const blockers = verdict.findings.filter((f) => f.severity === "blocker").length;
      const limitations = verdict.findings.filter((f) => f.severity === "limitation").length;
      const passed = verdict.checks.filter((c) => c.status === "passed").length;
      expect(card.textContent).toContain(
        `${blockers} blocker${blockers === 1 ? "" : "s"} · ${limitations} limitation${
          limitations === 1 ? "" : "s"
        } · ${passed} passed`,
      );
      for (const limitation of verdict.limitations) {
        expect(within(card).getByText(limitation)).toBeTruthy();
      }
      for (const action of verdict.nextActions) {
        expect(within(card).getByText(`Next: ${action}`)).toBeTruthy();
      }
    });

    it("lists every finding, grouped by severity, with rule, file, values and next action", async () => {
      const station = stationFor(fixture);
      await renderPackage(fixture, station);
      const { verdict, pkg } = fixture;
      const rows = findingRows();
      const expected = expectedOrder(verdict);
      expect(rows).toHaveLength(verdict.findings.length);
      expected.forEach((finding, index) => {
        const row = rows[index] as HTMLElement;
        const cells = within(row).getAllByRole("cell");
        const check = verdict.checks.find((item) => item.ruleId === finding.ruleId);
        expect(row.getAttribute("data-severity")).toBe(finding.severity);
        expect(cells[0]?.textContent).toBe(
          severityLabel(finding.severity, check?.status === "passed"),
        );
        expect(cells[1]?.textContent).toContain(check?.title ?? finding.ruleId);
        expect(cells[1]?.textContent).toContain(finding.message);
        if (finding.filePath !== undefined) {
          expect(cells[2]?.textContent).toBe(
            pathDisplayName(finding.filePath, pkg.files, pkg.captureRecord),
          );
        }
        if (finding.measured !== undefined) {
          expect(cells[3]?.textContent).toContain(finding.measured);
        }
        if (finding.expected !== undefined) {
          expect(cells[3]?.textContent).toContain(`Expected: ${finding.expected}`);
        }
        expect(cells[4]?.textContent).toBe(finding.nextAction);
      });
      const findings = screen.getByRole("region", { name: "Findings" });
      expect(within(findings).getByText(verdict.statement)).toBeTruthy();
    });

    it("lists every file with role, size, SHA-256, HUB state and a download link", async () => {
      const station = stationFor(fixture);
      await renderPackage(fixture, station);
      const filesRegion = screen.getByRole("region", { name: "Files" });
      const rows = within(filesRegion)
        .getAllByRole("row")
        .filter((row) => row.hasAttribute("data-path"));
      expect(rows.map((row) => row.getAttribute("data-path"))).toEqual(
        fixture.pkg.files.map((file) => file.path),
      );
      fixture.pkg.files.forEach((file, index) => {
        const row = rows[index] as HTMLElement;
        expect(row.textContent).toContain(formatBytes(file.bytes));
        expect(within(row).getByTitle(file.sha256)).toBeTruthy();
        expect(row.textContent).toContain(
          file.bytes > 45_000_000 ? "Linked (over 45 MB)" : "Uploaded",
        );
        expect(within(row).getByRole("link", { name: /^Download / })).toBeTruthy();
      });
    });
  },
);

describe("package detail states", () => {
  const fixture = contractExampleCase();

  it("shows 'checks running' while the station has no verdict yet", async () => {
    const pkg = { ...structuredClone(fixture.pkg), status: "checking" as const };
    delete pkg.verdict;
    const station = createFakeStation({
      projects: [fixture.project],
      packages: [pkg],
      verdicts: {},
      decisions: {},
    });
    await renderPackage(fixture, station);
    expect(screen.getByText("Checks running")).toBeTruthy();
    expect(screen.queryByRole("region", { name: "Findings" })).toBeNull();
    expect(station.calls.some((call) => call.path.endsWith("/verdict"))).toBe(false);
  });

  it("shows 'checks running' when the station answers verdict_not_ready", async () => {
    const station = stationFor(fixture, null);
    await renderPackage(fixture, station);
    expect(screen.getByText("Checks running")).toBeTruthy();
    expect(screen.queryByRole("region", { name: /^Verdict: / })).toBeNull();
  });

  it("highlights and scrolls to the file named by ?file=", async () => {
    const target = fixture.pkg.files.find((file) => file.role === "mesh_glb");
    expect(target).toBeDefined();
    const station = stationFor(fixture);
    await renderPackage(fixture, station, { file: target?.path ?? "" });
    const highlighted = document.querySelector('tr[aria-current="true"]');
    expect(highlighted?.getAttribute("data-path")).toBe(target?.path);
    expect(highlighted?.textContent).toContain("Linked (over 45 MB)");
    expect(Element.prototype.scrollIntoView).toHaveBeenCalled();
  });

  it("shows the capture record line from the station", async () => {
    const station = stationFor(fixture);
    await renderPackage(fixture, station);
    const record = fixture.pkg.captureRecord;
    expect(record).toBeDefined();
    const heading = screen.getByRole("heading", { level: 1 });
    expect(heading.textContent).toBe(`${record?.address.formatted} · revision 1`);
    const main = screen.getByRole("main");
    expect(main.textContent).toContain(`by ${record?.operator.name}`);
    expect(main.textContent).toContain("whole floor × 2");
    for (const capture of record?.captures ?? []) {
      expect(main.textContent).toContain(capture.captureId);
    }
  });

  it("previews plan PNGs through this app for bim users", async () => {
    const withPlan = cases.find((item) => item.pkg.files.some((file) => file.role === "plan_png"));
    expect(withPlan).toBeDefined();
    if (withPlan === undefined) {
      return;
    }
    const station = stationFor(withPlan);
    const { container } = await renderPackage(withPlan, station);
    const images = [...container.querySelectorAll("img")];
    const plans = withPlan.pkg.files.filter((file) => file.role === "plan_png");
    expect(images).toHaveLength(plans.length);
    for (const image of images) {
      expect(image.getAttribute("src")).toMatch(
        new RegExp(`^/packages/${withPlan.pkg.packageId}/files/preview\\?path=`),
      );
    }
    expect(station.calls.some((call) => call.path.endsWith("/files/download"))).toBe(false);
  });

  it("shows the project list with each latest outcome", async () => {
    const station = stationFor(fixture);
    await renderPackage(fixture, station);
    const nav = screen.getByRole("navigation", { name: "Projects" });
    const link = within(nav).getByRole("link", {
      name: new RegExp(fixture.project.address.formatted),
    });
    expect(link.getAttribute("aria-current")).toBe("page");
    expect(link.textContent).toContain("▲ Limited · r1 · 2 floors");
  });
});
