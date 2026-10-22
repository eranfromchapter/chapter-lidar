// The review screen and contract/openapi/station.yaml 1.1.0 (WR-AC11 from the web's side):
// every call the station client makes is a documented operation with valid parameters and
// body, and every answer of the fake station the web's tests run against validates against the
// documented response, so the fixtures cannot drift from the station API.

import { beforeAll, describe, expect, it, vi } from "vitest";
import type { StationRole } from "@/lib/roles";
import { createStationClient, StationError, type StationClient } from "@/lib/station";
import type { StationPackage } from "@/lib/station-types";
import type { ViewerSession } from "@/lib/viewer";
import {
  createFakeStation,
  sessionFor,
  STATION_URL,
  TEST_ACCESS_TOKEN,
  type FakeStation,
} from "./support/station";
import { contractExampleCase, generatedFixtureCases } from "./support/fixtures";
import { StationOpenApi } from "./support/openapi";
import { DEALS, drawnScenario, emptyScenario, IDS, statesScenario } from "./support/scenarios";

const state = vi.hoisted(() => ({ session: null as ViewerSession | null }));

vi.mock("@/lib/viewer", () => ({
  getViewerSession: async () => state.session,
  requireViewerSession: async () => state.session,
}));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));

const now = new Date("2026-10-21T18:00:00Z");
let openapi: StationOpenApi;

beforeAll(() => {
  openapi = new StationOpenApi();
});

function client(station: FakeStation): StationClient {
  return createStationClient({
    baseUrl: STATION_URL,
    accessToken: TEST_ACCESS_TOKEN,
    fetchImpl: station.fetch,
  });
}

async function settle<T>(promise: Promise<T>): Promise<T | StationError> {
  try {
    return await promise;
  } catch (error) {
    if (error instanceof StationError) {
      return error;
    }
    throw error;
  }
}

/** Calls every operation the review screen uses, for every project and package of `station`. */
async function exercise(station: FakeStation): Promise<void> {
  const api = client(station);
  await api.listReviewProjects();
  await api.listReviewProjects({ q: "West End", limit: 2 });
  await api.listReviewProjects({ q: "5d236b10" });
  await api.listReviewPackages();
  await api.listReviewPackages({ q: "nothing", limit: 200 });
  await api.listAllModelingDecisions({ limit: 100 });
  const deals = [...new Set(station.data.packages.map((pkg) => pkg.dealId))];
  for (const dealId of deals) {
    await settle(api.getProject(dealId));
    await api.listPackages(dealId);
    await api.listAllModelingDecisions({ dealId, limit: 200 });
  }
  await settle(api.getProject("no-such-deal"));
  for (const pkg of station.data.packages) {
    const detail = await api.getPackage(pkg.packageId);
    await api.getVerdict(pkg.packageId);
    await settle(api.getSpatialReportLink(pkg.packageId));
    const verified = detail.files.find((file) => file.status === "verified");
    if (verified !== undefined) {
      await api.getFileDownloadLink(pkg.packageId, verified.path);
    }
    const pending = detail.files.find((file) => file.status !== "verified");
    if (pending !== undefined) {
      await settle(api.getFileDownloadLink(pkg.packageId, pending.path));
    }
    if (detail.manifestFile !== undefined) {
      await api.getFileDownloadLink(pkg.packageId, detail.manifestFile.path);
    }
    await api.listModelingDecisions(pkg.packageId);
  }
  await settle(api.getPackage("00000000-0000-4000-8000-000000000000"));
  const [first] = station.data.packages as [StationPackage];
  const dxf = first.files.find((file) => file.role === "plan_dxf");
  await api.createModelingDecision(first.packageId, {
    element: "Living Room walls",
    decision: "native Revit walls",
    sources: [{ path: dxf?.path ?? "" }],
  });
  await settle(
    api.createModelingDecision(first.packageId, {
      element: "x",
      decision: "y",
      sources: [{ path: "Original Exports/elsewhere.dxf" }],
    }),
  );
}

function violations(station: FakeStation): string[] {
  const problems: string[] = [];
  for (const call of station.calls) {
    const op = openapi.match(call.method, call.path);
    if (op === undefined) {
      problems.push(`${call.method} ${call.path}: not an operation of the station API`);
      continue;
    }
    for (const error of openapi.queryErrors(op, call.search)) {
      problems.push(`${op.operationId} query: ${error}`);
    }
    if (call.body !== undefined) {
      for (const error of openapi.bodyErrors(op, call.body)) {
        problems.push(`${op.operationId} body: ${error}`);
      }
    }
    for (const error of openapi.responseErrors(op, call.status ?? 0, call.response)) {
      problems.push(`${op.operationId} ${call.status} ${call.path}: ${error}`);
    }
  }
  return problems;
}

