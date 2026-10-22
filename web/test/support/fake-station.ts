// In-memory station API: a fetch implementation that answers the operations the review screen
// uses (contract/openapi/station.yaml 1.1.0) from fixture data, and records each call. The
// component tests use it through the real station client; the end-to-end station serves it
// over HTTP (web/e2e/mock-station.ts). No Next.js or server-only imports here.

import type { Verdict } from "@chapter/capture-contract";
import type {
  DownloadLink,
  HubProject,
  ModelingDecision,
  ModelingDecisionInput,
  ModelingDecisionWithContext,
  PackageSummary,
  ReviewPackage,
  ReviewProject,
  SpatialReportLink,
  StationPackage,
} from "@/lib/station-types";
import { summaryOf } from "./fixtures";

export const STATION_URL = "https://station.test";
export const TEST_ACCESS_TOKEN = "test-access-token";

export interface FakeStationData {
  /** The HUB projects the station knows (cache); a deal without one answers 404. */
  projects: HubProject[];
  packages: StationPackage[];
  /** Verdict per packageId; absent means 404 verdict_not_ready. */
  verdicts: Record<string, Verdict>;
  decisions: Record<string, ModelingDecision[]>;
}

export interface RecordedCall {
  method: string;
  path: string;
  search: URLSearchParams;
  authorization: string | null;
  body: unknown;
  /** Status the fake answered with. */
  status?: number;
  /** Body the fake answered with (JSON). */
  response?: unknown;
}

export interface FakeStationOptions {
  /** Base of the signed links it hands out (a blob store). */
  readonly blobBase?: string;
  /** Bearer tokens it accepts. */
  readonly tokens?: readonly string[];
  /** Accept any bearer token (the end-to-end station; roles are the web's to hide). */
  readonly acceptAnyToken?: boolean;
}

export interface FakeStation {
  data: FakeStationData;
  readonly calls: RecordedCall[];
  readonly fetch: typeof fetch;
  /** Who the station records as the author of new decisions. */
  author: { name: string; userId: string };
  /** Time the station records for new decisions. */
  now: string;
  /** Status to answer every call with instead (station down, 401, ...). */
  failWith?: number;
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": status >= 400 ? "application/problem+json" : "application/json",
    },
  });
}

function problem(status: number, code: string, detail: string): Response {
  return json(status, { type: "about:blank", title: code, status, code, detail });
}

const HEX_ID = /^[0-9a-f-]{8,}$/;

function newestFirst(a: StationPackage, b: StationPackage): number {
  return Date.parse(b.createdAt) - Date.parse(a.createdAt) || b.revision - a.revision;
}

/** Name and address of a deal: the HUB cache, else the newest capture record, else the deal. */
function dealName(
  data: FakeStationData,
  dealId: string,
): { projectName?: string; address: { formatted: string } } {
  const cached = data.projects.find((project) => project.dealId === dealId);
  if (cached !== undefined) {
    return {
      ...(cached.projectName === undefined ? {} : { projectName: cached.projectName }),
      address: cached.address,
    };
  }
  const record = data.packages
    .filter((pkg) => pkg.dealId === dealId && pkg.captureRecord !== undefined)
    .sort(newestFirst)[0]?.captureRecord;
  if (record !== undefined) {
    return {
      ...(record.hub.projectName === undefined ? {} : { projectName: record.hub.projectName }),
      address: { formatted: record.address.formatted },
    };
  }
  return { address: { formatted: `HUB deal ${dealId}` } };
}

function matches(data: FakeStationData, pkg: StationPackage, q: string | null): boolean {
  if (q === null) {
    return true;
  }
  const needle = q.toLowerCase();
  const name = dealName(data, pkg.dealId);
  const texts = [
    name.projectName ?? "",
    name.address.formatted,
    pkg.captureRecord?.address.formatted ?? "",
    pkg.captureRecord?.hub.projectName ?? "",
  ];
  if (texts.some((text) => text.toLowerCase().includes(needle))) {
    return true;
  }
  if (pkg.dealId.toLowerCase().startsWith(needle)) {
    return true;
  }
  return (
    HEX_ID.test(needle) &&
    (pkg.packageId.startsWith(needle) ||
      pkg.captures.some((capture) => capture.captureId.startsWith(needle)))
  );
}

function limitOf(search: URLSearchParams): number {
  const raw = search.get("limit");
  return raw === null ? 100 : Number(raw);
}

