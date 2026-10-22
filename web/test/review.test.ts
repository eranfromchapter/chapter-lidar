// web-review §6.1-6.3: verdict tabs, list cells and package words shared by the lists.

import { describe, expect, it } from "vitest";
import { pendingWords } from "@/components/hub/VerdictBadge";
import { stationSteps } from "@/components/package/StationCard";
import {
  newerRevisions,
  newestPerVisit,
  replacedBy,
  replacedByText,
  uploadStoppedText,
} from "@/lib/packages";
import { checkedAt, contentsLine, packageSubLine } from "@/lib/project-view";
import {
  capturedText,
  emptyTabText,
  filterByTab,
  hubText,
  latestPackageText,
  newestUpdate,
  normalizeQuery,
  parseTab,
  projectTitle,
  tabCounts,
  uploadPercent,
} from "@/lib/review";
import type { PackageSummary, ReviewProject } from "@/lib/station-types";
import { summaryOf } from "./support/fixtures";
import { drawnScenario, IDS, statesScenario } from "./support/scenarios";

const now = new Date("2026-10-21T18:00:00Z");
const data = drawnScenario(now);
const summary = (id: string): PackageSummary =>
  summaryOf(data.packages.find((pkg) => pkg.packageId === id) ?? (undefined as never));

describe("tabs", () => {
  const projects: ReviewProject[] = data.packages.map((pkg) => ({
    dealId: pkg.dealId,
    address: { formatted: pkg.dealId },
    packageCount: 1,
    latest: summaryOf(pkg),
  }));

  it("count projects by their newest package", () => {
    // Shawnee's two revisions count twice here; the station returns one row per deal.
    expect(tabCounts(projects)).toEqual({ all: 6, blocked: 2, limited: 1, ready: 2, progress: 1 });
    expect(filterByTab(projects, "progress").map((project) => project.latest.packageId)).toEqual([
      IDS.valley1,
    ]);
    expect(filterByTab(projects, "all")).toBe(projects);
  });

  it("read the tab and the search from the URL", () => {
    expect(parseTab("limited")).toBe("limited");
    expect(parseTab(["ready", "blocked"])).toBe("ready");
    expect(parseTab("anything")).toBe("all");
    expect(parseTab(undefined)).toBe("all");
    expect(normalizeQuery("  424 West  ")).toBe("424 West");
    expect(normalizeQuery("x".repeat(250))).toHaveLength(200);
    expect(emptyTabText("blocked")).toBe("No Blocked projects.");
    expect(emptyTabText("progress")).toBe("No packages uploading or being checked.");
  });
});

describe("list cells", () => {
  it("words the newest package", () => {
    expect(latestPackageText(summary(IDS.westEnd1))).toEqual({
      text: "Revision 1 · sealed Oct 17, 2026",
    });
    const valley = latestPackageText(summary(IDS.valley1));
    expect(valley.text).toBe("Revision 1 · uploading from the phone");
    expect(valley.percent).toBe(uploadPercent(summary(IDS.valley1)));
    expect(valley.percent).toBeGreaterThan(55);
    expect(valley.percent).toBeLessThanOrEqual(67);
  });

  it("words who captured the package and when", () => {
    expect(capturedText(summary(IDS.westEnd1), now)).toBe("Oct 17, 2026 · Test Operator");
    expect(capturedText(summary(IDS.valley1), now)).toBe("Today · Casey Capture");
    const { createdBy: _by, ...anonymous } = summary(IDS.valley1);
    expect(capturedText(anonymous, now)).toBe("Today");
  });

  it("words the HUB state", () => {
    expect(hubText(summary(IDS.westEnd1))).toEqual({
      text: "Published Oct 17, 2026",
      tone: "normal",
    });
    expect(hubText(summary(IDS.valley1))).toEqual({ text: "—", tone: "muted" });
    expect(hubText(summary(IDS.blocked1))).toEqual({
      text: "Not published · re-seal needed",
      tone: "normal",
    });
    const pending = {
      ...summary(IDS.westEnd1),
      publication: { status: "publishing" as const, hubFolder: "x" },
    };
    expect(hubText(pending)).toEqual({ text: "Publishing…", tone: "muted" });
    const failed = {
      ...pending,
      publication: { status: "publish_failed" as const, hubFolder: "x" },
    };
    expect(hubText(failed)).toEqual({ text: "Publishing failed", tone: "danger" });
  });

  it("titles projects by name, else address", () => {
    expect(
      projectTitle({ projectName: "424 West End Ave, Apt 4K", address: { formatted: "x" } }),
    ).toBe("424 West End Ave, Apt 4K");
    expect(projectTitle({ address: { formatted: "618 Valley Street" } })).toBe("618 Valley Street");
    expect(newestUpdate(data.packages.map(summaryOf))).toBe(summary(IDS.westEnd1).updatedAt);
    expect(newestUpdate([])).toBeUndefined();
  });
});