describe("station API contract", () => {
  it("is station.yaml 1.1.0", () => {
    expect(openapi.version).toBe("1.1.0");
  });

  it("has every operation the review screen calls", () => {
    for (const operationId of [
      "getProject",
      "listPackages",
      "getPackage",
      "getVerdict",
      "getFileDownloadLink",
      "getSpatialReportLink",
      "listModelingDecisions",
      "createModelingDecision",
      "listReviewProjects",
      "listReviewPackages",
      "listAllModelingDecisions",
    ]) {
      expect(
        openapi.operations.some((op) => op.operationId === operationId),
        operationId,
      ).toBe(true);
    }
  });

  it.each([
    ["the drawn scenario, spatial report pending", () => drawnScenario(now)],
    ["the drawn scenario, spatial report ready", () => drawnScenario(now, { reportReady: true })],
    ["every other package state", () => statesScenario(now)],
    ["no packages", () => emptyScenario()],
  ])("calls and answers of %s follow the contract", async (_name, data) => {
    const station = createFakeStation(data());
    if (station.data.packages.length > 0) {
      await exercise(station);
    } else {
      await client(station).listReviewProjects();
      await client(station).listReviewPackages();
    }
    expect(station.calls.length).toBeGreaterThan(0);
    expect(violations(station)).toEqual([]);
  });

  it("answers for every generated fixture and the contract example follow the contract", async () => {
    const cases = [contractExampleCase(), ...generatedFixtureCases()];
    const station = createFakeStation({
      projects: [],
      packages: cases.map((fixture, index) => ({
        ...fixture.pkg,
        // Fixtures share ids; the station would not.
        packageId: `${String(index).padStart(8, "0")}-0000-4000-8000-000000000000`,
        dealId: `deal-${index}`,
      })),
      verdicts: {},
      decisions: {},
    });
    const api = client(station);
    for (const pkg of station.data.packages) {
      await api.getPackage(pkg.packageId);
      await api.listPackages(pkg.dealId);
    }
    await api.listReviewProjects();
    expect(violations(station)).toEqual([]);
  });

  it("catches a fixture that drifts from the API", async () => {
    const station = createFakeStation(drawnScenario(now));
    const [pkg] = station.data.packages as [StationPackage];
    await client(station).getPackage(pkg.packageId);
    const op = openapi.match("GET", `/packages/${pkg.packageId}`);
    if (op === undefined) {
      throw new Error("getPackage is an operation");
    }
    const body = station.calls[0]?.response as Record<string, unknown>;
    expect(openapi.responseErrors(op, 200, body)).toEqual([]);
    expect(openapi.responseErrors(op, 200, { ...body, registeredAt: body.createdAt })).not.toEqual(
      [],
    );
    const { totals: _totals, ...withoutTotals } = body;
    expect(openapi.responseErrors(op, 200, withoutTotals)).not.toEqual([]);
    expect(openapi.queryErrors(op, new URLSearchParams("extra=1"))).not.toEqual([]);
  });

  it("sends the signed-in user's token on every call", async () => {
    const station = createFakeStation(drawnScenario(now));
    await client(station).listReviewProjects();
    expect(
      station.calls.every((call) => call.authorization === `Bearer ${TEST_ACCESS_TOKEN}`),
    ).toBe(true);
  });

  it.each([["capture"], ["bim"], ["admin"]] as [StationRole][])(
    "every page calls only operations the %s role may call",
    async (role) => {
      const { default: ProjectsPage } = await import("@/app/(review)/page");
      const { default: PackagesPage } = await import("@/app/(review)/packages/page");
      const { default: ProjectPage } = await import("@/app/(review)/projects/[dealId]/page");
      const { default: PackagePage } = await import("@/app/(review)/packages/[packageId]/page");
      const { default: DecisionLogPage } = await import("@/app/(review)/decisions/page");
      const station = createFakeStation(drawnScenario(now, { reportReady: true }));
      state.session = sessionFor([role], station);
      await ProjectsPage({ searchParams: Promise.resolve({}) });
      await PackagesPage({ searchParams: Promise.resolve({}) });
      for (const dealId of Object.values(DEALS)) {
        await ProjectPage({
          params: Promise.resolve({ dealId }),
          searchParams: Promise.resolve({ tab: "log" }),
        });
      }
      for (const packageId of [IDS.westEnd1, IDS.valley1, IDS.shawnee1, IDS.blocked1]) {
        await PackagePage({
          params: Promise.resolve({ packageId }),
          searchParams: Promise.resolve({}),
        });
      }
      await DecisionLogPage();
      expect(station.calls.length).toBeGreaterThan(10);
      const refused = station.calls
        .map((call) => ({ call, op: openapi.match(call.method, call.path) }))
        .filter(({ op }) => op === undefined || !op.roles.includes(role))
        .map(({ call, op }) => `${op?.operationId ?? call.path}`);
      expect(refused).toEqual([]);
      expect(violations(station)).toEqual([]);
      state.session = null;
    },
  );
});