export function createFakeStation(
  data: FakeStationData,
  options: FakeStationOptions = {},
): FakeStation {
  const calls: RecordedCall[] = [];
  const blobBase = options.blobBase ?? "https://blob.test";
  const tokens = options.tokens ?? [TEST_ACCESS_TOKEN];

  const answer = (station: FakeStation, method: string, url: URL, body: unknown): Response => {
    const path = url.pathname.slice(3);
    const segments = path
      .split("/")
      .filter((part) => part.length > 0)
      .map(decodeURIComponent);
    const { data } = station;

    if (method === "GET" && segments[0] === "projects" && segments.length === 2) {
      const project = data.projects.find((item) => item.dealId === segments[1]);
      return project === undefined ? problem(404, "not_found", "No project.") : json(200, project);
    }
    if (method === "GET" && path === "/packages") {
      const dealId = url.searchParams.get("dealId");
      const packages = data.packages
        .filter((pkg) => pkg.dealId === dealId)
        .sort(newestFirst)
        .map(summaryOf);
      return json(200, { packages });
    }
    if (method === "GET" && path === "/review/projects") {
      const q = url.searchParams.get("q");
      const limit = limitOf(url.searchParams);
      const deals = new Map<string, StationPackage[]>();
      for (const pkg of data.packages) {
        deals.set(pkg.dealId, [...(deals.get(pkg.dealId) ?? []), pkg]);
      }
      const projects: ReviewProject[] = [...deals.entries()]
        .filter(([, packages]) => packages.some((pkg) => matches(data, pkg, q)))
        .map(([dealId, packages]) => {
          const sorted = [...packages].sort(newestFirst);
          return {
            dealId,
            ...dealName(data, dealId),
            packageCount: packages.length,
            latest: summaryOf(sorted[0] as StationPackage),
          };
        })
        .sort((a, b) => Date.parse(b.latest.updatedAt) - Date.parse(a.latest.updatedAt));
      return json(200, { projects: projects.slice(0, limit), truncated: projects.length > limit });
    }
    if (method === "GET" && path === "/review/packages") {
      const q = url.searchParams.get("q");
      const limit = limitOf(url.searchParams);
      const packages: ReviewPackage[] = data.packages
        .filter((pkg) => matches(data, pkg, q))
        .sort(newestFirst)
        .map((pkg) => ({ ...summaryOf(pkg), ...dealName(data, pkg.dealId) }));
      return json(200, { packages: packages.slice(0, limit), truncated: packages.length > limit });
    }
    if (method === "GET" && path === "/modeling-decisions") {
      const dealId = url.searchParams.get("dealId");
      const limit = limitOf(url.searchParams);
      const decisions: ModelingDecisionWithContext[] = Object.values(data.decisions)
        .flat()
        .flatMap((decision) => {
          const pkg = data.packages.find((item) => item.packageId === decision.packageId);
          return pkg === undefined || (dealId !== null && pkg.dealId !== dealId)
            ? []
            : [{ ...decision, dealId: pkg.dealId, revision: pkg.revision }];
        })
        .sort((a, b) => Date.parse(b.decidedAt) - Date.parse(a.decidedAt));
      return json(200, {
        decisions: decisions.slice(0, limit),
        truncated: decisions.length > limit,
      });
    }
    if (segments[0] === "packages" && segments[1] !== undefined) {
      const pkg = data.packages.find((item) => item.packageId === segments[1]);
      if (pkg === undefined) {
        return problem(404, "not_found", "No package with this id.");
      }
      const rest = segments.slice(2).join("/");
      if (method === "GET" && rest === "") {
        return json(200, pkg);
      }
      if (method === "GET" && rest === "verdict") {
        const verdict = data.verdicts[pkg.packageId];
        return verdict === undefined
          ? problem(404, "verdict_not_ready", "The acceptance checks have not finished.")
          : json(200, verdict);
      }
      if (method === "GET" && rest === "files/download") {
        const filePath = url.searchParams.get("path");
        const manifest = pkg.manifestFile;
        if (manifest !== undefined && filePath === manifest.path) {
          const link: DownloadLink = {
            path: manifest.path,
            sha256: manifest.sha256,
            bytes: manifest.bytes,
            url: `${blobBase}/originals/${encodeURIComponent(manifest.path)}?sig=secret-sas`,
            expiresAt: "2026-10-17T15:52:07Z",
          };
          return json(200, link);
        }
        const file = pkg.files.find((item) => item.path === filePath);
        if (file === undefined) {
          return problem(404, "not_found", "No such file.");
        }
        if (file.status !== "verified") {
          return problem(409, "file_not_verified", "Not verified.");
        }
        const link: DownloadLink = {
          path: file.path,
          sha256: file.sha256,
          bytes: file.bytes,
          url: `${blobBase}/originals/${encodeURIComponent(file.path)}?sig=secret-sas`,
          expiresAt: "2026-10-17T15:52:07Z",
        };
        return json(200, link);
      }
      if (method === "GET" && rest === "spatial-report") {
        const report = pkg.report;
        const verdict = data.verdicts[pkg.packageId];
        if (
          report?.status !== "ready" ||
          verdict === undefined ||
          report.sha256 === undefined ||
          report.bytes === undefined ||
          report.pages === undefined ||
          report.checksPage === undefined
        ) {
          return problem(
            404,
            "report_not_ready",
            "The station has no spatial report for the package's current verdict yet.",
          );
        }
        const name = `spatial-report-${verdict.verdictId}.pdf`;
        const link: SpatialReportLink = {
          verdictId: verdict.verdictId,
          name,
          sha256: report.sha256,
          bytes: report.bytes,
          pages: report.pages,
          checksPage: report.checksPage,
          generatedAt: report.generatedAt ?? verdict.evaluatedAt,
          url: `${blobBase}/reports/${name}?sig=secret-sas`,
          expiresAt: "2026-10-17T15:52:07Z",
        };
        return json(200, link);
      }
      if (rest === "modeling-decisions") {
        const list = (data.decisions[pkg.packageId] ??= []);
        if (method === "GET") {
          return json(200, { decisions: list });
        }
        if (method === "POST") {
          const input = body as ModelingDecisionInput;
          const unknown = input.sources.findIndex(
            (source) => !pkg.files.some((file) => file.path === source.path),
          );
          if (unknown >= 0) {
            return json(422, {
              type: "about:blank",
              title: "decision_rule_violation",
              status: 422,
              code: "decision_rule_violation",
              errors: [
                { pointer: `/sources/${unknown}/path`, message: "not a file of the package" },
              ],
            });
          }
          const decision: ModelingDecision = {
            decisionId: `00000000-0000-4000-8000-${String(list.length + 1).padStart(12, "0")}`,
            packageId: pkg.packageId,
            element: input.element,
            decision: input.decision,
            ...(input.captureId === undefined ? {} : { captureId: input.captureId }),
            ...(input.areaKey === undefined ? {} : { areaKey: input.areaKey }),
            sources: input.sources,
            ...(input.note === undefined ? {} : { note: input.note }),
            decidedBy: station.author,
            decidedAt: station.now,
          };
          list.push(decision);
          return json(201, decision);
        }
      }
    }
    return problem(404, "not_found", "Unknown operation.");
  };

  const station: FakeStation = {
    data,
    calls,
    author: { name: "Dana BIM", userId: "11111111-1111-4111-8111-111111111111" },
    now: "2026-10-17T15:42:07Z",
    fetch: async (input, init) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      const method = init?.method ?? "GET";
      const headers = new Headers(init?.headers);
      const body = typeof init?.body === "string" ? (JSON.parse(init.body) as unknown) : undefined;
      if (!url.pathname.startsWith("/v1/")) {
        return problem(404, "not_found", "Unknown path.");
      }
      const call: RecordedCall = {
        method,
        path: url.pathname.slice(3),
        search: url.searchParams,
        authorization: headers.get("authorization"),
        body,
      };
      calls.push(call);
      let response: Response;
      const authorization = headers.get("authorization") ?? "";
      const accepted =
        options.acceptAnyToken === true
          ? /^Bearer \S+$/.test(authorization)
          : tokens.some((token) => authorization === `Bearer ${token}`);
      if (!accepted) {
        response = problem(401, "unauthorized", "Missing token.");
      } else if (station.failWith !== undefined) {
        response = problem(station.failWith, "station_error", "The station failed.");
      } else {
        response = answer(station, method, url, body);
      }
      call.status = response.status;
      call.response = await response.clone().json();
      return response;
    },
  };
  return station;
}

/** The package summaries of a deal, newest first, as listPackages answers. */
export function summariesOf(data: FakeStationData, dealId: string): PackageSummary[] {
  return data.packages
    .filter((pkg) => pkg.dealId === dealId)
    .sort(newestFirst)
    .map(summaryOf);
}