describe("project table words", () => {
  const states = statesScenario(now);
  const deal = (dealId: string) =>
    states.packages
      .filter((pkg) => pkg.dealId === dealId)
      .map(summaryOf)
      .sort((a, b) => b.revision - a.revision);

  it("words the contents with the spatial report's room facts when present", () => {
    expect(contentsLine(summary(IDS.westEnd1))).toBe("1 floor · 33 files · 584 KB");
    const ready = summaryOf(
      drawnScenario(now, { reportReady: true }).packages.find(
        (pkg) => pkg.packageId === IDS.westEnd1,
      ) ?? (undefined as never),
    );
    expect(contentsLine(ready)).toBe("1 floor · 12 rooms · 33 files · 584 KB");
  });

  it("words the package line by state", () => {
    const packages = data.packages.map(summaryOf);
    expect(packageSubLine(summary(IDS.westEnd1), packages)).toMatchObject({
      text: "capture 33ede7f4…",
      mono: true,
    });
    expect(packageSubLine(summary(IDS.valley1), packages).text).toMatch(
      /^uploading from the phone · \d+%$/,
    );
    const checking = summaryOf(
      states.packages.find((pkg) => pkg.packageId === IDS.checking) ?? (undefined as never),
    );
    expect(packageSubLine(checking, [checking]).text).toBe("sealed · checks running");
    const failed = summaryOf(
      states.packages.find((pkg) => pkg.packageId === IDS.checkError) ?? (undefined as never),
    );
    expect(packageSubLine(failed, [failed]).text).toBe("sealed · checks did not finish");
    expect(checkedAt(checking)).toBeUndefined();
  });

  it("labels an upload the phone replaced with a new revision", () => {
    const stopped = deal("4419004");
    const [second, first] = stopped;
    if (first === undefined || second === undefined) {
      throw new Error("the states scenario has two revisions of 7 Stopped Road");
    }
    expect(replacedBy(stopped, first)?.packageId).toBe(IDS.stopped2);
    expect(replacedBy(stopped, second)).toBeUndefined();
    expect(packageSubLine(first, stopped).text).toBe("upload stopped · replaced by revision 2");
    expect(newerRevisions(stopped, first).map((pkg) => pkg.revision)).toEqual([2]);
    expect(newestPerVisit(stopped).map((pkg) => pkg.packageId)).toEqual([IDS.stopped2]);
  });

  it("words a stopped upload one way: badge, lines and station steps", () => {
    const stopped = deal("4419004");
    const [second, first] = stopped;
    if (first === undefined || second === undefined) {
      throw new Error("the states scenario has two revisions of 7 Stopped Road");
    }
    expect(uploadStoppedText(second)).toBe("upload stopped · replaced by revision 2");
    expect(replacedByText(second)).toBe("replaced by revision 2");
    expect(pendingWords("uploading", true)).toBe("Not checked");
    expect(pendingWords("uploading")).toBe("Not checked yet");
    const steps = stationSteps(first, null, second);
    expect(steps.map((step) => [step.label, step.note])).toEqual([
      ["Registered", undefined],
      ["Upload stopped", "replaced by revision 2"],
      ["Verdict", "not checked"],
      ["Not published", undefined],
    ]);
    expect(steps.slice(1).every((step) => step.glyph === "dash")).toBe(true);
    // Without a successor the upload is still waiting for its checks.
    expect(stationSteps(first, null).map((step) => [step.label, step.note])).toContainEqual([
      "Checks",
      "after upload",
    ]);
  });

  it("prefixes the visit day when a project has several visits", () => {
    const shawnee = data.packages.filter((pkg) => pkg.dealId === "4416950").map(summaryOf);
    const other = { ...summary(IDS.east811), dealId: "4416950" };
    expect(packageSubLine(other, [...shawnee, other]).prefix).toMatch(/^visit Oct \d+, 2026 · $/);
    expect(packageSubLine(shawnee[0] as PackageSummary, shawnee).prefix).toBe("");
  });
});
