// In-memory station API for tests: a fetch implementation that answers the operations the
// review screen uses (contract/openapi/station.yaml) from fixture data, and records each call.

import type { Verdict } from "@chapter/capture-contract";
import { createStationClient, type StationClient } from "@/lib/station";
import type {
  DownloadLink,
  HubProject,
  ModelingDecision,
  ModelingDecisionInput,
  PackageSummary,
  StationPackage,
} from "@/lib/station-types";
import type { StationRole } from "@/lib/roles";
import { canReview } from "@/lib/roles";
import type { ViewerSession } from "@/lib/viewer";

export const STATION_URL = "https://station.test";
export const TEST_ACCESS_TOKEN = "test-access-token";

export interface FakeStationData {
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
}

export interface FakeStation {
  readonly data: FakeStationData;
  readonly calls: RecordedCall[];
  readonly fetch: typeof fetch;
  /** Who the station records as the author of new decisions. */
  author: { name: string; userId: string };
  /** Time the station records for new decisions. */
  now: string;
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

function summaryOf(pkg: StationPackage): PackageSummary {
  return {
    packageId: pkg.packageId,
    visitId: pkg.visitId,
    dealId: pkg.dealId,
    revision: pkg.revision,
    status: pkg.status,
    createdAt: pkg.createdAt,
    ...(pkg.sealedAt === undefined ? {} : { sealedAt: pkg.sealedAt }),
    ...(pkg.verdict === undefined ? {} : { verdict: pkg.verdict }),
  };
}

export function createFakeStation(data: FakeStationData): FakeStation {
  const calls: RecordedCall[] = [];
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
      const path = url.pathname.slice(3);
      calls.push({
        method,
        path,
        search: url.searchParams,
        authorization: headers.get("authorization"),
        body,
      });
      if (headers.get("authorization") !== `Bearer ${TEST_ACCESS_TOKEN}`) {
        return problem(401, "unauthorized", "Missing token.");
      }
      const segments = path
        .split("/")
        .filter((part) => part.length > 0)
        .map(decodeURIComponent);

      if (method === "GET" && path === "/projects") {
        const q = url.searchParams.get("q")?.toLowerCase();
        const projects = data.projects.filter(
          (project) =>
            q === undefined ||
            project.address.formatted.toLowerCase().includes(q) ||
            project.dealId.toLowerCase().includes(q),
        );
        return json(200, { projects });
      }
      if (method === "GET" && segments[0] === "projects" && segments.length === 2) {
        const project = data.projects.find((item) => item.dealId === segments[1]);
        return project === undefined
          ? problem(404, "not_found", "No project.")
          : json(200, project);
      }
      if (method === "GET" && path === "/packages") {
        const dealId = url.searchParams.get("dealId");
        const packages = data.packages
          .filter((pkg) => pkg.dealId === dealId)
          .sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1))
          .map(summaryOf);
        return json(200, { packages });
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
            url: `https://blob.test/originals/${encodeURIComponent(file.path)}?sig=secret-sas`,
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
              ...input,
              decidedBy: station.author,
              decidedAt: station.now,
            };
            list.push(decision);
            return json(201, decision);
          }
        }
      }
      return problem(404, "not_found", "Unknown operation.");
    },
  };
  return station;
}

/** A viewer session with the given roles whose station client talks to the fake station. */
export function sessionFor(
  roles: StationRole[],
  station: FakeStation,
  name = "Dana BIM",
): ViewerSession {
  const client: StationClient = createStationClient({
    baseUrl: STATION_URL,
    accessToken: TEST_ACCESS_TOKEN,
    fetchImpl: station.fetch,
  });
  return {
    viewer: {
      name,
      userId: "11111111-1111-4111-8111-111111111111",
      roles,
      canReview: canReview(roles),
    },
    station: client,
  };
}
