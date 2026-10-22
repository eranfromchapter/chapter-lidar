// Server-only client for the station API (contract/openapi/station.yaml 1.1.0). Every call sends
// the signed-in user's station access token as a bearer token; the browser never talks to the
// station and never sees the token. Errors carry the HTTP status and the problem code only.

import "server-only";
import type {
  DownloadLink,
  HubProject,
  ModelingDecision,
  ModelingDecisionInput,
  ModelingDecisionWithContext,
  PackageSummary,
  Problem,
  ReviewPackage,
  ReviewProject,
  SpatialReportLink,
  StationPackage,
  StationPage,
  Verdict,
} from "./station-types";

/** Base path of the station API (OpenAPI servers[0].url). */
export const STATION_BASE_PATH = "/v1";

const TIMEOUT_MS = 20_000;

export class StationError extends Error {
  constructor(
    readonly status: number,
    /** Problem code, for example not_found or verdict_not_ready; "unknown" when absent. */
    readonly code: string,
    /** Plain-language detail from the station, when given. */
    readonly detail?: string,
    readonly fieldErrors: readonly { pointer: string; message: string }[] = [],
  ) {
    super(`station answered ${status} (${code})`);
    this.name = "StationError";
  }
}

/** Query of the review lists (listReviewProjects, listReviewPackages). */
export interface ReviewListQuery {
  /** 1 to 200 characters; empty means no search. */
  readonly q?: string;
  /** 1 to 200; the station's default is 100. */
  readonly limit?: number;
}

export interface StationClient {
  /** getProject: the HUB project of a deal. */
  getProject(dealId: string): Promise<HubProject>;
  /** listPackages: the packages of one deal, newest first. */
  listPackages(dealId: string): Promise<PackageSummary[]>;
  /** getPackage: one package with its files. */
  getPackage(packageId: string): Promise<StationPackage>;
  /** getVerdict: the verdict, or null while the checks have not finished (verdict_not_ready). */
  getVerdict(packageId: string): Promise<Verdict | null>;
  /** getFileDownloadLink: a 10-minute read-only link. Never render it into a page. */
  getFileDownloadLink(packageId: string, path: string): Promise<DownloadLink>;
  /** getSpatialReportLink: a 10-minute link to the station's spatial report. Never render it. */
  getSpatialReportLink(packageId: string): Promise<SpatialReportLink>;
  /** listModelingDecisions: the decisions of one package, oldest first. */
  listModelingDecisions(packageId: string): Promise<ModelingDecision[]>;
  /** createModelingDecision: the station records the author and the time. */
  createModelingDecision(
    packageId: string,
    input: ModelingDecisionInput,
  ): Promise<ModelingDecision>;
  /** listReviewProjects: projects that have packages, most recent package change first. */
  listReviewProjects(query?: ReviewListQuery): Promise<StationPage<ReviewProject>>;
  /** listReviewPackages: every package, newest first. */
  listReviewPackages(query?: ReviewListQuery): Promise<StationPage<ReviewPackage>>;
  /** listAllModelingDecisions: decisions across packages, newest first. */
  listAllModelingDecisions(query?: {
    readonly dealId?: string;
    readonly limit?: number;
  }): Promise<StationPage<ModelingDecisionWithContext>>;
}

export interface StationClientOptions {
  /** Station host, without the /v1 base path. */
  readonly baseUrl: string;
  /** The signed-in user's station access token. */
  readonly accessToken: string;
  readonly fetchImpl?: typeof fetch;
}

async function problemOf(response: Response): Promise<Problem> {
  try {
    const body: unknown = await response.json();
    return typeof body === "object" && body !== null ? (body as Problem) : {};
  } catch {
    return {};
  }
}

function listQuery(query: ReviewListQuery): Record<string, string | undefined> {
  const q = query.q?.trim();
  return {
    q: q === undefined || q.length === 0 ? undefined : q,
    limit: query.limit === undefined ? undefined : String(query.limit),
  };
}

export function createStationClient(options: StationClientOptions): StationClient {
  const fetchImpl = options.fetchImpl ?? fetch;
  const root = `${options.baseUrl.replace(/\/+$/, "")}${STATION_BASE_PATH}`;

  async function call<T>(
    method: "GET" | "POST",
    path: string,
    init: { query?: Record<string, string | undefined>; body?: unknown } = {},
  ): Promise<T> {
    const url = new URL(`${root}${path}`);
    for (const [key, value] of Object.entries(init.query ?? {})) {
      if (value !== undefined) {
        url.searchParams.set(key, value);
      }
    }
    const headers: Record<string, string> = {
      authorization: `Bearer ${options.accessToken}`,
      accept: "application/json",
    };
    if (init.body !== undefined) {
      headers["content-type"] = "application/json";
    }
    let response: Response;
    try {
      response = await fetchImpl(url, {
        method,
        headers,
        cache: "no-store",
        signal: AbortSignal.timeout(TIMEOUT_MS),
        ...(init.body === undefined ? {} : { body: JSON.stringify(init.body) }),
      });
    } catch {
      throw new StationError(503, "station_unreachable", "The station did not answer.");
    }
    if (!response.ok) {
      const problem = await problemOf(response);
      throw new StationError(
        response.status,
        typeof problem.code === "string" ? problem.code : "unknown",
        typeof problem.detail === "string" ? problem.detail : undefined,
        Array.isArray(problem.errors) ? problem.errors : [],
      );
    }
    return (await response.json()) as T;
  }

  const seg = encodeURIComponent;

  return {
    getProject(dealId) {
      return call<HubProject>("GET", `/projects/${seg(dealId)}`);
    },
    async listPackages(dealId) {
      const body = await call<{ packages: PackageSummary[] }>("GET", "/packages", {
        query: { dealId },
      });
      return body.packages;
    },
    getPackage(packageId) {
      return call<StationPackage>("GET", `/packages/${seg(packageId)}`);
    },
    async getVerdict(packageId) {
      try {
        return await call<Verdict>("GET", `/packages/${seg(packageId)}/verdict`);
      } catch (error) {
        if (
          error instanceof StationError &&
          error.status === 404 &&
          error.code === "verdict_not_ready"
        ) {
          return null;
        }
        throw error;
      }
    },
    getFileDownloadLink(packageId, path) {
      return call<DownloadLink>("GET", `/packages/${seg(packageId)}/files/download`, {
        query: { path },
      });
    },
    getSpatialReportLink(packageId) {
      return call<SpatialReportLink>("GET", `/packages/${seg(packageId)}/spatial-report`);
    },
    async listModelingDecisions(packageId) {
      const body = await call<{ decisions: ModelingDecision[] }>(
        "GET",
        `/packages/${seg(packageId)}/modeling-decisions`,
      );
      return body.decisions;
    },
    createModelingDecision(packageId, input) {
      return call<ModelingDecision>("POST", `/packages/${seg(packageId)}/modeling-decisions`, {
        body: input,
      });
    },
    async listReviewProjects(query = {}) {
      const body = await call<{ projects: ReviewProject[]; truncated: boolean }>(
        "GET",
        "/review/projects",
        { query: listQuery(query) },
      );
      return { items: body.projects, truncated: body.truncated };
    },
    async listReviewPackages(query = {}) {
      const body = await call<{ packages: ReviewPackage[]; truncated: boolean }>(
        "GET",
        "/review/packages",
        { query: listQuery(query) },
      );
      return { items: body.packages, truncated: body.truncated };
    },
    async listAllModelingDecisions(query = {}) {
      const body = await call<{ decisions: ModelingDecisionWithContext[]; truncated: boolean }>(
        "GET",
        "/modeling-decisions",
        {
          query: {
            dealId: query.dealId,
            limit: query.limit === undefined ? undefined : String(query.limit),
          },
        },
      );
      return { items: body.decisions, truncated: body.truncated };
    },
  };
}
